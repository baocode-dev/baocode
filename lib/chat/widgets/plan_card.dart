import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../chat_models.dart';
import '../side_panel/file_open.dart';
import 'hover_builder.dart';
import 'fade_curve.dart';
import 'markdown_view.dart';

/// A round of planning in the conversation: the plan's title over its
/// text, the text fading out past a height; a click shows it in full beside
/// the chat (see [FileOpenScope]). A plan sent back gives way to the next round's:
/// it folds to one line, with what the user said should change.
class PlanCard extends StatelessWidget {
  const PlanCard({super.key, required this.item});

  final PlanItem item;

  /// The status as text, in [l10n]'s language.
  static String status(PlanStatus status, AppLocalizations l10n) =>
      switch (status) {
        PlanStatus.drafting => l10n.planDrafting,
        PlanStatus.awaiting => l10n.planAwaiting,
        PlanStatus.approved => l10n.planApproved,
        PlanStatus.sentBack => l10n.planSentBack,
      };

  /// The card as text, e.g. for copying; in [l10n]'s language (English
  /// when null).
  static String plainText(PlanItem item, {AppLocalizations? l10n}) {
    final strings = l10n ?? englishLocalizations;
    return [
      '${strings.planCardLabel} ${strings.planCardRound(item.round)}',
      item.name,
      status(item.status, strings),
      ?item.feedback,
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final files = FileOpenScope.maybeOf(context);
    final VoidCallback? open = files == null
        ? null
        : () => files.onOpen(FileOpenRequest(item.path, plan: true));
    final card = item.status == PlanStatus.sentBack
        ? _folded(context, open)
        : _card(context, open);
    return SizedBox(width: double.infinity, child: card);
  }

  /// Sent back: one line.
  Widget _folded(BuildContext context, VoidCallback? open) {
    final l10n = context.l10n;
    final faint = TextStyle(color: AppColors.textFaint, fontSize: 12.5);
    return HoverBuilder(
      cursor: open == null ? MouseCursor.defer : SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Icon(
                Icons.checklist_rounded,
                size: 15,
                color: AppColors.textFaint,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text:
                            '${l10n.planCardLabel} '
                            '${l10n.planCardRound(item.round)} · '
                            '${l10n.planSentBack}',
                        style: TextStyle(
                          color: hovered
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                        ),
                      ),
                      if (item.feedback case final feedback?)
                        TextSpan(text: '：$feedback'),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: faint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// How high the card's text goes, past which it fades out: about twice
  /// a card without it.
  static const maxBodyHeight = 150.0;

  Widget _card(BuildContext context, VoidCallback? open) {
    final l10n = context.l10n;
    final text = _body(item);
    return HoverBuilder(
      cursor: open == null ? MouseCursor.defer : SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
          decoration: BoxDecoration(
            // Hovered, half a list row's hover over it: the whole of it is
            // heavy on a card this big.
            color: hovered
                ? Color.alphaBlend(
                    AppColors.hover.withValues(alpha: AppColors.hover.a * 0.5),
                    AppColors.surface,
                  )
                : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // As the approvals that carry it out unasked show.
                  Icon(
                    Icons.checklist_rounded,
                    size: 16,
                    color: AppColors.caution,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                  if (item.round > 1) ...[
                    const SizedBox(width: 8),
                    Text(
                      l10n.planCardRound(item.round),
                      style: TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              ),
              if (text != null) ...[
                const SizedBox(height: 6),
                // Its text is the card's: a click on it opens the plan.
                IgnorePointer(
                  child: _FadedBody(
                    maxHeight: maxBodyHeight,
                    child: MarkdownView(
                      text,
                      style: MarkdownView.baseStyle.copyWith(fontSize: 13),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// [item]'s text under its title: without the heading the title is.
  static String? _body(PlanItem item) {
    final text = item.text;
    if (text == null) return null;
    final lines = text.trimLeft().split('\n');
    if (lines.isNotEmpty && PlanItem.titleOf(lines.first) == item.title) {
      lines.removeAt(0);
    }
    final body = lines.join('\n').trim();
    return body.isEmpty ? null : body;
  }
}

/// [child] in full up to [maxHeight]; past that, its top [maxHeight],
/// fading out through its alpha towards the bottom (as a long message in
/// the history does), what is behind it showing through.
class _FadedBody extends SingleChildRenderObjectWidget {
  const _FadedBody({required this.maxHeight, required super.child});

  final double maxHeight;

  @override
  _RenderFadedBody createRenderObject(BuildContext context) =>
      _RenderFadedBody(maxHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderFadedBody renderObject) {
    renderObject.maxHeight = maxHeight;
  }
}

class _RenderFadedBody extends RenderProxyBox {
  _RenderFadedBody(this._maxHeight);

  double _maxHeight;
  set maxHeight(double value) {
    if (value == _maxHeight) return;
    _maxHeight = value;
    markNeedsLayout();
  }

  /// Over how much of the bottom it fades out.
  static const _fadeLength = 56.0;

  /// How far above the bottom it is hidden completely: the eased end of a
  /// fade is faint but not zero, and would show the tops of the last
  /// line's glyphs.
  static const _fadeOffset = 6.0;

  bool _overflows = false;
  final _maskLayer = LayerHandle<ShaderMaskLayer>();

  @override
  bool get alwaysNeedsCompositing => _overflows;

  @override
  void dispose() {
    _maskLayer.layer = null;
    super.dispose();
  }

  @override
  void performLayout() {
    final child = this.child!;
    child.layout(
      BoxConstraints(maxWidth: constraints.maxWidth),
      parentUsesSize: true,
    );
    final overflows = child.size.height > _maxHeight;
    if (overflows != _overflows) {
      _overflows = overflows;
      markNeedsCompositingBitsUpdate();
    }
    size = constraints.constrain(
      Size(child.size.width, overflows ? _maxHeight : child.size.height),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child!;
    if (!_overflows) {
      _maskLayer.layer = null;
      context.paintChild(child, offset);
      return;
    }
    final fade = Rect.fromLTRB(
      0,
      size.height - _fadeLength - _fadeOffset,
      size.width,
      size.height - _fadeOffset,
    );
    final samples = easedFade().toList().reversed;
    _maskLayer.layer = (_maskLayer.layer ?? ShaderMaskLayer())
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          for (final (_, opacity) in samples)
            Color.fromRGBO(255, 255, 255, opacity),
        ],
        stops: [for (final (t, _) in samples) 1 - t],
      ).createShader(fade)
      ..maskRect = offset & size
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(
      _maskLayer.layer!,
      (context, offset) => context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        (context, offset) => context.paintChild(child, offset),
      ),
      offset,
    );
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      _overflows ? Offset.zero & size : null;

  @override
  double computeMinIntrinsicHeight(double width) =>
      super.computeMinIntrinsicHeight(width).clamp(0, _maxHeight);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      super.computeMaxIntrinsicHeight(width).clamp(0, _maxHeight);
}
