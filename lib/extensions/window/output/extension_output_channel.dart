/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/output/common/output.ts
// (`OutputChannelUpdateMode`, `IOutputChannelDescriptor`),
// src/vs/workbench/contrib/output/common/outputChannelModel.ts
// (`FileOutputChannelModel.update`: a clear or replace resets the file's
// offsets to `till`, else to the end of what was read; `clear()`; the
// content loaded and polled only while shown, dropped when hidden).
//
// Deviations: the content is an [OutputText] (lines) instead of a text
// model; a replace clears what is shown and reads from `till` (upstream
// computes minimal edits to the same result); the "Extension Host" channel
// is kept in memory (upstream has no such channel: it writes the extension
// host's console to the developer tools).

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';

import 'output_file_tailer.dart';
import 'output_text.dart';

/// `OutputChannelUpdateMode`.
enum OutputChannelUpdateMode {
  append,
  replace,
  clear;

  /// From its wire value (`Append` = 1, `Replace`, `Clear`).
  static OutputChannelUpdateMode? fromWire(int value) => switch (value) {
    1 => append,
    2 => replace,
    3 => clear,
    _ => null,
  };
}

/// An output channel: an extension's (`createOutputChannel`), a log's (a
/// registered, visible logger), or the app's "Extension Host" channel.
final class ExtensionOutputChannel extends ChangeNotifier {
  /// A channel whose content is [file], which someone else writes.
  ExtensionOutputChannel.file({
    required this.id,
    required this.label,
    required VsUri this.file,
    required this.log,
    this.languageId,
    this.extensionId,
    int maxBytes = OutputFileTailer.defaultMaxBytes,
    this.pollInterval = const Duration(milliseconds: 500),
  }) : text = OutputText(maxChars: maxBytes, parseLevels: log),
       _tailer = file.scheme == 'file'
           ? OutputFileTailer(file.fsPath(), maxBytes: maxBytes)
           : null;

  /// A channel whose content is what is [append]ed to it.
  ExtensionOutputChannel.memory({
    required this.id,
    required this.label,
    this.log = true,
    int maxBytes = OutputFileTailer.defaultMaxBytes,
  }) : file = null,
       languageId = null,
       extensionId = null,
       pollInterval = Duration.zero,
       text = OutputText(maxChars: maxBytes, parseLevels: log),
       _tailer = null;

  final String id;
  final String label;

  /// Its content's file; null for an in-memory channel.
  final VsUri? file;

  /// A log channel: lines are log entries, filtered by level.
  final bool log;
  final String? languageId;

  /// The extension that made it (`descriptor.extensionId`).
  final String? extensionId;
  final Duration pollInterval;

  /// What is shown: of a file channel, only while [shown].
  final OutputText text;
  final OutputFileTailer? _tailer;

  /// The file's path when it is on this machine.
  String? get filePath => _tailer?.path;

  bool get isMemory => file == null;

  /// Bytes of the file before what [text] holds that were skipped: more
  /// was new than is kept.
  int get skippedBytes => _skipped;
  int _skipped = 0;

  /// Whether the panel shows it (then its file is read and followed).
  bool get shown => _shown;
  bool _shown = false;

  bool get isDisposed => _disposed;
  bool _disposed = false;

  Timer? _poll;
  Future<void>? _reading;
  bool _readAgain = false;

  /// Shows or hides it: upstream loads the model when the view shows the
  /// channel, polls the file, and drops it all once hidden.
  void setShown(bool shown) {
    if (_disposed || shown == _shown) return;
    _shown = shown;
    final tailer = _tailer;
    if (tailer == null) return;
    if (shown) {
      unawaited(sync());
      _poll = Timer.periodic(pollInterval, (_) => unawaited(sync()));
    } else {
      _poll?.cancel();
      _poll = null;
      tailer.reset();
      _skipped = 0;
      text.clear();
      notifyListeners();
    }
  }

  /// `update(mode, till)`: what the extension host says it did to the
  /// file. An append is read at once when shown; a clear or replace moves
  /// the start to [till] (the byte offset where the channel's content now
  /// starts), else to what was read.
  void update(OutputChannelUpdateMode mode, [int? till]) {
    if (_disposed) return;
    final tailer = _tailer;
    if (mode != OutputChannelUpdateMode.append) {
      if (tailer != null) {
        if (till != null) {
          tailer.reset(till);
        } else {
          tailer.resetToEnd();
        }
      }
      _skipped = 0;
      text.clear();
      notifyListeners();
    }
    if (_shown && tailer != null) unawaited(sync());
  }

  /// Clear Output: nothing is sent to the extension host; what was read so
  /// far is no longer shown (`resetToEnd`).
  void clear() => update(OutputChannelUpdateMode.clear);

  /// Adds to an in-memory channel.
  void append(String value) {
    if (_disposed || !isMemory || value.isEmpty) return;
    text.append(value);
    notifyListeners();
  }

  /// Reads what the file has new (one read at a time; a request while one
  /// runs reads again after it).
  Future<void> sync() async {
    final tailer = _tailer;
    if (tailer == null || _disposed) return;
    if (_reading != null) {
      _readAgain = true;
      return _reading;
    }
    final done = Completer<void>();
    _reading = done.future;
    try {
      do {
        _readAgain = false;
        final read = await tailer.read();
        if (_disposed || !_shown || read == null) continue;
        if (read.restarted || read.skipped > 0) {
          text.clear();
          _skipped = read.skipped;
        }
        text.append(read.text);
        notifyListeners();
      } while (_readAgain && !_disposed && _shown);
    } finally {
      _reading = null;
      done.complete();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _poll?.cancel();
    _poll = null;
    super.dispose();
  }
}
