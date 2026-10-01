import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/cursor_theme.dart';
import '../../theme/workbench_theme.dart';
import '../editor/monaco/flutter/editor_surface.dart';
import '../editor/monaco/vs/base/common/filters.dart';
import '../ide_hover.dart';
import '../ide_input.dart';
import '../lsp/lsp_protocol.dart';
import 'editor_language_session.dart';
import 'hover_markdown.dart';
import 'language_icons.dart';
import 'suggest_session.dart';

// The widgets' colors are the color theme's, by the ids their upstream
// CSS reads (suggest.css, parameterHints.css, actionWidget.css,
// renameWidget.ts, messageController.css, hover.css).

/// The editor's font for code in the widgets, in [color].
TextStyle _mono(Color color) => TextStyle(
  fontFamily: CursorFonts.mono,
  fontSize: 12.5,
  color: color,
  height: 1.4,
);

/// Text drawn at CSS `opacity`.
Color _faded(Color color, double opacity) =>
    color.withValues(alpha: color.a * opacity);

/// `--vscode-shadow-lg`, a workbench constant (not a theme color).
const _shadowLarge = [BoxShadow(color: Color(0x24000000), blurRadius: 12)];

/// A widget's box: the [background] and [border] colors' ids, and its
/// [shadow].
BoxDecoration _box({
  required String background,
  required String border,
  required List<BoxShadow> shadow,
}) {
  final colors = themeColors;
  return BoxDecoration(
    color: colors[background],
    border: Border.all(color: colors[border]),
    borderRadius: BorderRadius.circular(4),
    boxShadow: shadow,
  );
}

