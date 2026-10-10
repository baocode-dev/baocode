/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Typing through an extension's `type` command (VSCodeVim and other
// modal editing extensions register it and see every key typed).
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/editor/browser/view/viewController.ts and
// src/vs/editor/browser/widget/codeEditor/codeEditorWidget.ts (typing runs
// the `type` command, `replacePreviousChar`, `compositionType`,
// `compositionStart`, `compositionEnd`, `paste`, `cut` through the command
// service when one is registered by someone other than the editor; the
// extension calls `default:type` to insert text itself).
//
// How the editor glue uses it: before inserting typed text, call
// [TypeCommandInterceptor.type]; when it returns true, an extension took the
// text, and the editor inserts nothing (the extension types through
// `default:type`, which the editor port of the built-in commands runs).

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'extension_command_registry.dart';

/// Routes typing to extensions' `type` (and related) commands while one is
/// registered.
final class TypeCommandInterceptor extends ChangeNotifier {
  TypeCommandInterceptor(this.registry) {
    registry.addListener(_update);
    _active = _computeActive();
  }

  final ExtensionCommandRegistry registry;

  bool _active = false;

  /// Whether an extension registered `type`: the editor should route
  /// typing here.
  bool get active => _active;

  bool _computeActive() => registry.isExtensionCommand('type');

  void _update() {
    final next = _computeActive();
    if (next == _active) return;
    _active = next;
    notifyListeners();
  }

  bool _run(String id, Map<String, Object?> args) {
    if (!registry.isExtensionCommand(id)) return false;
    unawaited(
      registry.executeCommand(id, [args]).catchError((Object error) {
        debugPrint('$id: $error');
        return null;
      }),
    );
    return true;
  }

  /// Typed [text] (`type`, `{text}`): true when an extension took it.
  bool type(String text) => _run('type', {'text': text});

  /// An input method replaced characters before the cursor
  /// (`replacePreviousChar`): true when an extension took it.
  bool replacePreviousChar(String text, int replaceCharCnt) =>
      _run('replacePreviousChar', {
        'text': text,
        'replaceCharCnt': replaceCharCnt,
      });

  /// `compositionType`: true when an extension took it.
  bool compositionType(
    String text, {
    int replacePrevCharCnt = 0,
    int replaceNextCharCnt = 0,
    int positionDelta = 0,
  }) => _run('compositionType', {
    'text': text,
    'replacePrevCharCnt': replacePrevCharCnt,
    'replaceNextCharCnt': replaceNextCharCnt,
    'positionDelta': positionDelta,
  });

  /// An input method starts composing (`compositionStart`): the
  /// extension is told; the editor composes as usual.
  void compositionStart() => _run('compositionStart', const {});

  /// It ended (`compositionEnd`).
  void compositionEnd() => _run('compositionEnd', const {});

  /// Pasting [text] (`paste`): true when an extension took it.
  bool paste(String text, {bool pasteOnNewLine = false}) => _run('paste', {
    'text': text,
    'pasteOnNewLine': pasteOnNewLine,
    'multicursorText': null,
    'mode': null,
  });

  @override
  void dispose() {
    registry.removeListener(_update);
    super.dispose();
  }
}
