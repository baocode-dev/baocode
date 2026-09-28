import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../../kernel/kernel_types.dart';
import '../../theme/cursor_theme.dart';
import '../chat_models.dart';
import '../chat_session.dart';
import '../floating/floating_layer.dart';
import '../floating/floating_placement.dart';
import '../floating/floating_registry.dart';
import '../../workspace/window_controls.dart';
import '../widgets/hover_builder.dart';
import '../widgets/image_thumbnails.dart';
import 'composer_caret.dart';
import 'composer_draft.dart';
import 'composer_embeds.dart';
import 'composer_images.dart';
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
///
/// The dock's composer sends to [session]. With [onSubmit] it edits instead
/// (e.g. a sent message reopened in the history): it starts from
/// [initialText], shows no stop button or context ring, and Esc calls
/// [onCancel].
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.session,
    this.contextPanelOpen = false,
    this.onToggleContextPanel,
    this.initialText,
    this.initialImages = const [],
    this.onSubmit,
    this.onCancel,
    this.tapRegionGroupId,
    this.draft,
  });

  final ChatSession session;
  final bool contextPanelOpen;
  final VoidCallback? onToggleContextPanel;

  /// Text to start from; `@mentions` and a leading `/command` in it become
  /// tokens again.
  final String? initialText;

  /// Images to start from (the message being edited had them).
  final List<ImageAttachment> initialImages;
  final ValueChanged<ComposerMessage>? onSubmit;
  final VoidCallback? onCancel;

  /// Group of a [TapRegion] around this composer: its menus, which open in
  /// the overlay, count as inside it.
  final Object? tapRegionGroupId;

  /// Where what is typed is kept while the composer is gone; once saved,
  /// it starts from there rather than [initialText] and [initialImages].
  final ComposerDraft? draft;

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

  late final QuillController _controller = _createController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'Composer');
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<EditorState> _editorKey = GlobalKey();
  final GlobalKey _boxKey = GlobalKey();

  bool _hasContent = false;
  late final List<ImageAttachment> _images = [
    ...(widget.draft?.saved ?? false)
        ? widget.draft!.images
        : widget.initialImages,
  ];
  _Trigger? _trigger;
  _Trigger? _dismissedTrigger;
  List<SuggestionMatch> _matches = const [];
  int _highlighted = 0;
  double _menuX = 0;

  QuillController _createController() {
    final config = QuillControllerConfig(
      // Quill's only hook for taking over paste; experimental in 11.x.
      // ignore: experimental_member_use
      clipboardConfig: QuillClipboardConfig(onClipboardPaste: _paste),
    );
    if (widget.draft case final draft? when draft.saved) {
      final document = Document.fromDelta(draft.content!);
      final end = document.length - 1;
      return QuillController(
        document: document,
        selection: TextSelection(
          baseOffset: draft.selection.baseOffset.clamp(0, end),
          extentOffset: draft.selection.extentOffset.clamp(0, end),
        ),
        config: config,
      );
    }
    final text = widget.initialText;
    if (text == null || text.isEmpty) {
      return QuillController.basic(config: config);
    }
    final document = Document.fromDelta(
      composerDeltaFromText(text, ComposerVocabulary.read(context)),
    );
    return QuillController(
      document: document,
      selection: TextSelection.collapsed(offset: document.length - 1),
      config: config,
    );
  }

  /// Pastes the clipboard's plain text with its @mentions (and a leading
  /// /command) as tokens, as the message will show once sent: copied from
  /// the history, from this editor or from elsewhere alike. Also keeps
  /// Quill from pasting HTML or Markdown as rich text into this plain-text
  /// input. Returns false (Quill's own handling, e.g. images) for no text.
  Future<bool> _paste() async {
    if (widget.session.acceptsImages) {
      final images = await WindowControls.readPasteboardImages();
      if (images.isNotEmpty) {
        await _addImages(images);
        return true;
      }
    }
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || !mounted) return false;
    final selection = _controller.selection;
    final start = selection.start;
    final content = composerDeltaFromPaste(
      text.replaceAll('\r\n', '\n'),
      ComposerVocabulary.read(context),
      atStart: start == 0,
    );
    final delta =
        (Delta()
              ..retain(start)
              ..delete(selection.end - start))
            .concat(content);
    // `compose` keeps the caret where it was (before the insert), whatever
    // selection it is given: move it after the pasted text.
    _controller
      ..compose(delta, selection, ChangeSource.local)
      ..updateSelection(
        TextSelection.collapsed(
          // Delta.length counts operations, not characters.
          offset:
              start + content.toList().fold(0, (sum, op) => sum + op.length!),
        ),
        ChangeSource.local,
      );
    return true;
  }

  @override
  void initState() {
    super.initState();
    _padTrailingTokens();
    _hasContent = _controller.document.toPlainText().trim().isNotEmpty;
    _controller.addListener(_handleEditorChanged);
    _focusNode.addListener(_handleFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    FloatingRegistry.closePopover(_menuOwner);
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void focus() => _focusNode.requestFocus();

  // --- Images --------------------------------------------------------------

  /// At most this many per message.
  static const _maxImages = 20;

  Future<void> _addImages(List<ImageAttachment> images) async {
    final prepared = [
      for (final image in await Future.wait(images.map(prepareImage))) ?image,
    ];
    if (!mounted || prepared.isEmpty) return;
    setState(() {
      _images.addAll(prepared.take(_maxImages - _images.length));
    });
    _saveDraft();
    _focusNode.requestFocus();
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
    _saveDraft();
    _focusNode.requestFocus();
  }

  bool get _canSend => _hasContent || _images.isNotEmpty;

  // --- Suggested prompt ----------------------------------------------------

  /// What the agent suggests sending next, shown as the placeholder of an
  /// empty dock composer; Tab takes it.
  String? _suggestion;

  void _acceptSuggestion() {
    final suggestion = _suggestion;
    if (suggestion == null) return;
    _controller.replaceText(
      0,
      0,
      suggestion,
      TextSelection.collapsed(offset: suggestion.length),
    );
  }

  /// The text area's own scroll position (it scrolls past its maximum
  /// height), or null before it is laid out.
  ScrollPosition? get editorScrollPosition =>
      _scrollController.hasClients ? _scrollController.position : null;

  /// The editor subtree, built once and reused so that keystrokes (which
  /// rebuild this state for the menu and send button) do not hand Quill a
  /// new config: it treats new styles as a change and relays out every line.
  /// Rebuilt only when an inherited dependency (theme, window size) changes.
  Widget? _editor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _editor = null;
  }

  // --- Editor state --------------------------------------------------------

  bool get _isComposing {
    final state = _editorKey.currentState;
    return state is QuillRawEditorState && state.composingRange.value.isValid;
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) _closeMenu();
    setState(() {});
  }

  /// Keeps what is typed, and where the caret is, in the draft.
  void _saveDraft() => widget.draft?.save(
    _controller.document.toDelta(),
    _controller.selection,
    _images,
  );

  void _handleEditorChanged() {
    if (_padTrailingTokens()) return; // Re-entered with the fixed document.
    _saveDraft();
    final plain = _controller.document.toPlainText();
    final hasContent = plain.trim().isNotEmpty;
    final trigger = _findTrigger(plain);

    if (trigger == null || !trigger.sameAnchor(_dismissedTrigger)) {
      _dismissedTrigger = null;
    }
    final visible = trigger != null && _dismissedTrigger == null;

    if (visible) {
      final vocabulary = ComposerVocabulary.read(context);
      final source = trigger.kind == SuggestionKind.command
          ? vocabulary.commands
          : vocabulary.mentions;
      final queryChanged =
          !trigger.sameAnchor(_trigger) || trigger.query != _trigger!.query;
      if (queryChanged) {
        _matches = rankSuggestions(source, trigger.query);
        if (trigger.kind != SuggestionKind.command) {
          if (vocabulary.suggestFiles case final suggest?) {
            _lookUpFiles(trigger, suggest, source);
          }
        }
      }
      if (queryChanged) _highlighted = 0;
      _highlighted = _highlighted.clamp(0, math.max(0, _matches.length - 1));
      _menuX = _caretX(trigger.start);
    }
    _trigger = visible ? trigger : null;
    _syncMenuRegistration();
    _hasContent = hasContent;
    setState(() {});
  }

  int _lookups = 0;

  /// Asks the kernel for files matching [trigger], and shows them ahead of
  /// the fixed mentions. Answers to older queries are dropped.
  Future<void> _lookUpFiles(
    _Trigger trigger,
    Future<List<FileSuggestion>> Function(String query) suggest,
    List<Suggestion> fixed,
  ) async {
    final lookup = ++_lookups;
    final files = await suggest(trigger.query);
    final current = _trigger;
    if (!mounted ||
        lookup != _lookups ||
        current == null ||
        !current.sameAnchor(trigger) ||
        current.query != trigger.query) {
      return;
    }
    setState(() {
      _matches = [
        for (final suggestion in files.map(fileSuggestion))
          SuggestionMatch(
            suggestion,
            fuzzyMatch(suggestion.label, trigger.query)?.indexes ?? const [],
          ),
        ...rankSuggestions(fixed, trigger.query),
      ];
      _highlighted = _highlighted.clamp(0, math.max(0, _matches.length - 1));
    });
    _syncMenuRegistration();
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
    // Only at the end of a query: a caret moved into existing text (e.g.
    // `@pubspec.|yaml`) is not typing one.
    if (caret < plain.length && !isBoundary(plain[caret])) return null;

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
    _syncMenuRegistration();
  }

  /// Identifies the suggestion menu to [FloatingRegistry].
  final Object _menuOwner = Object();
  bool _menuRegistered = false;

  void _syncMenuRegistration() {
    final open = _trigger != null;
    if (open == _menuRegistered) return;
    _menuRegistered = open;
    if (open) {
      FloatingRegistry.openPopover(_menuOwner, () {
        if (mounted) setState(_closeMenu);
      });
    } else {
      FloatingRegistry.closePopover(_menuOwner);
    }
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
    // An open picker menu (or tooltip) takes arrows, Enter and Esc first.
    if (FloatingRegistry.handleKey(event) case final result?) return result;
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

    if (key == LogicalKeyboardKey.tab &&
        _suggestion != null &&
        !_hasContent &&
        !keyboard.isShiftPressed) {
      _acceptSuggestion();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape && widget.onCancel != null) {
      widget.onCancel!();
      return KeyEventResult.handled;
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
    return ComposerMessage(
      text: text.toString().trim(),
      mentions: mentions,
      images: [..._images],
    );
  }

  /// The dock's composer shows a stop button while a turn runs; an editing
  /// composer can always submit (resending stops the running turn).
  bool get _showsStop =>
      widget.onSubmit == null &&
      widget.session.isStreaming &&
      !(widget.session.canQueue && _canSend);

  void _submit() {
    if (_showsStop) return;
    final message = _buildMessage();
    if (message.text.isEmpty && message.images.isEmpty) return;
    if (widget.onSubmit case final onSubmit?) {
      onSubmit(message);
      return;
    }
    widget.session.send(message);
    _controller.clear();
    setState(_images.clear);
    _saveDraft();
    _dismissedTrigger = null;
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    final suggestion = widget.onSubmit == null
        ? widget.session.promptSuggestion
        : null;
    if (suggestion != _suggestion) {
      _suggestion = suggestion;
      _editor = null; // The placeholder shows it.
    }
    return FloatingLayer(
      visible: _trigger != null,
      // Above the composer at the trigger character; below it when there
      // is no room above.
      placement: (side: FloatingSide.top, align: FloatingAlign.start),
      anchorRect: (box) =>
          Rect.fromLTWH(box.left + _menuX, box.top, 1, box.height),
      // Clicks in the menu are not outside the editor.
      tapRegionGroupId: _focusNode,
      outerTapRegionGroupId: widget.tapRegionGroupId,
      builder: _buildMenu,
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
            children: [
              if (_images.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: ImageThumbnails(
                    images: _images,
                    size: 48,
                    onRemove: _removeImage,
                  ),
                ),
              _editor ??= _buildEditor(context),
              _buildToolbar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    final trigger = _trigger!;
    return SuggestionMenu(
      title: trigger.kind == SuggestionKind.command
          ? 'Commands'
          : 'Files, folders & context',
      matches: _matches,
      highlighted: _highlighted,
      onHighlight: (index) => setState(() => _highlighted = index),
      onSelect: _accept,
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
          child: Listener(
            onPointerDown: _handleSelectPointerDown,
            onPointerMove: _handleSelectPointerMove,
            onPointerUp: (_) => _selectDragFrom = null,
            onPointerCancel: (_) => _selectDragFrom = null,
            child: Listener(
              onPointerDown: _handleMenuPointerDown,
              onPointerUp: _handleMenuPointerUp,
              onPointerCancel: (_) => _menuPressAt = null,
              child: _buildQuill(context),
            ),
          ),
        ),
      ),
    );
  }

  // --- Context menu -------------------------------------------------------
  //
  // A right click opens the system's menu (Quill's own is a Flutter one,
  // turned off). Quill has placed the caret by the time it opens: at the
  // click, unless the click is on a selection.

  /// Where a right click went down; null for other presses.
  Offset? _menuPressAt;

  void _handleMenuPointerDown(PointerDownEvent event) {
    _menuPressAt =
        event.kind == PointerDeviceKind.mouse &&
            event.buttons == kSecondaryMouseButton
        ? event.position
        : null;
  }

  void _handleMenuPointerUp(PointerUpEvent event) {
    final down = _menuPressAt;
    _menuPressAt = null;
    if (down == null || (event.position - down).distance > kTouchSlop) return;
    // After Quill's handling of the click, which comes after this.
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => _showContextMenu(event.position))
      ..scheduleFrame();
  }

  Future<void> _showContextMenu(Offset position) async {
    if (!mounted || !WindowControls.hasNativeMenus) return;
    final selected = !_controller.selection.isCollapsed;
    final canPaste = await WindowControls.canPaste();
    if (!mounted) return;
    final chosen = await WindowControls.showContextMenu(position, [
      NativeMenuItem('cut', 'Cut', key: 'x', enabled: selected),
      NativeMenuItem('copy', 'Copy', key: 'c', enabled: selected),
      NativeMenuItem('paste', 'Paste', key: 'v', enabled: canPaste),
      const NativeMenuItem.separator(),
      NativeMenuItem(
        'selectAll',
        'Select All',
        key: 'a',
        enabled: _controller.document.length > 1,
      ),
    ]);
    final editor = _editorKey.currentState;
    if (!mounted || editor == null) return;
    _focusNode.requestFocus();
    // As their shortcuts do: the selection stays where it is.
    switch (chosen) {
      case 'cut':
        editor.cutSelection(SelectionChangedCause.keyboard);
      case 'copy':
        editor.copySelection(SelectionChangedCause.keyboard);
      case 'paste':
        await editor.pasteText(SelectionChangedCause.keyboard);
      case 'selectAll':
        editor.selectAll(SelectionChangedCause.keyboard);
    }
  }

  // --- Drag selection -----------------------------------------------------
  //
  // Quill throttles a mouse drag selection to one update per 50ms (Flutter's
  // own text fields no longer do), so the selection trails the pointer.
  // Extend it on every move instead; Quill's late update then lands on the
  // same position.

  /// Where a primary mouse press that may become a drag selection went down.
  Offset? _selectDragFrom;
  bool _selectDragging = false;

  void _handleSelectPointerDown(PointerDownEvent event) {
    final plainPress =
        event.kind == PointerDeviceKind.mouse &&
        event.buttons == kPrimaryMouseButton &&
        !HardwareKeyboard.instance.isShiftPressed;
    _selectDragFrom = plainPress ? event.position : null;
    _selectDragging = false;
  }

  void _handleSelectPointerMove(PointerMoveEvent event) {
    final from = _selectDragFrom;
    if (from == null || event.buttons != kPrimaryMouseButton) return;
    // Past the same slop at which Quill's drag recognizer starts.
    if (!_selectDragging &&
        (event.position - from).distance <= kPrecisePointerPanSlop) {
      return;
    }
    _selectDragging = true;
    final to = event.position;
    // Pointer listeners see a move before gesture recognizers do: on the
    // move that starts the drag, Quill sets the selection's origin after
    // this handler returns.
    scheduleMicrotask(() {
      final editor = _editorKey.currentState?.renderEditor;
      if (_selectDragFrom == null || editor == null || !editor.attached) {
        return;
      }
      editor.extendSelection(to, cause: SelectionChangedCause.drag);
    });
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
        placeholder: switch (_suggestion) {
          final suggestion? => '$suggestion    ⇥ Tab',
          null => 'Plan, search, build anything  ·  @ 提及  / 命令',
        },
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
    // Only the dock's composer picks the kernel, and only until it starts.
    final kernel = widget.onSubmit == null ? session.kernelChoice : null;
    final mode = session.modes;
    final permission = session.permissions;
    final model = session.models;
    final effort = session.efforts;
    final context = session.context;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      child: Row(
        children: [
          // Takes the room left, so the actions sit at the far end; scrolls
          // when the pickers do not fit.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (kernel != null) ...[
                    ComposerPicker(
                      options: kernel.options,
                      selected: kernel.selected,
                      tapRegionGroupId: widget.tapRegionGroupId,
                      focusNode: _focusNode,
                      onSelected: kernel.onSelected,
                    ),
                    const SizedBox(width: 2),
                  ],
                  if (mode != null) ...[
                    ComposerPicker(
                      options: mode.options,
                      selected: mode.selected,
                      emphasized: true,
                      tapRegionGroupId: widget.tapRegionGroupId,
                      focusNode: _focusNode,
                      onSelected: mode.onSelected,
                    ),
                    const SizedBox(width: 2),
                  ],
                  if (permission != null) ...[
                    ComposerPicker(
                      options: permission.options,
                      selected: permission.selected,
                      title: 'How should ${session.kernel.label} get approval?',
                      menuWidth: 290,
                      tapRegionGroupId: widget.tapRegionGroupId,
                      focusNode: _focusNode,
                      onSelected: permission.onSelected,
                    ),
                    const SizedBox(width: 2),
                  ],
                  if (model != null)
                    ComposerPicker(
                      options: model.options,
                      selected: model.selected,
                      tapRegionGroupId: widget.tapRegionGroupId,
                      focusNode: _focusNode,
                      onSelected: model.onSelected,
                    ),
                  if (effort != null) ...[
                    const SizedBox(width: 2),
                    ComposerPicker(
                      options: effort.options,
                      selected: effort.selected,
                      tapRegionGroupId: widget.tapRegionGroupId,
                      focusNode: _focusNode,
                      onSelected: effort.onSelected,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if ((widget.onToggleContextPanel, context) case (
            final onToggle?,
            final usage?,
          )) ...[
            _ContextRing(
              fraction: usage.fraction,
              active: widget.contextPanelOpen,
              onTap: onToggle,
            ),
            const SizedBox(width: 2),
          ],
          const SizedBox(width: 2),
          _SendButton(
            streaming: _showsStop,
            enabled: _canSend,
            onSend: _submit,
            onStop: session.stop,
          ),
        ],
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
    return Tooltip(
      message: 'Context usage',
      waitDuration: const Duration(milliseconds: 400),
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 23,
            height: 22,
            // The ring keeps its square: the box is taller than it.
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active || hovered
                  ? CursorColors.hover
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: SizedBox.square(
              dimension: 13,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: fraction),
                duration: const Duration(milliseconds: 400),
                builder: (context, value, _) =>
                    CustomPaint(painter: _RingPainter(value)),
              ),
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
    canvas.drawArc(
      rect.deflate(1),
      -math.pi / 2,
      math.pi * 2 * fraction.clamp(0, 1),
      false,
      stroke..color = CursorColors.textMuted,
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
