// Files, folders and disks as Finder draws them, for the remote browser:
// the phone app's (mobile's lib/ui/files/file_icons.dart), with the home
// folder's and the disks' added.

import 'dart:math' as math;

import 'package:bao_remote/client.dart' show BrowseRootKind;
import 'package:flutter/widgets.dart';

/// What a file is, as its icon tells it.
enum FileKind { document, image, pdf, archive, audio, video }

/// The kind of the file at [path], by its extension.
FileKind fileKindOf(String path) => switch (fileExtensionOf(path)) {
  'png' ||
  'jpg' ||
  'jpeg' ||
  'gif' ||
  'webp' ||
  'heic' ||
  'heif' ||
  'bmp' ||
  'tif' ||
  'tiff' ||
  'ico' ||
  'icns' ||
  'svg' => FileKind.image,
  'pdf' => FileKind.pdf,
  'zip' ||
  'tar' ||
  'gz' ||
  'tgz' ||
  'bz2' ||
  'xz' ||
  'zst' ||
  'rar' ||
  '7z' ||
  'dmg' ||
  'jar' => FileKind.archive,
  'mp3' ||
  'wav' ||
  'm4a' ||
  'aac' ||
  'flac' ||
  'ogg' ||
  'aiff' => FileKind.audio,
  'mp4' || 'mov' || 'm4v' || 'avi' || 'mkv' || 'webm' => FileKind.video,
  _ => FileKind.document,
};

/// The extension of the file at [path], lower case; empty for none (a
/// leading dot is not one: `.gitignore` has none).
String fileExtensionOf(String path) {
  final name = path.substring(path.lastIndexOf('/') + 1);
  final dot = name.lastIndexOf('.');
  return dot <= 0 || dot == name.length - 1
      ? ''
      : name.substring(dot + 1).toLowerCase();
}

/// The file at [path] as Finder draws one: a white page, its corner
/// folded; what it is under the fold (its extension, or a picture's,
/// a sound's, a film's, an archive's mark), lines of text when small.
class FinderFileIcon extends StatelessWidget {
  const FinderFileIcon(this.path, {super.key, this.size = 16});

  final String path;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _PagePainter(
        kind: fileKindOf(path),
        label: fileExtensionOf(path).toUpperCase(),
        font: DefaultTextStyle.of(context).style,
      ),
    ),
  );
}

/// A folder as Finder draws one: blue, its tab at the back; the home
/// folder's with a house on its front ([home]); a new one's with a green
/// plus at its corner ([add]).
class FinderFolderIcon extends StatelessWidget {
  const FinderFolderIcon({
    super.key,
    this.size = 16,
    this.home = false,
    this.add = false,
  });

  final double size;
  final bool home;
  final bool add;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _FolderPainter(home: home, add: add),
    ),
  );
}

/// A disk as Finder draws one: a grey slab, its front darker; a removable
/// one's light amber, a network one's a globe's blue, a disc's a disc.
class FinderDiskIcon extends StatelessWidget {
  const FinderDiskIcon({
    super.key,
    this.size = 16,
    this.kind = BrowseRootKind.fixed,
  });

  final double size;
  final BrowseRootKind kind;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _DiskPainter(kind)),
  );
}

/// A computer as Finder draws one, for Explorer's This PC: a screen, blue
/// as a desktop's, on its stand.
class FinderComputerIcon extends StatelessWidget {
  const FinderComputerIcon({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: const CustomPaint(painter: _ComputerPainter()),
  );
}

/// Finder's colors: the page, its edge and fold, what is drawn on it.
abstract final class _Finder {
  static const page = Color(0xFFFCFCFC);
  static const edge = Color(0x33000000);
  static const fold = Color(0xFFE4E4E7);
  static const mark = Color(0xFF8E8E93);
  static const lines = Color(0xFFC7C7CC);
  static const pdf = Color(0xFFE5463B);

  static const folderBack = Color(0xFF5AA7EC);
  static const folderTop = Color(0xFF8FCEFB);
  static const folderBottom = Color(0xFF6DB8F4);
  static const folderEdge = Color(0xFFB6E1FD);
  static const folderMark = Color(0xFF2A73C2);
  static const add = Color(0xFF34C759);

  static const diskTop = Color(0xFFF2F2F4);
  static const diskBottom = Color(0xFFD1D1D6);
  static const diskFront = Color(0xFF9E9EA4);
  static const diskEdge = Color(0x40000000);
  static const diskLight = Color(0xFF34C759);
  static const removable = Color(0xFFF5B940);
  static const network = Color(0xFF5AA7EC);
}

class _PagePainter extends CustomPainter {
  const _PagePainter({
    required this.kind,
    required this.label,
    required this.font,
  });

  final FileKind kind;
  final String label;

