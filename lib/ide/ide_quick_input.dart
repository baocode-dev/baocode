import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/cursor_theme.dart';
import 'ide_fuzzy.dart';

/// One row of the quick input list (files, commands or a message).
class IdeQuickPickItem {
  const IdeQuickPickItem({
    required this.label,
    this.labelMatches = const [],
    this.description,
    this.descriptionMatches = const [],
    this.icon,
    this.keybinding,
    this.group,
    this.onAccept,
  });

  final String label;
  final List<int> labelMatches;

  /// Muted text after the label, e.g. a file's folder.
  final String? description;
  final List<int> descriptionMatches;
  final Widget? icon;

  /// A formatted keybinding shown at the right.
  final String? keybinding;

  /// Shown at the right of the first row of a group, e.g. `recently used`.
  final String? group;

  /// Null makes the row an informational message that cannot be picked.
  final VoidCallback? onAccept;
}

/// VS Code's quick input: a filter box at the top center of the window with a
/// list under it, shared by Quick Open, the command palette and Go to Line.
/// The owner computes rows from the text (whose prefix picks the mode).
class IdeQuickInput extends StatefulWidget {
  const IdeQuickInput({
    super.key,
    required this.initialText,
    required this.itemsFor,
    required this.onClose,
    this.placeholderFor,
    this.refresh,
  });

  final String initialText;
  final List<IdeQuickPickItem> Function(String text) itemsFor;
  final String Function(String text)? placeholderFor;

  /// Closes the input; called before an accepted item runs.
  final VoidCallback onClose;

  /// Recomputes the rows when it notifies, e.g. when a file index loads.
  final Listenable? refresh;

  static const rowHeight = 24.0;
  static const maxVisibleRows = 14;

  @override
  State<IdeQuickInput> createState() => IdeQuickInputState();
}

