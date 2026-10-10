/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Settings → Keyboard Shortcuts: every keybinding in effect and every
// command without one, searched by text or by keys recorded, and changed in
// the user's keybindings.json: a key recorded in a dialog, a `when` typed in
// place, a keybinding removed, a command reset. The keymap in use and an
// import from VS Code or Cursor are above.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/preferences/browser/keybindingsEditor.ts
// (`KeybindingsEditor`: the search and its `recordKeysAction`, the table's
// columns, `onContextMenu` and its actions, `defineKeybinding`,
// `updateKeybinding`, `copyKeybinding`, `showSimilarKeybindings`),
// keybindingWidgets.ts (`KeybindingsSearchWidget`'s recording,
// `DefineKeybindingWidget`), preferences.contribution.ts (the table's keys)
// and src/vs/workbench/services/preferences/browser/keybindingsEditorModel.ts
// (`KeybindingsEditorModel.resolve`: the unbound commands, the sources and
// `compareKeybindingData`).
//
// Deviations:
// - The search matches each word anywhere in a row (its title, command,
//   key, `when` or source), without highlights; a quoted key (`"cmd+k"`, as
//   recording writes it) shows the keybindings starting with it. No
//   `@command:`, `@source:`, `@ext:` or `@keybinding:` filters, no sort by
//   precedence and no search history.
// - The command's id is always under its title. Keybindings of commands
//   BaoCode does not have, keys that do not parse and `when` clauses that
//   never hold (unknown context keys, or not parsing) are marked; upstream
//   reports those in keybindings.json only.
// - Keys are recorded in a small modal dialog, not an overlay on the table;
//   clicking its count of existing commands filters the table behind it. The
//   `when` input has no suggestions.
// - The keymap picker and the import are BaoCode's (upstream installs keymap
//   extensions).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ide/ide_button.dart';
import '../../ide/ide_hover.dart';
import '../../ide/ide_input.dart';
import '../../ide/ide_list.dart';
import '../../ide/ide_menu.dart';
import '../../ide/ide_quick_input.dart' show IdeKeycap;
import '../../chat/widgets/scroll_edge_fade.dart';
import '../../keybindings/default_keybindings.dart';
import '../../keybindings/key_chord.dart';

import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';

import '../../keybindings/keybinding_service.dart';
import '../../keybindings/keybindings_editing.dart';
import '../../l10n/command_titles.dart';
import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../jsonc_file.dart' show JsoncFileException;
import 'settings_dropdown.dart';
import 'settings_widgets.dart' show SettingsColors;

/// A keymap [KeybindingsSettingsPage] offers.
typedef KeymapChoice = ({String id, String name});

/// The Keyboard Shortcuts page of the settings dialog.
class KeybindingsSettingsPage extends StatefulWidget {
  const KeybindingsSettingsPage({
    super.key,
    required this.keybindings,
    required this.editing,
    this.keymaps = const [],
    this.onSelectKeymap,
    this.onImport,
  });

  /// The keybindings shown: the page follows its changes.
  final KeybindingService keybindings;

  /// Writes the changes into the user's keybindings.json.
  final KeybindingsEditingService editing;

  /// The keymaps to pick from, besides None.
  final List<KeymapChoice> keymaps;

  /// Makes keymap [id] the one in use; null for none.
  final FutureOr<void> Function(String? id)? onSelectKeymap;

  /// Opens the import from VS Code or Cursor.
  final VoidCallback? onImport;

  /// A row: the title, and the command's id under it.
  static const rowHeight = 38.0;

  @override
  State<KeybindingsSettingsPage> createState() =>
      _KeybindingsSettingsPageState();
}

/// One row: a keybinding, or a command without one ([item] null).
@immutable
class _Row {
  _Row({
    required this.command,
    required this.info,
    required this.supported,
    required this.userEntries,
    required this.order,
    required KeybindingPlatform platform,
    required Set<String> contextKeys,
    required AppLocalizations l10n,
    this.item,
  }) : title = switch (info) {
         final info? => localizedCommandTitleOf(
           l10n,
           command,
           info.title,
           category: info.category,
         ),
         null => '',
       },
       englishTitle = info?.label ?? '',
       keys = item?.keys,
       keyError = item?.keyError(platform),
       keyText =
           item?.keys?.userSettingsLabel(platform) ?? item?.keyError(platform),
       keyLabel = item?.keys?.label(platform),
       when = switch (item?.entry.when?.trim()) {
         final String text when text.isNotEmpty => text,
         _ => null,
       },
       whenProblem = _whenProblem(item, contextKeys, l10n),
       source = switch (item?.source) {
         KeybindingSource.defaults => 'Default',
         KeybindingSource.keymap => item!.keymapName ?? 'Keymap',
         KeybindingSource.user => 'User',
         // As upstream: a command whose default the user removed is theirs.
         null => userEntries ? 'User' : 'Default',
       },
       sourceLabel = switch (item?.source) {
         KeybindingSource.defaults => l10n.kbSourceDefault,
         KeybindingSource.keymap => item!.keymapName ?? l10n.kbKeymap,
         KeybindingSource.user => l10n.kbSourceUser,
         null => userEntries ? l10n.kbSourceUser : l10n.kbSourceDefault,
       };

