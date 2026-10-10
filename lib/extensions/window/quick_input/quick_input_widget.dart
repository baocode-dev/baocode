/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for
 *  license information.
 *--------------------------------------------------------------------------------------------*/

// The widget of an extension's quick input (`MainThreadQuickOpen`'s
// sessions): the title bar with its buttons and steps, the input, the
// list, the message and the progress bar, drawn as
// src/vs/platform/quickinput/browser/quickInput.ts and its media do
// (quickInput.css, quickInputList.css), on the app's own quick input
// widget (lib/ide/ide_quick_input.dart) behavior: the same rows, the same
// keys (Up/Down/PageUp/PageDown/Enter/Escape, Space in a multiple
// selection), the same highlighting.

import 'dart:io';

import 'package:flutter/material.dart';

import '../../../ide/ide_button.dart';
import '../../../ide/ide_hover.dart';
import '../../../ide/ide_input.dart';
import '../../../ide/ide_fuzzy.dart';
import '../../../ide/ide_quick_input.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/codicons.dart';
import '../../../theme/icon_registry.dart';
import '../../../theme/workbench_theme.dart' show themeColors;
import '../window_ports.dart' show ExtensionSeverity;
import 'quick_input_model.dart';
import 'quick_input_service.dart';

/// The layer that shows the quick input of a session over the workbench's
/// content, at the top center, as VS Code does.
class ExtensionQuickInputLayer extends StatelessWidget {
  const ExtensionQuickInputLayer({super.key, required this.service});

  final ExtensionQuickInputService service;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      final input = service.current;
      if (input == null) return const SizedBox.shrink();
      return Positioned.fill(
        child: ExtensionQuickInputView(
          key: ObjectKey(input),
          input: input,
          service: service,
        ),
      );
    },
  );
}

/// One quick input, live: its widget reads the model as it changes.
class ExtensionQuickInputView extends StatefulWidget {
  const ExtensionQuickInputView({
    super.key,
    required this.input,
    required this.service,
  });

  final ExtensionQuickInput input;
  final ExtensionQuickInputService service;

  @override
  State<ExtensionQuickInputView> createState() =>
      _ExtensionQuickInputViewState();
}

