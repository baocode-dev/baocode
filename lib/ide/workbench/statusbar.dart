// The status bar's entries, each added by the feature it tells of and kept
// current by it (upstream `IStatusbarService.addEntry`, which hands back
// an accessor to update or dispose it;
// src/vs/workbench/services/statusbar/browser/statusbar.ts).

import 'package:flutter/foundation.dart';

import '../ide_status_bar.dart';

enum StatusbarAlignment { left, right }

/// One entry's place and what it shows now.
class _Entry {
  _Entry(this.id, this.alignment, this.priority, this.order, this.item);

  final String id;
  final StatusbarAlignment alignment;
  final double priority;
  final int order;
  IdeStatusBarItem? item;
}

/// Updates or removes an entry added (upstream `IStatusbarEntryAccessor`).
class StatusbarEntryAccessor {
  StatusbarEntryAccessor._(this._service, this._entry);

  final StatusbarService _service;
  final _Entry _entry;

  /// What it shows now; null hides it, keeping its place.
  void update(IdeStatusBarItem? item) {
    if (identical(item, _entry.item)) return;
    _entry.item = item;
    _service._changed();
  }

  void dispose() {
    if (_service._entries.remove(_entry)) _service._changed();
  }
}

class StatusbarService extends ChangeNotifier {
  final List<_Entry> _entries = [];
  int _added = 0;

  /// Adds [item] as [id], on the [alignment] side: the greater its
  /// [priority], the further left (upstream's `StatusBarItem.priority`),
  /// those alike in the order they were added.
  StatusbarEntryAccessor addEntry(
    IdeStatusBarItem? item,
    String id,
    StatusbarAlignment alignment, {
    double priority = 0,
  }) {
    final entry = _Entry(id, alignment, priority, _added++, item);
    _entries.add(entry);
    _changed();
    return StatusbarEntryAccessor._(this, entry);
  }

  /// The [alignment] side's entries showing, left to right.
  List<IdeStatusBarItem> items(StatusbarAlignment alignment) {
    final entries = [
      for (final entry in _entries)
        if (entry.alignment == alignment && entry.item != null) entry,
    ];
    entries.sort((a, b) {
      final byPriority = b.priority.compareTo(a.priority);
      return byPriority != 0 ? byPriority : a.order.compareTo(b.order);
    });
    return [for (final entry in entries) entry.item!];
  }

  /// Whether [id] has an entry showing.
  bool shows(String id) =>
      _entries.any((entry) => entry.id == id && entry.item != null);

  void _changed() => notifyListeners();
}
