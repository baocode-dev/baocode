import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../workspace/window_controls.dart';
import 'composer_files.dart';

/// What a [FileDropRegion] does with files the system drags over it, from
/// other apps (Finder, Explorer, an editor…). Positions are the window's,
/// from its top left.
abstract interface class FileDropDelegate {
  /// [files] are over it, at [position]; again as the pointer moves.
  void fileDragOver(Offset position, List<ComposerFile> files);

  /// They left it, or the drag ended elsewhere.
  void fileDragLeave();

  /// [files] were let go over it, at [position].
  void fileDrop(Offset position, List<ComposerFile> files);
}

/// Where files dragged in from other apps can be let go: the system's drag
/// goes to the topmost region under the pointer (see [FileDrops]). What
/// covers it (a menu, a dialog) takes the drag from it.
class FileDropRegion extends SingleChildRenderObjectWidget {
  const FileDropRegion({super.key, required this.delegate, super.child});

  final FileDropDelegate delegate;

  @override
  RenderFileDropRegion createRenderObject(BuildContext context) =>
      RenderFileDropRegion(delegate);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderFileDropRegion renderObject,
  ) {
    renderObject.delegate = delegate;
  }
}

class RenderFileDropRegion extends RenderProxyBoxWithHitTestBehavior {
  RenderFileDropRegion(this.delegate)
    : super(behavior: HitTestBehavior.translucent);

  FileDropDelegate delegate;

  // Gone, it has nothing left to show (its delegate is going too).
  @override
  void detach() {
    if (identical(FileDrops._over, this)) FileDrops._over = null;
    super.detach();
  }
}

/// The system's drag and drop of files onto the window, as the window
/// reports it over `baocode/drop` (MainFlutterWindow.swift,
/// windows/runner/drop_target.cpp):
///
///   dragUpdate {x, y, files?}  the pointer is at x, y; files the first
///                              time (paths and whether each is a folder;
///                              none yet for files an app is still to
///                              write). Answers whether a region takes it,
///                              which the system shows with its cursor.
///   dragExit                   the drag left the window, or was cancelled
///   drop {x, y, files}         let go at x, y. Answers whether a region
///                              took them.
abstract final class FileDrops {
  static const channel = MethodChannel('baocode/drop');

  /// Starts taking the window's drags (once, from the workbench).
  static void listen() {
    if (!WindowControls.isDesktop) return;
    channel.setMethodCallHandler(handle);
  }

  static RenderFileDropRegion? _over;
  static List<ComposerFile> _files = const [];

  @visibleForTesting
  static Future<Object?> handle(MethodCall call) async {
    final arguments = call.arguments is Map
        ? (call.arguments as Map).cast<Object?, Object?>()
        : const <Object?, Object?>{};
    final position = Offset(
      (arguments['x'] as num?)?.toDouble() ?? 0,
      (arguments['y'] as num?)?.toDouble() ?? 0,
    );
    switch (call.method) {
      case 'dragUpdate':
        if (arguments['files'] case final List<Object?> files) {
          _files = decode(files);
        }
        final region = _regionAt(position);
        _moveTo(region);
        region?.delegate.fileDragOver(position, _files);
        return region != null;
      case 'dragExit':
        _moveTo(null);
        _files = const [];
        return null;
      case 'drop':
        final region = _regionAt(position) ?? _over;
        final files = arguments['files'] is List
            ? decode(arguments['files'] as List<Object?>)
            : _files;
        // Another one shown last takes its placeholder away.
        _moveTo(region);
        _over = null;
        _files = const [];
        if (region == null || files.isEmpty) {
          region?.delegate.fileDragLeave();
          return false;
        }
        region.delegate.fileDrop(position, files);
        return true;
    }
    return null;
  }

  static void _moveTo(RenderFileDropRegion? region) {
    final over = _over;
    if (identical(over, region)) return;
    _over = region;
    if (over != null && over.attached) over.delegate.fileDragLeave();
  }

  /// Files as the window sends them: `{path, directory}` each.
  static List<ComposerFile> decode(List<Object?> files) => [
    for (final file in files)
      if (file case {'path': final String path} when path.isNotEmpty)
        ComposerFile(path, directory: file['directory'] == true),
  ];

  /// The topmost region at [position] of the window.
  static RenderFileDropRegion? _regionAt(Offset position) {
    final binding = WidgetsBinding.instance;
    final view = binding.platformDispatcher.implicitView;
    if (view == null) return null;
    final result = HitTestResult();
    binding.hitTestInView(result, position, view.viewId);
    for (final entry in result.path) {
      if (entry.target case final RenderFileDropRegion region) return region;
    }
    return null;
  }
}
