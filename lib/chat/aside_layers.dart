import 'package:flutter/material.dart';

import 'agent_view.dart';

/// A conversation asked beside another (`/btw`) over that one, as a
/// subagent's is over its session's (see [ConversationLayer]): it comes in
/// from the right as the one under it fades out to the left, and goes back
/// the way it came. The one under stays built, scrolled where it was.
///
/// Built anew as either shows (keyed by it): [over] comes in when
/// [entering]; [leaving], the aside shown just before, goes.
class AsideLayers extends StatefulWidget {
  const AsideLayers({
    super.key,
    required this.under,
    this.over,
    this.entering = false,
    this.leaving,
  }) : assert(over == null || leaving == null);

  /// The conversation the aside was asked beside.
  final Widget under;

  /// The aside shown over it; none while that one shows.
  final Widget? over;

  /// Whether [over] comes in, from [under] shown just before; else it is
  /// there at once.
  final bool entering;

  /// The aside shown just before [under], going back; read once.
  final Widget? leaving;

  @override
  State<AsideLayers> createState() => _AsideLayersState();
}

class _AsideLayersState extends State<AsideLayers>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ConversationLayer.duration,
    value: widget.over != null && !widget.entering ? 1 : 0,
  );
  late final CurvedAnimation _animation = ConversationLayer.curve(_controller);

  /// The aside going back, until it has gone.
  Widget? _leaving;

  @override
  void initState() {
    super.initState();
    if (widget.over != null && widget.entering) {
      _controller.forward();
    } else if (widget.leaving case final leaving?) {
      _leaving = leaving;
      _controller.value = 1;
      _controller.reverse().whenComplete(() {
        if (mounted) setState(() => _leaving = null);
      });
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final over = widget.over ?? _leaving;
    return Stack(
      fit: StackFit.expand,
      children: [
        ConversationLayer(
          entrance: kAlwaysCompleteAnimation,
          cover: over == null ? null : _animation,
          interactive: widget.over == null,
          child: widget.under,
        ),
        if (over != null)
          ConversationLayer(
            entrance: _animation,
            interactive: widget.over != null,
            child: over,
          ),
      ],
    );
  }
}
