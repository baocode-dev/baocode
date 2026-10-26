// How diffs show, as JetBrains IDEs' diff viewer offers it from its
// toolbar: side by side, unified or by the width; whitespace not ignored,
// at the ends of lines or anywhere; the changes highlighted by character, word, line or
// not at all. One choice for every diff (the Git log's, the side panel's,
// the editor's diff tabs), kept in settings.json.

import 'package:flutter/foundation.dart';

import 'package:bao_editor/monaco/flutter/diff_editor_model.dart';

import '../settings/user_settings.dart';

/// `diffEditor.layout`: how the two sides show.
enum IdeDiffLayout { auto, sideBySide, unified }

/// What whitespace a diff ignores: none, at the ends of lines, any.
enum IdeDiffWhitespace { none, trim, all }

class IdeDiffOptions extends ChangeNotifier {
  IdeDiffOptions._();

  static final IdeDiffOptions instance = IdeDiffOptions._();

  static const _layoutKey = 'diffEditor.layout';
  static const _whitespaceKey = 'diffEditor.ignoreTrimWhitespace';
  static const _allWhitespaceKey = 'baocode.diff.ignoreAllWhitespace';
  static const _highlightKey = 'diffEditor.highlight';
  static const _collapseKey = 'diffEditor.hideUnchangedRegions.enabled';

  UserSettings? _settings;

  /// What was chosen this run, where there is no settings.json (tests).
  final Map<String, Object> _chosen = {};

  /// Reads and keeps the choices in [settings] from now on.
  void attach(UserSettings? settings) {
    if (settings == null || identical(settings, _settings)) return;
    _settings = settings;
    notifyListeners();
  }

  Object? _value(String key) => _settings?[key] ?? _chosen[key];

  void _set(String key, Object value) {
    _write(key, value);
    notifyListeners();
  }

  void _write(String key, Object value) {
    _chosen[key] = value;
    final settings = _settings;
    if (settings != null) {
      settings.update(key, value).catchError((Object _) {
        // A settings file that does not parse keeps the choice for the run.
      });
    }
  }

  IdeDiffLayout get layout => switch (_value(_layoutKey)) {
    'sideBySide' => IdeDiffLayout.sideBySide,
    'unified' => IdeDiffLayout.unified,
    _ => IdeDiffLayout.auto,
  };
  set layout(IdeDiffLayout value) => _set(_layoutKey, value.name);

  /// Side by side (true), unified (false), or by the width (null): for
  /// [DiffEditor.sideBySide].
  bool? get sideBySide => switch (layout) {
    IdeDiffLayout.auto => null,
    IdeDiffLayout.sideBySide => true,
    IdeDiffLayout.unified => false,
  };

  bool get ignoreTrimWhitespace => switch (_value(_whitespaceKey)) {
    final bool value => value,
    _ => true,
  };
  set ignoreTrimWhitespace(bool value) => _set(_whitespaceKey, value);

  IdeDiffWhitespace get whitespace => _value(_allWhitespaceKey) == true
      ? IdeDiffWhitespace.all
      : ignoreTrimWhitespace
      ? IdeDiffWhitespace.trim
      : IdeDiffWhitespace.none;
  set whitespace(IdeDiffWhitespace value) {
    _write(_allWhitespaceKey, value == IdeDiffWhitespace.all);
    _set(_whitespaceKey, value != IdeDiffWhitespace.none);
  }

  /// Unchanged lines hidden but for a few round the changes, as JetBrains
  /// IDEs do by default.
  bool get collapseUnchanged => switch (_value(_collapseKey)) {
    final bool value => value,
    _ => true,
  };
  set collapseUnchanged(bool value) => _set(_collapseKey, value);

  DiffHighlight get highlight => switch (_value(_highlightKey)) {
    final String name =>
      DiffHighlight.values.asNameMap()[name] ?? DiffHighlight.characters,
    _ => DiffHighlight.characters,
  };
  set highlight(DiffHighlight value) => _set(_highlightKey, value.name);

  /// Back to the defaults (tests).
  @visibleForTesting
  void reset() {
    _settings = null;
    _chosen.clear();
    notifyListeners();
  }
}