  /// The text's around it, for the label's face.
  final TextStyle font;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final width = s * 0.76;
    final height = s * 0.96;
    final page = Rect.fromLTWH(
      (size.width - width) / 2,
      (size.height - height) / 2,
      width,
      height,
    );
    final fold = width * 0.3;
    final r = s * 0.06;
    final stroke = math.max(0.75, s * 0.025);

    final outline = Path()
      ..moveTo(page.left + r, page.top)
      ..lineTo(page.right - fold, page.top)
      ..lineTo(page.right, page.top + fold)
      ..lineTo(page.right, page.bottom - r)
      ..arcToPoint(
        Offset(page.right - r, page.bottom),
        radius: Radius.circular(r),
      )
      ..lineTo(page.left + r, page.bottom)
      ..arcToPoint(
        Offset(page.left, page.bottom - r),
        radius: Radius.circular(r),
      )
      ..lineTo(page.left, page.top + r)
      ..arcToPoint(Offset(page.left + r, page.top), radius: Radius.circular(r))
      ..close();
    canvas
      ..drawPath(outline, Paint()..color = _Finder.page)
      ..drawPath(
        outline,
        Paint()
          ..color = _Finder.edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
    final corner = Path()
      ..moveTo(page.right - fold, page.top)
      ..lineTo(page.right - fold, page.top + fold - r)
      ..arcToPoint(
        Offset(page.right - fold + r, page.top + fold),
        radius: Radius.circular(r),
        clockwise: false,
      )
      ..lineTo(page.right, page.top + fold)
      ..close();
    canvas
      ..drawPath(corner, Paint()..color = _Finder.fold)
      ..drawPath(
        corner,
        Paint()
          ..color = _Finder.edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeJoin = StrokeJoin.round,
      );

    // What it is, under the fold.
    final body = Rect.fromLTRB(
      page.left + width * 0.16,
      page.top + fold + height * 0.06,
      page.right - width * 0.16,
      page.bottom - height * 0.1,
    );
    final mark = Paint()
      ..color = _Finder.mark
      ..style = PaintingStyle.fill;
    switch (kind) {
      case FileKind.image:
        _picture(canvas, body, mark);
      case FileKind.audio:
        _note(canvas, body, mark);
      case FileKind.video:
        _film(canvas, body, mark);
      case FileKind.archive:
        _zipper(canvas, page, fold, mark);
      case FileKind.pdf:
        _label(canvas, body, s, 'PDF', _Finder.pdf) ||
            _lines(canvas, body, s, _Finder.pdf.withValues(alpha: 0.6));
      case FileKind.document:
        _label(canvas, body, s, label, _Finder.mark) ||
            _lines(canvas, body, s, _Finder.lines);
    }
  }

