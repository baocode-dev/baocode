import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mermaid_core/mermaid_core.dart' as mermaid;
import 'package:mermaid_flutter/mermaid_flutter.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../chat_models.dart' show ImageAttachment;
import '../side_panel/file_link_menu.dart';
import 'code_citation.dart';
import 'content_image.dart' show ContentImagePlaceholder;
import 'image_thumbnails.dart' show ImageMenu, showImagePreview;
import 'mermaid_theme.dart';

/// Native, offline Mermaid rendering, with the ordinary code block as fallback.
/// Shown whole, a right click's menu and its copy are a picture's.
class MermaidCodeBlock extends StatefulWidget {
  const MermaidCodeBlock({super.key, required this.code, this.writing = false});

  final String code;

  /// Whether its fence is still being written (a reply streaming in): a
  /// picture's placeholder shows, not its source half written, until it
  /// is closed or [quietFor] goes by without more.
  final bool writing;

  /// How long a fence left open is still taken to be being written.
  static const quietFor = Duration(seconds: 3);

  @override
  State<MermaidCodeBlock> createState() => _MermaidCodeBlockState();
}

class _MermaidCodeBlockState extends State<MermaidCodeBlock> {
  Timer? _pending;
  mermaid.MermaidTheme? _theme;
  mermaid.RenderScene? _scene;

  /// A tall top-down flowchart drawn left to right too, for a column it
  /// fits less tall (see [_shown]).
  mermaid.RenderScene? _across;
  bool _showSource = false;
  bool _hovered = false;
  bool _copied = false;
  Timer? _copiedTimer;

  /// Whether [MermaidCodeBlock.writing] has gone quiet (see [_quiet]).
  bool _stale = false;
  Timer? _quiet;

  /// The picture of the scene shown, once asked for (see [_picture]).
  (mermaid.RenderScene, Future<ImageAttachment>)? _pictured;

  bool get _writing => widget.writing && !_stale;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  /// Takes the fence as no longer being written once it goes quiet.
  void _listen() {
    _quiet?.cancel();
    _stale = false;
    if (!widget.writing) return;
    _quiet = Timer(MermaidCodeBlock.quietFor, () {
      if (mounted) setState(() => _stale = true);
    });
  }

