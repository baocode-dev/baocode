import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'editor/monaco/flutter/document_snapshot.dart';
import 'editor/monaco/flutter/language_assets.dart';
import 'ide_editor.dart';
import 'ide_hover.dart';

/// One status bar entry; [onTap] makes it a button with a hover highlight.
/// Its [text] may name icons as VS Code's labels do: `$(error) 2`.
class IdeStatusBarItem {
  const IdeStatusBarItem(
    this.text, {
    this.icon,
    this.tooltip,
    this.onTap,
    this.color,
  });

  final String text;
  final IconData? icon;
  final String? tooltip;
  final VoidCallback? onTap;
  final Color? color;
}

/// The workbench's bottom bar: [left] items after the window edge, [right]
/// items against the other. In the color theme's `statusBar.*` and
/// `statusBarItem.*` colors (workbench/browser/parts/statusbar/
/// statusbarPart.ts, media/statusbarpart.css), but on the shell: no
/// background or top border of its own.
class IdeStatusBar extends StatelessWidget {
  const IdeStatusBar({super.key, required this.left, required this.right});

  final List<IdeStatusBarItem> left;
  final List<IdeStatusBarItem> right;

  static const height = 22.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  for (final item in left) Flexible(child: _StatusItem(item)),
                ],
              ),
            ),
            // Against the right edge, in up to half the bar (a Flexible
            // would start at the half); scrolls instead of overflowing in
            // a narrow window.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth / 2),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [for (final item in right) _StatusItem(item)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusItem extends StatefulWidget {
  const _StatusItem(this.item);

  final IdeStatusBarItem item;

  @override
  State<_StatusItem> createState() => _StatusItemState();
}

class _StatusItemState extends State<_StatusItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final colors = themeColors;
    final hovered = _hover && item.onTap != null;
    // The bar is on the shell (the side bar's color): `statusBar.*` text
    // where the theme's bar has that color too (or none), else the side
    // bar's, as white on Quiet Light's purple bar would not read there.
    final onSideBar = switch (colors.get('statusBar.background')) {
      null => true,
      final background => background == colors.get('sideBar.background'),
    };
    // Its icons too (`color: inherit`); its own color stays on hover.
    final color =
        item.color ??
        (onSideBar
            ? (hovered ? colors.get('statusBarItem.hoverForeground') : null) ??
                  colors['statusBar.foreground']
            : colors['sideBar.foreground']);
    // High contrast themes outline a hovered item (dashed upstream).
    final outline = hovered ? colors.get('contrastActiveBorder') : null;
    Widget child = Container(
      height: IdeStatusBar.height - 1,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: hovered
          ? colors['statusBarItem.hoverBackground']
          : Colors.transparent,
      foregroundDecoration: outline == null
          ? null
          : BoxDecoration(border: Border.all(color: outline)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.icon case final icon?) ...[
            Icon(icon, size: 14, color: color),
            if (item.text.isNotEmpty) const SizedBox(width: 4),
          ],
          if (item.text.isNotEmpty)
            Flexible(
              child: Text.rich(
                _label(item.text, color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: color),
              ),
            ),
        ],
      ),
    );
    if (item.onTap != null) {
      child = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: item.onTap,
          child: child,
        ),
      );
    }
    if (item.tooltip case final tooltip?) {
      child = IdeHover(
        message: tooltip,
        position: IdeHoverPosition.above,
        pointer: true,
        child: child,
      );
    }
    return child;
  }
}

/// The icons a label can name (`$(name)`).
const _labelIcons = {
  'error': Codicons.error,
  'warning': Codicons.warning,
  'info': Codicons.info,
};

final _labelIcon = RegExp(r'\$\(([a-z-]+)\)');

/// [text] with its `$(name)` icons as codicons (`renderLabelWithIcons`).
TextSpan _label(String text, Color color) {
  final spans = <InlineSpan>[];
  var start = 0;
  for (final match in _labelIcon.allMatches(text)) {
    final icon = _labelIcons[match[1]];
    if (icon == null) continue;
    if (match.start > start) {
      spans.add(TextSpan(text: text.substring(start, match.start)));
    }
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Icon(icon, size: 14, color: color),
      ),
    );
    start = match.end;
  }
  if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
  return TextSpan(children: spans);
}

/// `UTF-8 with BOM` when [text] starts with U+FEFF, else `UTF-8`.
String ideEncodingLabel(String text) =>
    text.startsWith('\uFEFF') ? 'UTF-8 with BOM' : 'UTF-8';

/// `LF`, `CRLF`, `CR` or `Mixed`, from the first [sample] line endings of
/// [snapshot] (cheap on large files). No line endings reads as `LF`.
String ideEolLabel(DocumentSnapshot snapshot, {int sample = 1000}) {
  var lf = false;
  var crlf = false;
  var cr = false;
  final lengths = snapshot.newlineLengths;
  final count = lengths.length < sample ? lengths.length : sample;
  for (var i = 0; i < count; i++) {
    final length = lengths[i];
    if (length == 2) {
      crlf = true;
    } else if (length == 1) {
      if (snapshot.text.codeUnitAt(snapshot.contentEnds[i]) == 0x0D) {
        cr = true;
      } else {
        lf = true;
      }
    }
  }
  final kinds = (lf ? 1 : 0) + (crlf ? 1 : 0) + (cr ? 1 : 0);
  if (kinds > 1) return 'Mixed';
  if (crlf) return 'CRLF';
  if (cr) return 'CR';
  return 'LF';
}

/// Language names from Monaco's pinned registrations (their first alias),
/// falling back to [languageNameForFile] until they load or when none match.
class IdeLanguageNames {
  IdeLanguageNames._();

  static List<MonacoLanguageRegistration>? _registrations;
  static Future<void>? _loading;

  /// Loads the registrations once; [onLoaded] runs when they first arrive.
  static void ensureLoaded(VoidCallback onLoaded) {
    if (_registrations != null) return;
    _loading ??= const MonacoLanguageAssets()
        .registrations()
        .then<void>((value) => _registrations = value)
        .catchError((Object _) {});
    unawaited(_loading!.then((_) => onLoaded()));
  }

  static String forPath(String path) {
    final registrations = _registrations;
    if (registrations == null) return languageNameForFile(path);
    final lower = p.basename(path).toLowerCase();
    MonacoLanguageRegistration? best;
    var bestLength = 0;
    for (final registration in registrations) {
      if (registration.filenames.any((name) => name.toLowerCase() == lower)) {
        best = registration;
        break;
      }
      for (final extension in registration.extensions) {
        if (extension.length > bestLength &&
            lower.endsWith(extension.toLowerCase())) {
          best = registration;
          bestLength = extension.length;
        }
      }
    }
    if (best == null) return languageNameForFile(path);
    return best.aliases.isNotEmpty ? best.aliases.first : best.id;
  }
}
