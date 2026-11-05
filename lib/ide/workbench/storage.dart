// Where the window is kept between runs (IdeWorkbench.viewState): each
// service reads and writes its own keys of it, as upstream's services
// store theirs as the window is about to be saved (`IStorageService`
// and `onWillSaveState`, src/vs/platform/storage/common/storage.ts). The
// keys and their values are what they were before the services had them.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'services.dart';

/// A service with keys of its own in the window's view state.
abstract interface class WorkbenchStorageParticipant {
  /// Reads its keys of [kept] (those a former run wrote).
  void restoreState(Map<String, Object?> kept);

  /// Writes its keys into [into].
  void saveState(Map<String, Object?> into);
}

class WorkbenchStorage implements WorkbenchDisposable {
  WorkbenchStorage({this.onChanged, this.save});

  /// Told when a participant's state changed, for the window to be kept a
  /// moment later.
  VoidCallback? onChanged;

  /// Where the window is kept as it changes (IdeWorkbench.onViewState); as
  /// the window is given, it may change. Nothing is kept with none.
  final ValueChanged<Map<String, Object?>>? Function()? save;

  /// Whether the window is kept at all.
  bool get keeps => save?.call() != null;

  final List<WorkbenchStorageParticipant> _participants = [];
  Map<String, Object?>? _kept;

  /// Adds [participant] until the returned callback runs; one added after
  /// the window was restored reads what it kept at once.
  VoidCallback register(WorkbenchStorageParticipant participant) {
    _participants.add(participant);
    if (_kept case final kept?) participant.restoreState(kept);
    return () => _participants.remove(participant);
  }

  /// Hands [kept] to each participant.
  void restore(Map<String, Object?> kept) {
    _kept = kept;
    for (final participant in [..._participants]) {
      participant.restoreState(kept);
    }
  }

  /// Each participant's keys, in the order they were added.
  Map<String, Object?> collect() {
    final into = <String, Object?>{};
    for (final participant in _participants) {
      participant.saveState(into);
    }
    return into;
  }

  /// A participant's state changed.
  void changed() {
    onChanged?.call();
    keepSoon();
  }

  /// Until [restoring] completes (the editors kept being opened again), the
  /// window is not kept, lest those not open yet be forgotten.
  void holdWhile(Future<void> restoring) {
    _holds++;
    unawaited(
      restoring.whenComplete(() {
        _holds--;
        keepSoon();
      }),
    );
  }

  int _holds = 0;
  Timer? _timer;
  String? _saved;

  /// A moment after a change, as a sash dragged changes it at each frame.
  void keepSoon() {
    if (!keeps || _holds > 0) return;
    _timer ??= Timer(const Duration(milliseconds: 300), keep);
  }

  /// Now (the app going to the background, the window closing): what the
  /// participants have, where it changed since it was last kept.
  void keep() {
    _timer?.cancel();
    _timer = null;
    final save = this.save?.call();
    if (save == null || _holds > 0) return;
    final state = collect();
    final json = jsonEncode(state);
    if (json == _saved) return;
    _saved = json;
    save(state);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
