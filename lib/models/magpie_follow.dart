import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'magpie.dart';
import 'magpie_stub.dart' if (dart.library.io) 'magpie_io.dart' as platform;
import 'model_provider.dart';
import 'model_providers.dart';
import 'model_runtime.dart';
import 'upstream.dart';

/// Keeps the upstream that follows magpie ([Magpie]) as magpie has it: at
/// the port its gateway listens on, with the models it serves. Also what
/// is known of magpie here, for Settings → Models to offer it.
class MagpieFollow extends ChangeNotifier {
  MagpieFollow({
    this._providers,
    Future<MagpieStatus> Function()? probe,
    Future<List<RemoteModel>> Function(ModelProvider provider, String? key)?
    list,
    Future<Object?> Function()? claudeSettings,
  }) : _probe = probe ?? platform.probeMagpie,
       _list = list ?? listUpstreamModels,
       _claudeSettings = claudeSettings ?? platform.readClaudeSettings;

  /// The app's; main() points it at this machine's magpie. Until then
  /// (and under test) magpie is never found.
  static MagpieFollow current = MagpieFollow(
    probe: () async => const MagpieStatus(),
  );

  /// How often the models are got again while the app runs: the gateway
  /// is on this machine, the list cheap to ask.
  static const interval = Duration(minutes: 10);

  final ModelProviders? _providers;
  final Future<MagpieStatus> Function() _probe;
  final Future<List<RemoteModel>> Function(ModelProvider, String?) _list;
  final Future<Object?> Function() _claudeSettings;

  ModelProviders get providers => _providers ?? ModelProviders.current;

  /// The upstream that follows magpie, if there is one.
  ModelProvider? get provider =>
      providers.providers.where((p) => p.followsMagpie).firstOrNull;

  /// What was last found of magpie; null before it is looked for.
  MagpieStatus? get status => _status;
  MagpieStatus? _status;

  /// Why its models were last not got, while they are not; not that the
  /// gateway is not running ([status]).
  String? get error => _error;
  String? _error;

  /// Whether its models are being got.
  bool get syncing => _syncing != null;
  Future<void>? _syncing;

  Timer? _timer;

  /// Gets the models now, if an upstream follows magpie, and every
  /// [interval] after.
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) {
      if (provider != null) unawaited(sync());
    });
    if (provider != null) unawaited(sync());
  }

  /// Looks for magpie: whether it is here and its gateway answers.
  Future<MagpieStatus> check() async {
    final status = await _probe();
    _set(status);
    return status;
  }

  void _set(MagpieStatus status) {
    final before = _status;
    _status = status;
    if (before?.installed != status.installed ||
        before?.port != status.port ||
        before?.version != status.version) {
      notifyListeners();
    }
  }

  /// Adds an upstream that follows magpie (or takes the one there is), its
  /// key with it, and gets its models: its id.
  Future<String> join() async {
    if (provider case final existing?) {
      unawaited(sync());
      return existing.id;
    }
    final status = _status ?? await check();
    final id = providers.newId(Magpie.name);
    await providers.save(Magpie.provider(id, port: status.port));
    await providers.setKey(id, Magpie.key);
    unawaited(sync());
    return id;
  }

  /// Gets magpie's models into the upstream that follows it, at the port
  /// its gateway is on now; one under way already is waited for.
  Future<void> sync() {
    if (_syncing case final running?) return running;
    final running = _syncing = _sync().whenComplete(() {
      _syncing = null;
      notifyListeners();
    });
    notifyListeners();
    return running;
  }

  Future<void> _sync() async {
    if (provider == null) return;
    final status = await check();
    var following = provider;
    if (following == null) return;
    // Moved to another port: there from now on.
    final moved = Magpie.at(following, status.port);
    if (!identical(moved, following)) {
      await providers.save(moved);
      following = moved;
    }
    if (!status.running) return;
    try {
      final listed = await _list(following, Magpie.key);
      final picks = Magpie.claudePicks(await _claudeSettings(), status.port);
      // As it is now: changed meanwhile, maybe.
      final now = provider;
      if (now == null) return;
      final synced = Magpie.synced(now, listed, picks);
      if (jsonEncode(synced.toJson()) != jsonEncode(now.toJson())) {
        await providers.save(synced);
      }
      _error = null;
      providers.reportError(now.id, null);
    } on Object catch (error) {
      _error = '$error';
      if (provider case final now?) providers.reportError(now.id, '$error');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
