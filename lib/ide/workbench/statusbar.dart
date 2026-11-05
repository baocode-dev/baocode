// The status bar's entries, each added by the feature it tells of and kept
// current by it (upstream `IStatusbarService.addEntry`, which hands back
// an accessor to update or dispose it;
// src/vs/workbench/services/statusbar/browser/statusbar.ts). An entry is
// built as the bar is, in its context (its text is localized there), and
// the bar is built again when what an entry shows [changes].

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../ide_status_bar.dart';

enum StatusbarAlignment { left, right }

/// What an entry shows now; null hides it, keeping its place.
typedef StatusbarEntryBuilder = IdeStatusBarItem? Function(
  BuildContext context,
);

/// What a group of entries shows now, left to right.
typedef StatusbarEntriesBuilder = Iterable<IdeStatusBarItem> Function(
  BuildContext context,
);

/// One entry's place and what it shows (a group's, all of them there).
class _Entry {
  _Entry(this.id, this.alignment, this.priority, this.order, this.build);

  final String id;
  final StatusbarAlignment alignment;
  final double priority;
  final int order;
  StatusbarEntriesBuilder build;
  Listenable? changes;
}

/// Updates or removes an entry added (upstream `IStatusbarEntryAccessor`).
class StatusbarEntryAccessor {
  StatusbarEntryAccessor._(this._service, this._entry);

  final StatusbarService _service;
  final _Entry _entry;

  /// What it shows from now on.
  void update(StatusbarEntryBuilder build) {
    _entry.build = _single(build);
    _service._changed();
  }

  void dispose() {
    if (!_service._entries.remove(_entry)) return;
    _entry.changes?.removeListener(_service._changed);
    _service._changed();
  }
}

class StatusbarService extends ChangeNotifier {
  final List<_Entry> _entries = [];
  int _added = 0;

  /// Adds the entry [id], built by [build], on the [alignment] side: the
  /// greater its [priority], the further left (upstream's
  /// `StatusBarItem.priority`), those alike in the order they were added.
  /// The bar is built again as [changes] tells.
  StatusbarEntryAccessor addEntry(
    String id,
    StatusbarAlignment alignment,
    StatusbarEntryBuilder build, {
    double priority = 0,
    Listenable? changes,
  }) => addEntries(
    id,
    alignment,
    _single(build),
    priority: priority,
    changes: changes,
  );

  /// Adds entries as [addEntry] does one, as many as [build] makes now
  /// (upstream's language status adds an entry for each of its items).
  StatusbarEntryAccessor addEntries(
    String id,
    StatusbarAlignment alignment,
    StatusbarEntriesBuilder build, {
    double priority = 0,
    Listenable? changes,
  }) {
    final entry = _Entry(id, alignment, priority, _added++, build)
      ..changes = changes;
    changes?.addListener(_changed);
    _entries.add(entry);
    _changed();
    return StatusbarEntryAccessor._(this, entry);
  }

  /// The [alignment] side's entries showing, left to right, with their
  /// priorities.
  List<(double priority, IdeStatusBarItem item)> entries(
    BuildContext context,
    StatusbarAlignment alignment,
  ) {
    final sides = [
      for (final entry in _entries)
        if (entry.alignment == alignment) entry,
    ];
    sides.sort((a, b) {
      final byPriority = b.priority.compareTo(a.priority);
      return byPriority != 0 ? byPriority : a.order.compareTo(b.order);
    });
    return [
      for (final entry in sides)
        for (final item in entry.build(context)) (entry.priority, item),
    ];
  }

  /// The [alignment] side's entries showing, left to right.
  List<IdeStatusBarItem> items(
    BuildContext context,
    StatusbarAlignment alignment,
  ) => [for (final (_, item) in entries(context, alignment)) item];

  void _changed() => notifyListeners();

  /// The message after the items on the left (upstream
  /// `INotificationService.status`): a chord's, a command's.
  String? get message => _message;
  String? _message;
  Timer? _messageTimer;

  /// Shows [message] in place of the last one, for [hideAfter] if given
  /// (`NotificationsStatus.doSetStatusMessage`); null hides it.
  void setMessage(String? message, {Duration? hideAfter}) {
    _messageTimer?.cancel();
    _messageTimer = message != null && hideAfter != null
        ? Timer(hideAfter, () => setMessage(null))
        : null;
    if (_message == message) return;
    _message = message;
    _changed();
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    for (final entry in _entries) {
      entry.changes?.removeListener(_changed);
    }
    _entries.clear();
    super.dispose();
  }
}

StatusbarEntriesBuilder _single(StatusbarEntryBuilder build) =>
    (context) => [?build(context)];

/// [entries] among [others] (the bar's items not yet entries, with the
/// priorities they would have), by priority, the entries after others
/// alike.
List<IdeStatusBarItem> mergeStatusbarItems(
  List<(double priority, IdeStatusBarItem item)> others,
  List<(double priority, IdeStatusBarItem item)> entries,
) {
  final all =
      [
        for (final (index, (priority, item)) in others.indexed)
          (priority, 0, index, item),
        for (final (index, (priority, item)) in entries.indexed)
          (priority, 1, index, item),
      ]..sort((a, b) {
        final byPriority = b.$1.compareTo(a.$1);
        if (byPriority != 0) return byPriority;
        final bySource = a.$2.compareTo(b.$2);
        return bySource != 0 ? bySource : a.$3.compareTo(b.$3);
      });
  return [for (final (_, _, _, item) in all) item];
}