  final String command;
  final CommandInfo? info;
  final KeybindingItem? item;

  /// Whether BaoCode has the command.
  final bool supported;

  /// Whether the user's file has entries of the command (for Reset).
  final bool userEntries;

  /// Where the resolver has it, for a stable sort.
  final int order;
  final KeySequence? keys;

  /// The key text that does not parse.
  final String? keyError;

  /// As keybindings.json writes it (`shift+cmd+e`), or the text that does
  /// not parse; null without a key.
  final String? keyText;

  /// As the UI shows it (`⇧⌘E`).
  final String? keyLabel;
  final String? when;

  /// Why its `when` never holds; null when it may.
  final String? whenProblem;

  /// Where it comes from, in English: part of its [id].
  final String source;

  /// [source] as the page shows it.
  final String sourceLabel;

  /// `Category: Title` in the display language; empty for a command BaoCode
  /// does not have.
  final String title;

  /// [title] in English, which the search also finds.
  final String englishTitle;

  /// Upstream `getId`: the same keybinding twice is one row.
  String get id => idOf(command, keyText, when, source);

  static String idOf(
    String command,
    String? keyText,
    String? when,
    String source,
  ) => '$command\u0000${keyText ?? ''}\u0000${when ?? ''}\u0000$source';

  /// Has a key here (one that parses or not).
  bool get bound => keyText != null;

  bool get isUser => item?.source == KeybindingSource.user;

  /// What the search looks through, lowercased.
  late final String haystack = [
    title,
    englishTitle,
    command,
    ?keyLabel,
    ?keyText,
    ?when,
    source,
    sourceLabel,
  ].join('\n').toLowerCase();

  static String? _whenProblem(
    KeybindingItem? item,
    Set<String> known,
    AppLocalizations l10n,
  ) {
    final when = item?.when;
    if (item == null || when == null) return null;
    if (when.error case final error?) return l10n.kbWhenNotParse(error);
    final unknown = item.unknownContextKeys(known).toList()..sort();
    if (unknown.isEmpty) return null;
    return l10n.kbUnknownContextKeys(unknown.length, unknown.join(', '));
  }
}

/// The page's rows: the keybindings in effect with a key here, then the
/// commands without any (upstream `KeybindingsEditorModel.resolve`), sorted
/// as upstream's `compareKeybindingData` sorts them.
List<_Row> _rowsOf(KeybindingService service, AppLocalizations l10n) {
  final platform = service.platform;
  final userCommands = {
    for (final entry in service.userEntries) entry.commandId,
  };
  _Row row(String command, KeybindingItem? item, int order) => _Row(
    command: command,
    info: commandCatalog[command],
    supported: service.isSupported(command),
    userEntries: userCommands.contains(command),
    order: order,
    platform: platform,
    contextKeys: service.contextKeys,
    l10n: l10n,
    item: item,
  );
  final rows = <_Row>[];
  final ids = <String>{};
  final bound = <String>{};
  for (final (index, item) in service.resolver(platform).items.indexed) {
    // None for this platform: it does nothing here.
    if (item.keys == null && item.keyError(platform) == null) continue;
    final keybinding = row(item.command, item, index);
    if (!ids.add(keybinding.id)) continue;
    rows.add(keybinding);
    bound.add(item.command);
  }
  var order = rows.length;
  for (final command in commandCatalog.keys) {
    if (!bound.contains(command)) rows.add(row(command, null, order++));
  }
  rows.sort(_compareRows);
  return rows;
}

int _compareRows(_Row a, _Row b) {
  if (a.bound != b.bound) return a.bound ? -1 : 1;
  final (aTitle, bTitle) = (a.title, b.title);
  if (aTitle.isNotEmpty != bTitle.isNotEmpty) return aTitle.isNotEmpty ? -1 : 1;
  if (aTitle != bTitle) {
    final byTitle = aTitle.toLowerCase().compareTo(bTitle.toLowerCase());
    return byTitle != 0 ? byTitle : aTitle.compareTo(bTitle);
  }
  if (a.command == b.command) {
    if (a.isUser != b.isUser) return a.isUser ? -1 : 1;
    return a.order - b.order;
  }
  return a.command.compareTo(b.command);
}

