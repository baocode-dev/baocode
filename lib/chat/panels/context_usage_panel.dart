import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';
import '../chat_session.dart';
import 'panel_card.dart';

/// Modal area: breakdown of the context window, opened from the composer ring.
class ContextUsagePanel extends StatelessWidget {
  const ContextUsagePanel({
    super.key,
    required this.session,
    required this.onClose,
  });

  final ChatSession session;
  final VoidCallback onClose;

  static const _colors = [
    Color(0xFF8C8C8C),
    Color(0xFFB392F0),
    Color(0xFFE2C08D),
    Color(0xFF4FC3F7),
    Color(0xFF4EC98A),
  ];

  static String _format(int tokens) =>
      tokens >= 1000 ? '${(tokens / 1000).toStringAsFixed(1)}k' : '$tokens';

  @override
  Widget build(BuildContext context) {
    final segments = session.contextSegments;
    final used = session.contextUsed;
    const total = ChatSession.contextWindow;
    return PanelCard(
      header: Row(
        children: [
          const Text(
            'Context window',
            style: TextStyle(
              color: CursorColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_format(used)} / ${_format(total)} tokens · '
            '${(used / total * 100).toStringAsFixed(0)}%',
            style: const TextStyle(color: CursorColors.textFaint, fontSize: 11),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onClose,
            child: const MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Icon(
                Icons.close_rounded,
                size: 15,
                color: CursorColors.textMuted,
              ),
            ),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: LayoutBuilder(
                  builder: (context, constraints) => Row(
                    children: [
                      for (var i = 0; i < segments.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width:
                              constraints.maxWidth * segments[i].tokens / total,
                          margin: const EdgeInsets.only(right: 1),
                          color: _colors[i % _colors.length],
                        ),
                      const Expanded(
                        child: ColoredBox(color: CursorColors.border),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                for (var i = 0; i < segments.length; i++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: _colors[i % _colors.length],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        segments[i].label,
                        style: const TextStyle(
                          color: CursorColors.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _format(segments[i].tokens),
                        style: const TextStyle(
                          color: CursorColors.text,
                          fontFamily: CursorFonts.mono,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '接近上限时会自动总结较早的对话，也可以输入 /summarize 手动压缩。',
              style: TextStyle(color: CursorColors.textFaint, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
