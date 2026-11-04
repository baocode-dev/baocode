import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ide/ide_button.dart';
import '../ide/ide_hover.dart';
import '../ide/ide_input.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../workspace/editor_launcher.dart';
import 'port_forwards.dart';
import 'remote_host_settings.dart';
import 'remote_location.dart';

/// The side panel's ports page, of an SSH project's conversation: the
/// ports forwarded for its host ([PortForwards]), each with its address to
/// copy or open in the browser, and to stop; and a port forwarded by
/// hand.
class PortsView extends StatefulWidget {
  const PortsView({super.key, required this.host, this.forwards, this.open});

  final String host;

  /// The app's by default.
  final PortForwards? forwards;

  /// Opens an address in the browser: the system's by default.
  final Future<void> Function(String url)? open;

  @override
  State<PortsView> createState() => _PortsViewState();
}

class _PortsViewState extends State<PortsView> {
  PortForwards get _forwards => widget.forwards ?? PortForwards.instance;

  /// The form to forward a port by hand, while open.
  bool _adding = false;
  ForwardDirection _direction = ForwardDirection.toLocal;
  final _port = TextEditingController();
  final _listen = TextEditingController();
  String? _failure;

  @override
  void dispose() {
    _port.dispose();
    _listen.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final port = int.tryParse(_port.text.trim());
    final listen = int.tryParse(_listen.text.trim());
    if (port == null || port <= 0 || port > 65535) {
      setState(() => _failure = context.l10n.portsPort);
      return;
    }
    try {
      await _forwards.open(
        widget.host,
        PortForwardSpec(
          direction: _direction,
          port: port,
          listen: listen != null && listen > 0 && listen < 65536
              ? listen
              : null,
        ),
      );
      if (!mounted) return;
      setState(() {
        _adding = false;
        _failure = null;
        _port.clear();
        _listen.clear();
      });
    } on Object catch (error) {
      if (mounted) setState(() => _failure = '$error');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _forwards,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final l10n = context.l10n;
    final name = RemoteLocation.hostName(widget.host);
    final forwards = _forwards.of(widget.host);
    return ListView(
      key: const ValueKey('ports-page'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.sidePanelPorts,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            IdeActionButton(
              key: const ValueKey('ports-add'),
              icon: Codicons.add,
              tooltip: l10n.portsAdd,
              onPressed: () => setState(() => _adding = !_adding),
            ),
          ],
        ),
        if (_adding) _form(context, name),
        if (forwards.isEmpty && !_adding)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.portsEmpty(name),
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
        for (final forward in forwards) _row(context, forward, name),
      ],
    );
  }

  Widget _form(BuildContext context, String name) {
    final l10n = context.l10n;
    Widget direction(ForwardDirection value, String label) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: IdeButton(
        label: label,
        secondary: _direction != value,
        onPressed: () => setState(() => _direction = value),
      ),
    );
    return Container(
      key: const ValueKey('ports-form'),
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.partBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            runSpacing: 6,
            children: [
              direction(ForwardDirection.toLocal, l10n.portsHostToHere(name)),
              direction(ForwardDirection.toRemote, l10n.portsHereToHost(name)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: IdeInputBox(
                  key: const ValueKey('ports-port'),
                  controller: _port,
                  placeholder: l10n.portsPort,
                  autofocus: true,
                  onSubmitted: (_) => unawaited(_add()),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: IdeInputBox(
                  key: const ValueKey('ports-listen'),
                  controller: _listen,
                  placeholder: l10n.portsListen,
                  onSubmitted: (_) => unawaited(_add()),
                ),
              ),
              const SizedBox(width: 6),
              IdeButton(
                key: const ValueKey('ports-forward'),
                label: l10n.portsForward,
                onPressed: () => unawaited(_add()),
              ),
            ],
          ),
          if (_failure case final failure?)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                failure,
                style: TextStyle(fontSize: 12, color: AppColors.removed),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, PortForward forward, String name) {
    final l10n = context.l10n;
    final toLocal = forward.direction == ForwardDirection.toLocal;
    final address = toLocal
        ? forward.localUrl
        : '127.0.0.1:${forward.remotePort ?? '?'}';
    final open = widget.open ?? ((url) => openExternal(url).then((_) {}));
    return Container(
      key: ValueKey(('port', forward.direction, forward.spec.port)),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.partBorder)),
      ),
      child: Row(
        children: [
          Icon(
            toLocal ? Codicons.arrowLeft : Codicons.arrowRight,
            size: 14,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${forward.spec.port}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        toLocal
                            ? l10n.portsHostToHere(name)
                            : l10n.portsHereToHost(name),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    if (forward.spec.auto) ...[
                      const SizedBox(width: 6),
                      Text(
                        l10n.portsAuto,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textFaint,
                        ),
                      ),
                    ],
                  ],
                ),
                if (address != null)
                  Text(
                    address,
                    style: TextStyle(fontSize: 12, color: AppColors.accent),
                  ),
                if (forward.error case final error?)
                  Text(
                    error,
                    style: TextStyle(fontSize: 12, color: AppColors.removed),
                  ),
              ],
            ),
          ),
          if (toLocal && address != null)
            IdeActionButton(
              key: ValueKey(('port-open', forward.spec.port)),
              icon: Codicons.globe,
              tooltip: l10n.portsOpen,
              onPressed: () => unawaited(open(address)),
            ),
          if (address != null)
            IdeActionButton(
              key: ValueKey(('port-copy', forward.spec.port)),
              icon: Codicons.copy,
              tooltip: l10n.portsCopy,
              onPressed: () =>
                  unawaited(Clipboard.setData(ClipboardData(text: address))),
            ),
          IdeActionButton(
            key: ValueKey(('port-stop', forward.spec.port)),
            icon: Codicons.close,
            tooltip: l10n.portsStop,
            onPressed: () => unawaited(_forwards.close(forward)),
          ),
        ],
      ),
    );
  }
}
