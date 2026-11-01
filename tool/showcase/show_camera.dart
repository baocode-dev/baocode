// The showcase's pictures: the app laid out at a window's size, with what
// the system draws around it drawn too (the wallpaper, the window's
// shadow, its rounded corners and traffic lights, the sidebar's material
// blurring the wallpaper), as a screenshot of the window would show. All
// drawn in the app, so it needs no screen recording, and comes out the
// same on any machine.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// The window's frame as the picture has it: its size, and how dark the
/// theme is (the material under the sidebar, the window's edge).
class ShowWindow {
  const ShowWindow(this.size, {this.dark = true});

  final Size size;
  final bool dark;

  /// The room around the window in the picture.
  static const margin = EdgeInsets.fromLTRB(56, 44, 56, 68);

  static const radius = 12.0;

  Size get canvas =>
      Size(size.width + margin.horizontal, size.height + margin.vertical);

  Rect get rect => Offset(margin.left, margin.top) & size;
}

/// The wallpaper behind the window: soft light over a dusk, warm as the
/// app's own colors.
void paintWallpaper(Canvas canvas, Size size) {
  final rect = Offset.zero & size;
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        const [Color(0xFF1B1F3B), Color(0xFF3A2B5C), Color(0xFF7A3E4E)],
        const [0, 0.55, 1],
      ),
  );
  void glow(Offset center, double radius, Color color) => canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.radial(center, radius, [
        color,
        color.withValues(alpha: 0),
      ]),
  );
  final longest = max(size.width, size.height);
  glow(
    Offset(size.width * 0.85, size.height * 0.95),
    longest * 0.55,
    const Color(0xCCE8A15A),
  );
  glow(
    Offset(size.width * 0.1, size.height * 0.05),
    longest * 0.5,
    const Color(0x993B6FD8),
  );
  glow(
    Offset(size.width * 0.45, size.height * 0.6),
    longest * 0.35,
    const Color(0x55D86A8A),
  );
}

/// Lays the app out at [window]'s size, at the view's top left, over what
/// the system's sidebar material would show there; [shotKey] takes its
/// picture.
class ShowFrame extends StatelessWidget {
  const ShowFrame({
    super.key,
    required this.window,
    required this.shotKey,
    required this.child,
  });