  @override
  void didUpdateWidget(MermaidCodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.writing != widget.writing) {
      _listen();
      // Closed: drawn at once, not its source shown a moment first.
      _theme = null;
    }
    if (oldWidget.code == widget.code) return;
    if (widget.writing) _listen();
    _pending?.cancel();
    // Never label the previous diagram as the current, partially written source.
    _scene = null;
    _across = null;
    _pending = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() {
        if (_theme case final theme?) _render(theme);
      });
    });
  }

  void _render(mermaid.MermaidTheme theme) {
    _theme = theme;
    _scene = _layout(widget.code, theme);
    _across = null;
    final size = _scene?.size;
    if (size == null || size.height <= size.width || size.height < 240) return;
    if (mermaidAcross(widget.code) case final across?) {
      _across = _layout(across, theme);
    }
  }

  /// [code] laid out, a flowchart's lines square where it is small enough
  /// (see [mermaidSquare]), and its text as it reads (see
  /// [mermaidUnescaped]); null for none.
  mermaid.RenderScene? _layout(String code, mermaid.MermaidTheme theme) {
    // Layout is synchronous: bound input before asking the native engine.
    if (code.length > 16000 || '\n'.allMatches(code).length > 200) {
      return null;
    }
    try {
      final type = mermaid.detectDiagramType(code);
      if (type == mermaid.DiagramType.flowchart) {
        // The parser expands grouped endpoints before returning its edge list.
        // Conservatively cap grouping tokens even inside labels/comments.
        if ('&'.allMatches(code).length > 20) return null;
        final graph = mermaid.parseFlowchart(code);
        if (graph.nodes.length > 100 || graph.edges.length > 200) return null;
        // ELK takes a few milliseconds up to here, far more past it.
        if (graph.nodes.length <= 30 && graph.edges.length <= 60) {
          code = mermaidSquare(code);
        }
      } else if (type == mermaid.DiagramType.packet) {
        final packet = mermaid.parsePacket(code);
        final config = mermaid.PacketConfig.fromSource(code);
        if (config.bitsPerRow < 1 || packet.fields.last.end > 2047) {
          return null;
        }
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
        return mermaid.RenderScene(
          size: scene.size,
          nodes: [for (final node in scene.nodes) mermaidUnescaped(node)],
        );
      }
    } catch (_) {
      // Incomplete streamed fences and unsupported syntax stay readable.
    }
    return null;
  }

  /// [scene], or [_across] where, [width] wide, that shows far less tall
  /// and its text not much smaller: the conversation's height is dear.
  mermaid.RenderScene _shown(mermaid.RenderScene scene, double width) {
    final across = _across;
    if (across == null || !width.isFinite) return scene;
    double scale(mermaid.RenderScene of) => math.min(1, width / of.size.width);
    double height(mermaid.RenderScene of) => of.size.height * scale(of);
    return scale(across) >= 0.8 && height(across) < height(scene) * 0.8
        ? across
        : scene;
  }

  void _copy() {
    unawaited(Clipboard.setData(ClipboardData(text: widget.code)));
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  /// [scene] as a picture, made once for it (see [mermaidPicture]).
  Future<ImageAttachment> _picture(mermaid.RenderScene scene) {
    if (_pictured case (final made, final picture) when made == scene) {
      return picture;
    }
    final picture = mermaidPicture(
      scene,
      background: themeColors['editor.background'],
    );
    _pictured = (scene, picture);
    return picture;
  }

  /// [scene] shown whole, as a picture is.
  Future<void> _preview(mermaid.RenderScene scene) async {
    final picture = await _picture(scene);
    if (mounted) showImagePreview(context, picture);
  }

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
              clusterBorder: color(AppColors.partBorder),
              edgeLabelBackground: color(background),
              fontFamily: DefaultTextStyle.of(context).style.fontFamily,
              fontSize: 13,
            )
            // A sequence's actors, boxes and notes as a flowchart's nodes.
            .withSequenceColors(
              actorBkg: color(AppColors.surface),
              actorBorder: color(AppColors.accent),
              actorTextColor: color(foreground),
              actorLineColor: color(AppColors.textFaint),
              signalColor: color(foreground),
              signalTextColor: color(foreground),
              labelBoxBkgColor: color(AppColors.surface),
              labelBoxBorderColor: color(AppColors.accent),
              labelTextColor: color(foreground),
              loopTextColor: color(foreground),
              noteBkgColor: color(AppColors.surfaceRaised),
              noteBorderColor: color(AppColors.partBorder),
              noteTextColor: color(foreground),
              activationBkgColor: color(AppColors.surface),
              activationBorderColor: color(AppColors.accent),
            );
    if (_writing) {
      return const Align(
        alignment: AlignmentDirectional.topStart,
        child: ContentImagePlaceholder(aspectRatio: 16 / 9),
      );
    }
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
            LayoutBuilder(
              builder: (context, constraints) {
                final shown = _shown(scene, constraints.maxWidth);
                return Align(
                  alignment: AlignmentDirectional.topStart,
                  child: FileLinkMenuRegion(
                    menu: _PictureMenu(() => _picture(shown)),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.zoomIn,
                      child: GestureDetector(
                        onTap: () => unawaited(_preview(shown)),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _Scene(scene: shown, source: widget.code),
                        ),
                      ),
                    ),
                  ),
                );
              },
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
                        onTap: () => unawaited(
                          _preview(
                            _shown(
                              scene,
                              context.size?.width ?? double.infinity,
                            ),
                          ),
                        ),
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
    _quiet?.cancel();
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

/// A right click's on a diagram: a picture's (see [ImageMenu]), the
/// picture made as it is asked for.
class _PictureMenu implements ChatItemMenu {
  const _PictureMenu(this.picture);

  final Future<ImageAttachment> Function() picture;

