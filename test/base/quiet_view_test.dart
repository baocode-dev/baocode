import 'dart:ui';

import 'package:baocode/base/quiet_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// [view] under another id, its frames counted rather than drawn.
class _CountedView implements FlutterView {
  _CountedView(this._view, this.viewId);

  final FlutterView _view;

  @override
  final int viewId;

  int frames = 0;

  @override
  void render(Scene scene, {Size? size}) => frames++;

  @override
  void updateSemantics(SemanticsUpdate update) {}

  @override
  PlatformDispatcher get platformDispatcher => _view.platformDispatcher;
  @override
  Display get display => _view.display;
  @override
  double get devicePixelRatio => _view.devicePixelRatio;
  @override
  Size get physicalSize => _view.physicalSize;
  @override
  ViewConstraints get physicalConstraints => _view.physicalConstraints;
  @override
  ViewPadding get padding => _view.padding;
  @override
  ViewPadding get viewPadding => _view.viewPadding;
  @override
  ViewPadding get viewInsets => _view.viewInsets;
  @override
  ViewPadding get systemGestureInsets => _view.systemGestureInsets;
  @override
  GestureSettings get gestureSettings => _view.gestureSettings;
  @override
  List<DisplayFeature> get displayFeatures => _view.displayFeatures;
  @override
  DisplayCornerRadii? get displayCornerRadii => _view.displayCornerRadii;
}

class _Spinner extends StatefulWidget {
  const _Spinner();

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner>
    with SingleTickerProviderStateMixin {
  late final _turns = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _turns,
    child: const SizedBox.square(dimension: 10),
  );
}

void main() {
  testWidgets('a view is sent a frame only when something in it changed', (
    tester,
  ) async {
    final moving = _CountedView(tester.view, 101);
    final still = _CountedView(tester.view, 102);
    final text = ValueNotifier('a');
    addTearDown(text.dispose);
    await tester.pumpWidget(
      wrapWithView: false,
      ViewCollection(
        views: [
          QuietView(
            view: moving,
            child: const Center(child: _Spinner()),
          ),
          QuietView(
            view: still,
            child: ValueListenableBuilder(
              valueListenable: text,
              builder: (context, value, _) =>
                  Text(value, textDirection: TextDirection.ltr),
            ),
          ),
        ],
      ),
    );
    final first = (moving.frames, still.frames);
    expect(first, (1, 1));

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(moving.frames, 11);
    // Nothing in it moved.
    expect(still.frames, 1);

    text.value = 'b';
    await tester.pump(const Duration(milliseconds: 16));
    expect(still.frames, 2);
    expect(moving.frames, 12);

    await tester.pumpWidget(
      wrapWithView: false,
      const ViewCollection(views: []),
    );
  });
}
