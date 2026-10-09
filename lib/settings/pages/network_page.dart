import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/ide_button.dart';
import '../../ide/ide_menu.dart';
import '../../l10n/l10n.dart';
import '../../network/network_proxy.dart';
import '../../theme/codicons.dart';
import '../user_settings.dart';
import 'network_test_view.dart';
import 'settings_dropdown.dart';
import 'settings_widgets.dart';

/// Settings → Network: the proxy BaoCode and the Claude Code it starts go
/// through (`http.proxyMode`, `http.proxy`), the one in use now, and a
/// test of it: whether a few sites answer through it, and how quickly.
class NetworkSettingsPage extends StatefulWidget {
  const NetworkSettingsPage({
    super.key,
    this.settings,
    this.detect = currentProxyRoute,
    this.probe = probeConnection,
    this.sites,
  });

  /// settings.json; none under test, where choices are not kept.
  final UserSettings? settings;

  /// The proxy in use now.
  final Future<ProxyRoute> Function() detect;

  /// How long a site takes to answer through it; throws a [ProbeFailure].
  final Future<Duration> Function(Uri url) probe;

  /// What the test asks; [TestSite.all] by default.
  final List<TestSite>? sites;

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

class _NetworkSettingsPageState extends State<NetworkSettingsPage> {
  /// The proxy in use, once detected; null while it is.
  ProxyRoute? _route;

  /// What was typed as the address, when it is not one.
  String? _invalid;

  /// The test's, by site; empty before it runs.
  Map<String, SiteResult> _results = const {};

  /// Counts the tests: a site's answer to one gone is not shown.
  int _run = 0;

  int _detecting = 0;

  List<TestSite> get _sites => widget.sites ?? TestSite.all;

  bool get _testing => _results.values.any((result) => result is SiteTesting);

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

  /// The proxy changed: what was tested went through the one before.
  void _changed() {
    _run++;
    setState(() => _results = const {});
    unawaited(_detect());
  }

  Future<void> _detect() async {
    final asked = ++_detecting;
    if (_route != null) setState(() => _route = null);
    final route = await widget.detect();
    if (mounted && asked == _detecting) setState(() => _route = route);
  }

  /// Asks every site at once, each shown as it answers.
  Future<void> _test() async {
    final run = ++_run;
    final sites = _sites;
    setState(
      () => _results = {for (final site in sites) site.id: const SiteTesting()},
    );
    Future<void> ask(TestSite site) async {
      SiteResult result;
      try {
        result = SiteReached(await widget.probe(site.url));
      } on ProbeFailure catch (failure) {
        result = SiteUnreached(failure);
      } on Object catch (error) {
        result = SiteUnreached(ProbeFailure(ProbeFailureKind.other, '$error'));
      }
      if (!mounted || run != _run) return;
      setState(() => _results = {..._results, site.id: result});
    }

    await Future.wait([for (final site in sites) ask(site)]);
  }

  /// What the answers together suggest, once all are in; null when they
  /// suggest nothing.
  String? _hint(BuildContext context) {
    final l10n = context.l10n;
    final results = _results;
    if (results.isEmpty || _testing) return null;
    final failures = [
      for (final result in results.values)
        if (result is SiteUnreached) result.failure.kind,
    ];
    if (failures.isEmpty) return null;
    if (failures.length == results.length) {
      return failures.every((kind) => kind == ProbeFailureKind.refused)
          ? l10n.networkTestHintRefused
          : l10n.networkTestHintOffline;
    }
    // Only the site at home answers: the others do not get through.
    final reached = [
      for (final MapEntry(:key, :value) in results.entries)
        if (value is SiteReached) key,
    ];
    if (reached.length == 1 && reached.single == 'baidu') {
      return l10n.networkTestHintBlocked;
    }
    return null;
  }

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
              description: _summary(context),
              trailing: IdeButton(
                label: _results.isEmpty
                    ? l10n.networkTestRun
                    : l10n.networkTestRunAgain,
                icon: _results.isEmpty ? Codicons.debugStart : Codicons.refresh,
                secondary: true,
                spinning: _testing,
                onPressed: _testing || _route == null
                    ? null
                    : () => unawaited(_test()),
              ),
            ),
            for (final site in _sites)
              NetworkTestRow(site: site, result: _results[site.id]),
            if (_hint(context) case final hint?)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                child: Text(hint, style: SettingsText.description),
              ),
          ],
        ),
      ],
    );
  }

  /// The test's description, and how many answered once all have.
  String _summary(BuildContext context) {
    final l10n = context.l10n;
    final results = _results;
    if (results.isEmpty || _testing) return l10n.networkTestDescription;
    final reached = results.values.whereType<SiteReached>().length;
    return l10n.networkTestSummary(reached, results.length);
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
