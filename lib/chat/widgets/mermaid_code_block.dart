import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mermaid_core/mermaid_core.dart' as mermaid;
import 'package:mermaid_flutter/mermaid_flutter.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'code_citation.dart';

/// Native, offline Mermaid rendering, with the ordinary code block as fallback.
class MermaidCodeBlock extends StatefulWidget {
  const MermaidCodeBlock({super.key, required this.code});

  final String code;

  @override
  State<MermaidCodeBlock> createState() => _MermaidCodeBlockState();
}

class _MermaidCodeBlockState extends State<MermaidCodeBlock> {
  Timer? _pending;
  mermaid.MermaidTheme? _theme;
  mermaid.RenderScene? _scene;
  bool _showSource = false;
  bool _hovered = false;
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void didUpdateWidget(MermaidCodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code == widget.code) return;
    _pending?.cancel();
    // Never label the previous diagram as the current, partially written source.
    _scene = null;
    _pending = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() => _render(_theme!));
    });
  }

  void _render(mermaid.MermaidTheme theme) {
    _theme = theme;
    _scene = null;
    final code = widget.code;
    // Layout is synchronous: bound input before asking the native engine.
    if (code.length > 16000 || '\n'.allMatches(code).length > 200) return;
    try {
      final type = mermaid.detectDiagramType(code);
      if (type == mermaid.DiagramType.flowchart) {
        // The parser expands grouped endpoints before returning its edge list.
        // Conservatively cap grouping tokens even inside labels/comments.
        if ('&'.allMatches(code).length > 20) return;
        final graph = mermaid.parseFlowchart(code);
        if (graph.nodes.length > 100 || graph.edges.length > 200) return;
      } else if (type == mermaid.DiagramType.packet) {
        final packet = mermaid.parsePacket(code);
        final config = mermaid.PacketConfig.fromSource(code);
        if (config.bitsPerRow < 1 || packet.fields.last.end > 2047) return;
      }
      final scene = mermaid.Mermaid(
        measurer: const FlutterTextMeasurer(),
        theme: theme,
      ).render(code);
      if (scene.size.width.isFinite &&
          scene.size.height.isFinite &&
          scene.size.width > 0 &&
          scene.size.height > 0) {
        // Drawn straight on the conversation: its fills already match it.
        _scene = mermaid.RenderScene(size: scene.size, nodes: scene.nodes);
      }
    } catch (_) {
      // Incomplete streamed fences and unsupported syntax stay readable.
    }
  }

  void _copy() {
    unawaited(Clipboard.setData(ClipboardData(text: widget.code)));
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _openDialog(mermaid.RenderScene scene) => showDialog<void>(
    context: context,
    builder: (context) => _DiagramDialog(scene: scene, source: widget.code),
  );

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    mermaid.Color color(Color value) => mermaid.Color(value.toARGB32());
    // The conversation's, which shapes filled "with the background" match.
    final background = colors['editor.background'];
    final foreground = colors['editor.foreground'];
    final theme =
        (colors.dark
                ? mermaid.MermaidTheme.darkTheme
                : mermaid.MermaidTheme.defaultTheme)
            .copyWith(
              background: color(background),
              primaryColor: color(AppColors.surface),
              mainBkg: color(AppColors.surface),
              primaryTextColor: color(foreground),
              textColor: color(foreground),
              titleColor: color(foreground),
              primaryBorderColor: color(AppColors.accent),
              nodeBorder: color(AppColors.accent),
              lineColor: color(foreground),
              arrowheadColor: color(foreground),
              clusterBkg: color(background),
              clusterBorder: color(AppColors.border),
              edgeLabelBackground: color(background),
              fontFamily: DefaultTextStyle.of(context).style.fontFamily,
              fontSize: 13,
            );
    if (_theme != theme) _render(theme);
    final scene = _scene;
    if (scene == null || _showSource) {
      return MarkdownCodeBlock(
        code: widget.code,
        language: 'mermaid',
        onPreview: scene == null
            ? null
            : () => setState(() => _showSource = false),
      );
    }
    final l10n = context.l10n;
    return SelectionContainer.disabled(
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Stack(
          children: [
            // Its own size, or narrowed to the column's; never scrolled.
            Align(
              alignment: AlignmentDirectional.topStart,
              child: MouseRegion(
                cursor: SystemMouseCursors.zoomIn,
                child: GestureDetector(
                  onTap: () => _openDialog(scene),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _Scene(scene: scene, source: widget.code),
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              top: 0,
              start: 0,
              child: Visibility.maintain(
                visible: _hovered || _copied,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colors['chat.requestBorder']),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CodeBlockIconButton(
                        icon: Codicons.code,
                        tooltip: l10n.sidePanelSource,
                        onTap: () => setState(() => _showSource = true),
                      ),
                      CodeBlockIconButton(
                        icon: Codicons.screenFull,
                        tooltip: l10n.cmdListExpand,
                        onTap: () => _openDialog(scene),
                      ),
                      CodeBlockIconButton(
                        icon: _copied ? Codicons.check : Codicons.copy,
                        tooltip: l10n.commonCopy,
                        onTap: _copy,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pending?.cancel();
    _copiedTimer?.cancel();
    super.dispose();
  }
}

class _Scene extends StatelessWidget {
  const _Scene({required this.scene, required this.source});

  final mermaid.RenderScene scene;
  final String source;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'Mermaid\n$source',
    child: CustomPaint(
      painter: ScenePainter(scene),
      size: Size(scene.size.width, scene.size.height),
    ),
  );
}

/// The diagram as large as it is, or as fits the window: zoomable, pannable.
class _DiagramDialog extends StatelessWidget {
  const _DiagramDialog({required this.scene, required this.source});

  final mermaid.RenderScene scene;
  final String source;

  static const _padding = 24.0;
  static const _titleHeight = 34.0;

  /// The title's and the line under it.
  static const _chrome = _titleHeight + 1;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return Dialog(
      backgroundColor: colors['editor.background'],
      insetPadding: const EdgeInsets.all(40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors['chat.requestBorder']),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fitScale = math.min(
            1.0,
            math.min(
              math.max(1, constraints.maxWidth - 2 * _padding) /
                  scene.size.width,
              math.max(1, constraints.maxHeight - _chrome - 2 * _padding) /
                  scene.size.height,
            ),
          );
          final width = scene.size.width * fitScale;
          final height = scene.size.height * fitScale;
          return SizedBox(
            width: math.min(constraints.maxWidth, width + 2 * _padding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: _titleHeight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
                    child: Row(
                      children: [
                        Text(
                          'mermaid',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        CodeBlockIconButton(
                          icon: Codicons.close,
                          tooltip: context.l10n.commonClose,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: colors['chat.requestBorder'],
                ),
                ClipRect(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    // Even an extremely wide scene can reach its native text size.
                    maxScale: math.max(8, 8 / fitScale),
                    child: Padding(
                      padding: const EdgeInsets.all(_padding),
                      child: Center(
                        child: SizedBox(
                          width: width,
                          height: height,
                          child: FittedBox(
                            child: _Scene(scene: scene, source: source),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