  /// [text] at the page's foot, where it is big enough to read.
  bool _label(Canvas canvas, Rect body, double s, String text, Color color) {
    if (s < 40 || text.isEmpty) return false;
    final shown = text.length > 4 ? text.substring(0, 4) : text;
    final painter = TextPainter(
      text: TextSpan(
        text: shown,
        style: font.copyWith(
          color: color,
          fontSize: s * (shown.length > 3 ? 0.13 : 0.15),
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          decoration: TextDecoration.none,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter
      ..paint(
        canvas,
        Offset(
          body.center.dx - painter.width / 2,
          body.bottom - painter.height,
        ),
      )
      ..dispose();
    return true;
  }

  /// A page's lines of text.
  bool _lines(Canvas canvas, Rect body, double s, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = math.max(1, s * 0.05)
      ..strokeCap = StrokeCap.round;
    final gap = body.height / 3.2;
    for (final (i, part) in const [1.0, 1.0, 0.6].indexed) {
      final y = body.top + gap * (i + 0.6);
      canvas.drawLine(
        Offset(body.left, y),
        Offset(body.left + body.width * part, y),
        paint,
      );
    }
    return true;
  }

  /// Hills and a sun.
  void _picture(Canvas canvas, Rect body, Paint paint) {
    final box = Rect.fromCenter(
      center: body.center,
      width: body.width,
      height: body.width * 0.78,
    );
    canvas
      ..drawCircle(
        Offset(box.left + box.width * 0.28, box.top + box.height * 0.28),
        box.width * 0.12,
        paint,
      )
      ..drawPath(
        Path()
          ..moveTo(box.left, box.bottom)
          ..lineTo(box.left + box.width * 0.36, box.top + box.height * 0.5)
          ..lineTo(box.left + box.width * 0.56, box.top + box.height * 0.74)
          ..lineTo(box.left + box.width * 0.72, box.top + box.height * 0.56)
          ..lineTo(box.right, box.bottom)
          ..close(),
        paint,
      );
  }

  /// A note.
  void _note(Canvas canvas, Rect body, Paint paint) {
    final w = body.width;
    final head = w * 0.17;
    final left = Offset(body.left + w * 0.28, body.bottom - head);
    final right = Offset(body.left + w * 0.78, body.bottom - head * 1.5);
    final stem = math.max(1.0, w * 0.08);
    canvas
      ..drawOval(Rect.fromCircle(center: left, radius: head), paint)
      ..drawOval(Rect.fromCircle(center: right, radius: head), paint)
      ..drawPath(
        Path()
          ..moveTo(left.dx + head - stem, left.dy)
          ..lineTo(left.dx + head - stem, body.top + w * 0.22)
          ..lineTo(right.dx + head, body.top)
          ..lineTo(right.dx + head, right.dy)
          ..lineTo(right.dx + head - stem, right.dy)
          ..lineTo(right.dx + head - stem, body.top + w * 0.2)
          ..lineTo(left.dx + head, body.top + w * 0.36)
          ..lineTo(left.dx + head, left.dy)
          ..close(),
        paint,
      );
  }

  /// A frame and play.
  void _film(Canvas canvas, Rect body, Paint paint) {
    final box = Rect.fromCenter(
      center: body.center,
      width: body.width,
      height: body.width * 0.74,
    );
    final r = box.height * 0.14;
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(box, Radius.circular(r)),
        Paint()
          ..color = paint.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, box.width * 0.08),
      )
      ..drawPath(
        Path()
          ..moveTo(
            box.center.dx - box.width * 0.13,
            box.center.dy - box.height * 0.22,
          )
          ..lineTo(box.center.dx + box.width * 0.2, box.center.dy)
          ..lineTo(
            box.center.dx - box.width * 0.13,
            box.center.dy + box.height * 0.22,
          )
          ..close(),
        paint,
      );
  }

  /// A zip down the middle, its pull at the end.
  void _zipper(Canvas canvas, Rect page, double fold, Paint paint) {
    final x = page.center.dx;
    final tooth = page.width * 0.09;
    var y = page.top;
    var left = true;
    while (y < page.top + page.height * 0.56) {
      canvas.drawRect(
        Rect.fromLTWH(left ? x - tooth : x, y, tooth, tooth * 0.8),
        paint,
      );
      y += tooth * 0.8;
      left = !left;
    }
    final pull = Rect.fromCenter(
      center: Offset(x, y + tooth * 1.2),
      width: tooth * 2.2,
      height: tooth * 2.6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(pull, Radius.circular(tooth * 0.5)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_PagePainter old) =>
      old.kind != kind || old.label != label || old.font != font;
}

class _FolderPainter extends CustomPainter {
  const _FolderPainter({this.home = false, this.add = false});

  final bool home;
  final bool add;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final width = s * 0.94;
    final height = s * 0.76;
    final box = Rect.fromLTWH(
      (size.width - width) / 2,
      (size.height - height) / 2,
      width,
      height,
    );
    final r = s * 0.07;
    final tab = height * 0.13;

    // The back, its tab at its left.
    final back = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(box.left, box.top + tab, box.right, box.bottom),
          Radius.circular(r),
        ),
      )
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(box.left, box.top, width * 0.42, tab * 2),
          Radius.circular(r),
        ),
      );
    canvas.drawPath(back, Paint()..color = _Finder.folderBack);

    // The front, over it, lower.
    final front = RRect.fromRectAndRadius(
      Rect.fromLTRB(box.left, box.top + tab * 2.1, box.right, box.bottom),
      Radius.circular(r),
    );
    canvas
      ..drawRRect(
        front,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_Finder.folderTop, _Finder.folderBottom],
          ).createShader(front.outerRect),
      )
      // Its top edge, catching the light.
      ..save()
      ..clipRRect(front)
      ..drawLine(
        Offset(front.left, front.top + 0.5),
        Offset(front.right, front.top + 0.5),
        Paint()
          ..color = _Finder.folderEdge
          ..strokeWidth = math.max(1, s * 0.03),
      )
      ..restore();
    if (home) _house(canvas, front.outerRect, s);
    if (add) _plus(canvas, box, s);
  }

  /// A white plus on a green disc, over the front's lower right corner.
  void _plus(Canvas canvas, Rect box, double s) {
    final radius = s * 0.25;
    final center = Offset(box.right - radius * 0.7, box.bottom - radius * 0.7);
    final arm = radius * 0.52;
    canvas
      ..drawCircle(
        center,
        radius + math.max(0.75, s * 0.04),
        Paint()..color = const Color(0x33000000),
      )
      ..drawCircle(center, radius, Paint()..color = _Finder.add)
      ..drawPath(
        Path()
          ..moveTo(center.dx - arm, center.dy)
          ..lineTo(center.dx + arm, center.dy)
          ..moveTo(center.dx, center.dy - arm)
          ..lineTo(center.dx, center.dy + arm),
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, s * 0.09)
          ..strokeCap = StrokeCap.round,
      );
  }

  /// A house pressed into the front, as the home folder's.
  void _house(Canvas canvas, Rect front, double s) {
    final h = front.height * 0.7;
    final w = h * 1.05;
    final c = front.center + Offset(0, front.height * 0.04);
    final left = c.dx - w / 2, right = c.dx + w / 2;
    final top = c.dy - h / 2, bottom = c.dy + h / 2;
    final eaves = top + h * 0.45;
    final inset = w * 0.17;
    final house = Path()
      ..moveTo(c.dx, top)
      ..lineTo(right, eaves)
      ..lineTo(right - inset, eaves)
      ..lineTo(right - inset, bottom)
      ..lineTo(left + inset, bottom)
      ..lineTo(left + inset, eaves)
      ..lineTo(left, eaves)
      ..close();
    canvas.drawPath(house, Paint()..color = _Finder.folderMark);
  }

  @override
  bool shouldRepaint(_FolderPainter old) => old.home != home || old.add != add;
}

