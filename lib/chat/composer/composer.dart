import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:bao_markdown/bao_markdown.dart';

import '../../kernel/agent_kernel.dart';
import '../../kernel/kernel_types.dart';
import '../../keybindings/chat_keybindings.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show WorkbenchColors, themeColors;
import '../chat_keys.dart';
import '../chat_models.dart';
import '../chat_session.dart';
import '../open_editor.dart';
import '../stop_confirmation.dart';
import '../floating/floating_layer.dart';
import '../floating/floating_placement.dart';
import '../floating/floating_registry.dart';
import '../../workspace/window_controls.dart';
import '../widgets/hover_builder.dart';
import 'composer_caret.dart';
import 'composer_controller.dart';
import 'composer_draft.dart';
import 'composer_embeds.dart';
import 'composer_files.dart';
import 'composer_images.dart';
import 'composer_mock_data.dart';
import 'composer_picker.dart';
import 'composer_polish.dart';
import 'pickers_row.dart';
import 'session_model_picker.dart';
import 'kernel_option_text.dart';
import 'file_drop.dart';
import 'suggestion_menu.dart';
import '../../ide/ide_hover.dart';
import '../../ide/ide_spinning.dart';
import '../../theme/codicons.dart';
import '../../ide/file_service.dart' show IdeFileService;
import '../../ide/ide_notifications.dart';
import 'remote_drops.dart';

/// An open query: a /command's (a slash starting a word), or a mention's
/// (an @ starting a word: a file, a folder or a conversation);
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

