import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../vs/editor/common/core/range.dart';
import 'editor_surface_controller.dart';
import 'viewport_layout.dart';

/// Opt-in native-painted editing prototype, not a drop-in IdeEditor replacement.
/// Supports one selection, full-value IME updates, and basic editable text
/// semantics. This is not complete accessibility or Monaco parity: there are no
/// word-navigation semantics, built-in syntax themes, multi-cursors, context menus/
/// selection handles, drag auto-scroll, or Monaco keybindings/undo grouping.
/// Navigation uses the controller's pinned grapheme approximation. Layout
/// reuses compatible shaped paragraphs across edits and paints only visible rows.
class EditorSurface extends StatefulWidget {
  const EditorSurface({
    super.key,
    required this.controller,
    this.focusNode,
    this.style = const TextStyle(
      fontFamily: 'monospace',
      fontSize: 14,
      height: 1.35,
      color: Color(0xffdddddd),
    ),
    this.backgroundColor = const Color(0xff1e1e1e),
    this.selectionColor = const Color(0x664a90e2),
    this.caretColor = const Color(0xffffffff),
    this.wrap = false,
    this.styledLines,
    this.readOnly = false,
  });

  final EditorSurfaceController controller;
  final FocusNode? focusNode;
  final TextStyle style;
  final Color backgroundColor;
  final Color selectionColor;
  final Color caretColor;
  final bool wrap;

  /// Optional one-based token spans, supplied by the active theme/tokenizer.
  final Map<int, List<TextSpan>>? styledLines;

  /// Allows selection and copying, but no user-originated text mutations.
  /// Programmatic changes to [controller] are still reflected in the surface.
  final bool readOnly;

  @override
  State<EditorSurface> createState() => _EditorSurfaceState();
}