  final ValueListenable<ShowWindow> window;
  final GlobalKey shotKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: window,
    builder: (context, window, _) {
      final media = MediaQueryData.fromView(View.of(context));
      return Align(
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(
          size: window.size,
          child: RepaintBoundary(
            key: shotKey,
            child: Stack(
              alignment: Alignment.topLeft,
              fit: StackFit.expand,
              children: [
                _Material(window: window),
                MediaQuery(
                  data: media.copyWith(size: window.size),
                  child: child,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// The sidebar's material: the wallpaper under the window, blurred and
/// tinted as the theme is.
class _Material extends StatelessWidget {
  const _Material({required this.window});

  final ShowWindow window;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: Stack(
      alignment: Alignment.topLeft,
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 50, sigmaY: 50),
          child: CustomPaint(painter: _WallpaperUnder(window)),
        ),
        ColoredBox(
          color: window.dark
              ? const Color(0xC8222226)
              : const Color(0xD0ECEBEA),
        ),
      ],
    ),
  );
}

class _WallpaperUnder extends CustomPainter {
  _WallpaperUnder(this.window);

  final ShowWindow window;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(-window.rect.left, -window.rect.top);
    paintWallpaper(canvas, window.canvas);
  }

  @override
  bool shouldRepaint(_WallpaperUnder old) =>
      old.window.size != window.size || old.window.dark != window.dark;
}

/// Takes the app's pictures, and puts them in their window.
class ShowCamera {
  ShowCamera(this.shotKey);

  final GlobalKey shotKey;

  /// The app as it shows, [pixelRatio] times its size.
  Future<ui.Image> app({double pixelRatio = 2}) async {
    final boundary =
        shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return boundary.toImage(pixelRatio: pixelRatio);
  }

  /// [app] in its window, on the wallpaper, as a picture of the window
  /// would show it; or, if [bare], the window alone, nothing around its
  /// rounded corners: for a page to set it on whatever it likes.
  Future<ui.Image> framed(
    ui.Image app,
    ShowWindow window, {
    double pixelRatio = 2,
    bool bare = false,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    final rect = bare ? Offset.zero & window.size : window.rect;
    final rounded = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(ShowWindow.radius),
    );
    if (!bare) {
      paintWallpaper(canvas, window.canvas);
      // The window's shadow: a wide soft one, and a close darker one.
      canvas.drawRRect(
        rounded.shift(const Offset(0, 22)),
        Paint()
          ..color = const Color(0x8C000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28),
      );
      canvas.drawRRect(
        rounded.shift(const Offset(0, 2)),
        Paint()
          ..color = const Color(0x66000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
    canvas
      ..save()
      ..clipRRect(rounded);
    canvas.drawImageRect(
      app,
      Offset.zero & Size(app.width.toDouble(), app.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
    _trafficLights(canvas, rect.topLeft);
    // The window's edge: a hairline, light on a dark window.
    canvas.drawRRect(
      rounded.deflate(0.25),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = window.dark
            ? const Color(0x40FFFFFF)
            : const Color(0x33000000),
    );
    final picture = recorder.endRecording();
    final size = (bare ? window.size : window.canvas) * pixelRatio;
    final image = await picture.toImage(
      size.width.round(),
      size.height.round(),
    );
    picture.dispose();
    return image;
  }

  /// The close, minimize and zoom buttons, where AppKit puts them.
  static void _trafficLights(Canvas canvas, Offset window) {
    const colors = [
      (Color(0xFFFF5F57), Color(0xFFE2463F)),
      (Color(0xFFFEBC2E), Color(0xFFE1A116)),
      (Color(0xFF28C840), Color(0xFF14AE2A)),
    ];
    for (final (i, (fill, edge)) in colors.indexed) {
      final center = window + Offset(14.0 + i * 20, 14);
      canvas
        ..drawCircle(center, 6, Paint()..color = fill)
        ..drawCircle(
          center,
          5.75,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5
            ..color = edge,
        );
    }
  }

  /// A picture of the window, as a PNG at [path]: on the wallpaper, and
  /// bare beside it (`<name>.window.png`).
  Future<void> shot(
    String path,
    ShowWindow window, {
    double pixelRatio = 2,
  }) async {
    final image = await app(pixelRatio: pixelRatio);
    for (final bare in [false, true]) {
      final framed = await this.framed(
        image,
        window,
        pixelRatio: pixelRatio,
        bare: bare,
      );
      final bytes = await framed.toByteData(format: ui.ImageByteFormat.png);
      framed.dispose();
      File(bare ? path.replaceFirst(RegExp(r'\.png$'), '.window.png') : path)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    }
    image.dispose();
  }

  /// Records the window, bare (see [framed]), as a video at [path], a
  /// frame each 1/[fps] of the app's time, until [body] is done: the app runs [dilation] times
  /// slower meanwhile ([dilate]), for each frame to be taken in time. The
  /// frames go straight to ffmpeg.
  Future<void> record(
    String path,
    ShowWindow window,
    Future<void> Function() body, {
    double pixelRatio = 1.5,
    int fps = 30,
    required double dilation,
    required void Function(double dilation) dilate,
  }) async {
    final size = window.size * pixelRatio;
    final width = size.width.round(), height = size.height.round();
    File(path).parent.createSync(recursive: true);
    final ffmpeg = await Process.start('ffmpeg', [
      '-y',
      '-loglevel',
      'error',
      '-f',
      'rawvideo',
      '-pix_fmt',
      'rgba',
      '-s',
      '${width}x$height',
      '-r',
      '$fps',
      '-i',
      '-',
      '-vf',
      'scale=1920:-2:flags=lanczos,format=yuv420p',
      '-c:v',
      'libx264',
      '-preset',
      'slow',
      '-crf',
      '24',
      '-movflags',
      '+faststart',
      path,
    ]);
    final errors = StringBuffer();
    final stderrDone = ffmpeg.stderr
        .transform(const SystemEncoding().decoder)
        .forEach(errors.write);
    var frames = 0;
    var recording = true;
    dilate(dilation);
    final interval = Duration(microseconds: (1e6 / fps * dilation).round());
    final clock = Stopwatch()..start();
    final done = body().whenComplete(() => recording = false);
    try {
      while (recording) {
        final wait = interval * frames - clock.elapsed;
        if (wait > Duration.zero) await Future<void>.delayed(wait);
        await SchedulerBinding.instance.endOfFrame;
        final image = await app(pixelRatio: pixelRatio);
        final framed = await this.framed(
          image,
          window,
          pixelRatio: pixelRatio,
          bare: true,
        );
        image.dispose();
        final bytes = (await framed.toByteData())!.buffer.asUint8List();
        framed.dispose();
        // Frames that came late are repeated: the video keeps the app's
        // time.
        do {
          ffmpeg.stdin.add(bytes);
          frames++;
        } while (interval * frames < clock.elapsed - interval);
        await ffmpeg.stdin.flush();
      }
      await done;
    } finally {
      dilate(1);
      await ffmpeg.stdin.close();
    }
    final code = await ffmpeg.exitCode;
    await stderrDone;
    if (code != 0) throw StateError('ffmpeg failed: $errors');
  }
}
