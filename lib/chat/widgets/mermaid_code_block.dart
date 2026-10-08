import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mermaid_core/mermaid_core.dart' as mermaid;
import 'package:mermaid_flutter/mermaid_flutter.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'code_citation.dart';
import 'wheel_latch.dart';

/// Native, offline Mermaid rendering, with the ordinary code block as fallback.
class MermaidCodeBlock extends StatefulWidget {
  const MermaidCodeBlock({super.key, required this.code});

  final String code;

  @override
  State<MermaidCodeBlock> createState() => _MermaidCodeBlockState();
}

class _MermaidCodeBlockState extends State<MermaidCodeBlock> {
  Timer? _pending;
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  mermaid.MermaidTheme? _theme;
  mermaid.RenderScene? _scene;

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
        _scene = scene;
      }
    } catch (_) {
      // Incomplete streamed fences and unsupported syntax stay readable.
    }
  }

  @override
  void dispose() {
    _pending?.cancel();
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    mermaid.Color color(Color value) => mermaid.Color(value.toARGB32());
    final background = colors['textCodeBlock.background'];
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
    return MarkdownCodeBlock(
      code: widget.code,
      language: 'mermaid',
      preview: scene == null
          ? null
          : SelectionContainer.disabled(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: LayoutBuilder(
                    builder: (context, constraints) => Scrollbar(
                      controller: _vertical,
                      child: SingleChildScrollView(
                        controller: _vertical,
                        child: WheelLatch(
                          child: Scrollbar(
                            controller: _horizontal,
                            thumbVisibility: true,
                            notificationPredicate: (notification) =>
                                notification.metrics.axis == Axis.horizontal,
                            child: SingleChildScrollView(
                              controller: _horizontal,
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minWidth: constraints.maxWidth,
                                ),
                                child: Center(
                                  child: _Scene(
                                    scene: scene,
                                    source: widget.code,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      onOpenPreview: scene == null
          ? null
          : () => showDialog<void>(
              context: context,
              builder: (context) =>
                  _DiagramDialog(scene: scene, source: widget.code),
            ),
    );
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

class _DiagramDialog extends StatelessWidget {
  const _DiagramDialog({required this.scene, required this.source});

  final mermaid.RenderScene scene;
  final String source;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: themeColors['textCodeBlock.background'],
    insetPadding: const EdgeInsets.all(24),
    child: Column(
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: IconButton(
            tooltip: context.l10n.commonClose,
            icon: Icon(Codicons.close, color: AppColors.text),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fitScale = math.min(
                math.max(1, constraints.maxWidth - 32) / scene.size.width,
                math.max(1, constraints.maxHeight - 32) / scene.size.height,
              );
              return ClipRect(
                child: InteractiveViewer(
                  minScale: 0.2,
                  // Even an extremely wide scene can reach its native text size.
                  maxScale: math.max(8, 8 / fitScale),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: FittedBox(
                        child: _Scene(scene: scene, source: source),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}
