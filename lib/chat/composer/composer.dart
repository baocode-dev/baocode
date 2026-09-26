import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../theme/cursor_theme.dart';
import '../chat_session.dart';
import '../widgets/hover_builder.dart';
import 'composer_caret.dart';
import 'composer_embeds.dart';
import 'composer_mock_data.dart';
import 'composer_picker.dart';
import 'suggestion_menu.dart';

/// An open @mention or /command query: the trigger character sits at
/// [start] and [query] is the text between it and the caret.
class _Trigger {
  const _Trigger(this.kind, this.start, this.query);

  final SuggestionKind kind;
  final int start;
  final String query;

  bool sameAnchor(_Trigger? other) =>
      other != null && other.kind == kind && other.start == start;
}

/// Cursor-style chat input built on flutter_quill.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.session,
    required this.contextPanelOpen,
    required this.onToggleContextPanel,
  });

  final ChatSession session;
  final bool contextPanelOpen;
  final VoidCallback onToggleContextPanel;

  @override
  State<ChatComposer> createState() => ChatComposerState();
}

class ChatComposerState extends State<ChatComposer> {
  static const _fontSize = 13.5;
  static const _textStyle = TextStyle(
    color: CursorColors.textPrimary,
    fontSize: _fontSize,
    height: 1.5,
    // Center glyphs in the line box so the custom caret lines up with them.
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const _lineHeight = _fontSize * 1.5;

  /// Resting height of the text area: roomier than one line, and it keeps
  /// the composer at the height it had with the old context row.
  static const _minEditorHeight = _lineHeight + 28;
  static const _maxEditorLines = 10;
  static const _plainTextEmbed = '￼';

  final QuillController _controller = QuillController.basic();
  final FocusNode _focusNode = FocusNode(debugLabel: 'Composer');
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<EditorState> _editorKey = GlobalKey();
  final GlobalKey _boxKey = GlobalKey();
  final LayerLink _menuLink = LayerLink();
  final OverlayPortalController _menuPortal = OverlayPortalController();

  ComposerOption _mode = ComposerMockData.modes.first;
  ComposerOption _model = ComposerMockData.models.first;

  bool _hasContent = false;
  _Trigger? _trigger;
  _Trigger? _dismissedTrigger;
  List<SuggestionMatch> _matches = const [];
  int _highlighted = 0;
  double _menuX = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleEditorChanged);
    _focusNode.addListener(_handleFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void focus() => _focusNode.requestFocus();

  // --- Editor state --------------------------------------------------------

  bool get _isComposing {
    final state = _editorKey.currentState;
    return state is QuillRawEditorState && state.composingRange.value.isValid;
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) _closeMenu();
    setState(() {});
  }

  void _handleEditorChanged() {
    if (_padTrailingTokens()) return; // Re-entered with the fixed document.
    final plain = _controller.document.toPlainText();
    final hasContent = plain.trim().isNotEmpty;
    final trigger = _findTrigger(plain);

    if (trigger == null || !trigger.sameAnchor(_dismissedTrigger)) {
      _dismissedTrigger = null;
    }
    final visible = trigger != null && _dismissedTrigger == null;

    if (visible) {
      final source = trigger.kind == SuggestionKind.command
          ? ComposerMockData.commands
          : ComposerMockData.mentions;
      final queryChanged =
          !trigger.sameAnchor(_trigger) || trigger.query != _trigger!.query;
      _matches = rankSuggestions(source, trigger.query);
      if (queryChanged) _highlighted = 0;
      _highlighted = _highlighted.clamp(0, math.max(0, _matches.length - 1));
      _menuX = _caretX(trigger.start);
      _menuPortal.show();
    } else if (_menuPortal.isShowing) {
      _menuPortal.hide();
    }
    _trigger = visible ? trigger : null;
    _hasContent = hasContent;
    setState(() {});
  }

