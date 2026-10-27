import 'dart:async';

import 'package:flutter/widgets.dart';

/// Shows [child] in place of the one before it (another key) once it is
/// ready: until then the one before stays, and the new one is laid out
/// unseen. Ready once nothing in it holds it back (see [ShownWhenReady.hold])
/// after its first frame, or after [wait] whatever holds it: a file's
/// preview read, compared, scrolled to its change and colored, rather than
/// each step of that shown in turn.
class ShownWhenReady extends StatefulWidget {
  const ShownWhenReady({
    super.key,
    required this.child,
    this.wait = const Duration(milliseconds: 500),
  });

  final Widget child;
  final Duration wait;

  /// Holds back what [context] is in from being shown, until the callback
  /// returned is called; null where nothing waits for it.
  static VoidCallback? hold(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_Readiness>()?.entry._hold();

  @override
  State<ShownWhenReady> createState() => _ShownWhenReadyState();
}

class _Entry {
  _Entry(this.child, this.onChanged);

  Widget child;
  final VoidCallback onChanged;
  int _holds = 0;
  bool shown = false;

  VoidCallback? _hold() {
    if (shown) return null;
    _holds++;
    var released = false;
    return () {
      if (released) return;
      released = true;
      _holds--;
      onChanged();
    };
  }

  bool get held => _holds > 0;
}

class _ShownWhenReadyState extends State<ShownWhenReady> {
  /// What shows; what is to show next, laid out unseen until ready.
  late _Entry _shown = _Entry(widget.child, _check)..shown = true;
  _Entry? _next;
  Timer? _timeout;
  bool _checkScheduled = false;

  @override
  void didUpdateWidget(ShownWhenReady oldWidget) {
    super.didUpdateWidget(oldWidget);
    final child = widget.child;
    if (Widget.canUpdate(_shown.child, child) && _next == null) {
      _shown.child = child;
      return;
    }
    if (_next case final next? when Widget.canUpdate(next.child, child)) {
      next.child = child;
      return;
    }
    if (Widget.canUpdate(_shown.child, child)) {
      // Back to what shows: what was to come is dropped.
      _shown.child = child;
      _drop();
      return;
    }
    _timeout?.cancel();
    _next = _Entry(child, _check);
    _timeout = Timer(widget.wait, () => _show(force: true));
    _check();
  }

  /// Whether what is to show is ready, after this frame.
  void _check() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      _show();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _show({bool force = false}) {
    final next = _next;
    if (!mounted || next == null || (next.held && !force)) return;
    _drop();
    setState(() {
      _shown = next..shown = true;
    });
  }

  void _drop() {
    _timeout?.cancel();
    _timeout = null;
    _next = null;
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  Widget _build(_Entry entry) => KeyedSubtree(
    key: ObjectKey(entry),
    child: Opacity(
      opacity: identical(entry, _shown) ? 1 : 0,
      child: IgnorePointer(
        ignoring: !identical(entry, _shown),
        child: _Readiness(entry: entry, child: entry.child),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // A stack either way: what shows keeps its state as the next comes.
    return Stack(
      fit: StackFit.expand,
      children: [if (_next case final next?) _build(next), _build(_shown)],
    );
  }
}

class _Readiness extends InheritedWidget {
  const _Readiness({required this.entry, required super.child});

  final _Entry entry;

  @override
  bool updateShouldNotify(_Readiness oldWidget) => false;
}
