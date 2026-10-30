import 'dart:async';

import 'package:bao_markdown/bao_markdown.dart';
import 'package:flutter/widgets.dart';

import 'stash_ai.dart';
import 'stash_editor.dart';
import 'stash_store.dart';

/// One stash's text in a [StashEditor], written to its file as it is
/// typed (a moment after), and read again when another window or app
/// changes it. With no [id], a new stash, made ([create]) once something
/// is written in it.
class StashNoteEditor extends StatefulWidget {
  const StashNoteEditor({
    super.key,
    required this.store,
    required this.id,
    required this.create,
    this.generation,
    this.autofocus = false,
    this.placeholder,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 20),
    this.focusNode,
    this.refs,
    this.attachments = false,
    this.scrollController,
  });

  /// Scrolls its text; its own when null.
  final ScrollController? scrollController;

  /// Its pictures and files shown above the text, each once.
  final bool attachments;

  /// What `[[`, `@` and `#` offer in it.
  final StashRefs? refs;

  final StashStore store;
  final int? id;

  /// Makes the stash, with [body]; its number.
  final Future<int> Function(String body) create;

  /// A change of it starts again from the file (as the panel shows again).
  final Object? generation;

  final bool autofocus;
  final String? placeholder;
  final EdgeInsets padding;
  final FocusNode? focusNode;

  @override
  State<StashNoteEditor> createState() => StashNoteEditorState();
}

class StashNoteEditorState extends State<StashNoteEditor> {
  final GlobalKey<StashEditorState> _editorKey = GlobalKey();
  late MarkdownController _controller;
  Timer? _debounce;

  /// The text's as last seen: a change of only the selection is none.
  int _version = 0;

  /// The stash, once it is one.
  int? _id;

  /// Its text as last written or read: what the file has.
  String _saved = '';

  /// The stash's number; null while nothing was written in a new one.
  int? get id => _id;

  /// Those built now, in any window.
  static final Set<StashNoteEditorState> _live = {};

  /// One showing [id]'s stash now, if any: where a change to it is made
  /// for Undo to take it back.
  static StashNoteEditorState? showing(int id) =>
      _live.where((editor) => editor.mounted && editor._id == id).firstOrNull;

  @override
  void initState() {
    super.initState();
    _live.add(this);
    _load();
    widget.store.addListener(_storeChanged);
  }

  @override
  void didUpdateWidget(StashNoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_storeChanged);
      widget.store.addListener(_storeChanged);
    }
    if (widget.id != oldWidget.id && widget.id == _id) return;
    if (widget.id != oldWidget.id ||
        widget.generation != oldWidget.generation) {
      unawaited(flush());
      _controller.removeListener(_changed);
      _controller.dispose();
      _load();
    }
  }

  @override
  void dispose() {
    _live.remove(this);
    unawaited(flush());
    widget.store.removeListener(_storeChanged);
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  void _load() {
    _id = widget.id;
    final note = _id == null ? null : widget.store.byId(_id!);
    final body = note?.body ?? '';
    _saved = body;
    _controller = StashEditor.controllerFor(body);
    _version = _controller.textVersion;
    _controller.addListener(_changed);
  }

  /// The text, its markdown as the file has it.
  String get markdown => _controller.text;

  void _changed() {
    if (_controller.textVersion == _version) return;
    _version = _controller.textVersion;
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(flush()),
    );
  }

  /// Writes what is typed, now.
  Future<void> flush() async {
    _debounce?.cancel();
    _debounce = null;
    final text = markdown;
    if (text == _saved) return;
    final id = _id;
    if (id == null) {
      if (text.trim().isEmpty) return;
      _saved = text;
      _id = await widget.create(text);
      // Written past what it was made with meanwhile.
      if (mounted && markdown != text) await flush();
      return;
    }
    _saved = text;
    await widget.store.update(id, (note) => note.body = text);
  }

  /// The stash, made if it was not yet (a picture is put in a new one).
  Future<int> _ensure() async {
    if (_id case final id?) return id;
    final text = markdown;
    _saved = text;
    return _id = await widget.create(text);
  }

  /// Another window, or app, changed it: shown as it is now, unless what
  /// is typed here is not written yet.
  void _storeChanged() {
    final id = _id;
    if (id == null || !mounted) return;
    final note = widget.store.byId(id);
    if (note == null) return;
    if (note.id != id) {
      // Merged into another.
      _id = note.id;
    }
    if (note.body == _saved || _debounce != null) return;
    if (note.body == markdown) {
      _saved = note.body;
      return;
    }
    final selection = _controller.selection;
    _saved = note.body;
    _controller.text = note.body;
    // Read, not typed: nothing to write back.
    _version = _controller.textVersion;
    _controller.selection = TextSelection.collapsed(
      offset: selection.baseOffset.clamp(0, _controller.length),
    );
  }

  void focusEnd() => _editorKey.currentState?.focusEnd();

  StashEditorState? get editor => _editorKey.currentState;

  @override
  Widget build(BuildContext context) {
    final editor = StashEditor(
      key: _editorKey,
      controller: _controller,
      store: widget.store,
      ensureNote: _ensure,
      autofocus: widget.autofocus,
      placeholder: widget.placeholder,
      padding: widget.padding,
      focusNode: widget.focusNode,
      refs: widget.refs,
      scrollController: widget.scrollController,
      onPolish: (text) => polishStashText(text, note: markdown),
    );
    if (!widget.attachments) return editor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StashAttachments(
          controller: _controller,
          store: widget.store,
          padding: EdgeInsets.fromLTRB(
            widget.padding.left,
            4,
            widget.padding.right,
            8,
          ),
        ),
        Expanded(child: editor),
      ],
    );
  }
}
