import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../theme/codicons.dart';
import '../theme/material_file_icons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'language/language_types.dart';
import 'lsp_ui/language_icons.dart';

/// The path of the active file under the tabs, one segment per folder with
/// chevrons between them, then the symbols around the caret. Tapping a
/// segment reveals it in the explorer; tapping a symbol reveals it. In the
/// color theme's `breadcrumb.*` colors (platform/theme/browser/
/// defaultStyles.ts `defaultBreadcrumbsWidgetStyles`).
class IdeBreadcrumbs extends StatelessWidget {
  const IdeBreadcrumbs({
    super.key,
    required this.root,
    required this.path,
    required this.onReveal,
    this.symbols = const [],
    this.onSymbol,
  });

  final String root;
  final String path;

  /// Called with the absolute path of a tapped folder or file segment.
  final ValueChanged<String> onReveal;

  /// The document symbols enclosing the caret, outermost first.
  final List<LspDocumentSymbol> symbols;
  final ValueChanged<LspDocumentSymbol>? onSymbol;

  static const height = 22.0;

  @override
  Widget build(BuildContext context) {
    final inside = p.isWithin(root, path);
    final parts = p.split(inside ? p.relative(path, from: root) : path);
    var base = inside ? root : '';
    final segments = <(String, String, bool)>[];
    for (final (i, part) in parts.indexed) {
      base = base.isEmpty ? part : p.join(base, part);
      segments.add((part, base, i == parts.length - 1));
    }
    // The separators are their item's color (`inherit`).
    final separator = themeColors['breadcrumb.foreground'];
    return Container(
      height: height,
      color: themeColors['breadcrumb.background'],
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          children: [
            for (final (i, (name, target, isFile)) in segments.indexed) ...[
              if (i > 0)
                Icon(Codicons.chevronRight, size: 14, color: separator),
              _Crumb(name: name, isFile: isFile, onTap: () => onReveal(target)),
            ],
            for (final symbol in symbols) ...[
              Icon(Codicons.chevronRight, size: 14, color: separator),
              _Crumb(
                name: symbol.name,
                isFile: false,
                symbol: symbol.kind,
                onTap: () => onSymbol?.call(symbol),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Crumb extends StatefulWidget {
  const _Crumb({
    required this.name,
    required this.isFile,
    required this.onTap,
    this.symbol,
  });

  final String name;
  final bool isFile;
  final LspSymbolKind? symbol;
  final VoidCallback onTap;

  @override
  State<_Crumb> createState() => _CrumbState();
}

class _CrumbState extends State<_Crumb> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isFile) ...[
                FileIcon(widget.name, size: 14),
                const SizedBox(width: 4),
              ],
              if (widget.symbol case final kind?) ...[
                Icon(
                  ideSymbolKindIcon(kind).icon,
                  size: 13,
                  color: ideSymbolKindIcon(kind).color,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                widget.name,
                // Hovered, `breadcrumb.focusForeground`; the file stands out
                // in it too.
                style: TextStyle(
                  fontSize: 11.5,
                  color: _hover || widget.isFile
                      ? themeColors['breadcrumb.focusForeground']
                      : themeColors['breadcrumb.foreground'],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