/// The rows [query] finds: those with every word of it, or with a key
/// starting with the quoted key (`"cmd+k"`).
List<_Row> _filterRows(List<_Row> rows, String query) {
  final text = query.trim();
  if (text.isEmpty) return rows;
  if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
    final quoted = text.substring(1, text.length - 1).trim();
    if (KeySequence.parse(quoted) case final keys?) {
      return [
        for (final row in rows)
          if (row.keys case final own?
              when own.chords.length >= keys.chords.length &&
                  listEquals(
                    own.chords.sublist(0, keys.chords.length),
                    keys.chords,
                  ))
            row,
      ];
    }
    final label = quoted.toLowerCase();
    return [
      for (final row in rows)
        if (row.keyLabel?.toLowerCase() == label) row,
    ];
  }
  final words = text.toLowerCase().split(RegExp(r'\s+'));
  return [
    for (final row in rows)
      if (words.every(row.haystack.contains)) row,
  ];
}

class _KeybindingsSettingsPageState extends State<KeybindingsSettingsPage> {
  final _search = TextEditingController();
  late final _searchFocus = FocusNode(
    debugLabel: 'Keybindings search',
    onKeyEvent: _searchKey,
  );
  late final _listFocus = FocusNode(
    debugLabel: 'Keybindings',
    onKeyEvent: _listKey,
  );
  final _scroll = ScrollController();
  final _when = TextEditingController();
  final _whenFocus = FocusNode(debugLabel: 'Keybinding when');

  List<_Row> _rows = const [];
  List<_Row> _shown = const [];

  /// The selected row's [_Row.id].
  String? _selected;

  /// Key presses go into the search as keys (upstream `recordKeysAction`).
  bool _recording = false;
  List<KeyChord> _chords = const [];

  /// The row whose `when` is being typed.
  String? _editingWhen;

  /// Why the last change failed.
  String? _error;

  /// The language the rows are in.
  AppLocalizations _l10n = englishLocalizations;

