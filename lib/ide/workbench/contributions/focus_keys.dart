// The context keys of where the keyboard is (upstream's
// `EditorContextKeys`, `InputFocusedContext`, `IsIDEContext`…): the text
// editor's and an input's, and the text editor's own last, asked after
// every other provider's.

import 'package:flutter/widgets.dart';

import '../../../chat/chat_keys.dart';
import '../../ide_workspace.dart';
import '../../services/editors.dart';
import '../context_keys.dart';
import '../contributions.dart';
import '../services.dart';

class FocusKeysContribution extends WorkbenchRegistrations {
  FocusKeysContribution(WorkbenchServices services) {
    final editors = services.get<EditorService>();
    final keys = services.get<ContextKeyService>();
    add(
      keys.addProvider((key) {
        final editor = editors.editor;
        final editorFocus = editor?.hasTextFocus ?? false;
        bool textField() {
          final focus = FocusManager.instance.primaryFocus;
          // A text field, or the chat's input (a rich text editor of its
          // own).
          return focus?.context?.findAncestorStateOfType<EditableTextState>() !=
                  null ||
              ChatKeys.focusedTargets().any(
                (target) => target.chatContextKey('inputFocus') == true,
              );
        }

        return switch (key) {
          'ideMode' => true,
          'chatMode' => false,
          'editorTextFocus' => editorFocus,
          // The editor or one of its widgets (find, rename).
          'editorFocus' => editor?.hasFocus ?? false,
          'editorHasSelection' =>
            editorFocus && editors.caret.value.selectionLength > 0,
          'editorReadonly' =>
            services.find<IdeWorkspace>()?.active?.readOnly ?? false,
          'textInputFocus' => editorFocus || textField(),
          'inputFocus' =>
            editorFocus ||
                textField() ||
                keys.getValue('terminalFocus') == true,
          'treestickyScrollFocused' => false,
          _ => editor?.contextKey(key),
        };
      }),
    );
  }
}
