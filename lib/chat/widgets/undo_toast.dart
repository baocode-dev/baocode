import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'hover_builder.dart';

/// A note at the bottom of the window that something was done, Undo
/// beside it, rather than a question before: shown for [shown], as long as
/// what was done waits to be done for real (see [Workspace.deleteLater]),
/// one at a time, a newer one in place of the one showing. Undo does
/// [onUndo] (calls it off) and puts it away. As the sidebar's menus look.
void showUndoToast(
  BuildContext context,
  String message, {
  required VoidCallback onUndo,
  required Duration shown,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _UndoToast.current?.call();
  late final OverlayEntry entry;
  // Once: by a newer one, or when it is done, whichever comes first.
  var removed = false;
  void remove() {
    if (removed) return;
    removed = true;
    if (_UndoToast.current == remove) _UndoToast.current = null;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (context) => _UndoToast(
      message: message,
      onUndo: onUndo,
      shown: shown,
      onDone: remove,
    ),
  );
  _UndoToast.current = remove;
  overlay.insert(entry);
}

class _UndoToast extends StatefulWidget {
  const _UndoToast({
    required this.message,
    required this.onUndo,
    required this.shown,
    required this.onDone,
  });

  /// Takes the one showing away.
  static VoidCallback? current;

  final String message;
  final VoidCallback onUndo;
  final Duration shown;
  final VoidCallback onDone;

  @override
  State<_UndoToast> createState() => _UndoToastState();
}

class _UndoToastState extends State<_UndoToast>
    with SingleTickerProviderStateMixin {
  static const _fade = Duration(milliseconds: 150);

  late final _shown = AnimationController(vsync: this, duration: _fade);
  late final Timer _wait;

  /// Going: Undo no longer there to press.
  bool _going = false;

  @override
  void initState() {
    super.initState();
    unawaited(_shown.forward());
    _wait = Timer(widget.shown, _go);
  }

  Future<void> _go() async {
    if (_going) return;
    _wait.cancel();
    setState(() => _going = true);
    await _shown.reverse();
    if (mounted) widget.onDone();
  }

  void _undo() {
    if (_going) return;
    widget.onUndo();
    unawaited(_go());
  }

  @override
  void dispose() {
    _wait.cancel();
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final curved = CurvedAnimation(parent: _shown, curve: Curves.easeOut);
    final style = TextStyle(
      color: colors['menu.foreground'],
      fontSize: 12.5,
      decoration: TextDecoration.none,
    );
    // At the bottom left, over the sidebar it is deleted from (above its
    // settings): clear of the conversation's input.
    return Positioned(
      left: 12,
      bottom: 44,
      child: IgnorePointer(
        ignoring: _going,
        child: FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.3),
              end: Offset.zero,
            ).animate(curved),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
              decoration: BoxDecoration(
                color: colors['menu.background'],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors['menu.border']),
                boxShadow: [
                  BoxShadow(
                    color: colors['widget.shadow'],
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Material(
                type: MaterialType.transparency,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        widget.message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      ),
                    ),
                    const SizedBox(width: 10),
                    HoverBuilder(
                      cursor: SystemMouseCursors.click,
                      builder: (context, hovered) => GestureDetector(
                        onTap: _undo,
                        child: Container(
                          height: 26,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: hovered
                                ? AppColors.hover
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            context.l10n.commonUndo,
                            style: style.copyWith(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
