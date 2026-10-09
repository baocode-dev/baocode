// The controls of the extension settings page (extension_settings_page.dart):
// a checkbox, a validated text field, a list of strings and an object of
// booleans, as VS Code's settings editor has them
// (src/vs/workbench/contrib/preferences/browser/settingsTree.ts,
// settingsWidgets.ts: `SettingBoolRenderer`, `SettingTextRenderer`,
// `SettingNumberRenderer`, `ListSettingWidget`, `ExcludeSettingWidget`,
// `ObjectSettingCheckboxWidget`).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../extensions/configuration/ui/setting_entries.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'settings_widgets.dart';

TextStyle get _mono => TextStyle(
  fontFamily: AppFonts.mono,
  fontFamilyFallback: AppFonts.monoFallbacks,
  fontSize: 12,
  color: AppColors.text,
);

Color get settingsErrorColor => themeColors['errorForeground'];

/// A checkbox (`settings.checkboxBackground`…), [label] read out.
class SettingCheckbox extends StatelessWidget {
  const SettingCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return Semantics(
      container: true,
      checked: value,
      label: label,
      excludeSemantics: true,
      onTap: () => onChanged(!value),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => onChanged(!value),
          child: Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  colors.get('settings.checkboxBackground') ??
                  colors['input.background'],
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color:
                    colors.get('settings.checkboxBorder') ??
                    AppColors.borderStrong,
              ),
            ),
            child: value
                ? Icon(
                    Codicons.check,
                    size: 14,
                    color:
                        colors.get('settings.checkboxForeground') ??
                        AppColors.textPrimary,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

/// A small text button (Add Item, Edit in settings.json).
class SettingTextButton extends StatelessWidget {
  const SettingTextButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = themeColors.get('textLink.foreground') ?? AppColors.accent;
    return Semantics(
      container: true,
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 4),
                ],
                Text(label, style: TextStyle(color: color, fontSize: 12.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A codicon button, [tooltip] read out.
class SettingIconButton extends StatefulWidget {
  const SettingIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<SettingIconButton> createState() => _SettingIconButtonState();
}

class _SettingIconButtonState extends State<SettingIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: widget.tooltip,
    excludeSemantics: true,
    onTap: widget.onTap,
    child: Tooltip(
      message: widget.tooltip,
      excludeFromSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? AppColors.hover : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(widget.icon, size: 14, color: AppColors.textMuted),
          ),
        ),
      ),
    ),
  );
}

InputDecoration _decoration({String? error, String? hint}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(4),
    borderSide: BorderSide(
      color: error != null ? settingsErrorColor : AppColors.borderStrong,
    ),
  );
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: _mono.copyWith(color: AppColors.textFaint),
    filled: true,
    fillColor: themeColors['input.background'],
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(
        color: error != null ? settingsErrorColor : themeColors['focusBorder'],
      ),
    ),
  );
}

/// The text field of a string or number setting: [value] as kept; what is
/// typed is checked against [schema] as it is typed, and [onCommit] gets
/// it, when valid and changed, once entered or the field loses focus.
class SettingTextControl extends StatefulWidget {
  const SettingTextControl({
    super.key,
    required this.value,
    required this.schema,
    required this.control,
    required this.label,
    required this.onCommit,
  });

  final Object? value;
  final Map<String, Object?> schema;
  final SettingControl control;
  final String label;
  final ValueChanged<Object?> onCommit;

  @override
  State<SettingTextControl> createState() => _SettingTextControlState();
}

class _SettingTextControlState extends State<SettingTextControl> {
  late final _controller = TextEditingController(text: _text(widget.value));
  final _focus = FocusNode();

