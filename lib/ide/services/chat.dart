// The chat beside the editor, as the workbench reaches it: code and
// questions sent to its composer (the chat shown for them), and Back to
// Chat, which leaves the IDE for the conversation.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../chat/composer/composer_files.dart' show CodeReference;
import '../workbench/contributions.dart';
import 'editors.dart';
import 'layout.dart';

class ChatService {
  ChatService({
    required this.host,
    required this.layout,
    required this.editors,
    required this._addCode,
    required this._ask,
    required this._back,
  });

  final WorkbenchHost host;
  final LayoutService layout;
  final EditorService editors;

  /// The app's: code into the composer, a question into it, the
  /// conversation in the IDE's place. None where the window has no chat.
  final ValueChanged<List<CodeReference>>? Function() _addCode;
  final ValueChanged<String>? Function() _ask;
  final VoidCallback Function() _back;

  bool get canAddCode => _addCode() != null;
  bool get canAsk => _ask() != null;

  /// The editor's lines selected in the chat's composer, the chat shown
  /// and the keyboard in it (as Cursor's ⌘L).
  void addSelection() {
    final code = editors.editor?.selectedCode() ?? const <CodeReference>[];
    if (!layout.chatShown) layout.toggleChat();
    _addCode()?.call(code);
  }

  /// [text] in the chat's composer, the chat shown.
  void ask(String text) {
    _ask()?.call(text);
    if (!layout.chatShown) layout.toggleChat();
  }

  /// Back to Chat: the editor's last keys in its document first.
  Future<void> back() async {
    try {
      await editors.flush();
      if (host.context != null) _back()();
    } catch (error) {
      host.report(error);
    }
  }
}
