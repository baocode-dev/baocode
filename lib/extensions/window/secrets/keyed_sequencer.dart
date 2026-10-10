/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/base/common/async.ts (`SequencerByKey`).

import 'dart:async';

/// Runs the tasks queued under one key one after another, in order; tasks
/// of different keys run at the same time.
final class KeyedSequencer<K> {
  final _last = <K, Future<void>>{};

  /// Runs [task] once every task queued before under [key] has ended.
  Future<T> queue<T>(K key, Future<T> Function() task) {
    final previous = _last[key] ?? Future<void>.value();
    final result = previous.then((_) => task());
    final done = result.then<void>((_) {}, onError: (Object _) {});
    _last[key] = done;
    unawaited(
      done.whenComplete(() {
        if (identical(_last[key], done)) _last.remove(key);
      }),
    );
    return result;
  }

  /// Whether a task of [key] is queued or running.
  bool isBusy(K key) => _last.containsKey(key);
}
