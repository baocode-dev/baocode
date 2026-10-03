/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The side bar's text inputs, as VS Code draws its InputBox: the input
// colors, a focus outline, toggles inside on the right, and a validation
// message attached below.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/base/browser/ui/inputbox/inputBox.css, toggle/toggle.css, and the
// SCM input's validation (contrib/scm/browser/media/scm.css), with the
// color theme's `input.*`, `inputOption.*` and `inputValidation.*` colors
// (platform/theme/browser/defaultStyles.ts `defaultInputBoxStyles`,
// `defaultToggleStyles`).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../chat/widgets/wheel_latch.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'ide_hover.dart';

/// The color theme's `input.*`, `inputOption.*` and `focusBorder`.
abstract final class IdeInputColors {
  static Color get background => themeColors['input.background'];

  /// Transparent where the theme has none: there is always a border.
  static Color get border => themeColors['input.border'];
  static Color get foreground => themeColors['input.foreground'];
  static Color get placeholder => themeColors['input.placeholderForeground'];
  static Color get focusBorder => themeColors['focusBorder'];
  static Color get optionActiveBackground =>
      themeColors['inputOption.activeBackground'];
  static Color get optionActiveBorder =>
      themeColors['inputOption.activeBorder'];
  static Color get optionActiveForeground =>
      themeColors['inputOption.activeForeground'];
  static Color get optionHoverBackground =>
      themeColors['inputOption.hoverBackground'];
}

enum IdeValidationSeverity { info, warning, error }

/// A message shown under an input.
class IdeInputValidation {
  const IdeInputValidation(
    this.message, [
    this.severity = IdeValidationSeverity.error,
  ]);

  final String message;
  final IdeValidationSeverity severity;

  /// `inputValidation.{info,warning,error}{Background,Border,Foreground}`.
  (Color background, Color border, Color foreground) get colors {
    final kind = severity.name;
    return (
      themeColors['inputValidation.${kind}Background'],
      themeColors['inputValidation.${kind}Border'],
      themeColors['inputValidation.${kind}Foreground'],
    );
  }
}