  static String _text(Object? value) => switch (value) {
    null => '',
    final num n when n == n.roundToDouble() && n is double => '${n.toInt()}',
    _ => '$value',
  };

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(SettingTextControl old) {
    super.didUpdateWidget(old);
    final text = _text(widget.value);
    if (!_focus.hasFocus && _controller.text != text) {
      _controller.text = text;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String text) {
    final l10n = context.l10n;
    final parsed = parseTyped(widget.schema, widget.control, text);
    if (parsed.error) return l10n.extensionSettingsValidationNumber;
    return validateSetting(widget.schema, parsed.value, l10n);
  }

  void _commit() {
    final text = _controller.text;
    if (_validate(text) != null) return;
    final parsed = parseTyped(widget.schema, widget.control, text);
    if (_text(parsed.value) == _text(widget.value) &&
        (parsed.value == null) == (widget.value == null)) {
      return;
    }
    widget.onCommit(parsed.value);
  }

  @override
  Widget build(BuildContext context) {
    final numeric =
        widget.control == SettingControl.number ||
        widget.control == SettingControl.integer;
    final multiline = widget.control == SettingControl.multilineString;
    final error = _validate(_controller.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: numeric ? 160 : 460),
          child: Semantics(
            container: true,
            textField: true,
            label: widget.label,
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              minLines: 1,
              maxLines: multiline ? 6 : 1,
              keyboardType: multiline ? TextInputType.multiline : null,
              style: _mono,
              cursorColor: AppColors.text,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _commit(),
              decoration: _decoration(error: error),
            ),
          ),
        ),
        if (error != null) SettingError(error),
      ],
    );
  }
}

/// A validation message, under a control.
class SettingError extends StatelessWidget {
  const SettingError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      message,
      style: TextStyle(color: settingsErrorColor, fontSize: 12, height: 1.4),
    ),
  );
}

/// An inline field adding (or changing) an item, with OK and Cancel.
class _ItemEditor extends StatefulWidget {
  const _ItemEditor({
    required this.initial,
    required this.validate,
    required this.onDone,
    required this.label,
  });

  final String initial;
  final String? Function(String text) validate;

  /// The text entered; null when cancelled.
  final ValueChanged<String?> onDone;
  final String label;

  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _ok() {
    final text = _controller.text.trim();
    if (text.isEmpty) return widget.onDone(null);
    final error = widget.validate(text);
    if (error != null) return setState(() => _error = error);
    widget.onDone(text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Semantics(
                  container: true,
                  textField: true,
                  label: widget.label,
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.escape): () =>
                          widget.onDone(null),
                    },
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      style: _mono,
                      cursorColor: AppColors.text,
                      onSubmitted: (_) => _ok(),
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                      decoration: _decoration(error: _error),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SettingTextButton(label: l10n.extensionSettingsOk, onTap: _ok),
            const SizedBox(width: 10),
            SettingTextButton(
              label: l10n.extensionSettingsCancel,
              onTap: () => widget.onDone(null),
            ),
          ],
        ),
        if (_error case final error?) SettingError(error),
      ],
    );
  }
}

/// A row of a list control: [child], its actions at the right on hover.
class _ListRow extends StatefulWidget {
  const _ListRow({required this.child, required this.actions});

  final Widget child;
  final List<Widget> actions;

  @override
  State<_ListRow> createState() => _ListRowState();
}

class _ListRowState extends State<_ListRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: Container(
      constraints: const BoxConstraints(minHeight: 26),
      padding: const EdgeInsets.only(left: 6, right: 2),
      decoration: BoxDecoration(
        color: _hover ? AppColors.hover : null,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(child: widget.child),
          // Kept for the semantics tree's shape; shown on hover.
          Opacity(
            opacity: _hover ? 1 : 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: widget.actions,
            ),
          ),
        ],
      ),
    ),
  );
}

/// A string array setting: its items, each editable and removable, and Add
/// Item (`ListSettingWidget`).
class SettingStringListControl extends StatefulWidget {
  const SettingStringListControl({
    super.key,
    required this.value,
    required this.schema,
    required this.onChanged,
  });

  final List<String> value;
  final Map<String, Object?> schema;
  final ValueChanged<List<String>> onChanged;

  @override
  State<SettingStringListControl> createState() =>
      _SettingStringListControlState();
}

