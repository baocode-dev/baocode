import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../../ide/ide_dialog.dart';
import '../../kernel/agent_kernel.dart';
import '../../kernel/kernel_types.dart';
import '../../keybindings/chat_keybindings.dart';
import '../../l10n/l10n.dart';
import '../../models/model_provider.dart' show builtinProviderId;
import '../../settings/settings_dialog.dart'
    show SettingsOpener, SettingsSection;
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show WorkbenchColors, themeColors;
import '../chat_keys.dart';
import '../chat_models.dart';
import '../chat_session.dart';
import '../floating/floating_layer.dart';
import '../floating/floating_placement.dart';
import '../floating/floating_registry.dart';
import '../../workspace/window_controls.dart';
import '../widgets/hover_builder.dart';
import '../widgets/image_thumbnails.dart';
import 'composer_caret.dart';
import 'composer_controller.dart';
import 'composer_draft.dart';
import 'composer_embeds.dart';
import 'composer_files.dart';
import 'composer_images.dart';
import 'composer_mock_data.dart';
import 'composer_picker.dart';
import 'kernel_option_text.dart';
import 'file_drop.dart';
import 'suggestion_menu.dart';
import '../../ide/ide_hover.dart';

/// An open query: a /command's, the slash starting the message, or a
/// mention's (an @ starting a word: a file, a folder or a conversation);
/// [query] is the text between it and the caret.
class _Trigger {
  const _Trigger(this.kind, this.start, this.query);

  /// [SuggestionKind.command], or [SuggestionKind.file] for a mention.
  final SuggestionKind kind;

  /// Where the slash or the @ is.
  final int start;
  final String query;

  bool sameAnchor(_Trigger? other) =>
      other != null && other.kind == kind && other.start == start;
}

/// The chat input, built on flutter_quill.
///
/// The dock's composer sends to [session]. With [onSubmit] it edits instead
/// (e.g. a sent message reopened in the history): it starts from
/// [initialText], shows no stop button or context ring, and Esc calls
/// [onCancel].
///
/// Its keys are keybindings (see [ChatCommandIds]): Enter sends, ↑ at its
/// start shows the messages sent before, the / menu's keys…
///
/// Files come in as tags of their paths (images as images, where the
/// conversation takes them): dragged onto it from other apps or from the
/// IDE, pasted after a copy, or picked (Add Context…). Code copied from the
/// IDE's editor pastes as a tag of its lines (see [CopiedCode]), and text
/// too long to lay out as a tag of it (see [PastedText]).
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

  /// Text to start from; `@paths`, `[path:lines]` and a leading `/command`
  /// in it become tags again.
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