class _EditorSurfaceState extends State<EditorSurface> with TextInputClient {
  final GlobalKey _paintKey = GlobalKey();
  late FocusNode _focusNode;
  late bool _ownsFocusNode;
  TextInputConnection? _connection;
  ViewportLayout? _layout;
  TextStyle? _layoutStyle;
  Size? _layoutSize;
  TextDirection? _layoutDirection;
  TextScaler? _layoutScaler;
  bool? _layoutWrap;
  Map<int, List<TextSpan>>? _layoutStyledLines;
  String? _layoutText;
  double _horizontalScroll = 0;
  double _verticalScroll = 0;
  int? _dragPointer;
  int _dragAnchor = 0;
  bool _updatingFromPlatform = false;
  bool _scrollToCaret = false;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onControllerChange);
  }

  @override
  void didUpdateWidget(covariant EditorSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChange);
      widget.controller.addListener(_onControllerChange);
      if (_connection?.attached == true) {
        _connection!.setEditingState(widget.controller.value);
      }
    }
    if (oldWidget.focusNode != widget.focusNode) {
      _focusNode.removeListener(_onFocusChange);
      _detach();
      if (_ownsFocusNode) _focusNode.dispose();
      _ownsFocusNode = widget.focusNode == null;
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode.addListener(_onFocusChange);
      if (_focusNode.hasFocus) _onFocusChange();
    }
    if (oldWidget.readOnly != widget.readOnly) _onFocusChange();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) _scrollToCaret = true;
    if (_focusNode.hasFocus && !widget.readOnly) {
      if (_connection?.attached != true) {
        _connection = TextInput.attach(
          this,
          TextInputConfiguration(
            viewId: View.of(context).viewId,
            inputType: TextInputType.multiline,
            inputAction: TextInputAction.newline,
            autocorrect: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            enableSuggestions: false,
            enableInteractiveSelection: false,
          ),
        );
      }
      _connection!.setEditingState(widget.controller.value);
      _connection!.show();
      _scheduleGeometry();
    } else {
      _detach();
    }
    if (mounted) setState(() {});
  }

  void _detach() {
    _connection?.close();
    _connection = null;
  }

  void _onControllerChange() {
    _scrollToCaret = true;
    if (!_updatingFromPlatform && _connection?.attached == true) {
      _connection!.setEditingState(widget.controller.value);
    }
    if (mounted) setState(() {});
  }

  @override
  TextEditingValue get currentTextEditingValue => widget.controller.value;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    if (!_canEdit || _connection?.attached != true) return;
    _updatingFromPlatform = true;
    try {
      widget.controller.value = value;
    } finally {
      _updatingFromPlatform = false;
    }
  }

  @override
  void performAction(TextInputAction action) {
    if (!_focusNode.hasFocus) return;
    if (_canEdit && action == TextInputAction.newline) {
      widget.controller.replaceSelection('\n');
    }
    if (action == TextInputAction.done) _focusNode.unfocus();
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  bool onFocusReceived() {
    _focusNode.requestFocus();
    return true;
  }

  @override
  void connectionClosed() {
    _connection = null;
    _focusNode.unfocus();
  }

  bool get _canEdit => mounted && _focusNode.hasFocus && !widget.readOnly;

  bool get _canCopy {
    final value = widget.controller.value;
    return mounted &&
        _focusNode.hasFocus &&
        value.selection.isValid &&
        !value.selection.isCollapsed &&
        value.selection.end <= value.text.length;
  }

  void _requestSemanticFocus() {
    if (!_focusNode.canRequestFocus) return;
    _focusNode.requestFocus();
    if (!widget.readOnly) _connection?.show();
  }

  void _setSemanticText(String text) {
    if (!_canEdit) return;
    // A full accessibility replacement commits any active composition, just
    // like Flutter's editable text semantics. Never normalize the raw text.
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _setSemanticSelection(TextSelection selection) {
    if (!mounted || !_focusNode.hasFocus || !selection.isValid) return;
    // Selection commands use the controller's composition-commit policy;
    // exposing semantics alone never changes the editing value or composition.
    widget.controller.select(selection.baseOffset, selection.extentOffset);
  }

  void _moveSemanticCursor(int direction, bool extendSelection) {
    if (!mounted || !_focusNode.hasFocus) return;
    widget.controller.moveHorizontal(
      direction,
      extend: extendSelection,
      collapseSelection: false,
    );
  }

  void _invokeTextAction(Intent intent) {
    final actionContext = _paintKey.currentContext;
    if (mounted && _focusNode.hasFocus && actionContext != null) {
      Actions.maybeInvoke(actionContext, intent);
    }
  }

  Future<void> _copyOrCut(CopySelectionTextIntent intent) {
    final controller = widget.controller;
    return intent.collapseSelection
        ? controller.cut(
            canEdit: () => _canEdit && identical(widget.controller, controller),
          )
        : controller.copy();
  }

  Future<void> _paste(PasteTextIntent intent) {
    final controller = widget.controller;
    return controller.paste(
      canEdit: () => _canEdit && identical(widget.controller, controller),
    );
  }

  // macOS can deliver editing keys as native selectors instead of key events.
  // Unknown selectors are deliberately left alone rather than guessed.
  @override
  void performSelector(String selectorName) {
    if (!_focusNode.hasFocus) return;
    final controller = widget.controller;
    switch (selectorName) {
      case 'deleteBackward:':
        if (_canEdit) controller.deleteBackward();
      case 'deleteForward:':
        if (_canEdit) controller.deleteForward();
      case 'moveLeft:':
      case 'moveBackward:':
        controller.moveHorizontal(-1);
      case 'moveRight:':
      case 'moveForward:':
        controller.moveHorizontal(1);
      case 'moveLeftAndModifySelection:':
        controller.moveHorizontal(-1, extend: true);
      case 'moveRightAndModifySelection:':
        controller.moveHorizontal(1, extend: true);
      case 'moveUp:':
        _moveVertical(-1);
      case 'moveDown:':
        _moveVertical(1);
      case 'moveUpAndModifySelection:':
        _moveVertical(-1, extend: true);
      case 'moveDownAndModifySelection:':
        _moveVertical(1, extend: true);
      case 'copy:':
        _invokeTextAction(CopySelectionTextIntent.copy);
      case 'cut:':
        _invokeTextAction(
          const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
        );
      case 'paste:':
        _invokeTextAction(
          const PasteTextIntent(SelectionChangedCause.keyboard),
        );
      case 'selectAll:':
        _invokeTextAction(
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
      case 'undo:':
        if (_canEdit) controller.undo();
      case 'redo:':
        if (_canEdit) controller.redo();
      default:
        break;
    }
  }

  void _moveVertical(int direction, {bool extend = false}) {
    final layout = _layout;
    if (layout == null) return;
    final controller = widget.controller;
    final selection = controller.value.selection;
    final origin = layout.caretRect(
      selection.isValid ? selection.extentOffset : 0,
    );
    final target = layout.hitTest(
      Offset(origin.left, origin.center.dy + direction * origin.height),
    );
    controller.select(
      extend && selection.isValid ? selection.baseOffset : target,
      target,
    );
  }

  void _scheduleGeometry() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _layout == null) return;
      final render = _paintKey.currentContext?.findRenderObject();
      if (render is! RenderBox || !render.hasSize) return;
      final layout = _layout!;
      final selection = widget.controller.value.selection;
      final offset = selection.isValid ? selection.extentOffset : 0;
      final caret = layout.caretRect(
        offset.clamp(0, layout.snapshot.text.length),
        affinity: selection.affinity,
      );
      final h = layout.viewportSize.height;
      final w = layout.viewportSize.width;
      final maxVertical = math.max(0.0, layout.contentHeight - h);
      final maxHorizontal = math.max(
        0.0,
        layout.rows.fold<double>(
              0,
              (maxWidth, row) => math.max(maxWidth, row.left + row.width),
            ) -
            w,
      );
      final nextV =
          (caret.top < 0
                  ? _verticalScroll + caret.top
                  : caret.bottom > h
                  ? _verticalScroll + caret.bottom - h
                  : _verticalScroll)
              .clamp(0.0, maxVertical);
      final nextH =
          (caret.left < 0
                  ? _horizontalScroll + caret.left
                  : caret.right > w
                  ? _horizontalScroll + caret.right - w
                  : _horizontalScroll)
              .clamp(0.0, maxHorizontal);
      if (_scrollToCaret) {
        _scrollToCaret = false;
        if (nextV != _verticalScroll || nextH != _horizontalScroll) {
          setState(() {
            _verticalScroll = nextV;
            _horizontalScroll = nextH;
            layout.setScrollOffset(horizontal: nextH, vertical: nextV);
          });
        }
      }
      // Selection/reveal still scrolls a read-only or unfocused surface. Only
      // the platform IME geometry requires an attached input connection.
      if (_connection?.attached != true) return;
      _connection!.setEditableSizeAndTransform(
        render.size,
        render.getTransformTo(null),
      );
      _connection!.updateStyle(
        TextInputStyle(
          fontFamily: widget.style.fontFamily,
          fontSize: widget.style.fontSize,
          fontWeight: widget.style.fontWeight,
          textDirection: Directionality.of(context),
          textAlign: TextAlign.start,
        ),
      );
      _connection!.setCaretRect(
        layout.caretRect(
          offset.clamp(0, layout.snapshot.text.length),
          affinity: selection.affinity,
        ),
      );
      final composing = widget.controller.value.composing;
      Rect composingRect = layout.caretRect(
        offset.clamp(0, layout.snapshot.text.length),
      );
      if (composing.isValid &&
          !composing.isCollapsed &&
          composing.start >= 0 &&
          composing.end <= layout.snapshot.text.length) {
        final boxes = layout.selectionRects(
          Range.fromPositions(
            layout.snapshot.positionAtOffset(composing.start),
            layout.snapshot.positionAtOffset(composing.end),
          ),
        );
        if (boxes.isNotEmpty) {
          composingRect = boxes.reduce((a, b) => a.expandToInclude(b));
        } else {
          composingRect = layout.caretRect(composing.start);
        }
      }
      _connection!.setComposingRect(composingRect);
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    _focusNode.requestFocus();
    if (_layout == null) return;
    _dragPointer = event.pointer;
    _dragAnchor = _layout!.hitTest(event.localPosition);
    widget.controller.select(_dragAnchor, _dragAnchor);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_dragPointer != event.pointer || _layout == null) return;
    widget.controller.select(
      _dragAnchor,
      _layout!.hitTest(event.localPosition),
    );
  }

  void _onPointerUp(PointerEvent event) {
    if (_dragPointer == event.pointer) _dragPointer = null;
  }

  void _onScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _layout == null) return;
    _scrollToCaret = false;
    final maxV = math.max(
      0.0,
      _layout!.contentHeight - _layout!.viewportSize.height,
    );
    final maxH = math.max(
      0.0,
      _layout!.rows.fold<double>(
            0,
            (width, row) => math.max(width, row.left + row.width),
          ) -
          _layout!.viewportSize.width,
    );
    setState(() {
      _verticalScroll = (_verticalScroll + event.scrollDelta.dy).clamp(
        0.0,
        maxV,
      );
      _horizontalScroll = (_horizontalScroll + event.scrollDelta.dx).clamp(
        0.0,
        maxH,
      );
      _layout!.setScrollOffset(
        horizontal: _horizontalScroll,
        vertical: _verticalScroll,
      );
    });
    _scheduleGeometry();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_focusNode.hasFocus ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final modifier = keyboard.isMetaPressed || keyboard.isControlPressed;
    final shift = keyboard.isShiftPressed;
    final key = event.logicalKey;
    final controller = widget.controller;
    if (modifier) {
      if (key == LogicalKeyboardKey.keyA) {
        _invokeTextAction(
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
        );
      } else if (key == LogicalKeyboardKey.keyC) {
        _invokeTextAction(CopySelectionTextIntent.copy);
      } else if (key == LogicalKeyboardKey.keyX) {
        _invokeTextAction(
          const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
        );
      } else if (key == LogicalKeyboardKey.keyV) {
        _invokeTextAction(
          const PasteTextIntent(SelectionChangedCause.keyboard),
        );
      } else if (key == LogicalKeyboardKey.keyZ) {
        if (_canEdit) {
          if (shift) {
            controller.redo();
          } else {
            controller.undo();
          }
        }
      } else if (key == LogicalKeyboardKey.keyY) {
        if (_canEdit) controller.redo();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      controller.moveHorizontal(
        key == LogicalKeyboardKey.arrowLeft ? -1 : 1,
        extend: shift,
      );
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      if (_layout == null) return KeyEventResult.ignored;
      _moveVertical(key == LogicalKeyboardKey.arrowUp ? -1 : 1, extend: shift);
    } else if (key == LogicalKeyboardKey.backspace) {
      if (_canEdit) controller.deleteBackward();
    } else if (key == LogicalKeyboardKey.delete) {
      if (_canEdit) controller.deleteForward();
    } else if (key == LogicalKeyboardKey.enter) {
      if (_canEdit) controller.replaceSelection('\n');
    } else if (key == LogicalKeyboardKey.tab) {
      if (_canEdit) controller.replaceSelection('\t');
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget _textSemantics(Widget child, TextDirection direction) {
    final value = widget.controller.value;
    final selection = value.selection;
    final validSelection =
        selection.isValid && selection.end <= value.text.length;
    final focused = _focusNode.hasFocus;
    return Semantics(
      container: true,
      textField: true,
      multiline: true,
      readOnly: widget.readOnly,
      focused: _focusNode.canRequestFocus ? focused : null,
      textDirection: direction,
      value: value.text,
      onFocus: _focusNode.canRequestFocus ? _requestSemanticFocus : null,
      onTap: _focusNode.canRequestFocus ? _requestSemanticFocus : null,
      onSetText: _canEdit ? _setSemanticText : null,
      onSetSelection: focused ? _setSemanticSelection : null,
      onMoveCursorBackwardByCharacter:
          focused && validSelection && selection.extentOffset > 0
          ? (extend) => _moveSemanticCursor(-1, extend)
          : null,
      onMoveCursorForwardByCharacter:
          focused &&
              validSelection &&
              selection.extentOffset < value.text.length
          ? (extend) => _moveSemanticCursor(1, extend)
          : null,
      onCopy: _canCopy
          ? () => _invokeTextAction(CopySelectionTextIntent.copy)
          : null,
      onCut: _canEdit && _canCopy
          ? () => _invokeTextAction(
              const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
            )
          : null,
      onPaste: _canEdit
          ? () => _invokeTextAction(
              const PasteTextIntent(SelectionChangedCause.keyboard),
            )
          : null,
      // Flutter has no built-in select-all semantics action. Expose a localized
      // custom action, backed by the same public intent as keyboard commands.
      customSemanticsActions: focused && value.text.isNotEmpty
          ? {
              CustomSemanticsAction(
                label:
                    Localizations.of<MaterialLocalizations>(
                      context,
                      MaterialLocalizations,
                    )?.selectAllButtonLabel ??
                    'Select all',
              ): () => _invokeTextAction(
                const SelectAllTextIntent(SelectionChangedCause.keyboard),
              ),
            }
          : null,
      child: _TextSelectionSemantics(
        selection: validSelection ? selection : null,
        // The editor is one document node, not one node per painted visible row.
        child: ExcludeSemantics(child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        assert(
          constraints.hasBoundedWidth && constraints.hasBoundedHeight,
          'EditorSurface needs bounded width and height',
        );
        final size = constraints.biggest;
        final direction = Directionality.of(context);
        final scaler = MediaQuery.textScalerOf(context);
        final snapshot = widget.controller.document.snapshot;
        if (_layout == null ||
            _layoutText != snapshot.text ||
            _layoutStyle != widget.style ||
            _layoutSize != size ||
            _layoutDirection != direction ||
            _layoutScaler != scaler ||
            _layoutWrap != widget.wrap ||
            !identical(_layoutStyledLines, widget.styledLines)) {
          final previousLayout = _layout;
          _layout = ViewportLayout(
            snapshot: snapshot,
            style: widget.style,
            viewportSize: size,
            wrap: widget.wrap && size.width > 0,
            textDirection: direction,
            textScaler: scaler,
            styledLines: widget.styledLines,
            previousLayout: previousLayout,
            horizontalScrollOffset: _horizontalScroll,
            verticalScrollOffset: _verticalScroll,
          );
          previousLayout?.dispose();
          _layoutText = snapshot.text;
          _layoutStyle = widget.style;
          _layoutSize = size;
          _layoutDirection = direction;
          _layoutScaler = scaler;
          _layoutWrap = widget.wrap;
          _layoutStyledLines = widget.styledLines;
        }
        if (_scrollToCaret || _connection?.attached == true) {
          _scheduleGeometry();
        }
        final paintedSurface = MouseRegion(
          cursor: SystemMouseCursors.text,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerUp,
            onPointerSignal: _onScroll,
            child: CustomPaint(
              key: _paintKey,
              size: size,
              painter: _EditorSurfacePainter(
                layout: _layout!,
                value: widget.controller.value,
                background: widget.backgroundColor,
                selectionColor: widget.selectionColor,
                caretColor: widget.caretColor,
                focused: _focusNode.hasFocus,
              ),
            ),
          ),
        );
        return Actions(
          actions: <Type, Action<Intent>>{
            CopySelectionTextIntent: _EditorTextAction<CopySelectionTextIntent>(
              enabled: (intent) =>
                  _canCopy && (!intent.collapseSelection || _canEdit),
              onInvoke: _copyOrCut,
            ),
            PasteTextIntent: _EditorTextAction<PasteTextIntent>(
              enabled: (_) => _canEdit,
              onInvoke: _paste,
            ),
            SelectAllTextIntent: _EditorTextAction<SelectAllTextIntent>(
              enabled: (_) =>
                  mounted &&
                  _focusNode.hasFocus &&
                  widget.controller.value.text.isNotEmpty,
              onInvoke: (_) {
                widget.controller.selectAll();
                return null;
              },
            ),
          },
          child: Focus(
            focusNode: _focusNode,
            includeSemantics: false,
            onKeyEvent: _onKey,
            child: _textSemantics(paintedSurface, direction),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChange);
    _focusNode.removeListener(_onFocusChange);
    _detach();
    if (_ownsFocusNode) _focusNode.dispose();
    _layout?.dispose();
    super.dispose();
  }
}

class _EditorTextAction<T extends Intent> extends Action<T> {
  _EditorTextAction({required this.enabled, required this.onInvoke});

  final bool Function(T) enabled;
  final Object? Function(T) onInvoke;

  @override
  bool isEnabled(T intent) => enabled(intent);

  @override
  Object? invoke(T intent) => isEnabled(intent) ? onInvoke(intent) : null;
}

/// [Semantics] exposes editing callbacks, but only the public rendering API
/// exposes selection base/extent. Merge this annotation into its document node.
class _TextSelectionSemantics extends SingleChildRenderObjectWidget {
  const _TextSelectionSemantics({
    required this.selection,
    required super.child,
  });

  final TextSelection? selection;

  @override
  _RenderTextSelectionSemantics createRenderObject(BuildContext context) =>
      _RenderTextSelectionSemantics(selection);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTextSelectionSemantics renderObject,
  ) {
    renderObject.selection = selection;
  }
}

class _RenderTextSelectionSemantics extends RenderProxyBox {
  _RenderTextSelectionSemantics(this._selection);

  TextSelection? _selection;

  set selection(TextSelection? value) {
    if (_selection == value) return;
    _selection = value;
    markNeedsSemanticsUpdate();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    if (_selection != null) config.textSelection = _selection;
  }
}

class _EditorSurfacePainter extends CustomPainter {
  const _EditorSurfacePainter({
    required this.layout,
    required this.value,
    required this.background,
    required this.selectionColor,
    required this.caretColor,
    required this.focused,
  });

  final ViewportLayout layout;
  final TextEditingValue value;
  final Color background;
  final Color selectionColor;
  final Color caretColor;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final selection = value.selection;
    if (selection.isValid && !selection.isCollapsed) {
      final range = Range.fromPositions(
        layout.snapshot.positionAtOffset(selection.start),
        layout.snapshot.positionAtOffset(selection.end),
      );
      final paint = Paint()..color = selectionColor;
      for (final rect in layout.selectionRects(range)) {
        canvas.drawRect(rect, paint);
      }
    }
    layout.paintVisibleText(canvas);
    final composing = value.composing;
    if (composing.isValid &&
        !composing.isCollapsed &&
        composing.start >= 0 &&
        composing.end <= layout.snapshot.text.length) {
      final range = Range.fromPositions(
        layout.snapshot.positionAtOffset(composing.start),
        layout.snapshot.positionAtOffset(composing.end),
      );
      final paint = Paint()..color = caretColor;
      for (final rect in layout.selectionRects(range)) {
        canvas.drawRect(
          Rect.fromLTWH(rect.left, rect.bottom - 1, rect.width, 1),
          paint,
        );
      }
    }
    if (focused) {
      final caret = layout.caretRect(
        selection.isValid ? selection.extentOffset : 0,
        affinity: selection.affinity,
      );
      canvas.drawRect(caret, Paint()..color = caretColor);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EditorSurfacePainter old) =>
      old.layout != layout ||
      old.value != value ||
      old.background != background ||
      old.selectionColor != selectionColor ||
      old.caretColor != caretColor ||
      old.focused != focused;
}
