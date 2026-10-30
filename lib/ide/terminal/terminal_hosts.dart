// Where a terminal shown in several places at once has its view (see
// [TerminalHosts]), and a view taking part ([HostedTerminalView]).

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'terminal_instance.dart';
import 'terminal_view.dart';

/// Which place has each of a window's terminals as its view: the one with
/// the terminal's keyboard focus and its size. A project's terminals show
/// in the chat's panel under the conversation, its side panel's terminal
/// page and the IDE's panel, all live: a place but the one that has it
/// mirrors it (see [TerminalView.mirror]) until pressed, as tmux's latest
/// client.
class TerminalHosts extends ChangeNotifier {
  final Map<TerminalInstance, Object> _hosts = {};
  bool _disposed = false;
  bool _telling = false;

  /// The place showing [terminal]; none while no place does.
  Object? hostOf(TerminalInstance terminal) => _hosts[terminal];

  /// Whether [place] has [terminal] as its view, taking it if no place
  /// does: while building, so the first place built has it, the others
  /// mirroring it.
  bool take(TerminalInstance terminal, Object place) =>
      identical(_hosts.putIfAbsent(terminal, () => place), place);

  /// [place] has [terminal] as its view from now on; where it had, it
  /// mirrors it.
  void claim(TerminalInstance terminal, Object place) {
    if (identical(_hosts[terminal], place)) return;
    _hosts[terminal] = place;
    notifyListeners();
  }

  /// [place] shows none of the terminals but [except]: the others are
  /// free for a place mirroring them. Told after the frame, as this is
  /// done while building, and as a place goes.
  void release(Object place, {TerminalInstance? except}) {
    final before = _hosts.length;
    _hosts.removeWhere(
      (terminal, host) => identical(host, place) && terminal != except,
    );
    if (_hosts.length == before || _telling) return;
    _telling = true;
    scheduleMicrotask(() {
      _telling = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// [instance]'s view in [place] while it is [hosts]'s there (taken if no
/// place has it), else a mirror of it ([builder]'s `mirror`) that takes it
/// when pressed. Not [takes] (its place hidden), a mirror whatever, and
/// the terminal free for another place.
class HostedTerminalView extends StatefulWidget {
  const HostedTerminalView({
    super.key,
    required this.hosts,
    required this.place,
    required this.instance,
    required this.builder,
    this.takes = true,
  });

  final TerminalHosts hosts;
  final Object place;
  final TerminalInstance instance;
  final bool takes;

  /// The [TerminalView], a mirror or not, and what it calls when pressed.
  final Widget Function(bool mirror, VoidCallback onActivate) builder;

  @override
  State<HostedTerminalView> createState() => _HostedTerminalViewState();
}

class _HostedTerminalViewState extends State<HostedTerminalView> {
  @override
  void dispose() {
    widget.hosts.release(widget.place);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.hosts,
    builder: (context, _) {
      final hosts = widget.hosts;
      final place = widget.place;
      final instance = widget.instance;
      hosts.release(place, except: widget.takes ? instance : null);
      final here = widget.takes && hosts.take(instance, place);
      return widget.builder(!here, () => hosts.claim(instance, place));
    },
  );
}