class _ExtensionQuickInputViewState extends State<ExtensionQuickInputView> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.input.value,
  );
  final FocusNode _focusNode = FocusNode(debugLabel: 'extension quick input');
  final FocusNode _listFocus = FocusNode(
    debugLabel: 'extension quick input list',
    skipTraversal: true,
  );
  final ScrollController _scroll = ScrollController();
  int _appliedValueSelection = -1;

  ExtensionQuickInput get _input => widget.input;

  @override
  void initState() {
    super.initState();
    _input.addListener(_changed);
    _syncValue(force: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(ExtensionQuickInputView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.input == widget.input) return;
    oldWidget.input.removeListener(_changed);
    widget.input.addListener(_changed);
  }

  @override
  void dispose() {
    _input.removeListener(_changed);
    _controller.dispose();
    _focusNode.dispose();
    _listFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The model changed: the value goes into the input where it differs
  /// (a change from the input itself is the input's already).
  void _changed() {
    if (!mounted) return;
    _syncValue();
    setState(() {});
    final take = _input is ExtensionQuickPick
        ? (_input as ExtensionQuickPick).takeScroll()
        : null;
    if (take != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(take));
    }
  }

  void _syncValue({bool force = false}) {
    final input = _input;
    if (force || _controller.text != input.value) {
      _controller.value = TextEditingValue(
        text: input.value,
        selection: TextSelection.collapsed(offset: input.value.length),
      );
    }
    // The extension host's valueSelection applies once per version.
    if (input.valueSelection case final selection?
        when input.valueSelectionVersion != _appliedValueSelection) {
      _appliedValueSelection = input.valueSelectionVersion;
      _controller.selection = TextSelection(
        baseOffset: selection.$1.clamp(0, _controller.text.length),
        extentOffset: selection.$2.clamp(0, _controller.text.length),
      );
    }
  }

  void _reveal(ExtensionQuickPickScroll scroll) {
    if (!_scroll.hasClients) return;
    switch (scroll) {
      case ExtensionQuickPickScroll.top:
        _scroll.jumpTo(0);
      case ExtensionQuickPickScroll.last:
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      case ExtensionQuickPickScroll.reveal:
        final pick = _input as ExtensionQuickPick;
        final index = pick.rows.indexWhere(
          (row) => identical(row.item, pick.focusedItem),
        );
        if (index < 0) return;
        var top = 0.0;
        for (var i = 0; i < index; i++) {
          top += _rowHeight(pick.rows[i]);
        }
        final height = _rowHeight(pick.rows[index]);
        final position = _scroll.position;
        if (top < position.pixels) {
          _scroll.jumpTo(top);
        } else if (top + height > position.pixels + position.viewportDimension) {
          _scroll.jumpTo(top + height - position.viewportDimension);
        }
    }
  }

  static double _rowHeight(ExtensionQuickPickRow row) =>
      (row.item.detail?.isNotEmpty ?? false)
      ? IdeQuickInput.detailRowHeight
      : IdeQuickInput.rowHeight;

  String? get _message {
    final input = _input;
    if (input.validationMessage?.isNotEmpty ?? false) {
      return input.validationMessage;
    }
    return input is ExtensionQuickPick ? input.message : null;
  }

  @override
  Widget build(BuildContext context) {
    final input = _input;
    final colors = themeColors;
    final rows = input is ExtensionQuickPick ? input.rows : const [];
    final listHeight = rows.fold<double>(
      0,
      (height, row) => height + _rowHeight(row),
    );
    final message = _message;
    final validationMessage = input.validationMessage;
    final validation = (validationMessage?.isNotEmpty ?? false)
        ? IdeInputValidation(validationMessage!, _severityOf(input))
        : null;
    return Column(
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              color: colors['quickInput.background'],
              elevation: 12,
              shadowColor: colors['widget.shadow'],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: switch (colors.get('widget.border')) {
                  final border? => BorderSide(color: border),
                  null => BorderSide.none,
                },
              ),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: 600,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (input.showsTitleBar) _TitleBar(input: input),
                    if (!input.enabled) const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                      child: Row(
                        children: [
                          Expanded(child: _field(input, validation)),
                          for (final button in input.inlineButtons)
                            _Button(button: button, input: input),
                        ],
                      ),
                    ),
                    if (message != null)
                      _Message(
                        message: message,
                        severity: input.severity,
                        showsValidation: validation != null,
                        prompt: switch (input) {
                          final ExtensionQuickPick pick => pick.prompt,
                          final ExtensionInputBox box => box.prompt,
                        },
                      ),
                    if (rows.isNotEmpty)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: listHeight > 14 * IdeQuickInput.rowHeight
                              ? 14 * IdeQuickInput.rowHeight
                              : listHeight,
                        ),
                        child: ListView.builder(
                          controller: _scroll,
                          padding: EdgeInsets.zero,
                          itemExtentBuilder: (index, _) =>
                              index < rows.length
                              ? _rowHeight(rows[index])
                              : null,
                          itemCount: rows.length,
                          itemBuilder: (context, index) => _Row(
                            input: input as ExtensionQuickPick,
                            row: rows[index],
                            selected: input.focusedItem == rows[index].item,
                          ),
                        ),
                      ),
                    if (input is ExtensionQuickPick && input.canSelectMany)
                      _SelectManyBar(pick: input),
                    if (input.progressVisible)
                      SizedBox(
                        height: 2,
                        child: LinearProgressIndicator(
                          minHeight: 2,
                          color: colors['progressBar.background'],
                          backgroundColor: Colors.transparent,
                        ),
                      ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => input.hide(),
          ),
        ),
      ],
    );
  }

  static IdeValidationSeverity _severityOf(ExtensionQuickInput input) =>
      switch (input.severity) {
        ExtensionSeverity.warning => IdeValidationSeverity.warning,
        ExtensionSeverity.info => IdeValidationSeverity.info,
        // An ignore-severity message still shows, as an error (upstream
        // shows a validation message whatever its severity says).
        _ => IdeValidationSeverity.error,
      };

  Widget _field(ExtensionQuickInput input, IdeInputValidation? validation) {
    final validationBorder = validation?.colors.$2;
    final enabled = input.enabled;
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: enabled,
      obscureText: input is ExtensionInputBox && input.password,
      autocorrect: false,
      enableSuggestions: false,
      cursorColor: IdeInputColors.foreground,
      cursorWidth: 1.5,
      style: TextStyle(color: IdeInputColors.foreground, fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: input.placeholder,
        hintStyle: TextStyle(color: IdeInputColors.placeholder, fontSize: 13),
        filled: true,
        fillColor: IdeInputColors.background,
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: BorderSide(color: IdeInputColors.border),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        suffixIcon: input.inputButtons.isEmpty
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final button in input.inputButtons)
                    _Button(button: button, input: input),
                ],
              ),
        suffixIconConstraints: const BoxConstraints(minHeight: 24),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: BorderSide(
            color: validationBorder ?? IdeInputColors.border,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: BorderSide(
            color: validationBorder ?? IdeInputColors.focusBorder,
          ),
        ),
      ),
      onChanged: (value) => input.setValueFromUi(value),
      onSubmitted: (_) => input.accept(),
    );
  }
}

