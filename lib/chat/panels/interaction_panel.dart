import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../kernel/kernel_types.dart';
import '../../keybindings/chat_keybindings.dart';
import '../../l10n/l10n.dart';
import '../../theme/cursor_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../chat_keys.dart';
import '../chat_models.dart';
import '../widgets/hover_builder.dart';
import '../widgets/markdown_view.dart';
import 'panel_card.dart';

/// The feedback area for what an agent waits on the user for: questions,
/// leave to use a tool, a plan to approve. Each is a series of steps of
/// options, driven alike: 1-9 pick, ↑/↓ move, Space toggles, Enter goes on,
/// Esc dismisses (keybindings but the digits: see [ChatCommandIds]). An
/// option may take words of the user's own.
class InteractionPanel extends StatefulWidget {
  const InteractionPanel({
    super.key,
    required this.request,
    required this.onAnswer,
  });

  final InteractionRequest request;
  final ValueChanged<InteractionAnswer> onAnswer;

  @override
  State<InteractionPanel> createState() => _InteractionPanelState();
}

class _Row {
  const _Row(this.label, {this.description = '', this.textHint, this.preview});

  final String label;
  final String description;

  /// Set for an option the user answers in their own words.
  final String? textHint;
  final String? preview;
}

class _Step {
  const _Step({
    required this.prompt,
    required this.rows,
    this.header = '',
    this.multiple = false,
    this.detail,
  });

  final String prompt;
  final String header;
  final List<_Row> rows;
  final bool multiple;

  /// Above the options, e.g. the command to run or the plan.
  final Widget? detail;
}