/// The suggest widget's box: `0 2px 8px widget.shadow`.
BoxDecoration _suggestBox() => _box(
  background: 'editorSuggestWidget.background',
  border: 'editorSuggestWidget.border',
  shadow: [
    BoxShadow(
      color: themeColors['widget.shadow'],
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ],
);

/// All language widgets over an editor surface, positioned with its
/// [EditorSurfaceView]. Place it above the surface in a [Stack], filling it;
/// it only takes pointer events on its widgets.
class IdeLanguageOverlay extends StatelessWidget {
  const IdeLanguageOverlay({
    super.key,
    required this.session,
    required this.view,
    this.colorize,
    this.language,
    this.renameHandlesKeys = true,
  });

  final EditorLanguageSession session;
  final EditorSurfaceView? Function() view;

  /// [IdeRenameInput.handleKeys].
  final bool renameHandlesKeys;

  /// Colors code in hovers and documentation as the editor does.
  final IdeCodeColorizer? colorize;

  /// The editor's language, for code blocks that name none.
  final String? language;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final view = this.view();
        if (view == null || view.textArea == null) {
          return const SizedBox.shrink();
        }
        final bounds = Offset.zero & constraints.biggest;
        final children = <Widget>[];

        Widget anchored(
          Rect anchor,
          Widget child, {
          bool above = false,
          Key? key,
        }) => Positioned.fill(
          key: key,
          child: CustomSingleChildLayout(
            delegate: _AnchoredLayout(anchor, bounds, preferAbove: above),
            child: child,
          ),
        );

        if (session.lightbulbLine case final line?
            when session.codeActionMenu == null) {
          final rect =
              view.glyphMarginRect(line + 1) ??
              _lineStartRect(view, session, line);
          if (rect != null && bounds.overlaps(rect)) {
            children.add(
              Positioned(
                key: const ValueKey('ide-lightbulb'),
                left: rect.left,
                top: rect.top,
                width: math.max(rect.width, 16),
                height: rect.height,
                child: IdeLightbulb(
                  autoFix: session.lightbulbHasPreferredFix,
                  onTap: () => unawaited(session.showCodeActions()),
                ),
              ),
            );
          }
        }

        if (session.hover case final hover?) {
          final anchor = view.rangeRectAt(hover.start, hover.end);
          if (anchor != null) {
            children.add(
              anchored(
                anchor,
                IdeHoverCard(
                  state: hover,
                  onPointer: session.onHoverCardPointer,
                  colorize: colorize,
                  language: language,
                ),
                above: true,
                key: const ValueKey('ide-hover'),
              ),
            );
          }
        }

        if (session.signature case final signature?) {
          final anchor = view.caretRectAt(
            session.controller.value.selection.extentOffset,
          );
          if (anchor != null) {
            children.add(
              anchored(
                anchor,
                IdeParameterHints(
                  state: signature,
                  onCycle: session.cycleSignature,
                  colorize: colorize,
                  language: language,
                ),
                above: true,
                key: const ValueKey('ide-parameter-hints'),
              ),
            );
          }
        }

        final suggest = session.suggest;
        if (suggest.visible) {
          final anchor = view.caretRectAt(suggest.anchorOffset);
          if (anchor != null) {
            children.add(
              anchored(
                anchor,
                IdeSuggestWidget(
                  session: suggest,
                  colorize: colorize,
                  language: language,
                ),
                key: const ValueKey('ide-suggest'),
              ),
            );
          }
        }

        if (session.codeActionMenu case final menu?) {
          final anchor = view.caretRectAt(menu.anchor);
          if (anchor != null) {
            children.add(
              anchored(
                anchor,
                IdeCodeActionMenuWidget(
                  menu: menu,
                  onSelect: session.selectCodeAction,
                  onApply: (action) =>
                      unawaited(session.applyCodeAction(action)),
                ),
                key: const ValueKey('ide-code-actions'),
              ),
            );
          }
        }

        if (session.rename case final rename?) {
          final anchor = view.rangeRectAt(rename.start, rename.end);
          if (anchor != null) {
            children.add(
              anchored(
                anchor,
                IdeRenameInput(
                  state: rename,
                  onAccept: () => unawaited(session.acceptRename()),
                  onCancel: session.cancelRename,
                  handleKeys: renameHandlesKeys,
                ),
                key: const ValueKey('ide-rename'),
              ),
            );
          }
        }

        if (session.message case final message?) {
          final anchor = view.caretRectAt(message.offset);
          if (anchor != null) {
            children.add(
              anchored(
                anchor,
                _MessageBox(text: message.text),
                above: true,
                key: const ValueKey('ide-editor-message'),
              ),
            );
          }
        }

        return Stack(children: children);
      },
    );
  }

  static Rect? _lineStartRect(
    EditorSurfaceView view,
    EditorLanguageSession session,
    int line,
  ) {
    final snapshot = session.document.model.snapshot;
    if (line >= snapshot.lineCount) return null;
    final caret = view.caretRectAt(snapshot.lineStarts[line]);
    final area = view.textArea;
    if (caret == null || area == null) return null;
    return Rect.fromLTWH(
      math.max(0, area.left - 18),
      caret.top,
      16,
      caret.height,
    );
  }
}

/// Places its child below [anchor] (or above with [preferAbove]), flipping
/// when there is no room, and keeps it inside [bounds].
class _AnchoredLayout extends SingleChildLayoutDelegate {
  _AnchoredLayout(this.anchor, this.bounds, {required this.preferAbove});

  final Rect anchor;
  final Rect bounds;
  final bool preferAbove;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final roomAbove = anchor.top - bounds.top;
    final roomBelow = bounds.bottom - anchor.bottom;
    final above = preferAbove
        ? roomAbove >= childSize.height || roomAbove > roomBelow
        : roomBelow < childSize.height && roomAbove > roomBelow;
    final top = above ? anchor.top - childSize.height : anchor.bottom;
    final left = anchor.left
        .clamp(
          bounds.left,
          math.max(bounds.left, bounds.right - childSize.width),
        )
        .toDouble();
    return Offset(
      left,
      top
          .clamp(
            bounds.top,
            math.max(bounds.top, bounds.bottom - childSize.height),
          )
          .toDouble(),
    );
  }

  @override
  bool shouldRelayout(_AnchoredLayout oldDelegate) =>
      oldDelegate.anchor != anchor ||
      oldDelegate.bounds != bounds ||
      oldDelegate.preferAbove != preferAbove;
}

