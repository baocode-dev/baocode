import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../theme/app_theme.dart';
import '../theme/icon_registry.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../workspace/islands.dart';

import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart'
    show EditorOffsetEdit;
import 'package:bao_editor/monaco/flutter/language_assets.dart';
import 'package:bao_editor/monaco/flutter/language_overrides.dart';
import 'package:bao_editor/textmate/textmate_manifest.dart';

import 'host_paths.dart';
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
    this.onTapRect,
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

  /// A click with where the entry is (global), for a menu anchored on it
  /// (the remote indicator's); [onTap] where the position is not needed.
  final void Function(Rect rect)? onTapRect;

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
/// items against the other (workbench/browser/parts/statusbar/
/// statusbarPart.ts, media/statusbarpart.css). On the window's color,
/// under the parts' cards, not a bar of
/// `statusBar.background`: its items muted, rounded where hovered or of a
/// color of their own (`statusBarItem.*`).
class IdeStatusBar extends StatelessWidget {
  const IdeStatusBar({
    super.key,
    required this.left,
    required this.right,
    this.onRightWidth,
  });

  final List<IdeStatusBarItem> left;
  final List<IdeStatusBarItem> right;

  /// Told each of [right]'s widths (by its index) as it is laid out.
  final void Function(int index, double width)? onRightWidth;

  static const height = Islands.belowHeight;

  /// An item's, centered in it.
  static const itemHeight = 22.0;

  /// Over it where the parts are not islands (see [IslandStyle]), the
  /// line upstream's has: `statusBar.border`, where the theme has one.
  static Color? get line => themeColors.get('statusBar.border');

  /// Under it and its items where the parts are not islands, as upstream's
  /// bar: `statusBar.background`; the window's color under the cards else.
  static Color? backgroundOf(BuildContext context) =>
      Islands.on(context) ? null : themeColors.get('statusBar.background');

  @override
  Widget build(BuildContext context) {
    final line = Islands.on(context) ? null : IdeStatusBar.line;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: switch ((backgroundOf(context), line)) {
        (null, null) => null,
        (final color, final line) => BoxDecoration(
          color: color,
          border: line == null ? null : Border(top: BorderSide(color: line)),
        ),
      },
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
                    for (final (i, item) in right.indexed) _measured(item, i),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// [item], its width told [onRightWidth]: keyed as it is.
  Widget _measured(IdeStatusBarItem item, int index) => switch (onRightWidth) {
    final told? => WidthReport(
      key: item.key,
      onWidth: (width) => told(index, width),
      child: _StatusItem(item),
    ),
    null => _StatusItem(item, key: item.key),
  };
}

/// A status bar's [right] items alone, as wide as they are: in another
/// row of the bar's height (under the IDE's chat, after its branch; see
/// [IslandFootTrailing]).
class IdeStatusBarTrailing extends StatelessWidget {
  const IdeStatusBarTrailing({super.key, required this.right, this.onWidth});

  final List<IdeStatusBarItem> right;

  /// Told each of [right]'s widths (by its index) as it is laid out.
  final void Function(int index, double width)? onWidth;

  @override
  Widget build(BuildContext context) => Container(
    height: IdeStatusBar.height,
    // As far from the window's edge as the bar's are where the parts are
    // not islands; a card's gaps about it else.
    padding: Islands.on(context)
        ? EdgeInsets.zero
        : const EdgeInsets.only(top: 1, right: 6),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, item) in right.indexed)
          switch (onWidth) {
            final told? => WidthReport(
              key: item.key,
              onWidth: (width) => told(i, width),
              child: _StatusItem(item),
            ),
            null => _StatusItem(item, key: item.key),
          },
      ],
    ),
  );
}

class _StatusItem extends StatefulWidget {
  const _StatusItem(this.item, {super.key});

  final IdeStatusBarItem item;

  @override
  State<_StatusItem> createState() => _StatusItemState();
}