class _SettingStringListControlState extends State<SettingStringListControl> {
  /// The item edited: its index, or the list's length when adding.
  int? _editing;

  String? _validate(String text, int index) {
    final l10n = context.l10n;
    final next = [...widget.value];
    if (index < next.length) {
      next[index] = text;
    } else {
      next.add(text);
    }
    return validateSetting(widget.schema, next, l10n);
  }

  void _done(int index, String? text) {
    setState(() => _editing = null);
    if (text == null) return;
    final next = [...widget.value];
    if (index < next.length) {
      next[index] = text;
    } else {
      next.add(text);
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, item) in items.indexed)
          _editing == i
              ? _ItemEditor(
                  initial: item,
                  label: l10n.extensionSettingsEditItem,
                  validate: (t) => _validate(t, i),
                  onDone: (t) => _done(i, t),
                )
              : _ListRow(
                  actions: [
                    SettingIconButton(
                      icon: Codicons.edit,
                      tooltip: l10n.extensionSettingsEditItem,
                      onTap: () => setState(() => _editing = i),
                    ),
                    SettingIconButton(
                      icon: Codicons.close,
                      tooltip: l10n.extensionSettingsRemoveItem,
                      onTap: () => widget.onChanged([...items]..removeAt(i)),
                    ),
                  ],
                  child: Text(item, style: _mono),
                ),
        const SizedBox(height: 4),
        if (_editing == items.length)
          _ItemEditor(
            initial: '',
            label: l10n.extensionSettingsAddItem,
            validate: (t) => _validate(t, items.length),
            onDone: (t) => _done(items.length, t),
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: SettingTextButton(
              label: l10n.extensionSettingsAddItem,
              icon: Codicons.add,
              onTap: () => setState(() => _editing = items.length),
            ),
          ),
      ],
    );
  }
}

/// An object of booleans (`files.exclude`): its keys, each with a
/// checkbox, removable, and Add Pattern (`ExcludeSettingWidget`,
/// `ObjectSettingCheckboxWidget`). A key the default has is turned off
/// rather than removed.
class SettingBooleanObjectControl extends StatefulWidget {
  const SettingBooleanObjectControl({
    super.key,
    required this.value,
    required this.defaults,
    required this.onChanged,
  });

  final Map<String, Object?> value;
  final Map<String, Object?> defaults;
  final ValueChanged<Map<String, Object?>> onChanged;

  @override
  State<SettingBooleanObjectControl> createState() =>
      _SettingBooleanObjectControlState();
}

class _SettingBooleanObjectControlState
    extends State<SettingBooleanObjectControl> {
  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final value = widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final MapEntry(:key, value: on) in value.entries)
          _ListRow(
            actions: [
              SettingIconButton(
                icon: Codicons.close,
                tooltip: l10n.extensionSettingsRemoveItem,
                onTap: () {
                  final next = {...value};
                  if (widget.defaults.containsKey(key)) {
                    next[key] = false;
                  } else {
                    next.remove(key);
                  }
                  widget.onChanged(next);
                },
              ),
            ],
            child: Row(
              children: [
                SettingCheckbox(
                  value: on != false,
                  label: key,
                  onChanged: (checked) =>
                      widget.onChanged({...value, key: checked}),
                ),
                const SizedBox(width: 8),
                Flexible(child: Text(key, style: _mono)),
                // `{ "when": "$(basename).ts" }`.
                if (on is Map && on['when'] is String) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'when: ${on['when']}',
                      style: SettingsText.description,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 4),
        if (_adding)
          _ItemEditor(
            initial: '',
            label: l10n.extensionSettingsAddPattern,
            validate: (_) => null,
            onDone: (text) {
              setState(() => _adding = false);
              if (text != null) widget.onChanged({...value, text: true});
            },
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: SettingTextButton(
              label: l10n.extensionSettingsAddPattern,
              icon: Codicons.add,
              onTap: () => setState(() => _adding = true),
            ),
          ),
      ],
    );
  }
}
