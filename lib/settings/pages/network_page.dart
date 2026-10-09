import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/ide_button.dart';
import '../../ide/ide_menu.dart';
import '../../l10n/l10n.dart';
import '../../network/network_proxy.dart';
import '../../theme/codicons.dart';
import '../user_settings.dart';
import 'settings_dropdown.dart';
import 'settings_widgets.dart';

/// Settings → Network: the proxy BaoCode and the Claude Code it starts go
/// through (`http.proxyMode`, `http.proxy`), the one in use now, and a
/// test of it.
class NetworkSettingsPage extends StatefulWidget {
  const NetworkSettingsPage({
    super.key,
    this.settings,
    this.detect = currentProxyRoute,
    this.probe = probeConnection,
  });

  /// settings.json; none under test, where choices are not kept.
  final UserSettings? settings;

  /// The proxy in use now.
  final Future<ProxyRoute> Function() detect;

  /// How long [probeUrl] takes to answer through it.
  final Future<Duration> Function(Uri url) probe;

  /// What Test Connection asks: Claude Code's API, the one that has to
  /// get through.
  static final probeUrl = Uri.parse('https://api.anthropic.com/');

  static String modeName(BuildContext context, ProxyMode mode) {
    final l10n = context.l10n;
    return switch (mode) {
      ProxyMode.system => l10n.networkProxySystem,
      ProxyMode.manual => l10n.networkProxyManual,
      ProxyMode.off => l10n.networkProxyOff,
    };
  }

  @override
  State<NetworkSettingsPage> createState() => _NetworkSettingsPageState();
}

/// Test Connection's answer.
sealed class _Probe {
  const _Probe();
}

class _Probing extends _Probe {
  const _Probing();
}

class _Reached extends _Probe {
  const _Reached(this.time);
  final Duration time;
}

class _Failed extends _Probe {
  const _Failed(this.error);
  final String error;
}

class _NetworkSettingsPageState extends State<NetworkSettingsPage> {
  /// The proxy in use, once detected; null while it is.
  ProxyRoute? _route;

  /// What was typed as the address, when it is not one.
  String? _invalid;

  _Probe? _probe;

  int _detecting = 0;

  @override
  void initState() {
    super.initState();
    widget.settings?.addListener(_changed);
    unawaited(_detect());
  }

  @override
  void dispose() {
    widget.settings?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    setState(() => _probe = null);
    unawaited(_detect());
  }

  Future<void> _detect() async {
    final asked = ++_detecting;
    if (_route != null) setState(() => _route = null);
    final route = await widget.detect();
    if (mounted && asked == _detecting) setState(() => _route = route);
  }

  Future<void> _test() async {
    setState(() => _probe = const _Probing());
    _Probe probe;
    try {
      probe = _Reached(await widget.probe(NetworkSettingsPage.probeUrl));
    } on Object catch (error) {
      probe = _Failed(_message(error));
    }
    if (mounted) setState(() => _probe = probe);
  }

  /// [error] in a line: a socket's message without its class.
  static String _message(Object error) => switch (error) {
    TimeoutException() => 'timed out',
    _ => '$error'.replaceFirst(RegExp(r'^\w+Exception:\s*'), ''),
  };

  void _write(String key, Object? value) {
    final settings = widget.settings;
    if (settings == null) return;
    unawaited(
      settings.update(key, value).catchError((Object error) {
        // A settings file that does not parse is left as it is; its error
        // is shown.
        debugPrint('$key not kept: $error');
      }),
    );
  }

  void _setMode(ProxyMode mode) {
    setState(() => _invalid = null);
    _write(
      ProxyMode.settingKey,
      mode == ProxyMode.defaultMode ? null : mode.value,
    );
  }

  void _setUrl(String text) {
    if (text.isNotEmpty && ProxyServer.parse(text) == null) {
      setState(() => _invalid = text);
      return;
    }
    setState(() => _invalid = null);
    _write(ProxyMode.urlKey, text.isEmpty ? null : text);
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return ListenableBuilder(
      listenable: settings ?? Listenable.merge(const []),
      builder: (context, _) => _page(
        context,
        ProxyMode.parse(settings?[ProxyMode.settingKey]),
        switch (settings?[ProxyMode.urlKey]) {
          final String url => url.trim(),
          _ => '',
        },
      ),
    );
  }

  Widget _page(BuildContext context, ProxyMode mode, String url) {
    final l10n = context.l10n;
    final modeName = NetworkSettingsPage.modeName(context, mode);
    final invalid = _invalid;
    return SettingsPage(
      title: l10n.networkSettingsTitle,
      description: l10n.networkSettingsDescription,
      children: [
        SettingsCard(
          children: [
            SettingsRow(
              label: l10n.networkProxy,
              description: l10n.networkProxyDescription,
              trailing: SettingsDropdown(
                current: modeName,
                semanticLabel: l10n.networkProxyLabel(modeName),
                entries: () => [
                  for (final choice in ProxyMode.values)
                    IdeMenuAction(
                      NetworkSettingsPage.modeName(context, choice),
                      checked: choice == mode,
                      onSelected: () => _setMode(choice),
                    ),
                ],
              ),
            ),
            if (mode == ProxyMode.manual)
              SettingsRow(
                label: l10n.networkProxyUrl,
                description: invalid == null
                    ? l10n.networkProxyUrlDescription
                    : l10n.networkProxyUrlInvalid(invalid),
                trailing: SettingsTextField(
                  value: url,
                  hint: 'http://127.0.0.1:7890',
                  semanticLabel: l10n.networkProxyUrl,
                  onSubmitted: _setUrl,
                ),
              ),
            SettingsRow(
              label: l10n.networkProxyStatus,
              description: _status(context, mode, url),
              trailing: IdeButton(
                label: l10n.networkProxyRefresh,
                icon: Codicons.refresh,
                secondary: true,
                onPressed: _route == null ? null : () => unawaited(_detect()),
              ),
            ),
          ],
        ),
        SettingsCard(
          children: [
            SettingsRow(
              label: l10n.networkTest,
              description: switch (_probe) {
                null => l10n.networkTestDescription,
                _Probing() => l10n.networkTesting,
                _Reached(:final time) => l10n.networkTestOk(
                  time.inMilliseconds,
                ),
                _Failed(:final error) => l10n.networkTestFailed(error),
              },
              trailing: IdeButton(
                label: l10n.networkTest,
                icon: Codicons.debugStart,
                secondary: true,
                onPressed: _probe is _Probing || _route == null
                    ? null
                    : () => unawaited(_test()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The proxy in use, in words.
  String _status(BuildContext context, ProxyMode mode, String url) {
    final l10n = context.l10n;
    final route = _route;
    if (route == null) return l10n.networkProxyStatusChecking;
    if (mode == ProxyMode.manual && ProxyServer.parse(url) == null) {
      return l10n.networkProxyStatusManualMissing;
    }
    final server = '${route.https ?? route.http ?? ''}';
    return switch (route.source) {
      ProxySource.system => l10n.networkProxyStatusSystem(server),
      ProxySource.environment => l10n.networkProxyStatusEnvironment(server),
      ProxySource.manual => l10n.networkProxyStatusManual(server),
      ProxySource.off => l10n.networkProxyStatusOff,
      ProxySource.none when route.autoConfig =>
        l10n.networkProxyStatusAutoConfig,
      ProxySource.none => l10n.networkProxyStatusNone,
    };
  }
}
