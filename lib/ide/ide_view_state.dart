import 'dart:collection';

import 'package:flutter/widgets.dart';

import 'package:bao_editor/monaco/flutter/editor_view_state.dart';

/// Where a tab's editor was left, given back when the tab shows again, is
/// opened again, or the app runs again: VS Code's editor view state
/// (`AbstractEditorWithViewState`), one part for each editor a file shows
/// in.
@immutable
class IdeViewState {
  const IdeViewState({
    this.selections,
    this.editor,
    this.diffScroll,
    this.previewLine,
    this.image,
  });

  static const empty = IdeViewState();

  /// The text editor's carets.
  final List<TextSelection>? selections;

  /// The text editor's scroll and folds.
  final EditorViewState? editor;

  /// A diff tab's scroll, both sides'.
  final Offset? diffScroll;

  /// The one-based line at the top of a markdown file's preview.
  final int? previewLine;

  /// The image preview's zoom and pan (a [Matrix4]'s storage).
  final List<double>? image;

  IdeViewState copyWith({
    List<TextSelection>? selections,
    EditorViewState? editor,
    Offset? diffScroll,
    int? previewLine,
    List<double>? image,
  }) => IdeViewState(
    selections: selections ?? this.selections,
    editor: editor ?? this.editor,
    diffScroll: diffScroll ?? this.diffScroll,
    previewLine: previewLine ?? this.previewLine,
    image: image ?? this.image,
  );

  /// What of it is kept from one run to the next (a diff tab's is not).
  Map<String, Object?> toJson() => {
    if (selections case final selections? when selections.isNotEmpty)
      'selections': [
        for (final s in selections) [s.baseOffset, s.extentOffset],
      ],
    'editor': ?editor?.toJson(),
    'preview': ?previewLine,
    'image': ?image,
  };

  static IdeViewState? fromJson(Object? json) {
    if (json is! Map) return null;
    final selections = <TextSelection>[
      if (json['selections'] case final List<Object?> list)
        for (final s in list)
          if (s case [final int base, final int extent]
              when base >= 0 && extent >= 0)
            TextSelection(baseOffset: base, extentOffset: extent),
    ];
    final image = switch (json['image']) {
      final List<Object?> values
          when values.length == 16 &&
              values.every((v) => v is num && v.isFinite) =>
        [for (final v in values) (v! as num).toDouble()],
      _ => null,
    };
    final state = IdeViewState(
      selections: selections.isEmpty ? null : selections,
      editor: EditorViewState.fromJson(json['editor']),
      previewLine: switch (json['preview']) {
        final int line when line >= 1 => line,
        _ => null,
      },
      image: image,
    );
    return state.isEmpty ? null : state;
  }

  bool get isEmpty =>
      selections == null &&
      editor == null &&
      diffScroll == null &&
      previewLine == null &&
      image == null;
}

/// The tabs' [IdeViewState]s by key, the one last kept last: VS Code's
/// `EditorMemento`, which keeps the [limit] most recent, those of tabs
/// closed too (`workbench.editor.restoreViewState`).
class IdeViewStates {
  IdeViewStates({this.limit = 100});

  final int limit;
  final LinkedHashMap<String, IdeViewState> _states = LinkedHashMap();

  /// Each tab's scrolled lists and such, for [PageStorage]: kept while the
  /// app runs, not from one run to the next.
  final Map<String, PageStorageBucket> _buckets = {};

  IdeViewState operator [](String key) => _states[key] ?? IdeViewState.empty;

  void keep(String key, IdeViewState state) {
    _states.remove(key);
    if (state.isEmpty) return;
    _states[key] = state;
    while (_states.length > limit) {
      final oldest = _states.keys.first;
      _states.remove(oldest);
      _buckets.remove(oldest);
    }
  }

  /// [key]'s [PageStorageBucket].
  PageStorageBucket bucket(String key) =>
      _buckets.putIfAbsent(key, PageStorageBucket.new);

  /// [from]'s state [to]'s, as its file moved (or was saved elsewhere).
  void move(String from, String to) {
    if (from == to) return;
    if (_states.remove(from) case final state?) keep(to, state);
    if (_buckets.remove(from) case final bucket?) _buckets[to] = bucket;
  }

  /// Those of [keep]'s keys, most recent last.
  List<Object?> toJson(bool Function(String key) keep) => [
    for (final MapEntry(:key, :value) in _states.entries)
      if (keep(key))
        if (value.toJson() case final json when json.isNotEmpty)
          {'key': key, ...json},
  ];

  /// The states of a [toJson], before any kept since.
  void restore(Object? json) {
    if (json is! List<Object?>) return;
    final kept = Map.of(_states);
    _states.clear();
    for (final entry in json) {
      if (entry is! Map || entry['key'] is! String) continue;
      if (IdeViewState.fromJson(entry) case final state?) {
        keep(entry['key'] as String, state);
      }
    }
    kept.forEach(keep);
  }
}