  KeybindingService get _keybindings => widget.keybindings;
  KeybindingPlatform get _platform => _keybindings.platform;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = context.l10n;
    if (identical(l10n, _l10n)) return;
    _l10n = l10n;
    _update();
  }

  @override
  void initState() {
    super.initState();
    _keybindings.addListener(_keybindingsChanged);
    _listFocus.addListener(_focusChanged);
    _whenFocus.addListener(_whenFocusChanged);
    _update();
  }

  @override
  void didUpdateWidget(KeybindingsSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keybindings != widget.keybindings) {
      oldWidget.keybindings.removeListener(_keybindingsChanged);
      widget.keybindings.addListener(_keybindingsChanged);
      _update();
    }
  }

  @override
  void dispose() {
    _keybindings.removeListener(_keybindingsChanged);
    _search.dispose();
    _searchFocus.dispose();
    _listFocus.dispose();
    _scroll.dispose();
    _when.dispose();
    _whenFocus.dispose();
    super.dispose();
  }

  void _update() {
    _rows = _rowsOf(_keybindings, _l10n);
    _shown = _filterRows(_rows, _search.text);
  }

  void _keybindingsChanged() {
    if (mounted) setState(_update);
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  // --- Search ---------------------------------------------------------------

  void _setSearch(String text) {
    _search.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() => _shown = _filterRows(_rows, text));
  }

  void _searchChanged(String text) {
    if (_recording) {
      // Typing adds nothing while recording (upstream `setInputValue`).
      _setSearch(_recordedText);
      return;
    }
    setState(() => _shown = _filterRows(_rows, text));
  }

  String get _recordedText => _chords.isEmpty
      ? ''
      : '"${KeySequence(_chords).userSettingsLabel(_platform)}"';

  void _setRecording(bool recording) {
    setState(() {
      _recording = recording;
      _chords = const [];
    });
    _searchFocus.requestFocus();
  }

  /// ⌥⌘K (Alt+K elsewhere) in the search: Record Keys.
  KeyChord get _recordKeysChord => KeyChord(
    LogicalKeyboardKey.keyK,
    alt: true,
    meta: _platform == KeybindingPlatform.mac,
  );

  /// While recording, each key pressed (upstream
  /// `KeybindingsSearchWidget.printKeybinding`): two chords at most, a third
  /// starting over; Escape stops.
  KeyEventResult _searchKey(FocusNode node, KeyEvent event) {
    if (!_recording) {
      if (event is KeyDownEvent &&
          KeyChord.fromEvent(event) == _recordKeysChord) {
        _setRecording(true);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final chord = KeyChord.fromEvent(event);
    if (chord == null) return KeyEventResult.handled;
    if (chord == const KeyChord(LogicalKeyboardKey.escape)) {
      _setRecording(false);
      return KeyEventResult.handled;
    }
    _chords = [if (_chords.length < 2) ..._chords, chord];
    _setSearch(_recordedText);
    return KeyEventResult.handled;
  }

  // --- The table --------------------------------------------------------------

  int get _selectedIndex {
    final selected = _selected;
    if (selected == null) return -1;
    return _shown.indexWhere((row) => row.id == selected);
  }

  void _select(int index, {bool reveal = true}) {
    if (_shown.isEmpty) return;
    final clamped = index.clamp(0, _shown.length - 1);
    setState(() => _selected = _shown[clamped].id);
    if (reveal) _reveal(clamped);
  }

  /// Scrolls row [index] into view.
  void _reveal(int index) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    const height = KeybindingsSettingsPage.rowHeight;
    final top = index * height;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (top + height > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(
        (top + height - position.viewportDimension).clamp(
          0,
          position.maxScrollExtent,
        ),
      );
    }
  }

  /// Selects [id] once the rows have it (after a change), else the row at
  /// [fallback]; and brings the keys back to the table.
  void _reselect(String? id, int fallback) {
    if (!mounted) return;
    final index = id == null ? -1 : _shown.indexWhere((row) => row.id == id);
    if (index >= 0) {
      _select(index);
    } else if (_selectedIndex < 0 && fallback >= 0) {
      _select(fallback);
    }
    _listFocus.requestFocus();
  }

  /// The table's keys (preferences.contribution.ts): arrows, Enter to
  /// change, Delete (⌘Backspace on macOS) to remove.
  KeyEventResult _listKey(FocusNode node, KeyEvent event) {
    // Not the `when` input's.
    if (!node.hasPrimaryFocus || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final chord = KeyChord.fromEvent(event);
    if (chord == null) return KeyEventResult.ignored;
    final index = _selectedIndex;
    final row = index < 0 ? null : _shown[index];
    final page =
        (_scroll.hasClients
                ? _scroll.position.viewportDimension ~/
                      KeybindingsSettingsPage.rowHeight
                : 10)
            .clamp(1, 1000);
    final mac = _platform == KeybindingPlatform.mac;
    const plain = KeyChord.new;
    if (chord == plain(LogicalKeyboardKey.arrowDown)) {
      _select(index + 1);
    } else if (chord == plain(LogicalKeyboardKey.arrowUp)) {
      if (index <= 0) {
        _searchFocus.requestFocus();
      } else {
        _select(index - 1);
      }
    } else if (chord == plain(LogicalKeyboardKey.pageDown)) {
      _select(index + page);
    } else if (chord == plain(LogicalKeyboardKey.pageUp)) {
      _select(index < 0 ? 0 : index - page);
    } else if (chord == plain(LogicalKeyboardKey.home)) {
      _select(0);
    } else if (chord == plain(LogicalKeyboardKey.end)) {
      _select(_shown.length - 1);
    } else if (chord == plain(LogicalKeyboardKey.enter) &&
        event is KeyDownEvent) {
      if (row != null) unawaited(_define(row));
    } else if ((mac
            ? chord == plain(LogicalKeyboardKey.backspace, meta: true)
            : chord == plain(LogicalKeyboardKey.delete)) &&
        event is KeyDownEvent) {
      if (row != null && _canRemove(row)) unawaited(_remove(row, index));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // --- Changes ----------------------------------------------------------------

  /// Runs [change], showing why it failed; whether it did not.
  Future<bool> _run(FutureOr<void> Function() change) async {
    try {
      await change();
      if (mounted && _error != null) setState(() => _error = null);
      return true;
    } on JsoncFileException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = context.l10n.kbChangeFailed('$error'));
      }
    }
    return false;
  }

  /// Records a key for [row] and binds it (upstream `defineKeybinding`):
  /// instead of its key, or as well when [add].
  Future<void> _define(_Row row, {bool add = false}) async {
    final index = _shown.indexOf(row);
    if (index >= 0) _select(index);
    final keys = await showDefineKeybindingDialog(
      context,
      keybindings: _keybindings,
      onShowExisting: (keys) =>
          _setSearch('"${keys.userSettingsLabel(_platform)}"'),
    );
    if (!mounted) return;
    if (keys == null) {
      _listFocus.requestFocus();
      return;
    }
    final item = row.item;
    final done = await _run(
      () => item == null || add
          ? widget.editing.addKeybinding(
              row.command,
              keys,
              when: item?.entry.when,
              args: item?.args,
            )
          : widget.editing.editKeybinding(item, keys),
    );
    _reselect(
      done
          ? _Row.idOf(
              row.command,
              keys.userSettingsLabel(_platform),
              row.when,
              'User',
            )
          : null,
      index,
    );
  }

  bool _canRemove(_Row row) =>
      row.keys != null || (row.item != null && row.isUser);

  Future<void> _remove(_Row row, int index) async {
    final item = row.item;
    if (item == null) return;
    await _run(() => widget.editing.removeKeybinding(item));
    _reselect(null, index);
  }

  Future<void> _reset(_Row row, int index) async {
    await _run(() => widget.editing.resetKeybinding(row.command));
    _reselect(null, index);
  }

  bool _canChangeWhen(_Row row) =>
      row.keys != null || (row.item != null && row.isUser);

  /// Types [row]'s `when` in place (upstream `defineWhenExpression`).
  void _defineWhen(_Row row) {
    final index = _shown.indexOf(row);
    if (index < 0) return;
    _select(index);
    setState(() {
      _editingWhen = row.id;
      _when.value = TextEditingValue(
        text: row.when ?? '',
        selection: TextSelection(
          baseOffset: 0,
          extentOffset: row.when?.length ?? 0,
        ),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editingWhen == row.id) _whenFocus.requestFocus();
    });
  }

  Future<void> _acceptWhen(_Row row) async {
    if (_editingWhen != row.id) return;
    final text = _when.text.trim();
    setState(() => _editingWhen = null);
    _listFocus.requestFocus();
    final item = row.item;
    if (item == null) return;
    final index = _shown.indexOf(row);
    final done = await _run(() => widget.editing.changeWhen(item, text));
    _reselect(
      done
          ? _Row.idOf(
              row.command,
              row.keyText,
              text.isEmpty ? null : text,
              'User',
            )
          : null,
      index,
    );
  }

  void _rejectWhen() {
    if (_editingWhen == null) return;
    setState(() => _editingWhen = null);
    _listFocus.requestFocus();
  }

  /// Leaving the input drops what was typed (upstream: on blur).
  void _whenFocusChanged() {
    if (!_whenFocus.hasFocus && _editingWhen != null) {
      setState(() => _editingWhen = null);
    }
  }

  // --- The context menu ---------------------------------------------------------

  Future<void> _contextMenu(_Row row, int index, Offset position) async {
    _select(index, reveal: false);
    _listFocus.requestFocus();
    final mac = _platform == KeybindingPlatform.mac;
    final bound = row.bound;
    final l10n = context.l10n;
    await showIdeMenu(
      context,
      position: position,
      entries: ideMenuGroups([
        [
          IdeMenuAction(l10n.commonCopy, onSelected: () => _copy(row)),
          IdeMenuAction(
            l10n.kbCopyCommandId,
            onSelected: () => _copyText(row.command),
          ),
          IdeMenuAction(
            l10n.kbCopyCommandTitle,
            enabled: row.title.isNotEmpty,
            onSelected: () => _copyText(row.title),
          ),
        ],
        [
          IdeMenuAction(
            bound
                ? l10n.kbChangeKeybindingEllipsis
                : l10n.kbAddKeybindingEllipsis,
            keybinding: const KeyChord(LogicalKeyboardKey.enter)
                .label(_platform),
            onSelected: () => unawaited(_define(row)),
          ),
          if (bound)
            IdeMenuAction(
              l10n.kbAddKeybindingEllipsis,
              onSelected: () => unawaited(_define(row, add: true)),
            ),
        ],
        [
          IdeMenuAction(
            l10n.kbRemoveKeybinding,
            enabled: _canRemove(row),
            keybinding:
                (mac
                        ? const KeyChord(
                            LogicalKeyboardKey.backspace,
                            meta: true,
                          )
                        : const KeyChord(LogicalKeyboardKey.delete))
                    .label(_platform),
            onSelected: () => unawaited(_remove(row, index)),
          ),
          IdeMenuAction(
            l10n.kbResetKeybinding,
            enabled: row.isUser || row.userEntries,
            onSelected: () => unawaited(_reset(row, index)),
          ),
        ],
        [
          IdeMenuAction(
            l10n.kbChangeWhen,
            enabled: _canChangeWhen(row),
            onSelected: () => _defineWhen(row),
          ),
        ],
        [
          IdeMenuAction(
            l10n.kbShowSame,
            enabled: row.keys != null,
            onSelected: () =>
                _setSearch('"${row.keys!.userSettingsLabel(_platform)}"'),
          ),
        ],
      ]),
    );
  }

  /// Upstream `copyKeybinding`: the entry as keybindings.json has it.
  void _copy(_Row row) => _copyText(
    const JsonEncoder.withIndent('  ').convert({
      'key': row.keyText ?? '',
      'command': row.command,
      'when': ?row.when,
    }),
  );

  void _copyText(String text) =>
      unawaited(Clipboard.setData(ClipboardData(text: text)));

  // --- Building -----------------------------------------------------------------

  static const _inset = 24.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = _Columns(constraints.maxWidth - 2 * _inset);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Room at the right for the dialog's close button.
          Padding(
            padding: const EdgeInsets.fromLTRB(_inset, 16, 48, 0),
            child: Text(
              context.l10n.settingsSectionKeyboard,
              style: TextStyle(
                color: SettingsColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _inset),
            child: _toolbar(),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _inset),
            child: _searchBox(),
          ),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.fromLTRB(_inset, 8, _inset, 0),
              child: _ErrorBanner(
                message: error,
                onClose: () => setState(() => _error = null),
              ),
            ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _inset),
            child: _header(columns),
          ),
          Expanded(child: _table(columns)),
        ],
      );
    },
  );

  Widget _toolbar() {
    final l10n = context.l10n;
    final keymapId = _keybindings.keymapId;
    final current = keymapId == null
        ? l10n.kbNone
        : widget.keymaps.where((k) => k.id == keymapId).firstOrNull?.name ??
              _keybindings.keymapName ??
              keymapId;
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.kbKeymap,
              style: TextStyle(
                color: SettingsColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 8),
            SettingsDropdown(
              current: current,
              semanticLabel: l10n.kbKeymapLabel(current),
              entries: () => [
                IdeMenuAction(
                  l10n.kbNone,
                  checked: keymapId == null,
                  onSelected: () => _selectKeymap(null),
                ),
                for (final keymap in widget.keymaps)
                  IdeMenuAction(
                    keymap.name,
                    checked: keymap.id == keymapId,
                    onSelected: () => _selectKeymap(keymap.id),
                  ),
              ],
            ),
          ],
        ),
        IdeButton(
          label: l10n.kbImport,
          secondary: true,
          onPressed: widget.onImport,
        ),
      ],
    );
  }

  void _selectKeymap(String? id) {
    final select = widget.onSelectKeymap;
    if (select == null || id == _keybindings.keymapId) return;
    unawaited(_run(() => select(id)));
  }

  Widget _searchBox() => IdeInputBox(
    controller: _search,
    focusNode: _searchFocus,
    placeholder: _recording
        ? context.l10n.kbRecordingPlaceholder
        : context.l10n.kbSearchPlaceholder,
    semanticsLabel: context.l10n.kbSearchLabel,
    onChanged: _searchChanged,
    shortcuts: {
      const SingleActivator(LogicalKeyboardKey.arrowDown): () {
        if (_selectedIndex < 0) _select(0);
        _listFocus.requestFocus();
      },
    },
    togglesInset: 2,
    toggles: [
      if (_recording) const _RecordingBadge(),
      IdeInputToggle(
        icon: Codicons.recordKeys,
        tooltip: context.l10n.kbRecordKeys(_recordKeysChord.label(_platform)),
        checked: _recording,
        onChanged: _setRecording,
      ),
    ],
  );

  Widget _header(_Columns columns) {
    Widget label(String text) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: _Columns.cellPadding),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: SettingsColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return Container(
      height: 26,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.partBorder)),
      ),
      child: Row(
        children: [
          const SizedBox(width: _Columns.actions),
          Expanded(
            flex: _Columns.commandFlex,
            child: label(context.l10n.kbColumnCommand),
          ),
          SizedBox(
            width: columns.keybinding,
            child: label(context.l10n.kbColumnKeybinding),
          ),
          Expanded(
            flex: _Columns.whenFlex,
            child: label(context.l10n.kbColumnWhen),
          ),
          if (columns.source > 0)
            SizedBox(
              width: columns.source,
              child: label(context.l10n.kbColumnSource),
            ),
        ],
      ),
    );
  }

  Widget _table(_Columns columns) {
    if (_shown.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(_inset),
        child: Text(
          context.l10n.kbNoneFound,
          style: TextStyle(color: SettingsColors.textSecondary, fontSize: 12),
        ),
      );
    }
    return Focus(
      focusNode: _listFocus,
      child: ScrollEdgeFade(
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(
            _inset - IdeListColors.inset,
            4,
            _inset - IdeListColors.inset,
            12,
          ),
          itemExtent: KeybindingsSettingsPage.rowHeight,
          itemCount: _shown.length,
          itemBuilder: (context, index) => _rowAt(index, columns),
        ),
      ),
    );
  }

  Widget _rowAt(int index, _Columns columns) {
    final row = _shown[index];
    final selected = row.id == _selected;
    final focused = _listFocus.hasFocus;
    return IdeListRow(
      key: ValueKey(row.id),
      height: KeybindingsSettingsPage.rowHeight,
      selected: selected,
      focused: focused,
      onTap: () {
        _select(index, reveal: false);
        _listFocus.requestFocus();
      },
      onDoubleTap: () => unawaited(_define(row)),
      onContextMenu: (position) =>
          unawaited(_contextMenu(row, index, position)),
      builder: (context, hovered) {
        final foreground = selected && focused
            ? IdeListColors.activeSelectionForeground
            : IdeListColors.foreground;
        return Row(
          children: [
            SizedBox(
              width: _Columns.actions,
              child: hovered || selected
                  ? IdeActionButton(
                      icon: row.bound ? Codicons.edit : Codicons.add,
                      tooltip: row.bound
                          ? context.l10n.kbChangeKeybinding
                          : context.l10n.kbAddKeybinding,
                      size: 20,
                      onPressed: () => unawaited(_define(row)),
                    )
                  : null,
            ),
            Expanded(
              flex: _Columns.commandFlex,
              child: _commandCell(row, foreground),
            ),
            SizedBox(width: columns.keybinding, child: _keybindingCell(row)),
            Expanded(
              flex: _Columns.whenFlex,
              child: _whenCell(row, foreground),
            ),
            if (columns.source > 0)
              SizedBox(
                width: columns.source,
                child: _cell(
                  Text(
                    row.sourceLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: IdeListColors.description,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  static Widget _cell(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: _Columns.cellPadding),
    child: Align(alignment: Alignment.centerLeft, child: child),
  );

  Widget _commandCell(_Row row, Color foreground) {
    final faint = !row.supported;
    final title = row.title.isEmpty ? row.command : row.title;
    return _cell(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: faint ? AppColors.textFaint : foreground,
                    fontSize: 13,
                    height: 17 / 13,
                  ),
                ),
              ),
              if (!row.supported) ...[
                const SizedBox(width: 6),
                const _NotSupportedTag(),
              ],
            ],
          ),
          if (row.title.isNotEmpty)
            Text(
              row.command,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: faint ? AppColors.textFaint : IdeListColors.description,
                fontSize: 11,
                height: 14 / 11,
              ),
            ),
        ],
      ),
    );
  }

  Widget _keybindingCell(_Row row) {
    if (row.keys case final keys?) {
      Widget keycaps = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, chord) in keys.chords.indexed) ...[
            if (index > 0) const SizedBox(width: 4),
            IdeKeycap(chord.label(_platform)),
          ],
        ],
      );
      if (!row.supported) keycaps = Opacity(opacity: .5, child: keycaps);
      return _cell(
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: keycaps,
        ),
      );
    }
    if (row.keyError case final text?) {
      return _cell(
        Row(
          children: [
            _WarningIcon(message: context.l10n.kbCannotReadKey(text)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: themeColors['errorForeground'],
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _whenCell(_Row row, Color foreground) {
    if (_editingWhen == row.id) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Center(
          child: IdeInputBox(
            controller: _when,
            focusNode: _whenFocus,
            autofocus: true,
            fontSize: 12,
            lineHeight: 16,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            placeholder: context.l10n.kbColumnWhen,
            semanticsLabel: context.l10n.kbWhenLabel,
            onSubmitted: (_) => unawaited(_acceptWhen(row)),
            shortcuts: {
              const SingleActivator(LogicalKeyboardKey.escape): _rejectWhen,
            },
          ),
        ),
      );
    }
    final when = row.when;
    if (when == null) return const SizedBox.shrink();
    return _cell(
      Row(
        children: [
          if (row.whenProblem case final problem?) ...[
            _WarningIcon(message: problem),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              when,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: row.supported ? foreground : AppColors.textFaint,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The table's column widths for a [width] wide page: the Source column
/// goes first when it narrows.
class _Columns {
  _Columns(double width)
    : keybinding = (width * .24).clamp(110.0, 170.0),
      source = width >= 560 ? 96 : 0;

  /// The row's change button.
  static const actions = 24.0;
  static const cellPadding = 6.0;
  static const commandFlex = 5;
  static const whenFlex = 4;

  final double keybinding;

  /// Zero: not shown.
  final double source;
}

/// "Recording Keys", beside the toggle while it is on.
class _RecordingBadge extends StatelessWidget {
  const _RecordingBadge();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(right: 4),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: IdeListColors.badgeBackground,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      context.l10n.kbRecordingKeys,
      style: TextStyle(
        color: IdeListColors.badgeForeground,
        fontSize: 10,
        height: 1.2,
      ),
    ),
  );
}

class _NotSupportedTag extends StatelessWidget {
  const _NotSupportedTag();

  @override
  Widget build(BuildContext context) => IdeHover(
    message: context.l10n.kbNotSupportedHover,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: AppColors.partBorder),
      ),
      child: Text(
        context.l10n.kbNotSupported,
        style: TextStyle(
          color: SettingsColors.textSecondary,
          fontSize: 10.5,
          height: 15 / 10.5,
        ),
      ),
    ),
  );
}

/// A warning mark, [message] in its hover.
class _WarningIcon extends StatelessWidget {
  const _WarningIcon({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => IdeHover(
    message: message,
    child: Icon(
      Codicons.warning,
      size: 14,
      color: themeColors['editorWarning.foreground'],
    ),
  );
}

/// Why the last change failed, until closed.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 2, 4),
      decoration: BoxDecoration(
        color: colors['inputValidation.errorBackground'],
        border: Border.all(color: colors['inputValidation.errorBorder']),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(Codicons.error, size: 14, color: colors['errorForeground']),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: colors['inputValidation.errorForeground'],
                fontSize: 12,
              ),
            ),
          ),
          IdeActionButton(
            icon: Codicons.close,
            tooltip: context.l10n.commonClose,
            size: 20,
            iconSize: 14,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

// --- Recording a keybinding ---------------------------------------------------

/// Asks for a key sequence (upstream `DefineKeybindingWidget`): what is
/// pressed, up to two chords, until Enter; null when Escape (with nothing
/// pressed) or a click outside cancels. [onShowExisting] gets the keys when
/// the count of commands that have them is clicked.
Future<KeySequence?> showDefineKeybindingDialog(
  BuildContext context, {
  required KeybindingService keybindings,
  ValueChanged<KeySequence>? onShowExisting,
}) => showGeneralDialog<KeySequence>(
  context: context,
  barrierDismissible: true,
  barrierLabel: context.l10n.commonDismiss,
  barrierColor: const Color(0x33000000),
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) => DefineKeybindingDialog(
    keybindings: keybindings,
    onShowExisting: onShowExisting,
  ),
);

/// [showDefineKeybindingDialog]'s dialog. Its focus takes every key before
/// any shortcut does: the chat's skip while a dialog is over them, the
/// IDE's are further up the focus tree.
class DefineKeybindingDialog extends StatefulWidget {
  const DefineKeybindingDialog({
    super.key,
    required this.keybindings,
    this.onShowExisting,
  });

  final KeybindingService keybindings;
  final ValueChanged<KeySequence>? onShowExisting;

  @override
  State<DefineKeybindingDialog> createState() => _DefineKeybindingDialogState();
}

class _DefineKeybindingDialogState extends State<DefineKeybindingDialog> {
  final _focus = FocusNode(debugLabel: 'Define keybinding');
  List<KeyChord> _chords = const [];

  KeybindingPlatform get _platform => widget.keybindings.platform;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final chord = KeyChord.fromEvent(event);
    if (chord == null) return KeyEventResult.handled;
    if (chord == const KeyChord(LogicalKeyboardKey.enter)) {
      Navigator.of(
        context,
      ).pop(_chords.isEmpty ? null : KeySequence(List.unmodifiable(_chords)));
    } else if (chord == const KeyChord(LogicalKeyboardKey.escape)) {
      // Upstream `clearOrHide`.
      if (_chords.isEmpty) {
        Navigator.of(context).pop();
      } else {
        setState(() => _chords = const []);
      }
    } else {
      setState(() => _chords = [if (_chords.length < 2) ..._chords, chord]);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final keys = _chords.isEmpty ? null : KeySequence(_chords);
    final existing = keys == null
        ? 0
        : widget.keybindings.resolver().itemsWithKeys(keys).length;
    final foreground = colors['editorWidget.foreground'];
    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors['editorWidget.background'],
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color:
                    colors.get('editorWidget.border') ?? AppColors.partBorder,
              ),
              boxShadow: [
                BoxShadow(
                  color: colors['widget.shadow'],
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.l10n.kbPressKeys,
                  style: TextStyle(color: foreground, fontSize: 13),
                ),
                const SizedBox(height: 8),
                // The input upstream records into.
                Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: IdeInputColors.background,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: IdeInputColors.focusBorder),
                  ),
                  child: Text(
                    keys?.userSettingsLabel(_platform) ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: IdeInputColors.foreground,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 22,
                  child: Row(
                    children: [
                      for (final (index, chord) in _chords.indexed) ...[
                        if (index > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              context.l10n.kbChordTo,
                              style: TextStyle(color: foreground, fontSize: 12),
                            ),
                          ),
                        IdeKeycap(chord.label(_platform)),
                      ],
                    ],
                  ),
                ),
                if (existing > 0 && keys != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => widget.onShowExisting?.call(keys),
                        child: Text(
                          context.l10n.kbExistingCommands(existing),
                          style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
