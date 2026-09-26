import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/cursor_theme.dart';
import '../chat_session.dart';
import '../widgets/hover_builder.dart';
import 'panel_card.dart';

/// Feedback area for the `ask_question` tool. Keyboard: 1-9 pick an option,
/// ↑/↓ move, Space toggles, Enter continues, Esc skips.
class AskQuestionPanel extends StatefulWidget {
  const AskQuestionPanel({
    super.key,
    required this.request,
    required this.onSubmit,
  });

  final AskQuestionRequest request;
  final ValueChanged<String> onSubmit;

  @override
  State<AskQuestionPanel> createState() => _AskQuestionPanelState();
}

class _AskQuestionPanelState extends State<AskQuestionPanel> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Ask question');
  late final List<Set<int>> _answers = [
    for (final _ in widget.request.questions) <int>{},
  ];
  int _step = 0;
  int _highlighted = 0;

  AskQuestion get _question => widget.request.questions[_step];
  bool get _isLast => _step == widget.request.questions.length - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _pick(int index) {
    setState(() {
      _highlighted = index;
      final answer = _answers[_step];
      if (_question.allowMultiple) {
        if (!answer.remove(index)) answer.add(index);
      } else {
        answer
          ..clear()
          ..add(index);
      }
    });
    if (!_question.allowMultiple) _advance();
  }

  void _advance() {
    if (_answers[_step].isEmpty) return;
    if (!_isLast) {
      setState(() {
        _step++;
        _highlighted = 0;
      });
      return;
    }
    widget.onSubmit(_summary());
  }

  void _skip() => widget.onSubmit(_summary(skipped: true));

  String _summary({bool skipped = false}) {
    final parts = <String>[];
    for (var i = 0; i < widget.request.questions.length; i++) {
      final question = widget.request.questions[i];
      final picked = (_answers[i].toList()..sort())
          .map((index) => question.options[index])
          .join('、');
      parts.add(picked.isEmpty ? '（跳过）' : picked);
    }
    return skipped && parts.every((part) => part == '（跳过）')
        ? '用户跳过了问题，按默认方案继续'
        : parts.join('；');
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final count = _question.options.length;
    final digit = int.tryParse(event.character ?? '');
    if (digit != null && digit >= 1 && digit <= count) {
      _pick(digit - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _highlighted = (_highlighted + 1) % count);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _highlighted = (_highlighted - 1 + count) % count);
    } else if (key == LogicalKeyboardKey.space) {
      _pick(_highlighted);
    } else if (key == LogicalKeyboardKey.enter) {
      if (_answers[_step].isEmpty) {
        _pick(_highlighted);
        if (_question.allowMultiple) _advance();
      } else {
        _advance();
      }
    } else if (key == LogicalKeyboardKey.escape) {
      _skip();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final question = _question;
    final total = widget.request.questions.length;
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: ListenableBuilder(
        listenable: _focusNode,
        builder: (context, _) => PanelCard(
          highlighted: _focusNode.hasFocus,
          header: Row(
            children: [
              const Icon(
                Icons.help_outline_rounded,
                size: 14,
                color: CursorColors.accent,
              ),
              const SizedBox(width: 6),
              Text(
                widget.request.title,
                style: const TextStyle(
                  color: CursorColors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              for (var i = 0; i < total; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(right: 4),
                  width: i == _step ? 14 : 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: i <= _step
                        ? CursorColors.accent
                        : CursorColors.borderStrong,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              const Spacer(),
              Text(
                '${_step + 1} / $total',
                style: const TextStyle(
                  color: CursorColors.textFaint,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _focusNode.requestFocus,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KeyedSubtree(
                  key: ValueKey(_step),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                        child: Text(
                          question.prompt +
                              (question.allowMultiple ? '（可多选）' : ''),
                          style: const TextStyle(
                            color: CursorColors.textPrimary,
                            fontSize: 13.5,
                            height: 1.45,
                          ),
                        ),
                      ),
                      for (var i = 0; i < question.options.length; i++)
                        _OptionRow(
                          index: i,
                          label: question.options[i],
                          multiple: question.allowMultiple,
                          selected: _answers[_step].contains(i),
                          highlighted: _focusNode.hasFocus && i == _highlighted,
                          onHover: () => setState(() => _highlighted = i),
                          onTap: () {
                            _focusNode.requestFocus();
                            _pick(i);
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text(
                      '1-9 选择 · ↵ 继续 · esc 跳过',
                      style: TextStyle(
                        color: CursorColors.textFaint,
                        fontSize: 11,
                      ),
                    ),
                    const Spacer(),
                    PanelButton(label: 'Skip', onTap: _skip),
                    const SizedBox(width: 6),
                    PanelButton(
                      label: _isLast ? 'Submit' : 'Next',
                      primary: true,
                      onTap: _answers[_step].isEmpty ? null : _advance,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.index,
    required this.label,
    required this.multiple,
    required this.selected,
    required this.highlighted,
    required this.onHover,
    required this.onTap,
  });

  final int index;
  final String label;
  final bool multiple;
  final bool selected;
  final bool highlighted;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0x1A4C9DFF)
                : highlighted
                ? CursorColors.hover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? const Color(0x554C9DFF) : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? CursorColors.accent : CursorColors.surface,
                  borderRadius: BorderRadius.circular(multiple ? 4 : 9),
                  border: Border.all(
                    color: selected
                        ? CursorColors.accent
                        : CursorColors.borderStrong,
                  ),
                ),
                child: selected && multiple
                    ? const Icon(
                        Icons.check_rounded,
                        size: 12,
                        color: CursorColors.background,
                      )
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: selected
                              ? CursorColors.background
                              : CursorColors.textMuted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected || highlighted
                        ? CursorColors.textPrimary
                        : CursorColors.text,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small text button shared by the panels.
class PanelButton extends StatelessWidget {
  const PanelButton({
    super.key,
    required this.label,
    this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return HoverBuilder(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary
                ? (enabled
                      ? (hovered
                            ? const Color(0xFFFFFFFF)
                            : CursorColors.textPrimary)
                      : const Color(0xFF3A3A3A))
                : (hovered && enabled
                      ? const Color(0x1AFFFFFF)
                      : Colors.transparent),
            borderRadius: BorderRadius.circular(5),
            border: primary
                ? null
                : Border.all(color: CursorColors.borderStrong),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: primary
                  ? (enabled ? CursorColors.background : CursorColors.textFaint)
                  : CursorColors.text,
              fontSize: 12,
              fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
