// Where the window is kept between runs (IdeWorkbench.viewState): each
// service reads and writes its own keys of it, as upstream's services
// store theirs as the window is about to be saved (`IStorageService`
// and `onWillSaveState`, src/vs/platform/storage/common/storage.ts). The
// keys and their values are what they were before the services had them.

import 'package:flutter/foundation.dart';

/// A service with keys of its own in the window's view state.
abstract interface class WorkbenchStorageParticipant {
  /// Reads its keys of [kept] (those a former run wrote).
  void restoreState(Map<String, Object?> kept);

  /// Writes its keys into [into].
  void saveState(Map<String, Object?> into);
}

class WorkbenchStorage {
  WorkbenchStorage({this.onChanged});

  /// Told when a participant's state changed, for the window to be kept a
  /// moment later.
  VoidCallback? onChanged;

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
  void changed() => onChanged?.call();
}
