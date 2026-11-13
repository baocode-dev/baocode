import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../l10n/l10n.dart';
import '../workspace/window_controls.dart';
import 'file_service.dart';
import 'host_paths.dart';
import 'transfer_progress.dart';

/// Whether a file shown can be saved elsewhere ([saveFileCopyAs]): where
/// there is a save panel.
bool get canSaveFileCopy => WindowControls.canPickFiles;

/// Save As… of the file [path] in a context menu: asks where on this
/// machine (the native save panel), then copies it there through [files],
/// downloading it from a remote project's host (how far shown in a
/// notification of [context]'s, which can give it up); [text] is written
/// instead when given. The path saved to, or null when cancelled.
Future<String?> saveFileCopyAs(
  IdeFileService files,
  String path, {
  String? text,
  BuildContext? context,
}) async {
  final local = files is! IdeHostFiles;
  final to = await WindowControls.pickSaveFile(
    // Not a folder of the host's: the panel is this machine's.
    directory: local ? p.dirname(path) : null,
    name: local ? p.basename(path) : hostPathsFor(path).basename(path),
  );
  if (to == null) return null;
  if (local || text != null || context == null || !context.mounted) {
    await saveCopyTo(files, path, to, text: text);
    return to;
  }
  try {
    await withTransferProgress(context, context.l10n.explorerDownloading, (
      transfer,
    ) async {
      transfer.onProgress(0, 1);
      await saveCopyTo(
        files,
        path,
        to,
        onFile: transfer.onFile,
        cancel: transfer.cancel,
      );
      transfer.onProgress(1, 1);
    }, cancellable: true);
  } on TransferCancelledException {
    return null;
  }
  return to;
}
