import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../theme/icon_registry.dart';
import '../theme/workbench_theme.dart' show themeColors;

import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart'
    show EditorOffsetEdit;
import 'package:bao_editor/monaco/flutter/language_assets.dart';
import 'package:bao_editor/textmate/textmate_manifest.dart';

import 'ide_editor.dart';
import 'ide_hover.dart';
import 'ide_spinning.dart';

/// The remote host the workbench's project is on, as the status bar shows
/// it first (VS Code's remote indicator): its state as [item], which
/// changes as the connection does.
abstract interface class IdeRemoteIndicator implements Listenable {
  IdeStatusBarItem item(BuildContext context);
}

/// One status bar entry; [onTap] makes it a button with a hover highlight.
/// Its [text] may name icons as VS Code's labels do: `$(error) 2`, and a
/// `~spin` modifier turns one: `$(sync~spin)`.
class IdeStatusBarItem {
  const IdeStatusBarItem(
    this.text, {
    this.icon,
    this.tooltip,
    this.tooltipContent,
    this.onTap,
    this.onContextMenu,
    this.color,
    this.background,
    this.hoverBackground,
    this.semanticsLabel,
    this.key,
  });

  final String text;
  final IconData? icon;
  final String? tooltip;

  /// Shown on hover instead of [tooltip] (e.g. a Markdown tooltip).
  final Widget? tooltipContent;
  final VoidCallback? onTap;

  /// A secondary click at a global position (e.g. the menu that hides it).
  final void Function(Offset position)? onContextMenu;
  final Color? color;

  /// Behind it (`statusBarItem.errorBackground`…); [hoverBackground] on
  /// hover, else the usual hover color.
  final Color? background;
  final Color? hoverBackground;

  /// What screen readers say (upstream `ariaLabel`).
  final String? semanticsLabel;

  /// Keeps its state (its hover) where items come and go.
  final Key? key;
}

/// The workbench's bottom bar: [left] items after the window edge, [right]
/// items against the other. In the color theme's `statusBar.*` and
/// `statusBarItem.*` colors (workbench/browser/parts/statusbar/
/// statusbarPart.ts, media/statusbarpart.css): `statusBar.background`,
/// and `statusBar.border` above it where the theme has one.
class IdeStatusBar extends StatelessWidget {
  const IdeStatusBar({super.key, required this.left, required this.right});

  final List<IdeStatusBarItem> left;
  final List<IdeStatusBarItem> right;

  static const height = 22.0;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: colors['statusBar.background'],
        border: switch (colors.get('statusBar.border')) {
          final border? => Border(top: BorderSide(color: border)),
          null => null,
        },
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  for (final item in left)
                    Flexible(child: _StatusItem(item, key: item.key)),
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
                  children: [
                    for (final item in right) _StatusItem(item, key: item.key),
                  ],
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
  const _StatusItem(this.item, {super.key});

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
    // Its icons too (`color: inherit`); its own color stays on hover.
    final color =
        item.color ??
        (hovered ? colors.get('statusBarItem.hoverForeground') : null) ??
        colors['statusBar.foreground'];
    // High contrast themes outline a hovered item (dashed upstream).
    final outline = hovered ? colors.get('contrastActiveBorder') : null;
    Widget child = Container(
      height: IdeStatusBar.height - 1,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: hovered
          ? item.hoverBackground ?? colors['statusBarItem.hoverBackground']
          : item.background ?? Colors.transparent,
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
    if (item.onTap != null || item.onContextMenu != null) {
      child = MouseRegion(
        cursor: item.onTap != null
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: item.onTap,
          onSecondaryTapUp: item.onContextMenu == null
              ? null
              : (details) => item.onContextMenu!(details.globalPosition),
          child: child,
        ),
      );
    }
    if (item.tooltipContent != null || item.tooltip != null) {
      child = IdeHover(
        message: item.tooltip,
        content: item.tooltipContent,
        position: IdeHoverPosition.above,
        pointer: true,
        child: child,
      );
    }
    if (item.semanticsLabel case final label?) {
      child = Semantics(label: label, button: item.onTap != null, child: child);
    }
    return child;
  }
}

final _labelIcon = RegExp(r'\$\(([a-z0-9-]+)(~[a-z]+)?\)');

/// [text] with its `$(name)` icons as codicons (`renderLabelWithIcons`),
/// those with `~spin` turning.
TextSpan _label(String text, Color color) {
  final spans = <InlineSpan>[];
  var start = 0;
  for (final match in _labelIcon.allMatches(text)) {
    if (!IconRegistry.instance.contains(match[1]!)) continue;
    if (match.start > start) {
      spans.add(TextSpan(text: text.substring(start, match.start)));
    }
    final glyph = ThemeIcon(match[1]!, size: 14, color: color);
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: match[2] == '~spin' ? IdeSpinning(glyph) : glyph,
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

/// The edits that end every line of [snapshot] with [eol] (`\n` or
/// `\r\n`), as VS Code's Change End of Line Sequence does; a lone CR, which
/// VS Code's model never keeps, becomes [eol] too.
List<EditorOffsetEdit> ideEolEdits(DocumentSnapshot snapshot, String eol) => [
  for (var i = 0; i < snapshot.newlineLengths.length; i++)
    if (snapshot.newlineLengths[i] > 0 &&
        snapshot.text.substring(
              snapshot.contentEnds[i],
              snapshot.contentEnds[i] + snapshot.newlineLengths[i],
            ) !=
            eol)
      EditorOffsetEdit(
        snapshot.contentEnds[i],
        snapshot.contentEnds[i] + snapshot.newlineLengths[i],
        eol,
      ),
];

/// Language names from Monaco's pinned registrations (their first alias),
/// then the TextMate languages (those only a TextMate grammar highlights,
/// e.g. Vue), falling back to [languageNameForFile] until they load or when
/// none match.
class IdeLanguageNames {
  IdeLanguageNames._();

  static List<MonacoLanguageRegistration>? _registrations;
  static List<TextMateLanguageRegistration> _textMateLanguages = const [];
  static Future<void>? _loading;

  /// Loads the registrations once; [onLoaded] runs when they first arrive.
  static void ensureLoaded(VoidCallback onLoaded) {
    if (_registrations != null) return;
    _loading ??= Future.wait([
      const MonacoLanguageAssets()
          .registrations()
          .then<void>((value) => _registrations = value)
          .catchError((Object _) {}),
      TextMateManifest.load(
            (path) => rootBundle.loadString('$textMateAssetRoot/$path'),
          )
          .then<void>((value) => _textMateLanguages = value.languages)
          .catchError((Object _) {}),
    ]);
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
    if (best == null) {
      return _textMateNameForPath(lower) ?? languageNameForFile(path);
    }
    return best.aliases.isNotEmpty ? best.aliases.first : best.id;
  }

  /// The TextMate language a file's lowercased base name [lower] selects
  /// by name or extension, named as VS Code's registry names it: its first
  /// alias, else its id.
  static String? _textMateNameForPath(String lower) {
    String? id;
    var bestLength = 0;
    for (final language in _textMateLanguages) {
      if (language.filenames.any((name) => name.toLowerCase() == lower)) {
        id = language.id;
        break;
      }
      for (final extension in language.extensions) {
        if (extension.length > bestLength &&
            lower.endsWith(extension.toLowerCase())) {
          id = language.id;
          bestLength = extension.length;
        }
      }
    }
    if (id == null) return null;
    for (final language in _textMateLanguages) {
      if (language.id == id && language.aliases.isNotEmpty) {
        return language.aliases.first;
      }
    }
    return id;
  }
}