class _MessageBox extends StatelessWidget {
  const _MessageBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    // `.monaco-editor-overlaymessage .message`.
    final colors = themeColors;
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors['editorHoverWidget.background'],
        border: Border.all(color: colors['inputValidation.infoBorder']),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: colors['editorHoverWidget.foreground'],
        ),
      ),
    );
  }
}

/// The editor hover (`ContentHoverWidget`): a row per problem at the
/// position (`MarkerHoverParticipant`), then one for the server's markdown
/// (`MarkdownHoverParticipant`), divided by half-strength rules.
///
/// Deviation: no status bar row (View Problem, Quick Fix).
class IdeHoverCard extends StatelessWidget {
  const IdeHoverCard({
    super.key,
    required this.state,
    this.onPointer,
    this.colorize,
    this.language,
  });

  final IdeHoverState state;
  final ValueChanged<bool>? onPointer;

  /// Colors the markdown's code as the editor does.
  final IdeCodeColorizer? colorize;

  /// The editor's language, for code blocks that name none.
  final String? language;

  /// `.monaco-hover .hover-row + .hover-row`'s `border-top`: the border at
  /// half strength.
  static Color get rowBorder {
    final border = themeColors['editorHoverWidget.border'];
    return border.withValues(alpha: border.a / 2);
  }

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final foreground = colors['editorHoverWidget.foreground'];
    final rowBorder = IdeHoverCard.rowBorder;
    final rows = <Widget>[
      for (final d in state.diagnostics)
        // The message in the editor's font, then `source(code)` at 60%.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text.rich(
            TextSpan(
              text: d.message,
              children: [
                if (d.source != null || d.code != null)
                  TextSpan(
                    text:
                        '  ${d.source ?? ''}'
                        '${d.code == null ? '' : '(${d.code})'}',
                    style: TextStyle(color: _faded(foreground, 0.6)),
                  ),
              ],
            ),
            style: ideHoverCodeStyle.copyWith(color: foreground),
          ),
        ),
      if (state.markdown case final markdown?)
        IdeHoverMarkdown(markdown, colorize: colorize, language: language),
    ];
    return MouseRegion(
      onEnter: (_) => onPointer?.call(true),
      onExit: (_) => onPointer?.call(false),
      child: Container(
        // `--vscode-hover-maxWidth` of text, and the hover's padding.
        constraints: const BoxConstraints(maxWidth: 500 + 16, maxHeight: 300),
        decoration: BoxDecoration(
          color: colors['editorHoverWidget.background'],
          border: Border.all(color: colors['editorHoverWidget.border']),
          borderRadius: BorderRadius.circular(8),
          boxShadow: _shadowLarge,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          // As wide as its longest line, up to the maximum.
          child: IntrinsicWidth(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, row) in rows.indexed)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: index == 0
                            ? null
                            : Border(top: BorderSide(color: rowBorder)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: row,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The glyph-margin lightbulb (upstream LightBulbWidget).
class IdeLightbulb extends StatelessWidget {
  const IdeLightbulb({super.key, required this.autoFix, required this.onTap});

  final bool autoFix;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: IdeHover(
        message: context.l10n.langShowCodeActions,
        child: Icon(
          autoFix ? Codicons.lightbulbAutofix : Codicons.lightBulb,
          size: 14,
          color:
              themeColors[autoFix
                  ? 'editorLightBulbAutoFix.foreground'
                  : 'editorLightBulb.foreground'],
        ),
      ),
    ),
  );
}

/// The suggest list with the focused item's details beside it.
class IdeSuggestWidget extends StatefulWidget {
  const IdeSuggestWidget({
    super.key,
    required this.session,
    this.colorize,
    this.language,
  });

  final IdeSuggestSession session;

  /// Colors code in hovers and documentation as the editor does.
  final IdeCodeColorizer? colorize;

  /// The editor's language, for code blocks that name none.
  final String? language;

  static const rowHeight = 22.0;
  static const width = 420.0;
  static const detailsWidth = 320.0;

  @override
  State<IdeSuggestWidget> createState() => _IdeSuggestWidgetState();
}

class _IdeSuggestWidgetState extends State<IdeSuggestWidget> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(IdeSuggestWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  void _reveal() {
    if (!mounted || !_scroll.hasClients) return;
    final top = widget.session.selectedIndex * IdeSuggestWidget.rowHeight;
    final viewport = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (top + IdeSuggestWidget.rowHeight > _scroll.offset + viewport) {
      _scroll.jumpTo(top + IdeSuggestWidget.rowHeight - viewport);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final items = session.items;
    final Widget list;
    if (items.isEmpty) {
      list = Container(
        width: IdeSuggestWidget.width,
        height: IdeSuggestWidget.rowHeight + 4,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        decoration: _suggestBox(),
        child: Text(
          session.loading
              ? context.l10n.langLoading
              : context.l10n.langNoSuggestions,
          style: TextStyle(
            fontSize: 12.5,
            color: themeColors['editorSuggestWidget.foreground'],
          ),
        ),
      );
    } else {
      final visible = math.min(items.length, IdeSuggestSession.pageSize);
      list = Container(
        width: IdeSuggestWidget.width,
        height: visible * IdeSuggestWidget.rowHeight + 2,
        decoration: _suggestBox(),
        child: ListView.builder(
          controller: _scroll,
          itemExtent: IdeSuggestWidget.rowHeight,
          itemCount: items.length,
          itemBuilder: (context, index) => _SuggestRow(
            item: items[index],
            resolved: session.resolvedOf(items[index].completion),
            selected: index == session.selectedIndex,
            onTap: () {
              if (index == session.selectedIndex) {
                session.accept(items[index]);
              } else {
                session.select(index);
              }
            },
          ),
        ),
      );
    }
    final selected = session.selected;
    final details = selected == null || !session.detailsExpanded
        ? null
        : _SuggestDetails(
            item: session.resolvedOf(selected.completion),
            colorize: widget.colorize,
            language: widget.language,
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Details go beside the list when they fit, else under it.
        final beside =
            constraints.maxWidth >=
            IdeSuggestWidget.width + IdeSuggestWidget.detailsWidth + 2;
        return Flex(
          direction: beside ? Axis.horizontal : Axis.vertical,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [list, ?details],
        );
      },
    );
  }
}

class _SuggestRow extends StatelessWidget {
  const _SuggestRow({
    required this.item,
    required this.resolved,
    required this.selected,
    required this.onTap,
  });

  final IdeSuggestItem item;
  final LspCompletionItem resolved;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final completion = item.completion;
    final icon = ideCompletionKindIcon(completion.kind);
    final label = completion.label;
    final spans = <TextSpan>[];
    var at = 0;
    // The focused row: `selectedForeground`, its icon
    // `selectedIconForeground`, its matches `focusHighlightForeground`;
    // each inherits where the theme has none, as in CSS.
    final colors = themeColors;
    final unselected = colors['editorSuggestWidget.foreground'];
    final foreground = selected
        ? colors.get('editorSuggestWidget.selectedForeground') ?? unselected
        : unselected;
    final highlight = selected
        ? colors.get('editorSuggestWidget.focusHighlightForeground') ??
              foreground
        : colors['editorSuggestWidget.highlightForeground'];
    final iconColor = selected
        ? colors.get('editorSuggestWidget.selectedIconForeground') ?? foreground
        : icon.color;
    final focusOutline = selected
        ? colors.get('editorSuggestWidget.focusOutline')
        : null;
    final base = TextStyle(
      fontFamily: CursorFonts.mono,
      fontSize: 12.5,
      color: foreground,
      decoration: completion.deprecated ? TextDecoration.lineThrough : null,
    );
    for (final match in createMatches(item.score)) {
      final start = match.start.clamp(0, label.length);
      final end = match.end.clamp(start, label.length);
      if (start > at) spans.add(TextSpan(text: label.substring(at, start)));
      spans.add(
        TextSpan(
          text: label.substring(start, end),
          style: TextStyle(color: highlight, fontWeight: FontWeight.bold),
        ),
      );
      at = end;
    }
    if (at < label.length) spans.add(TextSpan(text: label.substring(at)));
    if (completion.labelDetail case final detail?) {
      // `.signature-label`.
      spans.add(
        TextSpan(
          text: detail,
          style: TextStyle(color: _faded(foreground, 0.6)),
        ),
      );
    }
    final right =
        completion.labelDescription ?? (selected ? resolved.detail : null);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          color: selected
              ? colors['editorSuggestWidget.selectedBackground']
              : null,
          foregroundDecoration: focusOutline == null
              ? null
              : BoxDecoration(border: Border.all(color: focusOutline)),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Icon(icon.icon, size: 14, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(children: spans),
                  style: base,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (right != null && right.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    right.replaceAll('\n', ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // `.details-label`.
                    style: TextStyle(fontSize: 11.5, color: foreground),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestDetails extends StatelessWidget {
  const _SuggestDetails({required this.item, this.colorize, this.language});

  final LspCompletionItem item;
  final IdeCodeColorizer? colorize;
  final String? language;

  @override
  Widget build(BuildContext context) {
    final detail = item.detail;
    final documentation = item.documentation;
    if ((detail == null || detail.isEmpty) &&
        (documentation == null || documentation.isEmpty)) {
      return const SizedBox.shrink();
    }
    final foreground = themeColors['editorSuggestWidget.foreground'];
    return Container(
      key: const ValueKey('ide-suggest-details'),
      width: IdeSuggestWidget.detailsWidth,
      constraints: const BoxConstraints(maxHeight: 280),
      margin: const EdgeInsets.only(left: 2),
      decoration: _suggestBox(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // `.header > .type`.
            if (detail != null && detail.isNotEmpty)
              Text(detail, style: _mono(_faded(foreground, 0.7))),
            if (detail != null &&
                detail.isNotEmpty &&
                documentation != null &&
                documentation.isNotEmpty)
              const SizedBox(height: 6),
            if (documentation != null && documentation.isNotEmpty)
              IdeHoverMarkdown(
                documentation,
                colorize: colorize,
                language: language,
                padding: 0,
                foreground: 'editorSuggestWidget.foreground',
              ),
          ],
        ),
      ),
    );
  }
}

/// Signature help: the active signature with its active parameter, the
/// overload count, and the documentation.
class IdeParameterHints extends StatelessWidget {
  const IdeParameterHints({
    super.key,
    required this.state,
    required this.onCycle,
    this.colorize,
    this.language,
  });

  final IdeSignatureState state;
  final ValueChanged<int> onCycle;

  /// Colors code in hovers and documentation as the editor does.
  final IdeCodeColorizer? colorize;

  /// The editor's language, for code blocks that name none.
  final String? language;

  /// `(start, end)` of the active parameter in [signature]'s label.
  static (int, int)? activeParameterRange(LspSignature signature, int active) {
    if (active < 0 || active >= signature.parameters.length) return null;
    final label = signature.label;
    var searchFrom = label.indexOf('(') + 1;
    for (final (index, parameter) in signature.parameters.indexed) {
      (int, int)? range = parameter.labelRange;
      if (range == null) {
        final at = parameter.label.isEmpty
            ? -1
            : label.indexOf(parameter.label, searchFrom);
        if (at >= 0) range = (at, at + parameter.label.length);
      }
      if (range != null) searchFrom = range.$2;
      if (index == active) return range;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final signature = state.signature;
    final active = state.activeParameter;
    final label = signature.label;
    final range = activeParameterRange(signature, active);
    final count = state.help.signatures.length;
    final parameterDoc = active >= 0 && active < signature.parameters.length
        ? signature.parameters[active].documentation
        : null;
    final colors = themeColors;
    final foreground = colors['editorHoverWidget.foreground'];
    final border = colors['editorHoverWidget.border'];
    return Container(
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 260),
      decoration: _box(
        background: 'editorHoverWidget.background',
        border: 'editorHoverWidget.border',
        shadow: _shadowLarge,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (count > 1) ...[
                  _OverloadButton(
                    icon: Codicons.chevronUp,
                    onTap: () => onCycle(-1),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      '${state.activeSignature + 1}/$count',
                      style: TextStyle(fontSize: 11.5, color: foreground),
                    ),
                  ),
                  _OverloadButton(
                    icon: Codicons.chevronDown,
                    onTap: () => onCycle(1),
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: range == null
                          ? [TextSpan(text: label)]
                          : [
                              TextSpan(text: label.substring(0, range.$1)),
                              TextSpan(
                                text: label.substring(range.$1, range.$2),
                                style: TextStyle(
                                  color:
                                      colors['editorHoverWidget.highlightForeground'],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextSpan(text: label.substring(range.$2)),
                            ],
                    ),
                    style: _mono(foreground),
                  ),
                ),
              ],
            ),
            if (parameterDoc != null && parameterDoc.isNotEmpty) ...[
              const SizedBox(height: 4),
              IdeHoverMarkdown(
                parameterDoc,
                colorize: colorize,
                language: language,
                padding: 0,
              ),
            ],
            if (signature.documentation case final doc?
                when doc.isNotEmpty) ...[
              // `.signature.has-docs::after`: the border at half opacity.
              Divider(height: 10, color: _faded(border, 0.5)),
              IdeHoverMarkdown(
                doc,
                colorize: colorize,
                language: language,
                padding: 0,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OverloadButton extends StatelessWidget {
  const _OverloadButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: Icon(
        icon,
        size: 16,
        color: themeColors['editorHoverWidget.foreground'],
      ),
    ),
  );
}

/// The ⌘. menu: actions grouped like upstream's action widget, quick fixes
/// first and preferred ones marked.
class IdeCodeActionMenuWidget extends StatelessWidget {
  const IdeCodeActionMenuWidget({
    super.key,
    required this.menu,
    required this.onSelect,
    required this.onApply,
  });

  final IdeCodeActionMenu menu;
  final ValueChanged<int> onSelect;
  final ValueChanged<IdeCodeAction> onApply;

  static IconData iconFor(IdeCodeAction action) {
    final kind = action.kind ?? '';
    // codeActionMenu.ts's groups.
    if (kind.startsWith('quickfix')) return Codicons.lightBulb;
    if (kind.startsWith('refactor')) return Codicons.wrench;
    if (kind.startsWith('surround')) return Codicons.surroundWith;
    if (kind.startsWith('source')) return Codicons.symbolFile;
    return Codicons.lightBulb;
  }

  @override
  Widget build(BuildContext context) {
    // actionWidget.css; the lightbulb's color is `actionList.ts`'.
    final colors = themeColors;
    final foreground = colors['menu.foreground'];
    final disabledForeground = colors['disabledForeground'];
    final rows = <Widget>[];
    var index = 0;
    for (final (group, actions) in menu.groups) {
      if (menu.groups.length > 1) {
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
            child: Text(
              group.title,
              style: TextStyle(
                fontSize: 11,
                color: colors['descriptionForeground'],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }
      for (final action in actions) {
        final i = index++;
        final selected = i == menu.selected;
        final disabled = action.isDisabled;
        final focused = selected && !disabled;
        final rowForeground = focused
            ? colors.get('list.hoverForeground') ?? foreground
            : foreground;
        final icon = iconFor(action);
        final outline = focused ? colors.get('contrastActiveBorder') : null;
        Widget row = Container(
          height: 22,
          color: focused ? colors['list.hoverBackground'] : null,
          foregroundDecoration: outline == null
              ? null
              : BoxDecoration(border: Border.all(color: outline)),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Icon(
                icon,
                size: 14,
                color: disabled
                    ? disabledForeground
                    : icon != Codicons.lightBulb
                    ? rowForeground
                    : colors[action.isPreferred
                          ? 'editorLightBulbAutoFix.foreground'
                          : 'editorLightBulb.foreground'],
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  action.action.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: disabled ? disabledForeground : rowForeground,
                  ),
                ),
              ),
              if (action.isPreferred && !disabled) ...[
                const SizedBox(width: 6),
                IdeHover(
                  message: context.l10n.langPreferred,
                  child: Icon(
                    Codicons.starFull,
                    size: 11,
                    color: colors['editorLightBulbAutoFix.foreground'],
                  ),
                ),
              ],
            ],
          ),
        );
        if (disabled) {
          row = IdeHover(message: action.action.disabledReason!, child: row);
        } else {
          row = MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => onSelect(i),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onApply(action),
              child: row,
            ),
          );
        }
        rows.add(row);
      }
    }
    return Container(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 440),
      padding: const EdgeInsets.symmetric(vertical: 3),
      decoration: _box(
        background: 'menu.background',
        border: 'editorHoverWidget.border',
        shadow: _shadowLarge,
      ),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }
}

/// The inline rename box (upstream RenameWidget): Enter renames, Escape or
/// losing focus cancels.
class IdeRenameInput extends StatefulWidget {
  const IdeRenameInput({
    super.key,
    required this.state,
    required this.onAccept,
    required this.onCancel,
    this.handleKeys = true,
  });

  final IdeRenameState state;
  final VoidCallback onAccept;
  final VoidCallback onCancel;

  /// Whether Enter renames and Escape cancels by themselves; false when the
  /// app's keybindings run `acceptRenameInput` and `cancelRenameInput` (the
  /// host takes the keys as they bubble up).
  final bool handleKeys;

  @override
  State<IdeRenameInput> createState() => _IdeRenameInputState();
}

class _IdeRenameInputState extends State<IdeRenameInput> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    widget.state.focusNode.addListener(_focusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.state.focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    widget.state.focusNode.removeListener(_focusChanged);
    super.dispose();
  }

  void _focusChanged() {
    if (!widget.state.focusNode.hasFocus && !_done && mounted) {
      _done = true;
      widget.onCancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    // `RenameWidget._updateStyles`.
    final colors = themeColors;
    final foreground = colors['input.foreground'];
    final inputBorder = colors.get('input.border');
    final border = inputBorder == null
        ? InputBorder.none
        : OutlineInputBorder(borderSide: BorderSide(color: inputBorder));
    return Container(
      width: 240,
      padding: const EdgeInsets.all(4),
      decoration: _box(
        background: 'editorWidget.background',
        border: 'widget.border',
        shadow: [
          BoxShadow(
            color: colors['widget.shadow'],
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Focus(
            onKeyEvent: (node, event) {
              if (widget.handleKeys &&
                  event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                _done = true;
                widget.onCancel();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              key: const ValueKey('ide-rename-field'),
              controller: widget.state.text,
              focusNode: widget.state.focusNode,
              autofocus: true,
              style: _mono(foreground),
              cursorColor: foreground,
              cursorHeight: ideCaretHeight(12.5),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: colors['input.background'],
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 5,
                ),
                border: border,
                enabledBorder: border,
                focusedBorder: border,
              ),
              onSubmitted: widget.handleKeys
                  ? (_) {
                      _done = true;
                      widget.onAccept();
                    }
                  : null,
            ),
          ),
          // `.rename-label`.
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 2),
            child: Text(
              context.l10n.langRenameHint,
              style: TextStyle(fontSize: 10.5, color: _faded(foreground, 0.8)),
            ),
          ),
        ],
      ),
    );
  }
}