class _InteractionPanelState extends State<InteractionPanel>
    with ChatKeyTarget {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Interaction');
  final FocusNode _textFocus = FocusNode(debugLabel: 'Interaction text');

  /// In the display language: made again when it changes.
  late List<_Step> _steps;
  late final List<Set<int>> _picks = [for (final _ in _steps) <int>{}];
  late final List<TextEditingController> _texts = [
    for (final _ in _steps) TextEditingController(),
  ];
  int _step = 0;
  int _highlighted = 0;

  _Step get _current => _steps[_step];
  bool get _isLast => _step == _steps.length - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _steps = _stepsFor(widget.request, context.l10n);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _textFocus.dispose();
    for (final text in _texts) {
      text.dispose();
    }
    super.dispose();
  }

  // --- Steps, by request ------------------------------------------------------------

  static List<_Step> _stepsFor(
    InteractionRequest request,
    AppLocalizations l10n,
  ) => switch (request) {
    QuestionRequest(:final questions) => [
      for (final question in questions)
        _Step(
          prompt: question.prompt,
          header: question.header,
          multiple: question.allowMultiple,
          rows: [
            for (final option in question.options)
              _Row(
                option.label,
                description: option.description,
                preview: option.preview,
              ),
            if (question.allowOther)
              _Row(
                l10n.interactionOther,
                textHint: l10n.interactionTypeYourAnswer,
              ),
          ],
        ),
    ],
    ApprovalRequest(:final reason, :final preview, :final alwaysAllowLabel) => [
      _Step(
        prompt: reason ?? '',
        detail: _ApprovalPreview(preview),
        rows: [
          _Row(l10n.interactionAllowOnce),
          if (alwaysAllowLabel != null) _Row(alwaysAllowLabel),
          _Row(l10n.interactionDeny, textHint: l10n.interactionDenyHint),
        ],
      ),
    ],
    PlanReviewRequest(:final plan, :final approveLabel) => [
      _Step(
        prompt: '',
        detail: _PlanPreview(plan),
        rows: [
          _Row(approveLabel),
          _Row(
            l10n.interactionKeepPlanningOption,
            textHint: l10n.interactionWhatShouldChange,
          ),
        ],
      ),
    ],
  };

  InteractionAnswer _answer({required bool dismissed}) {
    switch (widget.request) {
      case QuestionRequest():
        return QuestionAnswer([
          for (final (i, step) in _steps.indexed)
            [
              for (final row in (_picks[i].toList()..sort()))
                if (step.rows[row].textHint != null)
                  _texts[i].text.trim().isEmpty
                      ? step.rows[row].label
                      : _texts[i].text.trim()
                else
                  step.rows[row].label,
            ],
        ], skipped: dismissed && _picks.every((pick) => pick.isEmpty));
      case ApprovalRequest(:final alwaysAllowLabel):
        final pick = dismissed ? null : _picks.first.firstOrNull;
        final rows = _steps.first.rows;
        if (pick == null || rows[pick].textHint != null) {
          return ApprovalAnswer(
            ApprovalDecision.deny,
            message: _texts.first.text.trim(),
          );
        }
        return ApprovalAnswer(
          pick == 1 && alwaysAllowLabel != null
              ? ApprovalDecision.allowAlways
              : ApprovalDecision.allowOnce,
        );
      case PlanReviewRequest():
        final pick = dismissed ? 1 : _picks.first.firstOrNull ?? 1;
        return PlanAnswer(
          pick == 0 ? PlanDecision.approve : PlanDecision.keepPlanning,
          feedback: _texts.first.text.trim(),
        );
    }
  }

  // --- Driving ------------------------------------------------------------------------

  void _pick(int index) {
    final row = _current.rows[index];
    setState(() {
      _highlighted = index;
      final picks = _picks[_step];
      if (_current.multiple) {
        if (!picks.remove(index)) picks.add(index);
      } else {
        picks
          ..clear()
          ..add(index);
      }
    });
    if (row.textHint != null && _picks[_step].contains(index)) {
      _textFocus.requestFocus();
      return;
    }
    if (!_current.multiple) _advance();
  }

  void _advance() {
    if (_picks[_step].isEmpty) return;
    if (!_isLast) {
      setState(() {
        _step++;
        _highlighted = 0;
      });
      _focusNode.requestFocus();
      return;
    }
    widget.onAnswer(_answer(dismissed: false));
  }

  void _dismiss() => widget.onAnswer(_answer(dismissed: true));

  void _moveHighlight(int step) {
    final count = _current.rows.length;
    setState(() => _highlighted = (_highlighted + step + count) % count);
  }

  /// Enter: the highlighted option if none is picked, then on.
  void _continue() {
    if (_picks[_step].isEmpty) {
      _pick(_highlighted);
      if (_current.multiple) _advance();
    } else {
      _advance();
    }
  }

  @override
  Object? chatContextKey(String key) => switch (key) {
    // The options, not the words of an option (its text field).
    ChatContextKeys.inInteraction => _focusNode.hasPrimaryFocus,
    _ => null,
  };

  @override
  Map<String, VoidCallback> get chatCommands => {
    ChatCommandIds.interactionFocusNext: () => _moveHighlight(1),
    ChatCommandIds.interactionFocusPrevious: () => _moveHighlight(-1),
    ChatCommandIds.interactionToggle: () => _pick(_highlighted),
    ChatCommandIds.interactionAccept: _continue,
    ChatCommandIds.interactionDismiss: _dismiss,
  };

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (ChatKeys.isHandled(event)) return KeyEventResult.handled;
    // 1-9 pick, on the options (the text field types them).
    final keyboard = HardwareKeyboard.instance;
    final digit = int.tryParse(event.character ?? '');
    if (_focusNode.hasPrimaryFocus &&
        digit != null &&
        digit >= 1 &&
        digit <= _current.rows.length &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed) {
      _pick(digit - 1);
      return KeyEventResult.handled;
    }
    return ChatKeys.dispatch(event) ?? KeyEventResult.ignored;
  }

  // --- Building -----------------------------------------------------------------------

  (IconData, Color) get _icon => switch (widget.request) {
    QuestionRequest() => (Icons.help_outline_rounded, CursorColors.accent),
    // Waiting on the user, as the agent sessions list shows it.
    ApprovalRequest() => (
      Icons.shield_outlined,
      themeColors['list.warningForeground'],
    ),
    PlanReviewRequest() => (Icons.checklist_rounded, CursorColors.accent),
  };

  @override
  Widget build(BuildContext context) {
    final step = _current;
    final total = _steps.length;
    final (icon, color) = _icon;
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: ListenableBuilder(
        listenable: Listenable.merge([_focusNode, _textFocus]),
        builder: (context, _) => PanelCard(
          highlighted: _focusNode.hasFocus || _textFocus.hasFocus,
          maxBodyHeight: 360,
          header: Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              // All the room there is, so the count sits at the end.
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.request.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: CursorColors.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (total > 1) ...[
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
                    ],
                  ],
                ),
              ),
              if (total > 1) ...[
                const SizedBox(width: 8),
                Text(
                  context.l10n.interactionStepOf(_step + 1, total),
                  style: TextStyle(color: CursorColors.textFaint, fontSize: 11),
                ),
              ],
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
                      if (step.detail case final detail?)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                          child: detail,
                        ),
                      if (step.prompt.isNotEmpty || step.header.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                if (step.header.isNotEmpty)
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: _HeaderChip(step.header),
                                  ),
                                TextSpan(
                                  text:
                                      step.prompt +
                                      (step.multiple ? '（可多选）' : ''),
                                ),
                              ],
                            ),
                            style: TextStyle(
                              color: CursorColors.textPrimary,
                              fontSize: 13.5,
                              height: 1.45,
                            ),
                          ),
                        ),
                      for (var i = 0; i < step.rows.length; i++)
                        _OptionRow(
                          index: i,
                          row: step.rows[i],
                          multiple: step.multiple,
                          selected: _picks[_step].contains(i),
                          highlighted: _focusNode.hasFocus && i == _highlighted,
                          text: _texts[_step],
                          textFocus: _textFocus,
                          onTextSubmitted: _advance,
                          onTextEscape: _focusNode.requestFocus,
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
                    Expanded(
                      child: Text(
                        context.l10n.interactionKeysHint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: CursorColors.textFaint,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PanelButton(
                      label: switch (widget.request) {
                        QuestionRequest() => context.l10n.interactionSkip,
                        ApprovalRequest() => context.l10n.interactionDeny,
                        PlanReviewRequest() =>
                          context.l10n.interactionKeepPlanning,
                      },
                      onTap: _dismiss,
                    ),
                    const SizedBox(width: 6),
                    PanelButton(
                      label: _isLast
                          ? context.l10n.interactionSubmit
                          : context.l10n.interactionNext,
                      primary: true,
                      onTap: _picks[_step].isEmpty ? null : _advance,
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

class _HeaderChip extends StatelessWidget {
  const _HeaderChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: themeColors['badge.background'],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: themeColors['badge.foreground'],
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.index,
    required this.row,
    required this.multiple,
    required this.selected,
    required this.highlighted,
    required this.text,
    required this.textFocus,
    required this.onTextSubmitted,
    required this.onTextEscape,
    required this.onHover,
    required this.onTap,
  });

  final int index;
  final _Row row;
  final bool multiple;
  final bool selected;
  final bool highlighted;
  final TextEditingController text;
  final FocusNode textFocus;
  final VoidCallback onTextSubmitted;
  final VoidCallback onTextEscape;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hint = row.textHint;
    final colors = themeColors;
    // As upstream's question list: hover, then the selection; high contrast
    // themes outline the selection.
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
                ? colors['list.activeSelectionBackground']
                : highlighted
                ? CursorColors.hover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected
                  ? colors['contrastActiveBorder']
                  : Colors.transparent,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Marker(index: index, multiple: multiple, selected: selected),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.label,
                          style: TextStyle(
                            color: selected
                                ? colors['list.activeSelectionForeground']
                                : highlighted
                                ? CursorColors.textPrimary
                                : CursorColors.text,
                            fontSize: 13,
                          ),
                        ),
                        if (row.description.isNotEmpty &&
                            row.description != row.label)
                          Text(
                            row.description,
                            style: TextStyle(
                              color: CursorColors.textMuted,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (hint != null && selected)
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 6, 0, 0),
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.escape):
                          onTextEscape,
                    },
                    child: TextField(
                      controller: text,
                      focusNode: textFocus,
                      autofocus: true,
                      minLines: 1,
                      maxLines: 4,
                      onSubmitted: (_) => onTextSubmitted(),
                      style: TextStyle(
                        color: colors['input.foreground'],
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: hint,
                        hintStyle: TextStyle(
                          color: colors['input.placeholderForeground'],
                          fontSize: 13,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 7,
                        ),
                        filled: true,
                        fillColor: colors['input.background'],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                            color: CursorColors.borderStrong,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                            color: CursorColors.borderStrong,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: colors['focusBorder']),
                        ),
                      ),
                    ),
                  ),
                ),
              if (row.preview case final preview? when highlighted || selected)
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 6, 0, 0),
                  child: MarkdownCodeBlock(code: preview),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker({
    required this.index,
    required this.multiple,
    required this.selected,
  });

  final int index;
  final bool multiple;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    // A checkbox; picked, the primary button's colors.
    final foreground =
        colors[selected ? 'button.foreground' : 'checkbox.foreground'];
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors[selected ? 'button.background' : 'checkbox.background'],
        borderRadius: BorderRadius.circular(multiple ? 4 : 9),
        border: Border.all(
          color: selected
              ? colors.get('button.border') ?? colors['button.background']
              : colors['checkbox.border'],
        ),
      ),
      child: selected && multiple
          ? Icon(Icons.check_rounded, size: 12, color: foreground)
          : Text(
              '${index + 1}',
              style: TextStyle(
                color: foreground,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}

/// What a tool would do: the command, the edit, or its input.
class _ApprovalPreview extends StatelessWidget {
  const _ApprovalPreview(this.preview);

  final ApprovalPreview? preview;

  static const _mono = TextStyle(
    fontFamily: CursorFonts.mono,
    fontSize: 12,
    height: 1.5,
  );

  @override
  Widget build(BuildContext context) {
    return switch (preview) {
      null => const SizedBox.shrink(),
      CommandPreview(:final command, :final description) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (description != null && description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                description,
                style: TextStyle(color: CursorColors.textMuted, fontSize: 12.5),
              ),
            ),
          _Box(
            child: Text.rich(
              TextSpan(
                style: _mono,
                children: [
                  TextSpan(
                    text: '\$ ',
                    style: TextStyle(color: CursorColors.textFaint),
                  ),
                  TextSpan(
                    text: command,
                    style: TextStyle(color: CursorColors.textPrimary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      DiffPreview(:final path, :final lines) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              path,
              style: _mono.copyWith(color: CursorColors.textMuted),
            ),
          ),
          _Box(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final line in lines.take(80))
                  Container(
                    color: switch (line.type) {
                      DiffLineType.added => CursorColors.addedBackground,
                      DiffLineType.removed => CursorColors.removedBackground,
                      DiffLineType.context => null,
                    },
                    child: Text(
                      '${switch (line.type) {
                        DiffLineType.added => '+',
                        DiffLineType.removed => '-',
                        DiffLineType.context => ' ',
                      }} ${line.text}',
                      style: _mono.copyWith(
                        color: switch (line.type) {
                          DiffLineType.added => CursorColors.added,
                          DiffLineType.removed => CursorColors.removed,
                          DiffLineType.context => CursorColors.text,
                        },
                      ),
                    ),
                  ),
                if (lines.length > 80)
                  Text(
                    context.l10n.interactionMoreLines(lines.length - 80),
                    style: _mono.copyWith(color: CursorColors.textFaint),
                  ),
              ],
            ),
          ),
        ],
      ),
      TextPreview(:final text) => _Box(
        child: Text(text, style: _mono.copyWith(color: CursorColors.text)),
      ),
    };
  }
}

