import 'dart:ui' show FlutterView;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A [View] whose frame is sent to the engine only when something in it
/// changed. Flutter composites every view at each frame, and the engine
/// draws each sent whole again: the stash's panel, hidden, and a window
/// where nothing moves were drawn as often as the one an agent writes in
/// (twice the work at each frame, for one other window). One not sent
/// keeps what it showed.
class QuietView extends StatefulWidget {
  const QuietView({super.key, required this.view, required this.child});

  final FlutterView view;
  final Widget child;

  @override
  State<QuietView> createState() => _QuietViewState();
}

class _QuietViewState extends State<QuietView> {
  late final _renderView = _QuietRenderView(view: widget.view);

  // What View's own would be, but telling this one's changes.
  late final _owner = PipelineOwner(
    onNeedVisualUpdate: _changed,
    onSemanticsOwnerCreated: () => _renderView.scheduleInitialSemantics(),
    onSemanticsUpdate: (update) => widget.view.updateSemantics(update),
    onSemanticsOwnerDisposed: () => _renderView.clearSemantics(),
  );

  /// Something in it is to be laid out or painted again: a frame for it.
  void _changed() {
    _renderView.changed = true;
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _owner.dispose();
    super.dispose();
  }

  @override
  // The way in to a view's pipeline and render view, deprecated since 3.10
  // and there still: were it to go, View, every view sent at each frame.
  Widget build(BuildContext context) => View(
    view: widget.view,
    // ignore: deprecated_member_use
    deprecatedDoNotUseWillBeRemovedWithoutNoticePipelineOwner: _owner,
    // ignore: deprecated_member_use
    deprecatedDoNotUseWillBeRemovedWithoutNoticeRenderView: _renderView,
    child: widget.child,
  );
}

class _QuietRenderView extends RenderView {
  _QuietRenderView({required super.view});

  /// Whether anything in it changed since its last frame; its first is to
  /// be sent.
  bool changed = true;

  @override
  void compositeFrame() {
    if (!changed) return;
    changed = false;
    super.compositeFrame();
  }
}
