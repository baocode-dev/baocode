// JetBrains IDEs' changelists: the local changes sorted into named lists,
// one of them active, where a change goes as it first shows; a file moved
// from one to another, a list renamed or deleted (its files going to the
// default list). BaoCode's own: what an agent changes in a turn goes to a
// list of that turn's, named after what it was asked.

import 'package:flutter/foundation.dart';

/// A changelist: [name] (empty for the default list, "Changes" in the
/// display language), [turn] for an agent's turn's.
class IdeGitChangelist {
  IdeGitChangelist(this.id, this.name, {this.turn = false});

  final String id;
  String name;
  final bool turn;
}

class IdeGitChangelists extends ChangeNotifier {
  static const defaultId = 'default';

  final List<IdeGitChangelist> _lists = [IdeGitChangelist(defaultId, '')];
  String _active = defaultId;

  /// The lists the files were put in, by path; the others are the active
  /// list's.
  final Map<String, String> _assigned = {};

  List<IdeGitChangelist> get lists => List.unmodifiable(_lists);

  /// Whether there is more than the default list.
  bool get several => _lists.length > 1;

  String get active => _active;

  IdeGitChangelist? byId(String id) {
    for (final list in _lists) {
      if (list.id == id) return list;
    }
    return null;
  }

  /// The list [path]'s change is in.
  String listOf(String path) => switch (_assigned[path]) {
    final id? when byId(id) != null => id,
    _ => _active,
  };

  int _next = 1;

  String _newId() {
    while (byId('list$_next') != null) {
      _next++;
    }
    return 'list${_next++}';
  }

  /// A new list named [name], [paths] moved to it.
  IdeGitChangelist create(String name, {Iterable<String> paths = const []}) {
    final list = IdeGitChangelist(_newId(), name);
    _lists.add(list);
    for (final path in paths) {
      _assigned[path] = list.id;
    }
    notifyListeners();
    return list;
  }

  /// [paths] moved to list [id].
  void move(Iterable<String> paths, String id) {
    if (byId(id) == null) return;
    for (final path in paths) {
      _assigned[path] = id;
    }
    notifyListeners();
  }

  /// List [id] made the active one: the changes in no list ([unassigned],
  /// the active list's until now) stay where they are.
  void setActive(String id, {Iterable<String> unassigned = const []}) {
    if (byId(id) == null || id == _active) return;
    for (final path in unassigned) {
      _assigned.putIfAbsent(path, () => _active);
    }
    _active = id;
    notifyListeners();
  }

  void rename(String id, String name) {
    final list = byId(id);
    if (list == null || list.name == name) return;
    list.name = name;
    notifyListeners();
  }

  /// List [id] gone, its files the default list's; the default list stays.
  void remove(String id) {
    if (id == defaultId || byId(id) == null) return;
    _lists.removeWhere((list) => list.id == id);
    _assigned.updateAll((_, list) => list == id ? defaultId : list);
    if (_active == id) _active = defaultId;
    notifyListeners();
  }

  /// [paths]' changes, in their agent's [turn] (its id), go to that turn's
  /// list, named [name], unless they are in a list already.
  void assignTurn(String turn, String name, Iterable<String> paths) {
    final id = 'turn:$turn';
    final fresh = [
      for (final path in paths)
        if (!_assigned.containsKey(path)) path,
    ];
    if (fresh.isEmpty) return;
    if (byId(id) == null) {
      _lists.add(IdeGitChangelist(id, name, turn: true));
    }
    for (final path in fresh) {
      _assigned[path] = id;
    }
    notifyListeners();
  }

  /// Only [changed] are changes still: the others are in no list, and a
  /// turn's list with none of them goes.
  void prune(Set<String> changed) {
    final before = (_assigned.length, _lists.length);
    _assigned.removeWhere((path, _) => !changed.contains(path));
    final used = _assigned.values.toSet();
    _lists.removeWhere(
      (list) => list.turn && list.id != _active && !used.contains(list.id),
    );
    if (before != (_assigned.length, _lists.length)) notifyListeners();
  }

  Map<String, Object?> toJson() => {
    'active': _active,
    'lists': [
      for (final list in _lists)
        {'id': list.id, 'name': list.name, if (list.turn) 'turn': true},
    ],
    'assigned': _assigned,
  };

  /// What [toJson] gave, where it can be read.
  void restore(Object? json) {
    if (json is! Map) return;
    final lists = json['lists'];
    if (lists is! List) return;
    _lists
      ..clear()
      ..add(IdeGitChangelist(defaultId, ''));
    for (final list in lists) {
      if (list case {'id': final String id, 'name': final String name}
          when id != defaultId) {
        _lists.add(IdeGitChangelist(id, name, turn: list['turn'] == true));
      }
    }
    _assigned.clear();
    if (json['assigned'] case final Map assigned) {
      for (final MapEntry(:key, :value) in assigned.entries) {
        if (key is String && value is String) _assigned[key] = value;
      }
    }
    _active = switch (json['active']) {
      final String id when byId(id) != null => id,
      _ => defaultId,
    };
    notifyListeners();
  }
}
