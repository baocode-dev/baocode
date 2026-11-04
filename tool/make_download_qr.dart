// Writes site/qr/: the two QR codes the download page's phone cards show
// (site/download.html and site/zh/download.html; site/style.css draws
// them). Run from anywhere in the repository:
//
//   dart run tool/make_download_qr.dart
//
// Each encodes that card's own link on the site — /dl/android, /dl/ios —
// and not the file on dl.baocode.dev: those links are permanent, and
// site-worker/index.js points them at the release current when the code is
// scanned, so a code written here (or photographed off the page) keeps
// working as the phone app is released again. The site has no build step:
// test/tool/download_qr_test.dart fails while site/qr/ is not what this
// writes, so run this and commit the files when a target changes.
import 'dart:io';

import 'package:baocode/link/phone_downloads.dart';
import 'package:qr/qr.dart';

/// Each phone card's target, as site/download.html links it, by the card
/// it belongs to: the phone app's two downloads (docs/release.md, 10), the
/// same as Settings → Mobile shows. test/tool/download_qr_test.dart holds
/// the pages to this.
const downloadQrTargets = phoneDownloadTargets;

/// The colors of the page they are shown on (site/style.css): its ink and
/// its paper. Scanners read that contrast as well as black on white.
const _ink = '#1B1A17';
const _paper = '#FFFFFF';

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: dart run tool/make_download_qr.dart');
    exit(1);
  }
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  for (final MapEntry(key: path, value: svg) in downloadQrSvgs().entries) {
    final file = File.fromUri(root.uri.resolve(path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(svg);
    stdout.writeln(file.path);
  }
}

/// Each code's SVG, by its path in the repository.
Map<String, String> downloadQrSvgs() => {
  for (final os in downloadQrTargets.keys)
    'site/qr/$os.svg': qrSvg(phoneDownloadUrl(os)),
};

/// [data] as a QR code in SVG: one unit to a module, the quiet margin the
/// standard asks for around it, and square corners that scaling keeps sharp
/// (`shape-rendering`).
String qrSvg(String data) {
  final image = QrImage(
    QrCode(
      payload: QrPayload.fromString(data),
      errorCorrectLevel: QrErrorCorrectLevel.medium,
    ),
  );
  final count = image.moduleCount;
  // Modules of white around it, as on the app's own codes
  // (lib/link/qr_view.dart).
  const quiet = 4;
  final side = count + quiet * 2;
  final path = StringBuffer();
  for (var row = 0; row < count; row++) {
    for (var col = 0; col < count; col++) {
      if (!image.isDark(row, col)) continue;
      // A run of dark modules is one command, not one per module.
      var run = 1;
      while (col + run < count && image.isDark(row, col + run)) {
        run++;
      }
      final x = col + quiet;
      final y = row + quiet;
      path.write('M$x ${y}h${run}v1h-${run}z');
      col += run - 1;
    }
  }
  return '<svg xmlns="http://www.w3.org/2000/svg" '
      'viewBox="0 0 $side $side" width="296" height="296" '
      'shape-rendering="crispEdges">'
      '<rect width="$side" height="$side" fill="$_paper"/>'
      '<path fill="$_ink" d="$path"/>'
      '</svg>\n';
}