/// `.quick-input-titlebar`: the title, the Back button and the buttons.
class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.input});

  final ExtensionQuickInput input;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return Container(
      height: 24,
      color: colors['quickInputTitle.background'],
      child: Row(
        children: [
          for (final button in input.leftButtons)
            _Button(button: button, input: input),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                input.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color:
                      colors.get('quickInputTitle.foreground') ??
                      colors['foreground'],
                ),
              ),
            ),
          ),
          for (final button in input.rightButtons)
            _Button(button: button, input: input),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

/// A title or input button; a toggle shows its state.
class _Button extends StatelessWidget {
  const _Button({required this.button, required this.input});

  final ExtensionQuickInputButton button;
  final ExtensionQuickInput input;

  @override
  Widget build(BuildContext context) => IdeActionButton(
    icon: quickInputIconData(button.icon),
    iconWidget: quickInputButtonGlyph(button.icon),
    tooltip: _tooltip(context),
    checked: button.checked == true,
    onPressed: () => input.triggerButton(button),
  );

  String _tooltip(BuildContext context) {
    final tooltip = button.tooltip;
    if (button.isBack) return context.l10n.commonCancel;
    if (button.isToggle) {
      return button.checked == true
          ? context.l10n.windowQuickInputToggleOn(tooltip ?? '')
          : context.l10n.windowQuickInputToggleOff(tooltip ?? '');
    }
    return tooltip ?? '';
  }
}

/// `.quick-input-message`: the validation message, a pick's message, or
/// the prompt with how to confirm it.
class _Message extends StatelessWidget {
  const _Message({
    required this.message,
    required this.severity,
    required this.showsValidation,
    this.prompt,
  });

  final String message;
  final ExtensionSeverity severity;
  final bool showsValidation;
  final String? prompt;

  bool get _hasPrompt => prompt?.isNotEmpty ?? false;

  @override
  Widget build(BuildContext context) {
    final colors = showsValidation
        ? IdeInputValidation(message, switch (severity) {
            ExtensionSeverity.warning => IdeValidationSeverity.warning,
            ExtensionSeverity.info => IdeValidationSeverity.info,
            _ => IdeValidationSeverity.error,
          }).colors
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: colors == null
            ? null
            : BoxDecoration(
                color: colors.$1,
                border: Border.all(color: colors.$2),
              ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 12.5,
                  color:
                      colors?.$3 ??
                      (showsValidation
                          ? themeColors['errorForeground']
                          : themeColors['quickInput.foreground']),
                ),
              ),
            ),
            if (_hasPrompt && !showsValidation)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  context.l10n.quickInputEntryWithPrompt(prompt!),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: themeColors['descriptionForeground'],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

}

/// A row: its icon, label (with matches), description, detail, its buttons
/// and a multiple selection's checkbox.
class _Row extends StatelessWidget {
  const _Row({
    required this.input,
    required this.row,
    required this.selected,
  });

