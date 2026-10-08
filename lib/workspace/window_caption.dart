import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'window_controls.dart';
import 'window_header/window_buttons.dart';

/// The top of the chat's window where the app draws the caption itself
/// (Windows; see [WindowControls.drawsHeader]): as on macOS, the sidebar's
/// and the conversation's own title bars reach the top of the window, and
/// the window's buttons sit over its top right, as the traffic lights do
/// over its top left there. No menu bar: the IDE's header keeps that (see
/// window_header/).
///
/// It tells the window where the title bars' controls are (each a
/// [TitleBarControls], which registers here): the window leaves those pixels
/// to Flutter, drags itself by the rest of the strip, and runs the three
/// window buttons (see [WindowControls.setHitTestAreas]). While not
/// [enabled] (the IDE shows, with a header of its own) it does neither.
///
/// Elsewhere it is only [child].
class WindowCaption extends StatefulWidget {
  const WindowCaption({super.key, required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  /// The strip the window drags itself by: the title bars' own height.
  static const height = AppMetrics.titleBarHeight;

  /// What the window's buttons take at the window's top right, for a title
  /// bar that reaches it to keep clear of (see [CaptionInset]).
  static double get buttonsWidth =>
      WindowControls.drawsHeader ? 3 * AppMetrics.windowButtonWidth : 0;

  /// The caption [context] is under, for its controls to register with; null
  /// outside any (macOS, the IDE's own title bar).
  static WindowCaptionState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CaptionScope>()?.state;

  @override
  State<WindowCaption> createState() => WindowCaptionState();
}

class WindowCaptionState extends State<WindowCaption> {
  /// The title bars' controls, as registered: read back as rectangles after
  /// each layout.
  final Set<BuildContext> _controls = {};

  final _minimize = GlobalKey(debugLabel: 'caption minimize');
  final _maximize = GlobalKey(debugLabel: 'caption maximize');
  final _close = GlobalKey(debugLabel: 'caption close');

  /// What the window was last told, so an unchanged caption is not told
  /// again.
  List<Rect>? _reported;

  /// [control] is one of a title bar's controls: a click there is Flutter's.
  void add(BuildContext control) => _controls.add(control);

  void remove(BuildContext control) => _controls.remove(control);

  @override
  void initState() {
    super.initState();
    if (WindowControls.drawsHeader) _watch();
  }

  @override
  void didUpdateWidget(WindowCaption oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The IDE's header told the window of its own meanwhile.
    if (!widget.enabled) _reported = null;
  }

  /// Checks where the controls are after every frame, as WindowHeader does:
  /// they move without this being built again. No frame is asked for, and
  /// the window hears only of a change.
  void _watch() {
    if (!mounted) return;
    if (widget.enabled) _report();
    SchedulerBinding.instance.addPostFrameCallback((_) => _watch());
  }

  @override
  Widget build(BuildContext context) {
    if (!WindowControls.drawsHeader) return widget.child;
    return _CaptionScope(
      state: this,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (widget.enabled)
            Positioned(
              top: 0,
              right: 0,
              child: WindowButtons(
                minimizeKey: _minimize,
                maximizeKey: _maximize,
                closeKey: _close,
                height: WindowCaption.height,
              ),
            ),
        ],
      ),
    );
  }

  void _report() {
    final minimize = _rect(_minimize.currentContext);
    final maximize = _rect(_maximize.currentContext);
    final close = _rect(_close.currentContext);
    // Not laid out yet (or going away): leave the window as it is.
    if (minimize == null || maximize == null || close == null) return;
    // The close button ends at the window's right.
    final width = close.right;
    final controls = <Rect>[
      for (final control in _controls)
        // Those in the strip: not a lower pane's title bar, nor a sidebar
        // slid out of the window.
        if (_rect(control) case final rect?
            when rect.top < WindowCaption.height &&
                rect.bottom > 0 &&
                rect.right > 0 &&
                rect.left < width)
          rect,
    ];
    final areas = [minimize, maximize, close, ...controls];
    if (listEquals(_reported, areas)) return;
    _reported = areas;
    WindowControls.setHitTestAreas(
      viewId: View.maybeOf(context)?.viewId ?? 0,
      height: WindowCaption.height,
      controls: controls,
      minimize: minimize,
      maximize: maximize,
      close: close,
    );
  }

  /// Where [context]'s widget is in the window, in the app's own pixels;
  /// null while it is not laid out.
  static Rect? _rect(BuildContext? context) {
    if (context == null || !context.mounted) return null;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}

class _CaptionScope extends InheritedWidget {
  const _CaptionScope({required this.state, required super.child});

  final WindowCaptionState state;

  @override
  bool updateShouldNotify(_CaptionScope oldWidget) => state != oldWidget.state;
}

/// How much of the right of the title bar in [child] the window's buttons
/// take (see [WindowCaption]): none but where the title bar reaches the
/// window's top right.
class CaptionInset extends InheritedWidget {
  const CaptionInset({super.key, required this.right, required super.child});

  final double right;

  /// The inset where [context] is; none outside any.
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CaptionInset>()?.right ?? 0;

  @override
  bool updateShouldNotify(CaptionInset oldWidget) => oldWidget.right != right;
}
