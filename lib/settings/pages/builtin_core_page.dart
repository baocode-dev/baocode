import 'dart:async';

import 'package:bao_agent/bao_agent.dart' show defaultCoreSystemPrompt;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ide/ide_button.dart';
import '../../ide/ide_input.dart';
import '../../ide/ide_menu.dart';
import '../../kernel/claude_code/claude_core_setting.dart';
import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../user_settings.dart';
import 'settings_dropdown.dart';
import 'settings_widgets.dart';

/// Settings → Built-in Core: customizes the system prompt of BaoCode's own
/// core (`claudeCode.core.systemPromptMode` and `claudeCode.core.systemPrompt`
/// in settings.json).
class BuiltinCoreSettingsPage extends StatefulWidget {
  const BuiltinCoreSettingsPage({super.key, this.settings});

  /// settings.json; none under test, where choices are not kept.
  final UserSettings? settings;

  @override
  State<BuiltinCoreSettingsPage> createState() =>
      _BuiltinCoreSettingsPageState();
}

class _BuiltinCoreSettingsPageState extends State<BuiltinCoreSettingsPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  String _committed = '';
  bool _defaultOpen = false;
  bool _copied = false;
  Timer? _copiedReset;

  UserSettings? get _settings => widget.settings;

  CoreSystemPrompt get _current => CoreSystemPrompt.parse(
    _settings?[CoreSystemPrompt.modeKey],
    _settings?[CoreSystemPrompt.textKey],
  );

  @override
  void initState() {
    super.initState();
    _syncFromSettings(force: true);
    _settings?.addListener(_onSettingsChanged);
    _focus.addListener(() {
      if (!_focus.hasFocus) _commitText();
    });
  }

  @override
  void didUpdateWidget(BuiltinCoreSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      oldWidget.settings?.removeListener(_onSettingsChanged);
      widget.settings?.addListener(_onSettingsChanged);
      _syncFromSettings(force: !_focus.hasFocus);
    }
  }

  @override
  void dispose() {
    _settings?.removeListener(_onSettingsChanged);
    _copiedReset?.cancel();
    // Keep any edits not yet blurred when the page or dialog closes.
    final text = _controller.text;
    if (text != _committed) {
      final settings = _settings;
      if (settings != null) {
        scheduleMicrotask(() => unawaited(_writeText(settings, text)));
      }
    }
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    _syncFromSettings(force: false);
    if (mounted) setState(() {});
  }

  void _syncFromSettings({required bool force}) {
    final text = _current.text;
    if (force || (text != _committed && !_focus.hasFocus)) {
      _controller.text = text;
      _committed = text;
    }
  }

  void _write(String key, Object? value) {
    final settings = _settings;
    if (settings == null) return;
    unawaited(
      settings.update(key, value).catchError((Object error) {
        debugPrint('$key not kept: $error');
      }),
    );
  }

  static Future<void> _writeText(UserSettings settings, String text) => settings
      .update(CoreSystemPrompt.textKey, text.trim().isEmpty ? null : text)
      .catchError((Object error) {
        debugPrint('${CoreSystemPrompt.textKey} not kept: $error');
      });

  void _commitText() {
    final text = _controller.text;
    if (text == _committed) return;
    _committed = text;
    final settings = _settings;
    if (settings != null) unawaited(_writeText(settings, text));
  }

  void _selectMode(CoreSystemPromptMode mode) {
    _commitText();
    _write(
      CoreSystemPrompt.modeKey,
      mode == CoreSystemPromptMode.defaultPrompt ? null : mode.setting,
    );
  }

  void _loadDefault() {
    final text = defaultCoreSystemPrompt();
    _controller.text = text;
    _committed = text;
    final settings = _settings;
    if (settings != null) unawaited(_writeText(settings, text));
    setState(() {});
  }

  void _reset() {
    _controller.clear();
    _committed = '';
    _write(CoreSystemPrompt.textKey, null);
    _write(CoreSystemPrompt.modeKey, null);
    setState(() {});
  }

  Future<void> _copyDefault() async {
    await Clipboard.setData(ClipboardData(text: defaultCoreSystemPrompt()));
    if (!mounted) return;
    _copiedReset?.cancel();
    setState(() => _copied = true);
    _copiedReset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  static String _modeLabel(AppLocalizations l10n, CoreSystemPromptMode mode) =>
      switch (mode) {
        CoreSystemPromptMode.defaultPrompt => l10n.builtinCoreModeDefault,
        CoreSystemPromptMode.append => l10n.builtinCoreModeAppend,
        CoreSystemPromptMode.replace => l10n.builtinCoreModeReplace,
      };

  static String _modeDetail(AppLocalizations l10n, CoreSystemPromptMode mode) =>
      switch (mode) {
        CoreSystemPromptMode.defaultPrompt => l10n.builtinCoreModeDefaultDetail,
        CoreSystemPromptMode.append => l10n.builtinCoreModeAppendDetail,
        CoreSystemPromptMode.replace => l10n.builtinCoreModeReplaceDetail,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final current = _current;
    final mode = current.mode;
    final modeName = _modeLabel(l10n, mode);
    final defaultPrompt = defaultCoreSystemPrompt();

    return SettingsPage(
      title: l10n.builtinCoreSettingsTitle,
      description: l10n.builtinCoreSettingsDescription,
      children: [
        SettingsGroup(
          title: l10n.builtinCoreSystemPromptGroup,
          children: [
            SettingsRow(
              label: l10n.builtinCoreSystemPromptMode,
              description: _modeDetail(l10n, mode),
              trailing: SettingsDropdown(
                current: modeName,
                semanticLabel: l10n.builtinCoreSystemPromptModeLabel(modeName),
                entries: () => [
                  for (final value in CoreSystemPromptMode.values)
                    IdeMenuAction(
                      _modeLabel(l10n, value),
                      checked: value == mode,
                      onSelected: () => _selectMode(value),
                    ),
                ],
              ),
            ),
            if (mode != CoreSystemPromptMode.defaultPrompt)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            mode == CoreSystemPromptMode.append
                                ? l10n.builtinCoreAppendLabel
                                : l10n.builtinCoreReplaceLabel,
                            style: SettingsText.label,
                          ),
                        ),
                        SettingsButtons(
                          children: [
                            if (mode == CoreSystemPromptMode.replace)
                              IdeButton(
                                label: l10n.builtinCoreLoadDefault,
                                secondary: true,
                                onPressed: _loadDefault,
                              ),
                            IdeButton(
                              label: l10n.builtinCoreResetDefault,
                              secondary: true,
                              onPressed: _reset,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    IdeInputBox(
                      controller: _controller,
                      focusNode: _focus,
                      placeholder: mode == CoreSystemPromptMode.append
                          ? l10n.builtinCoreAppendPlaceholder
                          : l10n.builtinCoreReplacePlaceholder,
                      semanticsLabel: mode == CoreSystemPromptMode.append
                          ? l10n.builtinCoreAppendLabel
                          : l10n.builtinCoreReplaceLabel,
                      minLines: 8,
                      maxLines: 16,
                    ),
                  ],
                ),
              ),
          ],
        ),
        SettingsFolding(
          title: l10n.builtinCoreDefaultPromptTitle,
          description: l10n.builtinCoreDefaultPromptDescription,
          open: _defaultOpen,
          onToggle: () => setState(() => _defaultOpen = !_defaultOpen),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: IdeButton(
                      label: _copied
                          ? l10n.builtinCoreCopiedDefault
                          : l10n.builtinCoreCopyDefault,
                      icon: _copied ? Codicons.check : Codicons.copy,
                      secondary: true,
                      onPressed: () => unawaited(_copyDefault()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(defaultPrompt, style: SettingsText.path),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