  /// Flutter lays out a line whose only content is an inline widget taller
  /// than a line with text, so a token must never end a line: when it does
  /// (e.g. the space after it was deleted), add a space after it and leave
  /// the caret where it was. Sending trims it. Returns true if it edited.
  bool _padTrailingTokens() {
    final plain = _controller.document.toPlainText();
    for (var i = plain.length - 1; i >= 0; i--) {
      final endsLine = i + 1 >= plain.length || plain[i + 1] == '\n';
      if (plain[i] != _plainTextEmbed || !endsLine) continue;
      final selection = _controller.selection;
      _controller.replaceText(i + 1, 0, ' ', selection);
      return true;
    }
    return false;
  }

  _Trigger? _findTrigger(String plain) {
    final selection = _controller.selection;
    if (!selection.isCollapsed || selection.baseOffset < 1) return null;
    final caret = math.min(selection.baseOffset, plain.length);

    bool isBoundary(String char) =>
        char.trim().isEmpty || char == _plainTextEmbed;

    for (var i = caret - 1; i >= 0; i--) {
      final char = plain[i];
      if (isBoundary(char)) return null;
      if (char == '@' && (i == 0 || isBoundary(plain[i - 1]))) {
        return _Trigger(SuggestionKind.file, i, plain.substring(i + 1, caret));
      }
      if (char == '/' && i == 0) {
        return _Trigger(SuggestionKind.command, 0, plain.substring(1, caret));
      }
    }
    return null;
  }

  /// Horizontal caret position of [offset] relative to the composer box.
  double _caretX(int offset) {
    final editor = _editorKey.currentState?.renderEditor;
    final box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (editor == null || box == null || !editor.attached) return 12;
    final caret = editor.getLocalRectForCaret(TextPosition(offset: offset));
    final global = editor.localToGlobal(caret.topLeft);
    final x = box.globalToLocal(global).dx - 8;
    return x.clamp(0, math.max(0, box.size.width - SuggestionMenu.width));
  }

  // --- Suggestions ---------------------------------------------------------

  void _closeMenu() {
    if (_trigger != null) _dismissedTrigger = _trigger;
    _trigger = null;
    if (_menuPortal.isShowing) _menuPortal.hide();
  }

  void _moveHighlight(int delta) {
    if (_matches.isEmpty) return;
    setState(() {
      _highlighted = (_highlighted + delta) % _matches.length;
    });
  }

  void _accept(int index) {
    final trigger = _trigger;
    if (trigger == null || index >= _matches.length) return;
    final suggestion = _matches[index].suggestion;
    final caret = _controller.selection.baseOffset;
    // Space first, then the token before it, so the token is never the last
    // thing on its line (see [_padTrailingTokens]).
    _controller.replaceText(
      trigger.start,
      caret - trigger.start,
      ' ',
      TextSelection.collapsed(offset: trigger.start + 1),
    );
    _controller.replaceText(
      trigger.start,
      0,
      ComposerTokenEmbed.fromSuggestion(suggestion),
      TextSelection.collapsed(offset: trigger.start + 2),
    );
    _focusNode.requestFocus();
  }

  // --- Keyboard ------------------------------------------------------------

  static final _allowedShortcutKeys = {
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyC,
    LogicalKeyboardKey.keyV,
    LogicalKeyboardKey.keyX,
    LogicalKeyboardKey.keyZ,
    LogicalKeyboardKey.keyY,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.backspace,
    LogicalKeyboardKey.delete,
    LogicalKeyboardKey.enter,
  };

