import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/cursor_theme.dart';
import 'edge_fade_mask.dart';
import 'hover_builder.dart';
import 'shimmer_text.dart';

/// `1.2k` for 1234 tokens.
String formatTokens(int tokens) => tokens < 1000
    ? '$tokens'
    : '${(tokens / 1000).toStringAsFixed(tokens < 10000 ? 1 : 0)}k';

/// Header of a thought: tokens so far while it streams, then how long it
/// took and its total.
String thinkingTitle({required int? seconds, required int tokens}) {
  final count = '${formatTokens(tokens)} tokens';
  if (seconds == null) return tokens == 0 ? 'Thinking' : 'Thinking · $count';
  return 'Thought for ${seconds}s · $count';
}

/// Collapsible thought. While it streams ([seconds] is null) its text sits
/// in a box of limited height that follows the newest lines, fading out at
/// the top over earlier ones; once done it shows in full.
class ThinkingSection extends StatefulWidget {
  const ThinkingSection({
    super.key,
    required this.text,
    required this.tokens,
    required this.seconds,
    required this.expanded,
    required this.onToggle,
  });

  final String text;
  final int tokens;
  final int? seconds;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  State<ThinkingSection> createState() => _ThinkingSectionState();
}

class _ThinkingSectionState extends State<ThinkingSection> {
  static const _textStyle = TextStyle(
    color: CursorColors.textMuted,
    fontSize: 13,
    height: 1.6,
  );

  /// Seven lines of text.
  static const _liveMaxHeight = 13 * 1.6 * 7;

  final ScrollController _scrollController = ScrollController();
  final SelectionListenerNotifier _selection = SelectionListenerNotifier();
  bool _contentAbove = false;

  /// The text shown while streaming: it holds still while any of it is
  /// selected. Each change of text rebuilds the paragraph's selection from
  /// where its ends were on screen, a frame late: new text would blink the
  /// highlight, and following it (scrolling) slide it onto other characters.
  /// It catches up with the first new text once the selection is gone.
  late String _liveText = widget.text;

  bool get _streaming => widget.seconds == null;

  bool get _selected =>
      _selection.registered &&
      _selection.selection.status == SelectionStatus.uncollapsed;

  @override
  void didUpdateWidget(ThinkingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text == _liveText || _selected) return;
    _liveText = widget.text;
    if (!_scrollController.hasClients) return;
    // Follow new lines, unless scrolled up to read earlier ones.
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 2) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      position.jumpTo(position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _selection.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Content scrolled (or grown and followed) past the top shows the mask.
  bool _handleScroll(Notification notification) {
    final metrics = switch (notification) {
      ScrollNotification(:final metrics) => metrics,
      ScrollMetricsNotification(:final metrics) => metrics,
      _ => null,
    };
    if (metrics == null) return false;
    final above = metrics.pixels > 0.5;
    if (above != _contentAbove) setState(() => _contentAbove = above);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Full width: the history centers each item in its column, and the text
    // alone would not fill it.
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: widget.expanded
                ? Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 6, bottom: 2),
                    child: _streaming
                        ? _buildLiveText()
                        : Text(widget.text, style: _textStyle),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final title = thinkingTitle(seconds: widget.seconds, tokens: widget.tokens);
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) {
        final color = hovered ? CursorColors.text : CursorColors.textMuted;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_streaming)
                  ShimmerText(title, ellipsis: false, padding: EdgeInsets.zero)
                else
                  Text(title, style: TextStyle(color: color, fontSize: 13)),
                const SizedBox(width: 2),
                AnimatedRotation(
                  turns: widget.expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLiveText() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _liveMaxHeight),
      child: NotificationListener<Notification>(
        onNotification: _handleScroll,
        child: EdgeFadeMask(
          top: _contentAbove,
          bottom: false,
          fadeLength: 24,
          fadeOffset: 2,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context)
                .copyWith(scrollbars: false),
            child: SingleChildScrollView(
              controller: _scrollController,
              child: SelectionListener(
                selectionNotifier: _selection,
                child: SizedBox(
                  width: double.infinity,
                  child: Text(_liveText, style: _textStyle),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
