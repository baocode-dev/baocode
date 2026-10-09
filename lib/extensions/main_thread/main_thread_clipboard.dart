/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadClipboard.ts, on Flutter's
// Clipboard (the system's plain text).

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/services.dart';

import 'main_thread_context.dart';

/// The system clipboard's text, replaceable in tests.
abstract interface class ExtensionClipboard {
  Future<String> readText();
  Future<void> writeText(String value);
}

/// [ExtensionClipboard] on Flutter's [Clipboard].
final class SystemExtensionClipboard implements ExtensionClipboard {
  const SystemExtensionClipboard();

  @override
  Future<String> readText() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';

  @override
  Future<void> writeText(String value) =>
      Clipboard.setData(ClipboardData(text: value));
}

final class MainThreadClipboard extends MainThreadClipboardUnsupported {
  const MainThreadClipboard([this._clipboard = const SystemExtensionClipboard()]);

  final ExtensionClipboard _clipboard;

  static RpcActor customer(MainThreadContext context) =>
      MainThreadClipboardActor(
        MainThreadClipboard(
          context.maybeService<ExtensionClipboard>() ??
              const SystemExtensionClipboard(),
        ),
      );

  @override
  Future<String> $readText() => _clipboard.readText();

  @override
  Future<void> $writeText(String value) => _clipboard.writeText(value);
}