class _StatusItemState extends State<_StatusItem> {
  bool _hover = false;

  /// Where the entry is, in the window (global): what a menu anchors on.
  Rect? get _rect {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final colors = themeColors;
    final tappable = item.onTap != null || item.onTapRect != null;
    final hovered = _hover && tappable;
    final islands = Islands.on(context);
    // Its icons too (`color: inherit`); its own color stays on hover. Where
    // the parts are not islands, upstream's `statusBar.*` colors, its items
    // square and as high as the bar (under its line).
    final color =
        item.color ??
        (islands
            ? (hovered ? AppColors.text : AppColors.textFaint)
            : (hovered ? colors.get('statusBarItem.hoverForeground') : null) ??
                  colors['statusBar.foreground']);
    // High contrast themes outline a hovered item (dashed upstream).
    final outline = hovered ? colors.get('contrastActiveBorder') : null;
    final radius = islands
        ? const BorderRadius.all(Radius.circular(5))
        : BorderRadius.zero;
    Widget child = Container(
      height: islands ? IdeStatusBar.itemHeight : IdeStatusBar.height - 1,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: hovered
            ? item.hoverBackground ??
                  (islands
                      ? AppColors.hover
                      : colors['statusBarItem.hoverBackground'])
            : item.background ?? Colors.transparent,
        borderRadius: radius,
      ),
      foregroundDecoration: outline == null
          ? null
          : BoxDecoration(
              border: Border.all(color: outline),
              borderRadius: radius,
            ),
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
                style: TextStyle(fontSize: islands ? 12 : 11.5, color: color),
              ),
            ),
        ],
      ),
    );
    if (tappable || item.onContextMenu != null) {
      final anchor = item.onTapRect;
      child = MouseRegion(
        cursor: tappable ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: item.onTap,
          onTapUp: anchor == null
              ? null
              : (_) {
                  if (_rect case final rect?) anchor(rect);
                },
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

  /// Once the registrations are loaded (see [ensureLoaded]).
  static Future<void> load() {
    ensureLoaded(() {});
    return _loading!;
  }

  /// Every language there is to pick (Change Language Mode): TextMate's
  /// and Monaco's, each once by its id, named by its first alias, with
  /// its extensions; by name.
  static List<({String id, String name, List<String> extensions})> get all {
    final names = <String, String>{};
    final extensions = <String, Set<String>>{};
    void add(String id, List<String> aliases, List<String> more) {
      if (id.isEmpty || id == EditorLanguageOverrides.plainText) return;
      if (aliases.firstOrNull case final alias? when alias.isNotEmpty) {
        names.putIfAbsent(id, () => alias);
      }
      (extensions[id] ??= {}).addAll(more);
    }

    for (final language in _textMateLanguages) {
      add(language.id, language.aliases, language.extensions);
    }
    for (final registration in _registrations ?? const []) {
      add(registration.id, registration.aliases, registration.extensions);
    }
    final all = [
      for (final MapEntry(key: id, value: more) in extensions.entries)
        (id: id, name: names[id] ?? id, extensions: more.toList()),
    ];
    all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return all;
  }

  /// The name of the language [id], as [forPath] names one.
  static String nameOf(String id) {
    if (id == EditorLanguageOverrides.plainText) return 'Plain Text';
    for (final language in _textMateLanguages) {
      if (language.id == id && language.aliases.isNotEmpty) {
        return language.aliases.first;
      }
    }
    for (final registration in _registrations ?? const []) {
      if (registration.id == id && registration.aliases.isNotEmpty) {
        return registration.aliases.first;
      }
    }
    return id;
  }

  static String forPath(String path) {
    if (EditorLanguageOverrides.instance.of(path) case final picked?) {
      return nameOf(picked);
    }
    final registrations = _registrations;
    if (registrations == null) return languageNameForFile(path);
    final lower = hostBasename(path).toLowerCase();
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
