// The editor's own panes beside the text editor: a file view's (a stash's
// page), an image's, and one for a document that could not be read
// (upstream's binary and too-large placeholders).

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../workspace/window_controls.dart';
import '../../file_service.dart';
import '../../ide_editor_placeholder.dart';
import '../../ide_image_preview.dart';
import '../../ide_workspace.dart';
import '../contributions.dart';
import '../editor_panes.dart';
import '../services.dart';

class EditorPanesContribution extends WorkbenchRegistrations {
  EditorPanesContribution(WorkbenchServices services) {
    final panes = services.get<EditorPaneRegistry>();
    final host = services.get<WorkbenchHost>();
    IdeWorkspace workspace() => services.get<IdeWorkspace>();

    /// Whether the project's files are this machine's (not a remote
    /// host's): only then are they opened in other apps.
    bool local() => workspace().files is! IdeHostFiles;
    add(panes.register(fileViewPane(), priority: EditorPanePriority.fileView));
    add(
      panes.register(
        EditorPane(
          id: 'workbench.editor.media',
          accepts: (doc) => doc.isMedia,
          build: (context, doc) => IdeImagePreview(
            key: ValueKey(doc),
            path: doc.path,
            initialTransform: workspace().viewStateOf(doc).image,
            onLeave: (transform) => workspace().keepViewState(
              doc,
              (kept) => kept.copyWith(image: transform),
            ),
            read: switch (workspace().files) {
              final IdeHostFiles files => files.readBytes,
              _ => null,
            },
            onOpenInDefaultApp: local() && WindowControls.canOpenInDefaultApp
                ? () => unawaited(host.openInDefaultApp(doc.path))
                : null,
          ),
        ),
        priority: EditorPanePriority.media,
      ),
    );
    add(
      panes.register(
        EditorPane(
          id: 'workbench.editor.placeholder',
          accepts: (doc) => doc.openError != null,
          build: (context, doc) => IdeEditorPlaceholder(
            key: ValueKey(doc),
            error: doc.openError!,
            path: doc.path,
            onOpenAnyway: () => unawaited(workspace().reopen(doc, force: true)),
            onRetry: () => unawaited(workspace().reopen(doc)),
            onOpenInDefaultApp:
                local() &&
                    WindowControls.canOpenInDefaultApp &&
                    doc.readRevision == null
                ? () => unawaited(host.openInDefaultApp(doc.path))
                : null,
          ),
        ),
        priority: EditorPanePriority.openError,
      ),
    );
  }
}
