import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';
import 'edge_fade_mask.dart';
import 'live_selectable_text.dart';
import 'step_header.dart';
import 'wheel_latch.dart';

/// Header of a thought: while it streams, how long so far ([elapsed], at
/// least "Thinking 1s"); then how long it took, "Thought 2s" or, under a
/// second, "Thought briefly".
String thinkingTitle({required int? seconds, Duration? elapsed}) =>
    switch (thinkingParts(seconds, elapsed: elapsed)) {
      (final verb, final object) => StepHeader.text(verb, object),
    };

(String, String) thinkingParts(int? seconds, {Duration? elapsed}) => switch ((
  seconds,
  elapsed,
)) {
  (null, final elapsed?) => ('Thinking', '${math.max(1, elapsed.inSeconds)}s'),
  (null, null) => ('Thinking', ''),
  (final int seconds, _) when seconds < 1 => ('Thought', 'briefly'),
  (final seconds, _) => ('Thought', '${seconds}s'),
};

/// Collapsible thought. While it streams ([seconds] is null) its text sits
/// in a box of limited height that follows the newest lines, fading out at
/// the top over earlier ones; once done it shows in full.
class ThinkingSection extends StatefulWidget {
  const ThinkingSection({
    super.key,
    required this.text,
    required this.seconds,
    required this.expanded,
    required this.onToggle,
    this.startedAt,
  });

  final String text;
  final int? seconds;

  /// When it began: while it streams, its time so far counts up.
  final DateTime? startedAt;
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
  bool _contentAbove = false;

  bool get _streaming => widget.seconds == null;

  /// Ticks the time shown while it streams.
  Timer? _clock;

  void _syncClock() {
    final ticking = _streaming && widget.startedAt != null;
    if (ticking == (_clock != null)) return;
    _clock?.cancel();
    _clock = ticking
        ? Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}))
        : null;
  }

  @override
  void initState() {
    super.initState();
    _syncClock();
  }

  /// Its text without the blank lines thoughts end with.
  String get _text => widget.text.trimRight();

  @override
  void didUpdateWidget(ThinkingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncClock();
    if (widget.text == oldWidget.text || !_scrollController.hasClients) return;
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
    _clock?.cancel();
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
            // Nothing to show until its first words (a summarized thought
            // may bring them only at its end).
            child: widget.expanded && _text.isNotEmpty
                ? Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 6, bottom: 2),
                    child: _streaming
                        ? _buildLiveText()
                        : Text(_text, style: _textStyle),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final (verb, object) = thinkingParts(
      widget.seconds,
      elapsed: switch (widget.startedAt) {
        final start? when _streaming => DateTime.now().difference(start),
        _ => null,
      },
    );
    return StepHeader(
      verb: verb,
      object: object,
      running: _streaming,
      expanded: widget.expanded,
      // Nothing to open until its first words.
      onToggle: _text.isEmpty ? null : widget.onToggle,
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
              // Selectable text that keeps its selection as it grows.
              child: WheelLatch(
                child: SizedBox(
                  width: double.infinity,
                  child: LiveSelectableText(_text, style: _textStyle),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