  @override
  Future<void> show(BuildContext context, Offset position) async {
    final made = await picture();
    if (context.mounted) await ImageMenu(made).show(context, position);
  }
}

/// [scene] as a PNG, on [background] (a picture see-through would be lost
/// on a dark viewer, or a light one), with a margin round it; at three
/// times its size, for its text to stay sharp enlarged, or as large as a
/// picture sensibly is.
Future<ImageAttachment> mermaidPicture(
  mermaid.RenderScene scene, {
  required Color background,
}) async {
  const margin = 24.0;
  final size = Size(
    scene.size.width + 2 * margin,
    scene.size.height + 2 * margin,
  );
  final ratio = math.min(3.0, 8192 / math.max(size.width, size.height));
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(ratio)
    ..drawRect(Offset.zero & size, Paint()..color = background)
    ..translate(margin, margin);
  ScenePainter(scene).paint(canvas, Size(scene.size.width, scene.size.height));
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (size.width * ratio).ceil(),
    (size.height * ratio).ceil(),
  );
  picture.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return ImageAttachment(
      bytes: data!.buffer.asUint8List(),
      mediaType: 'image/png',
      name: 'mermaid.png',
    );
  } finally {
    image.dispose();
  }
}

/// [code], a flowchart drawn top down (`flowchart TD`, `graph TB`, or no
/// direction), drawn across instead: left to right, or right to left for
/// bottom up; null for any other.
String? mermaidAcross(String code) {
  final header = _topDown.firstMatch(code);
  if (header == null) return null;
  final across = header[2] == 'BT' ? 'RL' : 'LR';
  return code.replaceRange(
    header.start,
    header.end,
    '${header[1]} $across${header[3]}',
  );
}

final _topDown = RegExp(
  r'^([ \t]*(?:flowchart|graph))(?:[ \t]+(TD|TB|BT))?([ \t]*;?[ \t]*)$',
  multiLine: true,
);

/// [code] laid out by ELK, whose lines go square, where it says no layout
/// of its own: its directive first (after any front matter), so that one
/// of the code's, coming later, wins.
String mermaidSquare(String code) {
  const directive = '%%{init: {"layout": "elk"}}%%\n';
  final front = _frontMatter.firstMatch(code);
  if (front == null) return '$directive$code';
  return code.replaceRange(front.end, front.end, directive);
}

final _frontMatter = RegExp(r'^\s*---[ \t]*\n[\s\S]*?\n[ \t]*---[ \t]*\n');

/// [node] with its text's entities read (`&lt;` as `<`, Mermaid's `#lt;`
/// too), as Mermaid's HTML labels show them; laid out as written, it only
/// comes out a little narrower than measured.
mermaid.SceneNode mermaidUnescaped(mermaid.SceneNode node) => switch (node) {
  mermaid.SceneText(:final text) when text.contains(_entity) => node.copyWith(
    text: text.replaceAllMapped(_entity, _character),
  ),
  mermaid.SceneGroup() => mermaid.SceneGroup(
    children: [for (final child in node.children) mermaidUnescaped(child)],
    id: node.id,
    role: node.role,
    semanticLabel: node.semanticLabel,
    link: node.link,
    tooltip: node.tooltip,
    edge: node.edge,
  ),
  _ => node,
};

final _entity = RegExp(r'[&#](#?)(x[0-9a-fA-F]+|\d+|[a-zA-Z]+);');

String _character(Match match) {
  final whole = match[0]!;
  final name = match[2]!;
  if (!_number.hasMatch(name)) return _named[name] ?? whole;
  // `&#60;`, and Mermaid's `#60;`; a bare `&60;` is none.
  if (whole.startsWith('&') && match[1]!.isEmpty) return whole;
  final code = name.startsWith('x')
      ? int.tryParse(name.substring(1), radix: 16)
      : int.tryParse(name);
  if (code == null || code < 0x20 || code > 0x10FFFF) return whole;
  return String.fromCharCode(code);
}

final _number = RegExp(r'^(x[0-9a-fA-F]+|\d+)$');

const _named = {
  'lt': '<',
  'gt': '>',
  'amp': '&',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
};