  KeyEventResult? _handleKey(KeyEvent event, Node? node) {
    if (event is KeyUpEvent || _isComposing) return null;
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;

    if (_trigger != null) {
      if (key == LogicalKeyboardKey.arrowDown) {
        _moveHighlight(1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        _moveHighlight(-1);
        return KeyEventResult.handled;
      }
      if ((key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.tab) &&
          _matches.isNotEmpty) {
        _accept(_highlighted);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        setState(_closeMenu);
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.enter && !keyboard.isShiftPressed) {
      _submit();
      return KeyEventResult.handled;
    }

    // This is a plain-text input: swallow Quill's rich-text shortcuts
    // (bold, headers, lists, links…) without triggering anything else.
    if ((keyboard.isMetaPressed || keyboard.isControlPressed) &&
        !_allowedShortcutKeys.contains(key) &&
        key != LogicalKeyboardKey.metaLeft &&
        key != LogicalKeyboardKey.metaRight &&
        key != LogicalKeyboardKey.controlLeft &&
        key != LogicalKeyboardKey.controlRight) {
      return KeyEventResult.skipRemainingHandlers;
    }
    return null;
  }

  // --- Submit --------------------------------------------------------------

  ComposerMessage _buildMessage() {
    final text = StringBuffer();
    final mentions = <String>[];
    for (final op in _controller.document.toDelta().toList()) {
      final data = op.data;
      if (data is String) {
        text.write(data);
      } else if (data is Map && data.containsKey(ComposerTokenEmbed.type)) {
        final raw = data[ComposerTokenEmbed.type];
        text.write(ComposerTokenEmbed.plainText(raw));
        final token = ComposerTokenEmbed.decode(raw);
        if (token.kind != SuggestionKind.command &&
            !mentions.contains(token.value)) {
          mentions.add(token.value);
        }
      }
    }
    return ComposerMessage(text: text.toString().trim(), mentions: mentions);
  }

  void _submit() {
    if (widget.session.isStreaming) return;
    final message = _buildMessage();
    if (message.text.isEmpty) return;
    widget.session.send(message);
    _controller.clear();
    _dismissedTrigger = null;
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    return CompositedTransformTarget(
      link: _menuLink,
      child: OverlayPortal(
        controller: _menuPortal,
        overlayChildBuilder: _buildMenu,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _focusNode.requestFocus,
          child: AnimatedContainer(
            key: _boxKey,
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: CursorColors.surfaceRaised,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: focused
                    ? const Color(0xFF4D4D4D)
                    : CursorColors.borderStrong,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_buildEditor(context), _buildToolbar()],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    final trigger = _trigger;
    if (trigger == null) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: _menuLink,
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.bottomLeft,
        offset: Offset(_menuX, -6),
        child: TapRegion(
          groupId: _focusNode,
          child: SuggestionMenu(
            title: trigger.kind == SuggestionKind.command
                ? 'Commands'
                : 'Files, folders & context',
            matches: _matches,
            highlighted: _highlighted,
            onHighlight: (index) => setState(() => _highlighted = index),
            onSelect: _accept,
          ),
        ),
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    // Slim overlay scrollbar for when the text exceeds the max height.
    return ScrollbarTheme(
      data: ScrollbarTheme.of(context).copyWith(
        thickness: const WidgetStatePropertyAll(4),
        crossAxisMargin: 3,
      ),
      child: Scrollbar(
        controller: _scrollController,
        // Desktop scroll behavior would add a second, default scrollbar to
        // Quill's internal scroll view.
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: _buildEditorBody(context),
        ),
      ),
    );
  }

  Widget _buildEditorBody(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: ClipRect(
        child: ComposerCaret(
          editorKey: _editorKey,
          controller: _controller,
          focusNode: _focusNode,
          scrollController: _scrollController,
          height: (_fontSize * 1.2).roundToDouble(),
          color: CursorColors.textPrimary,
          child: _buildQuill(context),
        ),
      ),
    );
  }

  /// Grows with content up to 10 lines, or a third of the window on short
  /// windows, then scrolls internally.
  double _maxEditorHeight(BuildContext context) {
    final byWindow = MediaQuery.sizeOf(context).height / 3;
    return math.max(
      _minEditorHeight,
      math.min(_lineHeight * _maxEditorLines, byWindow),
    );
  }

  Widget _buildQuill(BuildContext context) {
    return QuillEditor(
      controller: _controller,
      focusNode: _focusNode,
      scrollController: _scrollController,
      config: QuillEditorConfig(
        editorKey: _editorKey,
        placeholder: 'Plan, search, build anything  ·  @ 提及  / 命令',
        minHeight: _minEditorHeight,
        maxHeight: _maxEditorHeight(context),
        textCapitalization: TextCapitalization.none,
        enableSelectionToolbar: false,
        embedBuilders: const [ComposerTokenEmbedBuilder()],
        // ignore: experimental_member_use
        onKeyPressed: _handleKey,
        onTapOutside: (event, focusNode) {},
        showCursor: false,
        customStyles: _editorStyles(context),
      ),
    );
  }

  /// Quill's paragraph style does not inherit the ambient text theme, so
  /// derive it explicitly to match the rest of the UI.
  DefaultStyles _editorStyles(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    DefaultTextBlockStyle block(TextStyle style) => DefaultTextBlockStyle(
      base.merge(style),
      HorizontalSpacing.zero,
      VerticalSpacing.zero,
      VerticalSpacing.zero,
      null,
    );
    return DefaultStyles(
      paragraph: block(_textStyle),
      placeHolder: block(_textStyle.copyWith(color: CursorColors.textFaint)),
    );
  }

  Widget _buildToolbar() {
    final session = widget.session;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      child: Row(
        children: [
          ComposerPicker(
            options: ComposerMockData.modes,
            selected: _mode,
            emphasized: true,
            onSelected: (option) => setState(() => _mode = option),
          ),
          const SizedBox(width: 2),
          ComposerPicker(
            options: ComposerMockData.models,
            selected: _model,
            onSelected: (option) => setState(() => _model = option),
          ),
          const Spacer(),
          _ContextRing(
            fraction: session.contextUsed / ChatSession.contextWindow,
            active: widget.contextPanelOpen,
            onTap: widget.onToggleContextPanel,
          ),
          const SizedBox(width: 2),
          const _IconChip(icon: Icons.image_outlined, tooltip: 'Attach image'),
          const SizedBox(width: 4),
          _SendButton(
            streaming: session.isStreaming,
            enabled: _hasContent,
            onSend: _submit,
            onStop: session.stop,
          ),
        ],
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, required this.tooltip});

  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: () {},
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: hovered ? CursorColors.hover : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(
              icon,
              size: 14,
              color: hovered ? CursorColors.text : CursorColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _ContextRing extends StatelessWidget {
  const _ContextRing({
    required this.fraction,
    required this.active,
    required this.onTap,
  });

  final double fraction;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final percent = (fraction * 100).round();
    return Tooltip(
      message: '$percent% of context used',
      waitDuration: const Duration(milliseconds: 400),
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: active || hovered
                  ? CursorColors.hover
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 13,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: fraction),
                    duration: const Duration(milliseconds: 400),
                    builder: (context, value, _) =>
                        CustomPaint(painter: _RingPainter(value)),
                  ),
                ),
                if (hovered || active) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$percent%',
                    style: const TextStyle(
                      color: CursorColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.fraction);

  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect.deflate(1),
      0,
      math.pi * 2,
      false,
      stroke..color = CursorColors.borderStrong,
    );
    final color = fraction > 0.8
        ? CursorColors.removed
        : fraction > 0.6
        ? CursorColors.inlineCode
        : CursorColors.textMuted;
    canvas.drawArc(
      rect.deflate(1),
      -math.pi / 2,
      math.pi * 2 * fraction.clamp(0, 1),
      false,
      stroke..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction;
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.streaming,
    required this.enabled,
    required this.onSend,
    required this.onStop,
  });

  final bool streaming;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final active = streaming || enabled;
    return Tooltip(
      message: streaming ? 'Stop' : 'Send  ↵',
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: active ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: streaming ? onStop : (enabled ? onSend : null),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: active
                  ? CursorColors.textPrimary
                  : const Color(0xFF3A3A3A),
              shape: BoxShape.circle,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: streaming
                  ? Container(
                      key: const ValueKey('stop'),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: CursorColors.background,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    )
                  : Icon(
                      key: const ValueKey('send'),
                      Icons.arrow_upward_rounded,
                      size: 15,
                      color: active
                          ? CursorColors.background
                          : CursorColors.textFaint,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