  final ExtensionQuickPick input;
  final ExtensionQuickPickRow row;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final item = row.item;
    final message = row.separator != null && item.label.isEmpty;
    final highlight = TextStyle(
      color: colors[selected
          ? 'quickInputList.focusHighlightForeground'
          : 'list.highlightForeground'],
      fontWeight: FontWeight.w600,
    );
    final color = selected
        ? colors.get('quickInputList.focusForeground') ??
              colors['quickInput.foreground']
        : colors['quickInput.foreground'];
    final muted = TextStyle(
      color: color.withValues(alpha: color.a * (selected ? 1 : .7)),
      fontSize: 11.5,
    );
    Widget label = Row(
      children: [
        if (input.canSelectMany && !message) ...[
          SizedBox(
            width: 16,
            child: Checkbox(
              value: input.isChecked(item),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (value) => input.setItemChecked(item, value == true),
            ),
          ),
          const SizedBox(width: 4),
        ],
        if (quickInputIconWidget(item.icon) case final icon?) ...[
          SizedBox(width: 16, child: Center(child: icon)),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                ...ideHighlightSpans(
                  item.label,
                  row.labelMatches,
                  highlight,
                  style: TextStyle(fontSize: 12.5, color: color),
                ),
                if (item.description case final description?
                    when description.isNotEmpty) ...[
                  const TextSpan(text: '  '),
                  ...ideHighlightSpans(
                    description,
                    row.descriptionMatches,
                    highlight,
                    style: muted,
                  ),
                ],
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        for (final button in item.buttons)
          _ItemButton(
            button: button,
            onPressed: () => input.triggerItemButton(item, button),
          ),
      ],
    );
    if (item.detail case final detail? when detail.isNotEmpty) {
      label = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: IdeQuickInput.rowHeight - 2, child: label),
          Text.rich(
            TextSpan(
              children: ideHighlightSpans(
                detail,
                row.detailMatches,
                highlight,
                style: muted,
              ),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.left,
          ),
        ],
      );
    }
    final background = selected
        ? colors['quickInputList.focusBackground']
        : Colors.transparent;
    Widget content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: background,
      child: label,
    );
    if (row.separatorBorder) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: colors['pickerGroup.border']),
          ),
        ),
        child: content,
      );
    }
    return MouseRegion(
      cursor: message ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: message ? null : () => input.clickItem(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: content,
        ),
      ),
    );
  }
}

/// An item's button, kept visible while its row is hovered.
class _ItemButton extends StatelessWidget {
  const _ItemButton({required this.button, required this.onPressed});

  final ExtensionQuickInputButton button;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IdeActionButton(
    icon: quickInputIconData(button.icon),
    iconWidget: quickInputButtonGlyph(button.icon),
    tooltip: button.tooltip ?? '',
    onPressed: onPressed,
  );
}

/// The multiple selection's bar: how many are checked, all of them, and
/// OK.
class _SelectManyBar extends StatelessWidget {
  const _SelectManyBar({required this.pick});

  final ExtensionQuickPick pick;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors['pickerGroup.border'])),
      ),
      child: Row(
        children: [
          if (pick.checkedCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: colors['badge.background'],
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                '${pick.checkedCount}',
                style: TextStyle(
                  fontSize: 11,
                  color: colors['badge.foreground'],
                ),
              ),
            ),
          const Spacer(),
          _Checkbox(
            label: context.l10n.windowQuickInputSelectAll,
            value: pick.allVisibleChecked,
            onChanged: pick.setAllVisibleChecked,
          ),
          const SizedBox(width: 8),
          IdeButton(
            label: context.l10n.commonOk,
            secondary: true,
            onPressed: pick.accept,
          ),
        ],
      ),
    );
  }
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 16,
        child: Checkbox(
          value: value,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: (value) => onChanged(value == true),
        ),
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: TextStyle(fontSize: 12, color: themeColors['foreground']),
      ),
    ],
  );
}

/// The codicon of a `$(name)` icon an extension gave.
IconData quickInputIconData(ExtensionQuickInputIcon? icon) => switch (icon) {
  ExtensionThemeIcon(:final id) => Codicons.byName[id] ?? Codicons.symbolEvent,
  // An image path has no codicon; a file stands for it.
  ExtensionImageIcon() => Codicons.file,
  ExtensionResourceIcon(:final folder) => folder
      ? Codicons.folder
      : Codicons.file,
  null => Codicons.info,
};

/// A button's icon when it is an extension's font icon, which no
/// [IconData] is.
Widget? quickInputButtonGlyph(ExtensionQuickInputIcon? icon) => switch (icon) {
  ExtensionThemeIcon(:final id)
      when !Codicons.byName.containsKey(id) &&
          IconRegistry.instance.contains(id) =>
    ThemeIcon(id, size: 16, color: IdeActionButton.foreground),
  _ => null,
};

/// An image icon as a widget (a file from disk); the codicon for the rest.
Widget? quickInputIconWidget(ExtensionQuickInputIcon? icon) => switch (icon) {
  ExtensionImageIcon(:final light) => _ImageIcon(light),
  ExtensionResourceIcon(:final path) => _ImageIcon(path),
  ExtensionThemeIcon(:final id) => ThemeIcon(
    id,
    size: 16,
    fallback: Codicons.symbolEvent,
  ),
  null => null,
};

class _ImageIcon extends StatelessWidget {
  const _ImageIcon(this.path);

  final String path;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    if (!file.existsSync()) return Icon(Codicons.file, size: 16);
    return Image.file(
      file,
      width: 16,
      height: 16,
      errorBuilder: (context, _, _) => Icon(Codicons.file, size: 16),
    );
  }
}
