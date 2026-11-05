// A markdown file's preview as its editor's pane, and the commands that
// switch it and its source (markdown-language-features' `markdown.showPreview`
// and `markdown.showSource`), over the window's MarkdownPreviewService.

import 'dart:async';

import '../../ide_workspace.dart';
import '../../markdown/markdown_preview.dart' show IdeMarkdownPreviewState;
import '../../services/markdown_preview.dart';
import '../actions.dart';
import '../contributions.dart';
import '../editor_panes.dart';
import '../services.dart';

class MarkdownContribution extends WorkbenchRegistrations {
  MarkdownContribution(WorkbenchServices services) {
    final markdown = services.get<MarkdownPreviewService>();
    add(
      services.get<EditorPaneRegistry>().register(
        EditorPane(
          id: 'workbench.editor.markdownPreview',
          accepts: markdown.previewing,
          build: (context, doc) => markdown.build(doc),
          control: (doc) => switch (markdown.previewOf(doc)) {
            final preview? => _PreviewControl(preview),
            null => null,
          },
        ),
        priority: EditorPanePriority.markdownPreview,
      ),
    );
    add(
      services.get<ActionRegistry>().registerAll([
        WorkbenchAction(
          id: 'markdown.showPreview',
          category: 'Markdown',
          title: 'Open Preview',
          precondition: (services) => switch (services.find<IdeWorkspace>()) {
            final workspace? => switch (workspace.active) {
              final active? =>
                markdown.hasPreview(active) && !markdown.previewing(active),
              null => false,
            },
            null => false,
          },
          run: (_, _) => unawaited(markdown.setPreview(true)),
        ),
        WorkbenchAction(
          id: 'markdown.showSource',
          category: 'Markdown',
          title: 'Show Source',
          precondition: (services) =>
              markdown.previewing(services.find<IdeWorkspace>()?.active),
          run: (_, _) => unawaited(markdown.setPreview(false)),
        ),
      ]),
    );
  }
}

/// A preview as the workbench focuses it and shows a line of it.
class _PreviewControl implements EditorPaneControl {
  _PreviewControl(this.preview);

  final IdeMarkdownPreviewState preview;

  @override
  void focus() => preview.focus();

  @override
  void revealLine(int line, [int column = 1]) =>
      preview.revealLine(line, column);
}