/// An input box: [minLines] to [maxLines] lines (it grows, then scrolls),
/// [toggles] on the right, centered on the first line, and [validation]
/// below.
class IdeInputBox extends StatefulWidget {
  const IdeInputBox({
    super.key,
    required this.controller,
    this.focusNode,
    this.placeholder,
    this.minLines = 1,
    this.maxLines = 1,
    this.fontSize = 13,
    this.lineHeight = 18,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    this.toggles = const [],
    this.togglesInset = 1,
    this.validation,
    this.onChanged,
    this.onSubmitted,
    this.shortcuts = const {},
    this.autofocus = false,
    this.semanticsLabel,
    this.floatingValidation = false,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? placeholder;
  final int minLines;
  final int maxLines;
  final double fontSize;
  final double lineHeight;
  final EdgeInsets padding;
  final List<Widget> toggles;

  /// Between [toggles] and the border: `.controls { right: 2px }` is 1px
  /// inside it.
  final double togglesInset;
  final IdeInputValidation? validation;
  final ValueChanged<String>? onChanged;

  /// Enter, in a one-line input.
  final ValueChanged<String>? onSubmitted;

  /// Keys handled while the input has focus (⌘Enter to commit).
  final Map<ShortcutActivator, VoidCallback> shortcuts;
  final bool autofocus;
  final String? semanticsLabel;

  /// Shows [validation] over what is below instead of pushing it down, as
  /// the explorer's inline inputs do.
  final bool floatingValidation;

  /// Its text as dots (a key, a password): one line only.
  final bool obscureText;

  @override
  State<IdeInputBox> createState() => _IdeInputBoxState();
}

class _IdeInputBoxState extends State<IdeInputBox> {
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
    if (widget.floatingValidation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _portal.show();
      });
    }
  }

  @override
  void didUpdateWidget(IdeInputBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.focusNode ?? _ownFocus;
    if (old != _focus) {
      old?.removeListener(_focusChanged);
      _focus.addListener(_focusChanged);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _ownFocus?.dispose();
    super.dispose();
  }

  void _focusChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final validation = widget.validation;
    final floating = widget.floatingValidation;
    final focused = _focus.hasFocus;
    final outline = validation != null
        ? validation.colors.$2
        : focused
        ? IdeInputColors.focusBorder
        : IdeInputColors.border;
    final style = TextStyle(
      fontSize: widget.fontSize,
      height: widget.lineHeight / widget.fontSize,
      // CSS's half-leading: the glyphs centered in the line, as the caret
      // is (by default the extra height goes mostly above them).
      leadingDistribution: TextLeadingDistribution.even,
      color: IdeInputColors.foreground,
    );
    final multiline = widget.maxLines > 1;
    Widget field = TextField(
      controller: widget.controller,
      focusNode: _focus,
      autofocus: widget.autofocus,
      obscureText: widget.obscureText,
      minLines: widget.minLines,
      // Several lines: as many as it has, scrolled around it (below).
      maxLines: multiline ? null : widget.maxLines,
      keyboardType: multiline ? TextInputType.multiline : TextInputType.text,
      textInputAction: multiline
          ? TextInputAction.newline
          : TextInputAction.done,
      autocorrect: false,
      enableSuggestions: false,
      cursorColor: IdeInputColors.foreground,
      cursorWidth: 1,
      cursorHeight: ideCaretHeight(widget.fontSize),
      style: style,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        hintText: widget.placeholder,
        hintStyle: style.copyWith(color: IdeInputColors.placeholder),
        hintMaxLines: 1,
        isDense: true,
        isCollapsed: true,
        contentPadding: widget.padding,
        border: InputBorder.none,
        // The desktop's compact density would take the padding away.
        visualDensity: VisualDensity.standard,
      ),
    );
    if (multiline) {
      // Past [maxLines], it scrolls in a view of its own, not the field's,
      // so that a wheel gesture begun over it keeps to it (`WheelLatch`):
      // the side bar's list does not scroll on from its ends.
      field = ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              widget.lineHeight * widget.maxLines + widget.padding.vertical,
        ),
        child: SingleChildScrollView(child: WheelLatch(child: field)),
      );
    }
    // Scrolls past its lines without a scrollbar, as VS Code's inputs.
    field = ScrollConfiguration(
      behavior: const _WithoutScrollbars(),
      child: field,
    );
    if (widget.shortcuts.isNotEmpty) {
      field = CallbackShortcuts(bindings: widget.shortcuts, child: field);
    }
    if (widget.semanticsLabel case final label?) {
      field = Semantics(label: label, textField: true, child: field);
    }
    final box = Container(
      decoration: BoxDecoration(
        color: IdeInputColors.background,
        border: Border.all(color: outline),
        borderRadius: validation == null || floating
            ? BorderRadius.circular(4)
            : const BorderRadius.vertical(top: Radius.circular(4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: field),
          if (widget.toggles.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(right: widget.togglesInset),
              // Centered on the first line, as its text is.
              child: SizedBox(
                height: widget.padding.top * 2 + widget.lineHeight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: widget.toggles,
                ),
              ),
            ),
        ],
      ),
    );
    if (floating) {
      return LayoutBuilder(
        builder: (context, constraints) => CompositedTransformTarget(
          link: _link,
          child: OverlayPortal(
            controller: _portal,
            overlayChildBuilder: (context) => validation == null
                ? const SizedBox.shrink()
                : CompositedTransformFollower(
                    link: _link,
                    targetAnchor: Alignment.bottomLeft,
                    showWhenUnlinked: false,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        child: _message(validation),
                      ),
                    ),
                  ),
            child: box,
          ),
        ),
      );
    }
    if (validation == null) return box;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [box, _message(validation)],
    );
  }

  Widget _message(IdeInputValidation validation) {
    final (background, border, foreground) = validation.colors;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: background,
        border: Border(
          left: BorderSide(color: border),
          right: BorderSide(color: border),
          bottom: BorderSide(color: border),
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        child: Text(
          validation.message,
          style: TextStyle(fontSize: widget.fontSize * .9, color: foreground),
        ),
      ),
    );
  }
}

/// An input's toggle (`.monaco-custom-toggle`): a 16px codicon in a 20px
/// square, bordered and filled while [checked]. Unchecked, it is in the
/// color around it (`inherit`): the side bar's, where the search view has
/// it.
class IdeInputToggle extends StatefulWidget {
  const IdeInputToggle({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.checked,
    required this.onChanged,
  });

  final IconData icon;
  final String tooltip;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  State<IdeInputToggle> createState() => _IdeInputToggleState();
}

class _IdeInputToggleState extends State<IdeInputToggle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final checked = widget.checked;
    final colors = themeColors;
    // High contrast themes outline it on hover instead (dashed upstream).
    final highContrast = colors.highContrast;
    return IdeHover(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        toggled: checked,
        label: widget.tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onChanged(!checked),
            child: Container(
              width: 20,
              height: 20,
              margin: const EdgeInsets.only(left: 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: checked
                    ? IdeInputColors.optionActiveBackground
                    : _hover && !highContrast
                    ? IdeInputColors.optionHoverBackground
                    : null,
                border: Border.all(
                  color: _hover && highContrast
                      ? colors['focusBorder']
                      : checked
                      ? IdeInputColors.optionActiveBorder
                      : Colors.transparent,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Icon(
                widget.icon,
                size: 16,
                color: checked
                    ? IdeInputColors.optionActiveForeground
                    : colors['sideBar.foreground'],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws no scrollbar: a multi-line text field asks for one whatever
/// the inherited behavior says (`copyWith(scrollbars: true)`), then builds
/// it with this.
class _WithoutScrollbars extends MaterialScrollBehavior {
  const _WithoutScrollbars();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

/// A caret as tall as the font, ascent to descent (about 1.2 times its
/// size), as the browser draws one in VS Code's inputs; Flutter's is the
/// whole line, and 2px more on macOS.
double ideCaretHeight(double fontSize) {
  final height = (fontSize * 1.2).roundToDouble();
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => height - 2,
    _ => height,
  };
}