class ChatComposerState extends State<ChatComposer>
    with ChatKeyTarget
    implements FileDropDelegate {
  static const _fontSize = 13.5;
  static TextStyle get _textStyle => TextStyle(
    color: AppColors.textPrimary,
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

  late final ComposerController _controller = _createController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'Composer');
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<EditorState> _editorKey = GlobalKey();
  final GlobalKey _boxKey = GlobalKey();
  final GlobalKey<ComposerPickerState> _modePickerKey = GlobalKey();
  final GlobalKey<ComposerPickerState> _modelPickerKey = GlobalKey();

  bool _hasContent = false;

  /// Every image put in, by number, kept until sent: the text's references
  /// pick which go (see [_images]), so one taken out and brought back by
  /// undo is still there. Replaced, not changed, for the references
  /// showing them to see it.
  late Map<int, ImageAttachment> _pool = _initialPool();

  /// The images that go: those the text refers to, in its order, once
  /// each. Derived from the text alone, as it changes.
  List<ImageAttachment> _images = const [];
  _Trigger? _trigger;
  _Trigger? _dismissedTrigger;
  List<SuggestionMatch> _matches = const [];

  /// The conversations the open @ offers, as they were when it was typed.
  List<Suggestion> _sessions = const [];

  /// Whether the menu lists a mention's files and conversations or the
  /// commands: kept as it closes, for it to fade out as it was.
  SuggestionKind _menuKind = SuggestionKind.command;
  int _highlighted = 0;
  double _menuX = 0;

  Map<int, ImageAttachment> _initialPool() {
    if (widget.draft case final draft? when draft.saved) {
      return {for (final image in draft.images) ?image.number: image};
    }
    final pool = <int, ImageAttachment>{};
    var next = widget.session.lastImageNumber + 1;
    for (final image in widget.initialImages) {
      if (image.number case final number?) {
        pool[number] = image;
        next = math.max(next, number + 1);
      }
    }
    // Sent before images were numbered: numbered now.
    for (final image in widget.initialImages) {
      if (image.number != null) continue;
      pool[next] = image.withNumber(next);
      next++;
    }
    return pool;
  }

  ComposerController _createController() {
    final config = QuillControllerConfig(
      // Quill's only hook for taking over paste; experimental in 11.x.
      // ignore: experimental_member_use
      clipboardConfig: QuillClipboardConfig(onClipboardPaste: _paste),
    );
    if (widget.draft case final draft? when draft.saved) {
      final document = Document.fromDelta(draft.content!);
      final end = document.length - 1;
      return ComposerController(
        document: document,
        selection: TextSelection(
          baseOffset: draft.selection.baseOffset.clamp(0, end),
          extentOffset: draft.selection.extentOffset.clamp(0, end),
        ),
        config: config,
      );
    }
    var text = widget.initialText ?? '';
    final numbers = _pool.keys.toSet();
    // Every image referred to: those the text does not, at its start.
    final referred = {
      for (final match in imageReferencePattern.allMatches(text))
        int.parse(match[1]!),
    };
    final unreferred = numbers.where((n) => !referred.contains(n)).toList();
    if (unreferred.isNotEmpty) {
      text = [unreferred.map(imageReference).join(' '), text].join(' ');
    }
    if (text.isEmpty) return ComposerController.basic(config: config);
    final document = Document.fromDelta(
      composerDeltaFromText(
        text,
        ComposerVocabulary.read(context),
        images: numbers,
      ),
    );
    return ComposerController(
      document: document,
      selection: TextSelection.collapsed(offset: document.length - 1),
      config: config,
    );
  }

  /// Pastes what the clipboard holds: copied files as tags of their paths
  /// (images as images), code the IDE's editor copied as a tag of its lines,
  /// a picture (a screenshot), or else its plain text, with its `@paths`
  /// (and a leading /command) as tags, as the message will show once sent:
  /// copied from the history, from this editor or from elsewhere alike.
  /// Also keeps Quill from pasting HTML or Markdown as rich text into this
  /// plain-text input. Returns false (Quill's own handling) for nothing.
  Future<bool> _paste() async {
    final files = await WindowControls.readPasteboardFiles();
    if (!mounted) return false;
    if (files.isNotEmpty) {
      await insertFiles(files);
      return true;
    }
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (!mounted) return false;
    if (text != null) {
      if (CopiedCode.matching(text) case final code?) {
        _insertTags([
          ComposerCodeEmbed.of(
            code.withPath(displayPath(code.path, widget.session.root)),
          ),
        ]);
        return true;
      }
    }
    if (widget.session.acceptsImages) {
      final images = await WindowControls.readPasteboardImages();
      if (images.isNotEmpty) {
        await _addImages(images);
        return true;
      }
    }
    if (text == null || !mounted) return false;
    final plain = text.replaceAll('\r\n', '\n');
    if (PastedText.isLong(plain)) {
      _insertTags([
        ComposerPastedTextEmbed.of(
          PastedText(number: _nextPastedNumber(), text: plain),
        ),
      ]);
      return true;
    }
    final selection = _controller.selection;
    final start = selection.start;
    final content = composerDeltaFromPaste(
      plain,
      ComposerVocabulary.read(context),
      atStart: start == 0,
      images: _pool.keys.toSet(),
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

  /// The number for a long paste: one past the highest the text has.
  int _nextPastedNumber() {
    var highest = 0;
    for (final op in _controller.document.toDelta().toList()) {
      if (op.data case {ComposerPastedTextEmbed.type: final data}) {
        highest = math.max(
          highest,
          ComposerPastedTextEmbed.decode(data).number,
        );
      }
    }
    return highest + 1;
  }

  @override
  void initState() {
    super.initState();
    _padTrailingTokens();
    _images = _referredImages();
    _hasContent = _controller.document.toPlainText().trim().isNotEmpty;
    _controller.addListener(_handleEditorChanged);
    _focusNode.addListener(_handleFocusChanged);
    widget.draft?.addListener(_handleDraftChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _takeDraftFiles();
    });
  }

  @override
  void didUpdateWidget(covariant ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.draft, widget.draft)) {
      oldWidget.draft?.removeListener(_handleDraftChanged);
      widget.draft?.addListener(_handleDraftChanged);
    }
  }

  @override
  void dispose() {
    widget.draft?.removeListener(_handleDraftChanged);
    FloatingRegistry.closePopover(_menuOwner);
    _clickWindow?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void focus() => _focusNode.requestFocus();

  // --- Images --------------------------------------------------------------

  /// At most this many per message.
  static const _maxImages = 20;

  /// The numbers of the images the text refers to, in its order, with
  /// where each reference is.
  Iterable<({int number, int offset})> _references() sync* {
    var offset = 0;
    for (final op in _controller.document.toDelta().toList()) {
      if (op.data case {ComposerImageEmbed.type: final data}) {
        yield (number: ComposerImageEmbed.decode(data), offset: offset);
      }
      offset += op.length!;
    }
  }

  List<ImageAttachment> _referredImages() => [
    for (final number in {for (final r in _references()) r.number})
      ?_pool[number],
  ];

  /// Puts [images] in at [at] (in place of the selection when null), each
  /// as a reference in the text, numbered on from the conversation's last.
  Future<void> _addImages(List<ImageAttachment> images, {int? at}) async {
    final added = (await _numbered(images)).nonNulls;
    if (!mounted || added.isEmpty) return;
    _insertTags([
      for (final image in added) ComposerImageEmbed.of(image.number!),
    ], at: at);
  }

  /// [images] made ready to send (see [prepareImage]), numbered on from the
  /// conversation's last and put in the pool, in their places: null for
  /// those that are no images, or past the most a message takes.
  Future<List<ImageAttachment?>> _numbered(
    List<ImageAttachment?> images,
  ) async {
    final prepared = await Future.wait([
      for (final image in images)
        image == null ? Future<ImageAttachment?>.value() : prepareImage(image),
    ]);
    if (!mounted) return [for (final _ in images) null];
    var next =
        math.max(widget.session.lastImageNumber, _pool.keys.fold(0, math.max)) +
        1;
    var room = _maxImages - _images.length;
    final numbered = [
      for (final image in prepared)
        image != null && room-- > 0 ? image.withNumber(next++) : null,
    ];
    _pool = {
      ..._pool,
      for (final image in numbered.nonNulls) image.number!: image,
    };
    return numbered;
  }

  /// Puts [files] in at [at] (in place of the selection when null), in
  /// their order: each a tag of its path, from the project's root when it
  /// is in it, or, for an image the conversation takes, the image.
  Future<void> insertFiles(List<ComposerFile> files, {int? at}) async {
    if (files.isEmpty) return;
    var images = <ImageAttachment?>[for (final _ in files) null];
    if (widget.session.acceptsImages) {
      images = await _numbered(
        await Future.wait([
          for (final file in files)
            file.maybeImage
                ? WindowControls.readImageFile(file.path)
                : Future<ImageAttachment?>.value(),
        ]),
      );
    }
    if (!mounted) return;
    final root = widget.session.root;
    _insertTags([
      for (final (index, file) in files.indexed)
        if (images[index] case final image?)
          ComposerImageEmbed.of(image.number!)
        else
          ComposerTokenEmbed.file(
            displayPath(file.path, root),
            directory: file.directory,
          ),
    ], at: at);
  }

  /// Puts [tags] in at [at] (in place of the selection when null), apart
  /// from a word before them, each followed by a space, so that none is
  /// the last thing on its line (see [_padTrailingTokens]); the caret after
  /// them. One edit, undone as one.
  void _insertTags(List<Embeddable> tags, {int? at}) {
    if (tags.isEmpty) return;
    final selection = _controller.selection;
    final end = _controller.document.length - 1;
    final start = (at ?? selection.start).clamp(0, end);
    final replaced = at == null ? math.max(0, selection.end - start) : 0;
    final plain = _controller.document.toPlainText();
    final content = Delta();
    if (start > 0 && plain[start - 1].trim().isNotEmpty) content.insert(' ');
    for (final tag in tags) {
      content
        ..insert(tag.toJson())
        ..insert(' ');
    }
    _controller
      ..compose(
        (Delta()
              ..retain(start)
              ..delete(replaced))
            .concat(content),
        selection,
        ChangeSource.local,
      )
      ..updateSelection(
        TextSelection.collapsed(
          offset:
              start + content.toList().fold(0, (sum, op) => sum + op.length!),
        ),
        ChangeSource.local,
      );
    _focusNode.requestFocus();
  }

  /// Takes the image at [index] out: its references in the text become
  /// words (`[Image 2]`), the text otherwise as it was. One edit, undone
  /// as one, the image coming back with its references.
  void _removeImage(int index) {
    final number = _images[index].number;
    final words = context.l10n.imageReferenceRemoved(number ?? 0);
    final delta = Delta();
    var at = 0;
    for (final reference in _references()) {
      if (reference.number != number) continue;
      delta
        ..retain(reference.offset - at)
        ..delete(1)
        ..insert(words);
      at = reference.offset + 1;
    }
    if (delta.isEmpty) return;
    _controller.compose(delta, _controller.selection, ChangeSource.local);
    _focusNode.requestFocus();
  }

  bool get _canSend => _hasContent || _images.isNotEmpty;

  // --- Suggested prompt ----------------------------------------------------

  /// What the agent suggests sending next, shown as the placeholder of an
  /// empty dock composer; Tab takes it.
  String? _suggestion;

  /// The key that takes it, as the keybindings have it now: shown after
  /// it; none when unbound.
  String? _suggestionKey;

  /// The context keys where the suggested prompt's key applies.
  static const _suggestionKeyContext = {
    ChatContextKeys.inChatInput: true,
    ChatContextKeys.hasPromptSuggestion: true,
    ChatContextKeys.inputHasText: false,
  };

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
  /// Rebuilt only when an inherited dependency (theme, window size) or the
  /// color theme changes.
  Widget? _editor;

  /// The color theme's colors [_editor] was built with.
  WorkbenchColors? _editorColors;

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

  /// The files put in the draft from outside (see
  /// [ComposerDraft.insertFiles]), as if pasted.
  void _takeDraftFiles() {
    final files = widget.draft?.takeFiles() ?? const <ComposerFile>[];
    if (files.isNotEmpty) unawaited(insertFiles(files));
  }

  /// Keeps what is typed, and where the caret is, in the draft.
  void _saveDraft() {
    if (_takingDraft) return;
    widget.draft?.save(
      _controller.document.toDelta(),
      _controller.selection,
      _pool.values.toList(),
      by: this,
    );
  }

  /// Taking up [_handleDraftChanged]'s text: not the user's edit.
  bool _takingDraft = false;

  /// The draft typed in by another composer (the same agent's, in another
  /// window): its text here too, the caret kept where it was.
  void _handleDraftChanged() {
    final draft = widget.draft;
    if (draft != null && draft.pendingFiles.isNotEmpty) _takeDraftFiles();
    if (draft == null || identical(draft.savedBy, this) || !draft.saved) {
      return;
    }
    final current = _controller.document.toDelta();
    final change = current.diff(draft.content!);
    if (change.isEmpty) return;
    _pool = {..._pool, for (final image in draft.images) ?image.number: image};
    final selection = _controller.selection;
    final end = draft.content!.length - 1;
    final history = _controller.document.history;
    final ignoring = history.ignoreChange;
    _takingDraft = true;
    history.ignoreChange = true;
    try {
      _controller.compose(
        change,
        TextSelection(
          baseOffset: change
              .transformPosition(selection.baseOffset)
              .clamp(0, end),
          extentOffset: change
              .transformPosition(selection.extentOffset)
              .clamp(0, end),
        ),
        ChangeSource.remote,
      );
    } finally {
      history.ignoreChange = ignoring;
      _takingDraft = false;
    }
  }

  void _handleEditorChanged() {
    // The placeholder of a drag coming and going: not the user's edit.
    if (_ghosting) return;
    if (_padTrailingTokens()) return; // Re-entered with the fixed document.
    _images = _referredImages();
    _saveDraft();
    final plain = _controller.document.toPlainText();
    // Edited, a message recalled from the history is the one typed.
    if (_historyAt != null && !_recalling && plain != _historyShown) {
      _leaveHistory();
    }
    final hasContent = plain.trim().isNotEmpty;
    final trigger = _findTrigger(plain);

    if (trigger == null || !trigger.sameAnchor(_dismissedTrigger)) {
      _dismissedTrigger = null;
    }
    var visible = trigger != null && _dismissedTrigger == null;
    final vocabulary = ComposerVocabulary.read(context);
    // An @ with no file to look up and no other conversation to refer to
    // stays text.
    if (visible && trigger.kind == SuggestionKind.file) {
      if (!trigger.sameAnchor(_trigger)) {
        _sessions = vocabulary.sessions?.call() ?? [];
      }
      visible = vocabulary.suggestFiles != null || _sessions.isNotEmpty;
    }

    if (visible) {
      final queryChanged =
          !trigger!.sameAnchor(_trigger) || trigger.query != _trigger!.query;
      if (queryChanged) {
        if (trigger.kind == SuggestionKind.file) {
          _matches = rankGroupedSuggestions(_sessions, trigger.query);
          if (vocabulary.suggestFiles case final suggest?) {
            unawaited(_lookUpFiles(trigger, suggest));
          }
        } else {
          _matches = rankSuggestions(vocabulary.commands, trigger.query);
        }
        _highlighted = 0;
      }
      _menuKind = trigger.kind;
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
  /// the conversations. Answers to older queries are dropped.
  Future<void> _lookUpFiles(
    _Trigger trigger,
    Future<List<FileSuggestion>> Function(String query) suggest,
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
        ...rankGroupedSuggestions(_sessions, trigger.query),
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
    // `/re|view`) is not typing one.
    if (caret < plain.length && !isBoundary(plain[caret])) return null;
    if (plain.startsWith('/')) {
      final query = plain.substring(1, caret);
      if (!query.split('').any(isBoundary)) {
        return _Trigger(SuggestionKind.command, 0, query);
      }
    }
    // An @ starting the word the caret ends: a file or a conversation to
    // refer to.
    final vocabulary = ComposerVocabulary.read(context);
    if (vocabulary.sessions == null && vocabulary.suggestFiles == null) {
      return null;
    }
    for (var i = caret - 1; i >= 0; i--) {
      final char = plain[i];
      if (isBoundary(char)) return null;
      if (char == '@' && (i == 0 || isBoundary(plain[i - 1]))) {
        return _Trigger(SuggestionKind.file, i, plain.substring(i + 1, caret));
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
    _controller.replaceText(trigger.start, 0, switch (suggestion.kind) {
      SuggestionKind.file || SuggestionKind.folder => ComposerTokenEmbed.file(
        suggestion.value,
        directory: suggestion.kind == SuggestionKind.folder,
      ),
      _ => ComposerTokenEmbed.fromSuggestion(suggestion),
    }, TextSelection.collapsed(offset: trigger.start + 2));
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
    // Run by the window's keybindings (it sees keys first).
    if (ChatKeys.isHandled(event)) return KeyEventResult.handled;
    // An open picker menu (or tooltip) takes arrows, Enter and Esc first.
    if (FloatingRegistry.handleKey(event) case final result?) return result;
    // Then the keybindings: Enter sends, the menu's keys…
    if (ChatKeys.dispatch(event) case final result?) return result;
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;

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

  bool get _caretAtStart {
    final selection = _controller.selection;
    return selection.isCollapsed && selection.baseOffset <= 0;
  }

  bool get _caretAtEnd {
    final selection = _controller.selection;
    return selection.isCollapsed &&
        selection.baseOffset >= _controller.document.length - 1;
  }

  @override
  Object? chatContextKey(String key) => switch (key) {
    ChatContextKeys.inChatInput ||
    'inputFocus' ||
    'textInputFocus' => _focusNode.hasFocus,
    ChatContextKeys.inputHasText => _hasContent,
    // As upstream: at the very start, and the very end.
    ChatContextKeys.cursorAtTop => _caretAtStart,
    ChatContextKeys.cursorAtBottom => _caretAtEnd,
    ChatContextKeys.suggestWidgetVisible => _trigger != null,
    ChatContextKeys.hasPromptSuggestion => _suggestion != null,
    ChatContextKeys.currentlyEditing => widget.onSubmit != null,
    _ => null,
  };

  @override
  Map<String, VoidCallback> get chatCommands {
    final menu = _trigger != null;
    final history = widget.onSubmit == null;
    return {
      // Always: with nothing to send, Enter does nothing (no new line).
      ChatCommandIds.submit: _submit,
      ChatCommandIds.cancelEdit: ?widget.onCancel,
      if (history && (_historyAt ?? _sentPrompts().length) > 0)
        ChatCommandIds.showPreviousPrompt: () => _showPrompt(-1),
      if (history && _historyAt != null)
        ChatCommandIds.showNextPrompt: () => _showPrompt(1),
      if (_suggestion != null)
        ChatCommandIds.acceptPromptSuggestion: _acceptSuggestion,
      if (_modePickerKey.currentState case final picker?)
        ChatCommandIds.openModePicker: picker.toggle,
      if (widget.session.modes case final modes?)
        ChatCommandIds.nextMode: () => _nextMode(modes),
      if (_modelPickerKey.currentState case final picker?)
        ChatCommandIds.openModelPicker: picker.toggle,
      if (WindowControls.canPickFiles)
        ChatCommandIds.attachContext: _attachContext,
      if (menu) ...{
        ChatCommandIds.selectNextSuggestion: () => _moveHighlight(1),
        ChatCommandIds.selectPrevSuggestion: () => _moveHighlight(-1),
        if (_matches.isNotEmpty)
          ChatCommandIds.acceptSelectedSuggestion: () => _accept(_highlighted),
        ChatCommandIds.hideSuggestWidget: () => setState(_closeMenu),
      },
    };
  }

  @override
  bool get chatComposing => _isComposing;

  /// Picks the mode after the one picked, back to the first after the
  /// last.
  void _nextMode(KernelChoice modes) {
    final options = modes.options;
    final at = options.indexWhere((o) => o.id == modes.selected.id);
    modes.onSelected(options[(at + 1) % options.length]);
  }

  /// Asks for files (the system's open panel) and puts them in at the
  /// caret (upstream's Add Context… picks them in a picker of its own).
  Future<void> _attachContext() async {
    final files = await WindowControls.pickFiles();
    if (!mounted) return;
    await insertFiles(files);
    _focusNode.requestFocus();
  }

  // --- Drag and drop -----------------------------------------------------
  //
  // Files dragged over the composer, from other apps (see [FileDrops]) or
  // from the IDE ([FileDragData]), show where they would go: their tags,
  // faint, in the text at the pointer, the text making room for them. Let
  // go, the tags take their place.

  /// Where the placeholder is in the document, while a drag is over it.
  int? _ghostAt;

  /// The placeholder and the space after it.
  static const _ghostLength = 2;

  /// What the placeholder shows.
  List<ComposerFile> _ghostFiles = const [];

  /// The placeholder is being put in or taken out: no edit of the user's
  /// (see [_handleEditorChanged]), and nothing to undo.
  bool _ghosting = false;

  /// Where in the text [position] (the window's) would put what is let go
  /// there: an offset in the document without the placeholder. Below or
  /// beside the text (the toolbar, the pictures), its end.
  int _dropOffset(Offset position) {
    final end =
        _controller.document.length - 1 - (_ghostAt == null ? 0 : _ghostLength);
    final editor = _editorKey.currentState?.renderEditor;
    if (editor == null || !editor.attached) return end;
    final local = editor.globalToLocal(position);
    if (!(Offset.zero & editor.size).contains(local)) return end;
    var offset = editor.getPositionForOffset(position).offset;
    if (_ghostAt case final ghost? when offset > ghost) {
      offset = math.max(ghost, offset - _ghostLength);
    }
    return offset.clamp(0, end);
  }

  void _showGhost(Offset position, List<ComposerFile> files) {
    if (!mounted) return;
    final at = _dropOffset(position);
    if (at == _ghostAt && listEquals(files, _ghostFiles)) return;
    final shown = _ghostAt != null;
    _editGhost(() {
      _removeGhost();
      _controller.compose(
        Delta()
          ..retain(at)
          ..insert(ComposerGhostEmbed.of(files).toJson())
          ..insert(' '),
        _controller.selection,
        ChangeSource.local,
      );
      _ghostAt = at;
      _ghostFiles = files;
    });
    // The border shows it.
    if (!shown) setState(() {});
  }

  void _hideGhost() {
    if (!mounted || _ghostAt == null) return;
    _editGhost(_removeGhost);
    setState(() {});
  }

  void _removeGhost() {
    final at = _ghostAt;
    if (at == null) return;
    _ghostAt = null;
    _ghostFiles = const [];
    _controller.compose(
      Delta()
        ..retain(at)
        ..delete(_ghostLength),
      _controller.selection,
      ChangeSource.local,
    );
  }

  void _editGhost(VoidCallback edit) {
    final history = _controller.document.history;
    final ignoring = history.ignoreChange;
    _ghosting = true;
    history.ignoreChange = true;
    try {
      edit();
    } finally {
      history.ignoreChange = ignoring;
      _ghosting = false;
    }
  }

  @override
  void fileDragOver(Offset position, List<ComposerFile> files) => _showGhost(
    position,
    // Files an app is still to write (a mail's attachment) have no names
    // yet.
    files.isEmpty ? const [ComposerFile('…')] : files,
  );

  @override
  void fileDragLeave() => _hideGhost();

  @override
  void fileDrop(Offset position, List<ComposerFile> files) {
    if (!mounted) return;
    final at = _ghostAt ?? _dropOffset(position);
    _hideGhost();
    unawaited(insertFiles(files, at: at));
  }

  // --- Prompt history ------------------------------------------------------
  //
  // As upstream's chat input history: ↑ at the start of the input shows
  // the message sent before, ↓ at its end the one after, and past the last,
  // what was being typed.

  /// Where in [_sentPrompts] the history shows (their count: what was
  /// being typed); null when it does not.
  int? _historyAt;

  /// What was being typed when the history was opened.
  Delta? _historyDraft;

  /// The text the history put in: once it is edited, it is the message
  /// typed, and the history closes.
  String? _historyShown;
  bool _recalling = false;

  /// The messages sent in this conversation, oldest first, a message sent
  /// again in a row once.
  List<String> _sentPrompts() {
    final session = widget.session;
    final prompts = <String>[];
    for (var i = 0; i < session.itemCount; i++) {
      if (session.itemAt(i) case UserMessageItem(:final text)
          when text.trim().isNotEmpty &&
              (prompts.isEmpty || prompts.last != text)) {
        prompts.add(text);
      }
    }
    return prompts;
  }

  void _leaveHistory() {
    _historyAt = null;
    _historyDraft = null;
    _historyShown = null;
  }

  /// Shows the message [step] from the one shown (-1: the one before).
  void _showPrompt(int step) {
    final prompts = _sentPrompts();
    final document = _controller.document;
    final from = _historyAt ?? prompts.length;
    final at = from + step;
    if (at < 0 || at > prompts.length) return;
    _historyDraft ??= document.toDelta().slice(0, document.length - 1);
    final Delta content;
    if (at == prompts.length) {
      content = _historyDraft!;
    } else {
      content = composerDeltaFromPaste(
        prompts[at],
        ComposerVocabulary.read(context),
        atStart: true,
      );
    }
    _recalling = true;
    try {
      final length = document.length - 1;
      final delta = Delta();
      if (length > 0) delta.delete(length);
      _controller.compose(
        delta.concat(content),
        _controller.selection,
        ChangeSource.local,
      );
      // Going back, at the start: ↑ goes on back; going on, at the end.
      _controller.updateSelection(
        TextSelection.collapsed(
          offset: step < 0 ? 0 : _controller.document.length - 1,
        ),
        ChangeSource.local,
      );
    } finally {
      _recalling = false;
    }
    if (at == prompts.length) {
      _leaveHistory();
    } else {
      _historyAt = at;
      _historyShown = _controller.document.toPlainText();
    }
  }

  // --- Submit --------------------------------------------------------------

  ComposerMessage _buildMessage() {
    final text = StringBuffer();
    final mentions = <String>[];
    final code = <String, AppendedText>{};
    for (final op in _controller.document.toDelta().toList()) {
      final data = op.data;
      if (data is String) {
        text.write(data);
      } else if (data case {ComposerImageEmbed.type: final image}) {
        text.write(ComposerImageEmbed.plainText(image));
      } else if (data case {ComposerCodeEmbed.type: final raw}) {
        final reference = ComposerCodeEmbed.decode(raw);
        text.write(reference.reference);
        code.putIfAbsent(reference.reference, () => reference);
      } else if (data case {ComposerPastedTextEmbed.type: final raw}) {
        final pasted = ComposerPastedTextEmbed.decode(raw);
        text.write(pasted.reference);
        code.putIfAbsent(pasted.reference, () => pasted);
      } else if (data is Map && data.containsKey(ComposerTokenEmbed.type)) {
        final raw = data[ComposerTokenEmbed.type];
        text.write(ComposerTokenEmbed.plainText(raw));
        final token = ComposerTokenEmbed.decode(raw);
        if ((token.kind == SuggestionKind.file ||
                token.kind == SuggestionKind.folder) &&
            !mentions.contains(token.value)) {
          mentions.add(token.value);
        }
      }
    }
    return ComposerMessage(
      // The lines it refers to after it.
      text: text.toString().trim() + codeAppendix(code.values),
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
    _pool = {};
    _controller.clear();
    _leaveHistory();
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
    // Its key follows the keybindings (the window builds again when they
    // change).
    final suggestionKey = suggestion == null
        ? null
        : ChatKeys.keyLabel(
            ChatCommandIds.acceptPromptSuggestion,
            _suggestionKeyContext,
          );
    if (suggestion != _suggestion || suggestionKey != _suggestionKey) {
      _suggestion = suggestion;
      _suggestionKey = suggestionKey;
      _editor = null; // The placeholder shows them.
    }
    final colors = themeColors;
    if (!identical(colors, _editorColors)) {
      _editorColors = colors;
      _editor = null;
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
      child: FileDropRegion(
        delegate: this,
        child: DragTarget<FileDragData>(
          onWillAcceptWithDetails: (details) => details.data.files.isNotEmpty,
          onMove: (details) => _showGhost(details.offset, details.data.files),
          onLeave: (_) => _hideGhost(),
          onAcceptWithDetails: (details) =>
              fileDrop(details.offset, details.data.files),
          builder: (context, candidates, rejected) =>
              _buildBox(focused: focused || _ghostAt != null),
        ),
      ),
    );
  }

  Widget _buildBox({required bool focused}) {
    final colors = themeColors;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _focusNode.requestFocus,
      child: AnimatedContainer(
        key: _boxKey,
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          // The agents window's chat input; editing a sent message, its
          // bubble (as upstream), over the page: it floats when stuck.
          color: widget.onSubmit == null
              ? colors['agentsChatInput.background']
              : Color.alphaBlend(
                  colors['chat.requestBubbleBackground'],
                  colors['editor.background'],
                ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: focused
                ? colors['agentsChatInput.focusBorder']
                : colors['agentsChatInput.border'],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_images.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: ImageThumbnails(images: _images, onRemove: _removeImage),
              ),
            ComposerImages(
              images: _pool,
              child: _editor ??= _buildEditor(context),
            ),
            _buildToolbar(),
          ],
        ),
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    return SuggestionMenu(
      title: _menuKind == SuggestionKind.file
          ? context.l10n.composerMentions
          : context.l10n.composerCommands,
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
          color: themeColors['editorCursor.foreground'],
          child: Listener(
            onPointerDown: _handleSelectPointerDown,
            onPointerMove: _handleSelectPointerMove,
            onPointerUp: _handleSelectPointerUp,
            onPointerCancel: (_) {
              _selectDragFrom = null;
              _clickDownAt = null;
            },
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
    final l10n = context.l10n;
    final chosen = await WindowControls.showContextMenu(position, [
      NativeMenuItem('cut', l10n.commonCut, key: 'x', enabled: selected),
      NativeMenuItem('copy', l10n.commonCopy, key: 'c', enabled: selected),
      NativeMenuItem('paste', l10n.commonPaste, key: 'v', enabled: canPaste),
      const NativeMenuItem.separator(),
      NativeMenuItem(
        'selectAll',
        l10n.commonSelectAll,
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
    _handleClickDown(event, plainPress: plainPress);
  }

  void _handleSelectPointerUp(PointerUpEvent event) {
    _selectDragFrom = null;
    _handleClickUp(event);
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

  // --- Double-click -------------------------------------------------------
  //
  // A double-click with nothing selected selects everything; with text
  // selected it selects a word, as Quill does. Told apart here rather than
  // by Quill: a real click often moves the pointer a pixel or two, past
  // where Quill's drag recognizer takes the press from its tap, and then it
  // sees no double-click at all.

  /// How far a press may move and still be a click.
  static const _clickSlop = 6.0;

  /// Where the current plain press came down; null for other presses.
  Offset? _clickDownAt;

  /// Open from a click's up while a press near it is that click's double.
  Timer? _clickWindow;
  Offset? _clickUpAt;

  /// Whether text was selected when the last first click came down.
  bool _clickOnSelection = false;

  /// Whether the current press is a double-click's second.
  bool _secondClick = false;

  void _handleClickDown(PointerDownEvent event, {required bool plainPress}) {
    final upAt = _clickUpAt;
    _clickDownAt = plainPress ? event.position : null;
    _secondClick =
        plainPress &&
        _clickWindow?.isActive == true &&
        upAt != null &&
        (event.position - upAt).distance <= kDoubleTapSlop;
    _clickWindow?.cancel();
    _clickWindow = null;
    // The first click puts any selection away, so ask before it.
    if (!_secondClick) _clickOnSelection = !_controller.selection.isCollapsed;
  }

  void _handleClickUp(PointerUpEvent event) {
    final downAt = _clickDownAt;
    _clickDownAt = null;
    if (downAt == null || (event.position - downAt).distance > _clickSlop) {
      return;
    }
    // As Quill's, a third click is a click again (no window after a second).
    if (_secondClick) {
      if (_clickOnSelection) return;
      // After Quill's handling of the up, which comes after this: whatever
      // it made of the press (a word, a caret, a drag of a pixel).
      scheduleMicrotask(() {
        if (mounted) {
          _editorKey.currentState?.selectAll(SelectionChangedCause.tap);
        }
      });
      return;
    }
    _clickUpAt = event.position;
    _clickWindow = Timer(kDoubleTapTimeout, () => _clickWindow = null);
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
        // A suggested prompt, then the key that takes it as the keybindings
        // label it (`Tab`); alone when it has none.
        placeholder: _quillPlaceholder(switch ((_suggestion, _suggestionKey)) {
          (final suggestion?, final key?) => '$suggestion    $key',
          (final suggestion?, null) => suggestion,
          (null, _) => context.l10n.composerPlaceholder,
        }),
        minHeight: _minEditorHeight,
        maxHeight: _maxEditorHeight(context),
        textCapitalization: TextCapitalization.none,
        enableSelectionToolbar: false,
        embedBuilders: const [
          ComposerTokenEmbedBuilder(),
          ComposerImageEmbedBuilder(),
          ComposerCodeEmbedBuilder(),
          ComposerPastedTextEmbedBuilder(),
          ComposerGhostEmbedBuilder(),
        ],
        // ignore: experimental_member_use
        onKeyPressed: _handleKey,
        onTapOutside: (event, focusNode) {},
        showCursor: false,
        customStyles: _editorStyles(context),
      ),
    );
  }

  /// [text] as Quill's placeholder takes it. Quill reads the placeholder as
  /// JSON it splices the text into, escaping only its quotes: a backslash
  /// (a Windows path in a suggested prompt) or a control character (a line
  /// break) failed its build, and the input was a grey box until the app
  /// restarted. On one line, its backslashes escaped.
  static String _quillPlaceholder(String text) =>
      text.replaceAll(RegExp(r'[\x00-\x1f]+'), ' ').replaceAll(r'\', r'\\');

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
      placeHolder: block(
        _textStyle.copyWith(
          color: themeColors['agentsChatInput.placeholderForeground'],
        ),
      ),
    );
  }

  /// The model with its settings, e.g. "Opus · 1M · High": the context
  /// only when it is not the standard one; its upstream before it only
  /// when another upstream has a model of its name.
  String _modelLabel(KernelOption model, List<KernelOption> options) => [
    if (model.group case final group?
        when options.any(
          (other) => other.label == model.label && other.group?.id != group.id,
        ))
      group.label,
    model.label,
    for (final setting in widget.session.modelSettings(model.id))
      if (setting.selected case final selected?
          when setting.kind != KernelChoiceKind.context ||
              selected != setting.options.first)
        selected.label,
  ].join(' · ');

  /// Runs [pick], which switches to [option]: once confirmed, if that
  /// restarts the agent on another upstream mid-conversation.
  Future<void> _switchModel(KernelOption option, VoidCallback pick) async {
    final session = widget.session;
    if (!session.switchRestarts(option.id)) return pick();
    final l10n = context.l10n;
    final choice = await showIdeDialog(
      context,
      message: l10n.modelsSwitchTitle(option.group?.label ?? option.label),
      detail: l10n.modelsSwitchDetail,
      buttons: [l10n.modelsSwitchConfirm],
      type: IdeDialogType.question,
    );
    if (choice == 0 && mounted) pick();
  }

  Widget _buildToolbar() {
    final session = widget.session;
    // Only the dock's composer picks the kernel, and only until it starts.
    final kernel = widget.onSubmit == null ? session.kernelChoice : null;
    final mode = session.modes;
    final permission = session.permissions;
    final model = session.models;
    final context = session.context;
    final l10n = this.context.l10n;
    KernelOption localized(KernelOption option) => localizedKernelOption(
      l10n,
      session.kernel.id,
      KernelChoiceKind.permission,
      option,
    );
    // The pickers' and the ring's hovers, with the keys that do the same in
    // the input.
    const input = {ChatContextKeys.inChatInput: true};
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
                      key: _modePickerKey,
                      options: mode.options,
                      selected: mode.selected,
                      emphasized: true,
                      tooltip: ChatKeys.titleWithKey(
                        l10n.composerSetMode,
                        ChatCommandIds.openModePicker,
                        input,
                      ),
                      tapRegionGroupId: widget.tapRegionGroupId,
                      focusNode: _focusNode,
                      onSelected: mode.onSelected,
                    ),
                    const SizedBox(width: 2),
                  ],
                  if (permission != null) ...[
                    ComposerPicker(
                      options: [
                        for (final option in permission.options)
                          localized(option),
                      ],
                      selected: localized(permission.selected),
                      // `context` is the session's here.
                      title: l10n.composerApprovalTitle(session.kernel.label),
                      menuWidth: 290,
                      tapRegionGroupId: widget.tapRegionGroupId,
                      focusNode: _focusNode,
                      onSelected: permission.onSelected,
                    ),
                    const SizedBox(width: 2),
                  ],
                  if (model != null)
                    ComposerPicker(
                      key: _modelPickerKey,
                      options: model.options,
                      selected: model.selected,
                      label: _modelLabel(model.selected, model.options),
                      // The id and the context window: once there are
                      // upstreams' models.
                      describes: model.options.any(
                        (option) =>
                            option.group != null &&
                            option.group!.id != builtinProviderId,
                      ),
                      settingsOf: (option) => [
                        for (final setting in session.modelSettings(option.id))
                          ModelSettingChoice(
                            kind: setting.kind,
                            options: setting.options,
                            selected: setting.selected,
                            onSelected: (choice) => unawaited(
                              _switchModel(
                                option,
                                () => setting.onSelected(choice),
                              ),
                            ),
                          ),
                      ],
                      tooltip: ChatKeys.titleWithKey(
                        l10n.composerPickModel,
                        ChatCommandIds.openModelPicker,
                        input,
                      ),
                      menuWidth: 260,
                      searchPlaceholder: l10n.modelsSearch,
                      footer: switch (SettingsOpener.maybeOf(this.context)) {
                        final open? => (
                          label: l10n.modelsManage,
                          icon: Icons.tune_rounded,
                          onTap: () => open(SettingsSection.models),
                        ),
                        null => null,
                      },
                      tapRegionGroupId: widget.tapRegionGroupId,
                      focusNode: _focusNode,
                      onSelected: (option) => unawaited(
                        _switchModel(option, () => model.onSelected(option)),
                      ),
                    ),
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
              // Toggle Context Panel's, which has none by default.
              tooltip: ChatKeys.titleWithKey(
                l10n.composerContextUsage,
                ChatCommandIds.toggleContextPanel,
                const {...input, ChatContextKeys.inChat: true},
              ),
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
    required this.tooltip,
    required this.onTap,
  });

  final double fraction;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return IdeHover(
      message: tooltip,
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
              color: active
                  ? colors['toolbar.activeBackground']
                  : hovered
                  ? colors['toolbar.hoverBackground']
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: SizedBox.square(
              dimension: 13,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: fraction),
                duration: const Duration(milliseconds: 400),
                builder: (context, value, _) => CustomPaint(
                  painter: _RingPainter(
                    value,
                    track: colors['disabledForeground'],
                    arc: colors['icon.foreground'],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// As upstream's context usage widget: the track `disabledForeground`, the
/// arc `icon.foreground`.
class _RingPainter extends CustomPainter {
  _RingPainter(this.fraction, {required this.track, required this.arc});

  final double fraction;
  final Color track;
  final Color arc;

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
      stroke..color = track,
    );
    canvas.drawArc(
      rect.deflate(1),
      -math.pi / 2,
      math.pi * 2 * fraction.clamp(0, 1),
      false,
      stroke..color = arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.track != track ||
      oldDelegate.arc != arc;
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
    final colors = themeColors;
    // As upstream's submit button: the primary button's colors; disabled,
    // none but the disabled icon.
    final foreground = colors['button.foreground'];
    // With the keys that do the same, as the keybindings have them.
    const input = {ChatContextKeys.inChatInput: true};
    return IdeHover(
      message: streaming
          ? ChatKeys.titleWithKey(
              context.l10n.composerStop,
              ChatCommandIds.cancel,
              {...input, ChatContextKeys.requestInProgress: true},
            )
          : ChatKeys.titleWithKey(
              context.l10n.cmdChatSubmit,
              ChatCommandIds.submit,
              input,
            ),
      child: HoverBuilder(
        cursor: active ? SystemMouseCursors.click : SystemMouseCursors.basic,
        builder: (context, hovered) => GestureDetector(
          onTap: streaming ? onStop : (enabled ? onSend : null),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: !active
                  ? Colors.transparent
                  : hovered
                  ? colors['button.hoverBackground']
                  : colors['button.background'],
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
                        color: foreground,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    )
                  : Icon(
                      key: const ValueKey('send'),
                      Icons.arrow_upward_rounded,
                      size: 15,
                      color: active ? foreground : AppColors.textFaint,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