class _DiskPainter extends CustomPainter {
  const _DiskPainter(this.kind);

  final BrowseRootKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    if (kind == BrowseRootKind.optical) return _disc(canvas, size, s);
    final width = s * 0.94;
    final height = s * 0.66;
    final box = Rect.fromLTWH(
      (size.width - width) / 2,
      (size.height - height) / 2,
      width,
      height,
    );
    final r = s * 0.1;
    final body = RRect.fromRectAndRadius(box, Radius.circular(r));
    final accent = switch (kind) {
      BrowseRootKind.removable => _Finder.removable,
      BrowseRootKind.network => _Finder.network,
      _ => null,
    };
    canvas
      ..drawRRect(
        body,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              accent == null
                  ? _Finder.diskTop
                  : Color.lerp(_Finder.diskTop, accent, 0.35)!,
              accent ?? _Finder.diskBottom,
            ],
          ).createShader(box),
      )
      // Its front: the lower part, darker.
      ..save()
      ..clipRRect(body)
      ..drawRect(
        Rect.fromLTRB(
          box.left,
          box.bottom - height * 0.3,
          box.right,
          box.bottom,
        ),
        Paint()..color = _Finder.diskFront.withValues(alpha: 0.55),
      )
      ..restore()
      ..drawRRect(
        body,
        Paint()
          ..color = _Finder.diskEdge
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.75, s * 0.03),
      )
      // Its light, on the front.
      ..drawCircle(
        Offset(box.right - width * 0.14, box.bottom - height * 0.15),
        math.max(0.9, s * 0.045),
        Paint()..color = _Finder.diskLight,
      );
  }

  /// A disc: silver, its hole in the middle.
  void _disc(Canvas canvas, Size size, double s) {
    final center = size.center(Offset.zero);
    final radius = s * 0.46;
    canvas
      ..drawCircle(
        center,
        radius,
        Paint()
          ..shader = const SweepGradient(
            colors: [
              _Finder.diskTop,
              _Finder.diskBottom,
              _Finder.diskTop,
              _Finder.diskBottom,
              _Finder.diskTop,
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      )
      ..drawCircle(
        center,
        radius,
        Paint()
          ..color = _Finder.diskEdge
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.75, s * 0.03),
      )
      ..drawCircle(center, radius * 0.22, Paint()..color = _Finder.diskFront);
  }

  @override
  bool shouldRepaint(_DiskPainter old) => old.kind != kind;
}

class _ComputerPainter extends CustomPainter {
  const _ComputerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final width = s * 0.94;
    final height = s * 0.64;
    final screen = Rect.fromLTWH(
      (size.width - width) / 2,
      (size.height - s) / 2 + s * 0.08,
      width,
      height,
    );
    final r = s * 0.07;
    final frame = RRect.fromRectAndRadius(screen, Radius.circular(r));
    final glass = screen.deflate(math.max(1, s * 0.06));
    // The stand, then the screen over it.
    final stand = Path()
      ..moveTo(screen.center.dx - width * 0.12, screen.bottom)
      ..lineTo(screen.center.dx + width * 0.12, screen.bottom)
      ..lineTo(screen.center.dx + width * 0.17, screen.bottom + s * 0.2)
      ..lineTo(screen.center.dx - width * 0.17, screen.bottom + s * 0.2)
      ..close();
    canvas
      ..drawPath(stand, Paint()..color = _Finder.diskBottom)
      ..drawRRect(frame, Paint()..color = const Color(0xFF3A3A3C))
      ..drawRRect(
        RRect.fromRectAndRadius(glass, Radius.circular(r * 0.5)),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_Finder.folderTop, _Finder.folderBack],
          ).createShader(glass),
      );
  }

  @override
  bool shouldRepaint(_ComputerPainter old) => false;
}