class _PlanPreview extends StatelessWidget {
  const _PlanPreview(this.plan);

  final String plan;

  @override
  Widget build(BuildContext context) {
    return _Box(
      maxHeight: 200,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: CursorColors.background,
      child: MarkdownView(plan),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.child,
    this.maxHeight = 160,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    this.color,
  });

  final Widget child;
  final double maxHeight;
  final EdgeInsets padding;

  /// [CursorColors.code] when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: color ?? CursorColors.code,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: CursorColors.border),
      ),
      child: SingleChildScrollView(padding: padding, child: child),
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
    final colors = themeColors;
    // A button as upstream's: primary or secondary; dimmed when disabled.
    final border = primary
        ? colors.get('button.border')
        : colors.get('button.secondaryBorder');
    return HoverBuilder(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      builder: (context, hovered) => Opacity(
        opacity: enabled ? 1 : 0.4,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  colors[switch ((primary, hovered && enabled)) {
                    (true, true) => 'button.hoverBackground',
                    (true, false) => 'button.background',
                    (false, true) => 'button.secondaryHoverBackground',
                    (false, false) => 'button.secondaryBackground',
                  }],
              borderRadius: BorderRadius.circular(5),
              border: border == null ? null : Border.all(color: border),
            ),
            child: Text(
              label,
              style: TextStyle(
                color:
                    colors[primary
                        ? 'button.foreground'
                        : 'button.secondaryForeground'],
                fontSize: 12,
                fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