/// The chat input: an editor of plain text (bao_markdown's, see
/// [ComposerController]) with tags in it.
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
    this.openEditor,
    this.hostFiles,
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

  /// The file open in the editor beside the chat (see [ChatSession.send]).
  final OpenEditor? Function()? openEditor;

  /// A remote project's host's files, where files of this machine's put
  /// in (let go from another app, pasted, picked) are copied first, for its
  /// agent to read (see [RemoteDrops]); null for a local project.
  final IdeFileService? hostFiles;

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

  late final ComposerController _controller = _createController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'Composer');
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<MarkdownEditorState> _editorKey = GlobalKey();
  final GlobalKey _boxKey = GlobalKey();
  final GlobalKey<ComposerPickerState> _modePickerKey = GlobalKey();
  final GlobalKey<ComposerPickerState> _modelPickerKey = GlobalKey();

  bool _hasContent = false;

  /// Polish asked, its answer awaited (see [_polish]).
  bool _polishing = false;

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

  /// The stashes the open @ offers, after the files, as they were when it
  /// was typed.
  List<Suggestion> _stashes = const [];

  /// What an @ offers besides files: stashes, then conversations.
  List<SuggestionMatch> _rankOthers(String query) => [
    ...rankGroupedSuggestions(_stashes, query),
    ...rankGroupedSuggestions(_sessions, query),
  ];

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
    if (widget.draft case final draft? when draft.saved) {
      final content = draft.content!;
      final end = content.length;
      return ComposerController(
        text: content,
        selection: TextSelection(
          baseOffset: draft.selection.baseOffset.clamp(0, end),
          extentOffset: draft.selection.extentOffset.clamp(0, end),
        ),
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
    if (text.isEmpty) return ComposerController();
    final content = composerContentFromText(
      text,
      ComposerVocabulary.read(context),
      images: numbers,
    );
    return ComposerController(
      text: content,
      selection: TextSelection.collapsed(offset: content.length),
    );
  }

  /// Pastes what the clipboard holds: copied files as tags of their paths
  /// (images as images), code the IDE's editor copied as a tag of its lines,
  /// a picture (a screenshot), or else its plain text, with its `@paths`
  /// (and a leading /command) as tags, as the message will show once sent:
  /// copied from the history or from elsewhere alike. (What this editor
  /// copied itself, its tags and all, the editor pastes back as it was.)
  /// Returns false for nothing to paste. With `raw` (⇧⌘V / Ctrl+Shift+V),
  /// its text goes in as it is, past the long-paste tag; files and images
  /// still come in as such.
  Future<bool> _paste({bool raw = false}) async {
    final files = await WindowControls.readPasteboardFiles();
    if (!mounted) return false;
    if (files.isNotEmpty) {
      await insertFiles(files, here: true);
      return true;
    }
    final text = await WindowControls.readPasteboardText();
    if (!mounted) return false;
    if (text != null && !raw) {
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
    var plain = MdAtoms.strip(text.replaceAll('\r\n', '\n'));
    if (widget.session.acceptsImages) {
      plain = await _picturesIn(plain);
      if (!mounted) return false;
    }
    // Pasted raw, the text goes in as it is, whatever its length: no paste
    // tag (the shortcut is for exactly that), and no attachment offload,
    // which happens as the message is sent (see PasteStore.offload).
    if (!raw && PastedText.isLong(plain)) {
      _insertTags([
        ComposerPastedTextEmbed.of(
          PastedText(number: _nextPastedNumber(), text: plain),
        ),
      ]);
      return true;
    }
    final selection = _controller.selection;
    final start = selection.isValid ? selection.start : _controller.length;
    final end = selection.isValid ? selection.end : start;
    final content = raw
        ? plain
        : composerContentFromPaste(
            plain,
            ComposerVocabulary.read(context),
            atStart: start == 0,
            images: _pool.keys.toSet(),
          );
    _controller
      ..breakUndo()
      ..replace(start, end, content)
      ..breakUndo();
    return true;
  }

  /// The number for a long paste: one past the highest the text has.
  int _nextPastedNumber() {
    var highest = 0;
    for (final (:embed, start: _, end: _) in _controller.embeds) {
      if (embed.type == ComposerPastedTextEmbed.type) {
        highest = math.max(
          highest,
          ComposerPastedTextEmbed.decode(embed.data).number,
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
    _hasContent = _controller.text.trim().isNotEmpty;
    _controller.addListener(_handleEditorChanged);
    _focusNode.addListener(_handleFocusChanged);
    widget.draft?.addListener(_handleDraftChanged);
    ComposerPolishSetting.changes?.addListener(_handleSettingsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _takeDraftFiles();
      _takeDraftMessage();
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

  /// Settings → General's Polish button, turned on or off.
  void _handleSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.draft?.removeListener(_handleDraftChanged);
    ComposerPolishSetting.changes?.removeListener(_handleSettingsChanged);
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
    for (final (:embed, :start, end: _) in _controller.embeds) {
      if (embed.type == ComposerImageEmbed.type) {
        yield (number: ComposerImageEmbed.decode(embed.data), offset: start);
      }
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
  /// is in it, or, for an image the conversation takes, the image. [here],
  /// they are this machine's: a remote project's agent is given copies on
  /// its host ([ChatComposer.hostFiles]), those that could not be copied
  /// left out.
  Future<void> insertFiles(
    List<ComposerFile> files, {
    int? at,
    bool here = false,
  }) async {
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
    // The pictures go with the message as they are; the rest are copied.
    final List<ComposerFile?> paths = [
      for (final (index, file) in files.indexed)
        images[index] == null ? file : null,
    ];
    if (here && widget.hostFiles != null && paths.nonNulls.isNotEmpty) {
      final copies = await _copyToHost(paths.nonNulls.toList());
      if (!mounted) return;
      final copied = copies?.iterator;
      for (var i = 0; i < paths.length; i++) {
        if (paths[i] == null) continue;
        paths[i] = copied != null && copied.moveNext() ? copied.current : null;
      }
    }
    final root = widget.session.root;
    _insertTags([
      for (final (index, file) in files.indexed)
        if (images[index] case final image?)
          ComposerImageEmbed.of(image.number!)
        else if (paths[index] case final path?)
          ComposerTokenEmbed.file(
            displayPath(path.path, root),
            directory: file.directory,
          ),
    ], at: at);
  }

  /// [files], this machine's, copied onto the remote project's host, how
  /// far told in a notification once it takes a moment; null when they
  /// could not be, as a notification says.
  Future<List<ComposerFile>?> _copyToHost(List<ComposerFile> files) async {
    final notifications = IdeNotificationsScope.maybeOf(context);
    final l10n = context.l10n;
    var done = 0;
    var total = files.length;
    IdeNotification? shown;
    IdeNotificationProgress progress() =>
        IdeNotificationProgress(done.toDouble(), total: total.toDouble());
    final timer = notifications == null
        ? null
        : Timer(const Duration(milliseconds: 300), () {
            shown = notifications.notify(
              IdeSeverity.info,
              l10n.explorerUploading(done, total),
              progress: progress(),
              sticky: true,
            );
          });
    try {
      return await RemoteDrops.copy(
        widget.hostFiles!,
        files,
        onProgress: (worked, of) {
          done = worked;
          total = of;
          if (shown case final shown?) {
            notifications!.update(
              shown,
              message: l10n.explorerUploading(done, total),
              progress: progress(),
            );
          }
        },
      );
    } on Object catch (error) {
      notifications?.notify(
        IdeSeverity.error,
        l10n.composerCopyToHostFailed('$error'),
      );
      return null;
    } finally {
      timer?.cancel();
      if (shown case final shown?) notifications!.close(shown);
    }
  }

  /// [text]'s `@paths` of pictures that go in as such ([pastedAsPicture]:
  /// copied out of a stash) as the pictures: read, numbered, and referred
  /// to as `[Image #N]`, which the paste makes their tags.
  Future<String> _picturesIn(String text) async {
    final found = <(int, int, String)>[];
    for (var i = 0; i < text.length; i++) {
      if (text[i] != '@' || (i > 0 && text[i - 1].trim().isNotEmpty)) continue;
      if (parseFileReference(text, i)
          case (:final path, directory: false, :final end)
          when pastedAsPicture(path)) {
        found.add((i, end, path));
        i = end - 1;
      }
    }
    if (found.isEmpty) return text;
    final images = await _numbered(
      await Future.wait([
        for (final (_, _, path) in found) WindowControls.readImageFile(path),
      ]),
    );
    final out = StringBuffer();
    var at = 0;
    for (final (i, (start, end, _)) in found.indexed) {
      final image = images[i];
      if (image == null) continue;
      out
        ..write(text.substring(at, start))
        ..write(imageReference(image.number!));
      at = end;
    }
    out.write(text.substring(at));
    return out.toString();
  }

  /// Puts [tags] in at [at] (in place of the selection when null), apart
  /// from a word before them, each followed by a space, so that none is
  /// the last thing on its line (see [_padTrailingTokens]); the caret after
  /// them. One edit, undone as one.
  void _insertTags(List<ComposerEmbed> tags, {int? at}) {
    if (tags.isEmpty) return;
    final selection = _controller.selection;
    final end = _controller.length;
    final start = (at ?? (selection.isValid ? selection.start : end)).clamp(
      0,
      end,
    );
    final replaced = at == null && selection.isValid
        ? math.max(0, selection.end - start)
        : 0;
    final text = _controller.text;
    final content = StringBuffer();
    if (start > 0 && text[start - 1].trim().isNotEmpty) content.write(' ');
    for (final tag in tags) {
      content
        ..write(tag.atom)
        ..write(' ');
    }
    _controller
      ..breakUndo()
      ..replace(start, start + replaced, content.toString())
      ..breakUndo();
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
    final suggestion = MdAtoms.strip(_suggestion ?? '');
    if (suggestion.isEmpty) return;
    _controller.replace(
      0,
      0,
      suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );
  }

  /// The text area's own scroll position (it scrolls past its maximum
  /// height), or null before it is laid out.
  ScrollPosition? get editorScrollPosition =>
      _scrollController.hasClients ? _scrollController.position : null;

  /// The editor subtree, built once and reused so that keystrokes (which
  /// rebuild this state for the menu and send button) do not build it
  /// again. Rebuilt only when an inherited dependency (theme, window size),
  /// the color theme or the placeholder changes.
  Widget? _editor;

  /// [_shownOfText] when the box was last built.
  _ShownOfText? _shownBuilt;

  /// The color theme's colors [_editor] was built with.
  WorkbenchColors? _editorColors;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _editor = null;
  }

  // --- Editor state --------------------------------------------------------

  /// An input method is composing text: a composition not empty. A macOS
  /// one may leave an empty one (its letters deleted, or after a commit)
  /// until its next: not composing, or the keys (Tab, Enter) went to the
  /// editor (#143).
  bool get _isComposing => _controller.isComposing;

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _closeMenu();
    } else {
      // Focused, the caret in view: an edit's opens scrolled to its end.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final selection = _controller.selection;
        if (mounted && _focusNode.hasFocus && selection.isValid) {
          _editorKey.currentState?.ensureVisible(selection.extentOffset);
        }
      });
    }
    setState(() {});
  }

  /// The files put in the draft from outside (see
  /// [ComposerDraft.insertFiles]), as if pasted.
  void _takeDraftFiles() {
    final files = widget.draft?.takeFiles() ?? const <ComposerFile>[];
    if (files.isNotEmpty) unawaited(insertFiles(files));
  }

  /// The message put back in the draft to be edited (see
  /// [ComposerDraft.restore]): after what is typed, the caret at its end.
  void _takeDraftMessage() {
    final message = widget.draft?.takeMessage();
    if (message == null) return;
    _pool = {
      for (final image in message.images) ?image.number: image,
      ..._pool,
    };
    var text = message.text;
    final referred = {
      for (final match in imageReferencePattern.allMatches(text))
        int.parse(match[1]!),
    };
    final unreferred = [
      for (final image in message.images)
        if (image.number case final number? when !referred.contains(number))
          number,
    ];
    if (unreferred.isNotEmpty) {
      text = [unreferred.map(imageReference).join(' '), text].join(' ');
    }
    final content = composerContentFromText(
      text,
      ComposerVocabulary.read(context),
      images: _pool.keys.toSet(),
    );
    final end = _controller.length;
    _controller
      ..breakUndo()
      ..replace(
        end,
        end,
        content,
        selection: TextSelection.collapsed(offset: end + content.length),
      )
      ..breakUndo();
    _focusNode.requestFocus();
  }

  /// Keeps what is typed, and where the caret is, in the draft.
  void _saveDraft() {
    if (_takingDraft) return;
    widget.draft?.save(
      _controller.text,
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
    if (draft?.pendingMessage != null) _takeDraftMessage();
    if (draft == null || identical(draft.savedBy, this) || !draft.saved) {
      return;
    }
    final current = _controller.text;
    final content = draft.content!;
    if (current == content) return;
    _pool = {..._pool, for (final image in draft.images) ?image.number: image};
    // Only what differs replaced, the caret moved along.
    var start = 0;
    final shorter = math.min(current.length, content.length);
    while (start < shorter &&
        current.codeUnitAt(start) == content.codeUnitAt(start)) {
      start++;
    }
    var end = 0;
    while (end < shorter - start &&
        current.codeUnitAt(current.length - 1 - end) ==
            content.codeUnitAt(content.length - 1 - end)) {
      end++;
    }
    // Not into an atom: one changed is replaced whole.
    while (start > 0 && _inAtom(current, start)) {
      start--;
    }
    while (end > 0 && _inAtom(current, current.length - end)) {
      end--;
    }
    _takingDraft = true;
    try {
      // Not this composer's edit to undo, and its steps no longer the
      // text's.
      _controller
        ..forgetUndo()
        ..replaceUnrecorded(
          start,
          current.length - end,
          content.substring(start, content.length - end),
        );
    } finally {
      _takingDraft = false;
    }
  }

  /// Whether [offset] of [text] is inside an atom (after its opening mark,
  /// before or at its closing one).
  static bool _inAtom(String text, int offset) {
    if (offset <= 0 || offset > text.length) return false;
    final open = text.lastIndexOf(MdAtoms.open, offset - 1);
    if (open < 0) return false;
    final close = text.lastIndexOf(MdAtoms.close, offset - 1);
    return close < open;
  }

  /// What the box shows that follows the text, besides the text (which
  /// the editor shows itself): the menu, the images, whether the message
  /// can be sent and polished. A key typed that changes none of it since
  /// the box was built ([_shownBuilt]) does not build it again (its
  /// pickers, its buttons).
  _ShownOfText _shownOfText() => (
    menu: (_trigger != null, _menuX, _menuKind, _matches, _highlighted),
    pool: _pool,
    canSend: _canSend,
    polishable: ComposerPolishSetting.current() && _hasWords(),
  );

  /// Whether the text has words to polish: read again only once it
  /// changed, not each time the session builds the box.
  bool _hasWords() {
    final version = _controller.textVersion;
    if (version != _wordsVersion) {
      _wordsVersion = version;
      _words = _polishText().hasWords;
    }
    return _words;
  }

  int? _wordsVersion;
  bool _words = false;

  void _handleEditorChanged() {
    // The placeholder of a drag coming and going: not the user's edit.
    if (_ghosting) return;
    if (_padTrailingTokens()) return; // Re-entered with the fixed text.
    _images = _referredImages();
    _saveDraft();
    final text = _controller.text;
    // Edited, a message recalled from the history is the one typed.
    if (_historyAt != null && !_recalling && text != _historyShown) {
      _leaveHistory();
    }
    final hasContent = text.trim().isNotEmpty;
    final trigger = _findTrigger(text);

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
        _stashes = vocabulary.stashes?.call() ?? [];
      }
      visible =
          vocabulary.suggestFiles != null ||
          _sessions.isNotEmpty ||
          _stashes.isNotEmpty;
    }
    // A / within the message that starts no command's name (e.g. a path's)
    // stays text.
    List<SuggestionMatch>? commands;
    if (visible &&
        trigger != null &&
        trigger.kind == SuggestionKind.command &&
        trigger.start > 0) {
      commands = rankSuggestions(vocabulary.commands, trigger.query);
      visible = commands.isNotEmpty;
    }

    if (visible) {
      final queryChanged =
          !trigger!.sameAnchor(_trigger) || trigger.query != _trigger!.query;
      if (queryChanged) {
        if (trigger.kind == SuggestionKind.file) {
          _matches = _rankOthers(trigger.query);
          if (vocabulary.suggestFiles case final suggest?) {
            unawaited(_lookUpFiles(trigger, suggest));
          }
        } else {
          _matches =
              commands ?? rankSuggestions(vocabulary.commands, trigger.query);
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
    if (_shownOfText() != _shownBuilt) setState(() {});
  }

  int _lookups = 0;

  /// Asks the kernel for files matching [trigger], and shows them ahead of
  /// the conversations. Answers to older queries are dropped.
  Future<void> _lookUpFiles(
    _Trigger trigger,
    Future<List<Suggestion>> Function(String query) suggest,
  ) async {
    final lookup = ++_lookups;
    final List<Suggestion> files;
    try {
      files = await suggest(trigger.query);
    } on Object {
      return;
    }
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
        for (final suggestion in files)
          SuggestionMatch(
            suggestion,
            fuzzyMatch(suggestion.label, trigger.query)?.indexes ?? const [],
          ),
        ..._rankOthers(trigger.query),
      ];
      _highlighted = _highlighted.clamp(0, math.max(0, _matches.length - 1));
    });
    _syncMenuRegistration();
  }

  /// Flutter lays out a line whose only content is an inline widget taller
  /// than a line with text, so a token must never end a line: when it does
  /// (e.g. the space after it was deleted), add a space after it, part of
  /// the edit that left it there, and leave the caret where it was. Sending
  /// trims it. Returns true if it edited.
  bool _padTrailingTokens() {
    final text = _controller.text;
    for (final run in MdAtoms.parse(text).reversed) {
      final end = run.end;
      if (end < text.length && text[end] != '\n') continue;
      _controller.amend(end, end, ' ');
      return true;
    }
    return false;
  }

  _Trigger? _findTrigger(String text) {
    final selection = _controller.selection;
    if (!selection.isCollapsed || selection.baseOffset < 1) return null;
    final caret = math.min(selection.baseOffset, text.length);

    // A space, a line's end, or a tag's either end.
    bool isBoundary(String char) =>
        char.trim().isEmpty || char == MdAtoms.open || char == MdAtoms.close;
    // Only at the end of a query: a caret moved into existing text (e.g.
    // `/re|view`) is not typing one.
    if (caret < text.length && !isBoundary(text[caret])) return null;
    // A / or an @ starting the word the caret ends: a command, or a file or
    // a conversation to refer to.
    final vocabulary = ComposerVocabulary.read(context);
    final mentions =
        vocabulary.sessions != null ||
        vocabulary.suggestFiles != null ||
        vocabulary.stashes != null;
    for (var i = caret - 1; i >= 0; i--) {
      final char = text[i];
      if (isBoundary(char)) return null;
      if (i > 0 && !isBoundary(text[i - 1])) continue;
      final query = text.substring(i + 1, caret);
      if (char == '/') return _Trigger(SuggestionKind.command, i, query);
      if (char == '@' && mentions) {
        return _Trigger(SuggestionKind.file, i, query);
      }
    }
    return null;
  }

  /// Horizontal caret position of [offset] relative to the composer box.
  double _caretX(int offset) {
    final caret = _editorKey.currentState?.caretRect(offset);
    final box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (caret == null || box == null || !box.attached) return 12;
    final x = box.globalToLocal(caret.topLeft).dx - 8;
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
    final ComposerEmbed token;
    if (suggestion.kind == SuggestionKind.stash) {
      final stash = ComposerVocabulary.read(context).stash
          ?.call(int.parse(suggestion.id));
      if (stash == null) return;
      token = ComposerStashEmbed.of(stash);
    } else if (suggestion.kind == SuggestionKind.file ||
        suggestion.kind == SuggestionKind.folder) {
      token = ComposerTokenEmbed.file(
        suggestion.value,
        directory: suggestion.kind == SuggestionKind.folder,
      );
    } else {
      token = ComposerTokenEmbed.fromSuggestion(suggestion);
    }
    // The token and a space after it, so the token is never the last thing
    // on its line (see [_padTrailingTokens]).
    final tag = '${token.atom} ';
    _controller
      ..breakUndo()
      ..replace(
        trigger.start,
        caret,
        tag,
        selection: TextSelection.collapsed(offset: trigger.start + tag.length),
      )
      ..breakUndo();
    _focusNode.requestFocus();
  }

  // --- Keyboard ------------------------------------------------------------

  KeyEventResult _handleKey(KeyEvent event) {
    if (event is KeyUpEvent || _isComposing) return KeyEventResult.ignored;
    // Run by the window's keybindings (it sees keys first).
    if (ChatKeys.isHandled(event)) return KeyEventResult.handled;
    // An open picker menu (or tooltip) takes arrows, Enter and Esc first.
    if (FloatingRegistry.handleKey(event) case final result?) return result;
    // Then the keybindings: Enter sends, the menu's keys…
    return ChatKeys.dispatch(event) ?? KeyEventResult.ignored;
  }

  bool get _caretAtStart {
    final selection = _controller.selection;
    return selection.isCollapsed && selection.baseOffset <= 0;
  }

  bool get _caretAtEnd {
    final selection = _controller.selection;
    return selection.isCollapsed && selection.baseOffset >= _controller.length;
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
      // Paste the clipboard as plain text, past the long-paste tag.
      ChatCommandIds.pasteRaw: () => unawaited(_paste(raw: true)),
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
    await insertFiles(files, here: true);
    _focusNode.requestFocus();
  }

  // --- Drag and drop -----------------------------------------------------
  //
  // Files dragged over the composer, from other apps (see [FileDrops]) or
  // from the IDE ([FileDragData]), show where they would go: their tags,
  // faint, in the text at the pointer, the text making room for them. Let
  // go, the tags take their place.

  /// Where the placeholder is in the text, while a drag is over it.
  int? _ghostAt;

  /// The placeholder and the space after it, as they are in the text.
  String _ghost = '';

  /// What the placeholder shows.
  List<ComposerFile> _ghostFiles = const [];

  /// The placeholder is being put in or taken out: no edit of the user's
  /// (see [_handleEditorChanged]), and nothing to undo.
  bool _ghosting = false;

  /// Where in the text [position] (the window's) would put what is let go
  /// there: an offset in the text without the placeholder. Below or
  /// beside the text (the toolbar, the pictures), its end.
  int _dropOffset(Offset position) {
    final end = _controller.length - (_ghostAt == null ? 0 : _ghost.length);
    final editor = _editorKey.currentState;
    final area = editor?.viewportRect;
    if (editor == null || area == null || !area.contains(position)) {
      return end;
    }
    var offset = editor.offsetAt(position) ?? end;
    if (_ghostAt case final ghost? when offset > ghost) {
      offset = math.max(ghost, offset - _ghost.length);
    }
    return offset.clamp(0, end);
  }

  /// Stashes dragged from their page, let go at [position]: their tags
  /// where the text is there.
  void _dropStashes(Offset position, List<StashReference> stashes) {
    if (!mounted) return;
    final at = _dropOffset(position);
    final tags = [
      for (final stash in stashes) '${ComposerStashEmbed.of(stash).atom} ',
    ].join();
    _controller
      ..breakUndo()
      ..replace(
        at,
        at,
        tags,
        selection: TextSelection.collapsed(offset: at + tags.length),
      )
      ..breakUndo();
    _focusNode.requestFocus();
  }

  void _showGhost(Offset position, List<ComposerFile> files) {
    if (!mounted) return;
    final at = _dropOffset(position);
    if (at == _ghostAt && listEquals(files, _ghostFiles)) return;
    final shown = _ghostAt != null;
    _editGhost(() {
      _removeGhost();
      final ghost = '${ComposerGhostEmbed.of(files).atom} ';
      _controller.replaceUnrecorded(at, at, ghost);
      _ghostAt = at;
      _ghost = ghost;
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
    final length = _ghost.length;
    _ghostAt = null;
    _ghost = '';
    _ghostFiles = const [];
    _controller.replaceUnrecorded(at, at + length, '');
  }

  void _editGhost(VoidCallback edit) {
    _ghosting = true;
    try {
      edit();
    } finally {
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

  /// From another app: this machine's files.
  @override
  void fileDrop(Offset position, List<ComposerFile> files) =>
      _dropFiles(position, files, here: true);

  /// [files] let go at [position]; [here], this machine's (else the
  /// project's, dragged from the IDE).
  void _dropFiles(
    Offset position,
    List<ComposerFile> files, {
    required bool here,
  }) {
    if (!mounted) return;
    final at = _ghostAt ?? _dropOffset(position);
    _hideGhost();
    unawaited(insertFiles(files, at: at, here: here));
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
  String? _historyDraft;

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
    final from = _historyAt ?? prompts.length;
    final at = from + step;
    if (at < 0 || at > prompts.length) return;
    _historyDraft ??= _controller.text;
    final String content;
    if (at == prompts.length) {
      content = _historyDraft!;
    } else {
      content = composerContentFromPaste(
        prompts[at],
        ComposerVocabulary.read(context),
        atStart: true,
      );
    }
    _recalling = true;
    try {
      // Going back, at the start: ↑ goes on back; going on, at the end.
      _controller
        ..breakUndo()
        ..replace(
          0,
          _controller.length,
          content,
          selection: TextSelection.collapsed(
            offset: step < 0 ? 0 : content.length,
          ),
        )
        ..breakUndo();
    } finally {
      _recalling = false;
    }
    if (at == prompts.length) {
      _leaveHistory();
    } else {
      _historyAt = at;
      _historyShown = _controller.text;
    }
  }

  // --- Polish --------------------------------------------------------------

  /// The text as the model is given it to polish (see [composerPolishText]).
  ComposerPolishText _polishText() => composerPolishText(_controller.text);

  /// Has the auxiliary model polish the text into a clearer, more specific
  /// prompt (Enhance prompt), its tags, images, code and links kept as they
  /// are, the agent's last turn told to know what it answers; put in its place as one change (⌘Z takes it back), unless the
  /// text changed meanwhile. Why not, in a notification.
  Future<void> _polish() async {
    if (_polishing) return;
    final asked = _polishText();
    if (!asked.hasWords) return;
    final before = _controller.text;
    final notifications = IdeNotificationsScope.maybeOf(context);
    final l10n = context.l10n;
    setState(() => _polishing = true);
    try {
      final String polished;
      try {
        polished = await polishComposerText(
          asked,
          reply: widget.session.lastTurnReply,
          model: widget.session.selected(KernelChoiceKind.model),
          location: widget.session.kernelContext.cwd,
        );
      } on ComposerPolishException catch (error) {
        notifications?.notify(
          IdeSeverity.error,
          l10n.composerPolishFailed(error.message ?? l10n.stashAiNoAnswer),
        );
        return;
      }
      if (!mounted || _controller.text != before) return;
      // One change of its own to undo: not merged with what was typed just
      // before it, nor with what is typed next.
      _controller
        ..breakUndo()
        ..replace(
          0,
          _controller.length,
          polished,
          selection: TextSelection.collapsed(offset: polished.length),
        )
        ..breakUndo();
      _focusNode.requestFocus();
    } finally {
      if (mounted) setState(() => _polishing = false);
    }
  }

  // --- Submit --------------------------------------------------------------

  ComposerMessage _buildMessage() {
    final text = StringBuffer();
    final mentions = <String>[];
    final code = <String, AppendedText>{};
    for (final piece in composerPieces(_controller.text)) {
      switch (piece) {
        case final String data:
          text.write(data);
        case ComposerEmbed(type: ComposerImageEmbed.type, :final data):
          text.write(ComposerImageEmbed.plainText(data));
        case ComposerEmbed(type: ComposerCodeEmbed.type, :final data):
          final reference = ComposerCodeEmbed.decode(data);
          text.write(reference.reference);
          code.putIfAbsent(reference.reference, () => reference);
        case ComposerEmbed(type: ComposerPastedTextEmbed.type, :final data):
          final pasted = ComposerPastedTextEmbed.decode(data);
          text.write(pasted.reference);
          code.putIfAbsent(pasted.reference, () => pasted);
        case ComposerEmbed(type: ComposerStashEmbed.type, :final data):
          final stash = ComposerStashEmbed.decode(data);
          text.write(stash.reference);
          code.putIfAbsent(stash.reference, () => stash);
        case ComposerEmbed(type: ComposerTokenEmbed.type, :final data):
          text.write(ComposerTokenEmbed.plainText(data));
          final token = ComposerTokenEmbed.decode(data);
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
    // Empty while a turn runs, messages queued behind it: the first of them
    // taken up now, as its Send Now.
    if (widget.onSubmit == null && widget.session.isStreaming && !_canSend) {
      if (widget.session.queued.firstOrNull case (final id, _)) {
        widget.session.sendQueuedNow(id);
      }
      return;
    }
    if (_showsStop) return;
    final message = _buildMessage();
    if (message.text.isEmpty && message.images.isEmpty) return;
    if (widget.onSubmit case final onSubmit?) {
      onSubmit(message);
      return;
    }
    widget.session.send(message, editor: widget.openEditor);
    _pool = {};
    _controller.clear();
    _leaveHistory();
    _saveDraft();
    _dismissedTrigger = null;
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    _shownBuilt = _shownOfText();
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
    // Before what is built is told by it (see [_buildInputs]).
    _editor ??= _buildEditor(context);
    final inputs = _buildInputs();
    if (_built case final built? when listEquals(inputs, _builtFrom)) {
      return built;
    }
    _builtFrom = inputs;
    return _built = FloatingLayer(
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
        child: DragTarget<StashDragData>(
          onWillAcceptWithDetails: (details) =>
              details.data.references.isNotEmpty,
          onAcceptWithDetails: (details) =>
              _dropStashes(details.offset, details.data.references),
          builder: (context, stashes, _) => DragTarget<FileDragData>(
            onWillAcceptWithDetails: (details) => details.data.files.isNotEmpty,
            onMove: (details) => _showGhost(details.offset, details.data.files),
            onLeave: (_) => _hideGhost(),
            onAcceptWithDetails: (details) =>
                _dropFiles(details.offset, details.data.files, here: false),
            builder: (context, candidates, rejected) => _buildBox(
              focused: focused || _ghostAt != null || stashes.isNotEmpty,
            ),
          ),
        ),
      ),
    );
  }

  /// What [build] made, and of what ([_buildInputs]): the same again
  /// while none of it changed, so that the session's every change (an
  /// answer's each word, streaming) does not build the box again, its
  /// pickers and buttons.
  Widget? _built;
  List<Object?>? _builtFrom;

  /// The hovers of the toolbar's mode and model pickers and its context
  /// ring, with the keys that do the same in the input.
  late ({String mode, String model, String ring}) _hovers;

  /// All that [build] reads, as it is now: the widget's, the state's, and
  /// the session's that the toolbar shows. A kernel's options are the same
  /// list while they do not change; the kernel among these, the picks'
  /// callbacks built with it stay its.
  List<Object?> _buildInputs() {
    final session = widget.session;
    final l10n = context.l10n;
    const input = {ChatContextKeys.inChatInput: true};
    _hovers = (
      mode: ChatKeys.titleWithKey(
        l10n.composerSetMode,
        ChatCommandIds.openModePicker,
        input,
      ),
      model: ChatKeys.titleWithKey(
        l10n.composerPickModel,
        ChatCommandIds.openModelPicker,
        input,
      ),
      ring: ChatKeys.titleWithKey(
        l10n.composerContextUsage,
        ChatCommandIds.toggleContextPanel,
        const {...input, ChatContextKeys.inChat: true},
      ),
    );
    final model = session.models;
    return [
      session,
      widget.onSubmit == null,
      widget.tapRegionGroupId,
      widget.contextPanelOpen,
      widget.onToggleContextPanel,
      _focusNode.hasFocus,
      _ghostAt != null,
      _shownBuilt,
      _editor,
      _polishing,
      ComposerPolishSetting.current(),
      l10n,
      themeColors,
      _hovers,
      session.kernel,
      _showsStop,
      session.health.noModel,
      session.context?.fraction,
      for (final choice in [
        session.kernelChoice,
        session.modes,
        session.permissions,
        model,
      ]) ...[choice?.options, choice?.selected],
      // What the model's label says of its settings (see
      // SessionModelPicker): their lists are made anew each time.
      if (model != null)
        for (final setting in session.modelSettings(model.selected.id)) ...[
          setting.kind,
          setting.selected,
          setting.options.firstOrNull,
        ],
    ];
  }

  Widget _buildBox({required bool focused}) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _focusNode.requestFocus,
      child: AnimatedContainer(
        key: _boxKey,
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          // The agents window's chat input, editing a sent message too:
          // the color of every bubble, and their line; typed into, the line
          // turns a little towards the accent.
          color: AppColors.bubbleFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.bubbleBorder(focused: focused)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ComposerImages(images: _pool, child: _editor!),
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
        // the editor's scroll view.
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
          child: Listener(
            onPointerDown: _handleClickDown,
            onPointerUp: _handleClickUp,
            onPointerCancel: (_) => _clickDownAt = null,
            child: Listener(
              onPointerDown: _handleMenuPointerDown,
              onPointerUp: _handleMenuPointerUp,
              onPointerCancel: (_) => _menuPressAt = null,
              child: _buildMarkdownEditor(context),
            ),
          ),
        ),
      ),
    );
  }

  // --- Context menu -------------------------------------------------------
  //
  // A right click opens the system's menu, the caret first put at the
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
    final selection = _controller.selection;
    if (_editorKey.currentState?.offsetAt(event.position) case final at?
        when selection.isCollapsed ||
            at < selection.start ||
            at > selection.end) {
      _controller.selection = TextSelection.collapsed(offset: at);
    }
    _focusNode.requestFocus();
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
        enabled: _controller.length > 0,
      ),
    ]);
    final editor = _editorKey.currentState;
    if (!mounted || editor == null) return;
    _focusNode.requestFocus();
    // As their shortcuts do: the selection stays where it is.
    switch (chosen) {
      case 'cut':
        await editor.copy(cut: true);
      case 'copy':
        await editor.copy();
      case 'paste':
        await editor.paste();
      case 'selectAll':
        _selectAll();
    }
  }

  void _selectAll() => _controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: _controller.length,
  );

  // --- Double-click -------------------------------------------------------
  //
  // A double-click with nothing selected selects everything; with text
  // selected it selects a word, as the editor does. Told apart here rather
  // than by the editor: a real click often moves the pointer a pixel or
  // two, past where a drag starts, and then it sees no double-click at all.

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

  void _handleClickDown(PointerDownEvent event) {
    final plainPress =
        event.kind == PointerDeviceKind.mouse &&
        event.buttons == kPrimaryMouseButton &&
        !HardwareKeyboard.instance.isShiftPressed;
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
    // A third click is a click again (no window after a second).
    if (_secondClick) {
      if (_clickOnSelection) return;
      // After the editor's handling of the up, which comes after this:
      // whatever it made of the press (a word, a caret, a drag of a pixel).
      scheduleMicrotask(() {
        if (mounted) _selectAll();
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

  Widget _buildMarkdownEditor(BuildContext context) {
    final colors = themeColors;
    final base = DefaultTextStyle.of(context).style.merge(_textStyle);
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: _minEditorHeight,
        maxHeight: _maxEditorHeight(context),
      ),
      child: MarkdownEditor(
        key: _editorKey,
        controller: _controller,
        focusNode: _focusNode,
        scrollController: _scrollController,
        shrinkWrap: true,
        embeds: const ComposerChips(),
        // A suggested prompt, then the key that takes it as the keybindings
        // label it (`Tab`); alone when it has none. On one line.
        placeholder: switch ((_suggestion, _suggestionKey)) {
          (final suggestion?, final key?) => '$suggestion    $key',
          (final suggestion?, null) => suggestion,
          (null, _) => context.l10n.composerPlaceholder,
        }.replaceAll(RegExp(r'[\x00-\x1f]+'), ' '),
        onKey: _handleKey,
        onPaste: _paste,
        onPasteCopy: (markdown) =>
            renumberPastes(markdown, from: _nextPastedNumber()),
        style: MarkdownEditorStyle(
          text: base,
          selection: AppColors.textSelection,
          caret: colors['editorCursor.foreground'],
          placeholder: TextStyle(
            color: colors['agentsChatInput.placeholderForeground'],
          ),
        ),
      ),
    );
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      child: Row(
        children: [
          // Takes the room left, so the actions sit at the far end; the
          // model's label cut short to fit, scrolls when even that does not.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: PickersRow(
                  maxWidth: constraints.maxWidth,
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
                        tooltip: _hovers.mode,
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
                    // With none to pick, one to set up.
                    if (model != null || session.health.noModel)
                      SessionModelPicker(
                        session: session,
                        pickerKey: _modelPickerKey,
                        tooltip: _hovers.model,
                        tapRegionGroupId: widget.tapRegionGroupId,
                        focusNode: _focusNode,
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (ComposerPolishSetting.current()) ...[
            _PolishButton(
              busy: _polishing,
              enabled: _polishing || _shownBuilt!.polishable,
              onTap: () => unawaited(_polish()),
            ),
            const SizedBox(width: 2),
          ],
          if ((widget.onToggleContextPanel, context) case (
            final onToggle?,
            final usage?,
          )) ...[
            _ContextRing(
              fraction: usage.fraction,
              active: widget.contextPanelOpen,
              // Toggle Context Panel's, which has none by default.
              tooltip: _hovers.ring,
              onTap: onToggle,
            ),
            const SizedBox(width: 2),
          ],
          const SizedBox(width: 2),
          _SendButton(
            streaming: _showsStop,
            enabled: _canSend,
            onSend: _submit,
            onStop: () => stopTurn(this.context, session),
          ),
        ],
      ),
    );
  }
}

/// Polish, Enhance prompt as it says (see [ChatComposerState._polish]): a
/// sparkle, spinning while the model answers; faint with no words to polish.
class _PolishButton extends StatelessWidget {
  const _PolishButton({
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    final active = enabled && !busy;
    final icon = Icon(
      busy ? Codicons.loading : Codicons.sparkle,
      size: 14,
      color: enabled ? colors['icon.foreground'] : AppColors.textFaint,
    );
    return IdeHover(
      message: busy ? l10n.composerPolishing : l10n.composerPolishHint,
      child: HoverBuilder(
        cursor: active ? SystemMouseCursors.click : SystemMouseCursors.basic,
        builder: (context, hovered) => GestureDetector(
          // Keeps the editor's focus.
          onTapDown: (_) {},
          onTap: active ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 23,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active && hovered
                  ? colors['toolbar.hoverBackground']
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: busy ? IdeSpinning(icon) : icon,
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

typedef _ShownOfText = ({
  Object menu,
  Map<int, ImageAttachment> pool,
  bool canSend,
  bool polishable,
});