class IdeQuickInputState extends State<IdeQuickInput> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  final FocusNode _focusNode = FocusNode(debugLabel: 'ide quick input');
  final ScrollController _scroll = ScrollController();
  List<IdeQuickPickItem> _items = const [];
  int _selected = 0;

  String get text => _controller.text;

  /// Replaces the text (e.g. switching mode while open) and selects it.
  void setText(String value, {bool selectAll = false}) {
    _controller.value = TextEditingValue(
      text: value,
      selection: selectAll
          ? TextSelection(baseOffset: 0, extentOffset: value.length)
          : TextSelection.collapsed(offset: value.length),
    );
    _focusNode.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    _controller.selection = TextSelection.collapsed(
      offset: widget.initialText.length,
    );
    _controller.addListener(_recompute);
    widget.refresh?.addListener(_recompute);
    _items = widget.itemsFor(_controller.text);
    _selected = _firstSelectable();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(IdeQuickInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refresh != widget.refresh) {
      oldWidget.refresh?.removeListener(_recompute);
      widget.refresh?.addListener(_recompute);
    }
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_recompute);
    _controller.dispose();
    _focusNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String? _lastText;

  void _recompute() {
    if (!mounted) return;
    final textChanged = _lastText != _controller.text;
    _lastText = _controller.text;
    setState(() {
      _items = widget.itemsFor(_controller.text);
      if (textChanged || _selected >= _items.length) {
        _selected = _firstSelectable();
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
    });
  }

  int _firstSelectable() {
    final index = _items.indexWhere((item) => item.onAccept != null);
    return index < 0 ? 0 : index;
  }

  void _move(int delta) {
    final selectable = [
      for (var i = 0; i < _items.length; i++)
        if (_items[i].onAccept != null) i,
    ];
    if (selectable.isEmpty) return;
    var at = selectable.indexOf(_selected);
    if (at < 0) at = 0;
    at = delta.abs() == 1
        ? (at + delta) % selectable.length
        : (at + delta).clamp(0, selectable.length - 1);
    setState(() => _selected = selectable[at]);
    _reveal();
  }

  void _reveal() {
    if (!_scroll.hasClients) return;
    const row = IdeQuickInput.rowHeight;
    final top = _selected * row;
    final position = _scroll.position;
    if (top < position.pixels) {
      _scroll.jumpTo(top);
    } else if (top + row > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(top + row - position.viewportDimension);
    }
  }

  void _accept([int? index]) {
    final i = index ?? _selected;
    if (i < 0 || i >= _items.length) return;
    final action = _items[i].onAccept;
    if (action == null) return;
    widget.onClose();
    action();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
    } else if (key == LogicalKeyboardKey.pageDown) {
      _move(IdeQuickInput.maxVisibleRows - 1);
    } else if (key == LogicalKeyboardKey.pageUp) {
      _move(-(IdeQuickInput.maxVisibleRows - 1));
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) _accept();
    } else if (key == LogicalKeyboardKey.tab) {
      // Keep focus in the input, as VS Code does.
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = widget.placeholderFor?.call(_controller.text);
    final visibleRows = math.min(_items.length, IdeQuickInput.maxVisibleRows);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(600.0, constraints.maxWidth - 32);
        return Stack(
          children: [
            // A click outside dismisses, as focus loss does in VS Code.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onClose,
              ),
            ),
            Positioned(
              top: 6,
              left: (constraints.maxWidth - width) / 2,
              width: width,
              child: Material(
                color: CursorColors.surfaceRaised,
                elevation: 12,
                shadowColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: const BorderSide(color: CursorColors.borderStrong),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                      child: Focus(
                        canRequestFocus: false,
                        skipTraversal: true,
                        onKeyEvent: _onKey,
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          autocorrect: false,
                          enableSuggestions: false,
                          cursorColor: CursorColors.accent,
                          cursorWidth: 1.5,
                          style: const TextStyle(
                            color: CursorColors.textPrimary,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: placeholder,
                            hintStyle: const TextStyle(
                              color: CursorColors.textFaint,
                              fontSize: 13,
                            ),
                            filled: true,
                            fillColor: CursorColors.background,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 7,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(3),
                              borderSide: const BorderSide(
                                color: CursorColors.borderStrong,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(3),
                              borderSide: const BorderSide(
                                color: CursorColors.accent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_items.isNotEmpty)
                      SizedBox(
                        height: visibleRows * IdeQuickInput.rowHeight,
                        child: ListView.builder(
                          controller: _scroll,
                          padding: EdgeInsets.zero,
                          itemExtent: IdeQuickInput.rowHeight,
                          itemCount: _items.length,
                          itemBuilder: (context, index) => _QuickPickRow(
                            item: _items[index],
                            selected: index == _selected,
                            onTap: () => _accept(index),
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _QuickPickRow extends StatefulWidget {
  const _QuickPickRow({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final IdeQuickPickItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_QuickPickRow> createState() => _QuickPickRowState();
}

class _QuickPickRowState extends State<_QuickPickRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final message = item.onAccept == null;
    const highlight = TextStyle(
      color: Color(0xFF6FB3FF),
      fontWeight: FontWeight.w600,
    );
    final background = widget.selected && !message
        ? const Color(0x3D4C9DFF)
        : _hover && !message
        ? CursorColors.hover
        : Colors.transparent;
    return MouseRegion(
      cursor: message ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: message ? null : widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            children: [
              if (item.icon case final icon?) ...[
                SizedBox(width: 16, child: Center(child: icon)),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      ...ideHighlightSpans(
                        item.label,
                        item.labelMatches,
                        highlight,
                        style: TextStyle(
                          color: message
                              ? CursorColors.textMuted
                              : CursorColors.textPrimary,
                          fontSize: 12.5,
                        ),
                      ),
                      if (item.description case final description?
                          when description.isNotEmpty) ...[
                        const TextSpan(text: '  '),
                        ...ideHighlightSpans(
                          description,
                          item.descriptionMatches,
                          highlight,
                          style: const TextStyle(
                            color: CursorColors.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (item.group case final group?)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    group,
                    style: const TextStyle(
                      color: CursorColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ),
              if (item.keybinding case final keybinding?)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: IdeKeycap(keybinding),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A keybinding label drawn as a small key cap.
class IdeKeycap extends StatelessWidget {
  const IdeKeycap(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: CursorColors.text,
          fontSize: 11,
          height: 1.3,
        ),
      ),
    );
  }
}
