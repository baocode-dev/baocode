// The extensions' file decorations as the explorer's rows show them, after
// Git's (explorerViewer.ts's `fileDecorations: { colors, badges }`).

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';

import '../../ide/git/git_model.dart' show IdeGitDecoration;
import '../../ide/ide_explorer.dart' show IdeExplorerDecorations;
import 'file_decorations_service.dart';

/// [service]'s decorations of local paths.
final class ExplorerFileDecorations extends ChangeNotifier
    implements IdeExplorerDecorations {
  ExplorerFileDecorations(this.service) {
    service.addListener(notifyListeners);
  }

  final FileDecorationsService service;

  @override
  IdeGitDecoration? decorationOf(String path, {required bool isDirectory}) =>
      asIdeDecoration(
        service.getDecoration(VsUri.file(path), includeChildren: isDirectory),
      );

  /// [decoration] as the explorer draws one: a folder's children's as a
  /// dot.
  static IdeGitDecoration? asIdeDecoration(FileDecoration? decoration) {
    if (decoration == null) return null;
    return IdeGitDecoration(
      colorId: decoration.colorId,
      tooltip: decoration.bubbleOnly
          ? IdeGitDecoration.folderTooltip
          : decoration.tooltip,
      letter: decoration.bubbleOnly ? '•' : decoration.letter,
      strikeThrough: decoration.strikethrough,
    );
  }

  @override
  void dispose() {
    service.removeListener(notifyListeners);
    super.dispose();
  }
}
