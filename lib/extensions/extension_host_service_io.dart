import 'dart:async';
import 'dart:math';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';

import 'configuration/configuration_service.dart';
import 'host/ext_host_connection.dart';
import 'host/extension_host_manager.dart';
import 'host/extension_server_io.dart';
import 'host/extension_server_pool_io.dart';
import 'host/implicit_activation_events.dart';
import 'host/init_data.dart';
import 'main_thread/main_thread_context.dart';

/// The extensions a host runs, as the server scanned them
/// (`IExtensionDescription`s with `file:` URIs).
typedef ExtensionDescriptions = List<Map<String, Object?>>;

/// One workspace's extension host and what it needs: started on the first
/// activation event (opening a file, running a command…), its main thread
/// actors made from [customers] for every session.
final class ExtensionHostService extends ChangeNotifier {
  ExtensionHostService({
    required this.pool,
    this.product,
    this.loadProduct,
    required this.workspace,
    required this.configuration,
    required this.customers,
    this.services = const {},
    this.language = 'en',
    this.trusted = true,
    this.developmentLocations = const [],
    this.logger,
    this.includeExtension,
  }) {
    manager = ExtensionHostManager(
      start: _startSession,
      extensionServiceId: ExtHostContext.extHostExtensionService.nid,
    )..addListener(notifyListeners);
  }

  final ExtensionServerPool pool;

  /// The runtime's product, or how to read it once the runtime is there
  /// ([loadProduct]); one of them is given.
  final ExtHostProduct? product;
  final Future<ExtHostProduct> Function()? loadProduct;
  final ExtHostWorkspace workspace;
  final ConfigurationService configuration;

  /// The main thread actors this app implements, by `MainContext` id; every
  /// other shape answers each call as unsupported.
  final Map<int, MainThreadCustomer> customers;

  /// The app's services the actors use ([MainThreadContext.service]).
  final Map<Type, Object> services;
  final String language;
  final bool trusted;

  /// Folders loaded as extensions under development; a change applies as
  /// the host starts again.
  List<VsUri> developmentLocations;
  final RpcLogger? logger;

  /// Whether a scanned extension runs here (enabled, in this workspace);
  /// all do when null. Upstream leaves disabled extensions out of the
  /// registry altogether.
  final bool Function(Map<String, Object?> description)? includeExtension;

  late final ExtensionHostManager manager;

  /// `extensionRegistryVersionId`: bumped by every [refreshExtensions].
  int _extensionsVersionId = 0;

  /// The extensions the running session activated (lowercase ids), told by
  /// `MainThreadExtensionService`.
  final _activated = <String>{};

  /// [id] was activated in the running session.
  void didActivate(String id) => _activated.add(id.toLowerCase());

  bool isActivated(String id) => _activated.contains(id.toLowerCase());

  /// The extensions of the running (or last) session.
  ValueListenable<ExtensionDescriptions> get extensions => _extensions;
  final _extensions = ValueNotifier<ExtensionDescriptions>(const []);

  /// The running session's context; null when none runs.
  MainThreadContext? get context => _context;
  MainThreadContext? _context;

  final _sessionId = _randomId();
  final _machineId = _randomId();

  Future<ExtHostSession> _startSession() async {
    final server = await pool.server;
    final product = this.product ?? await loadProduct!();
    final environment = await server.environment();
    final scanned = _included(
      await server.scanExtensions(
        language: language,
        developmentLocations: developmentLocations,
      ),
    );
    _activated.clear();
    _extensions.value = List.unmodifiable(scanned);
    configuration.setExtensions(scanned);
    final previous = _context;
    _context = null;
    await previous?.dispose();
    late MainThreadContext context;
    final connection = await ExtHostConnection.start(
      server.address,
      language: language,
      actorNames: proxyIdentifierNames,
      logger: logger,
      initData: () => buildExtHostInitData(
        product: product,
        environment: environment,
        extensions: scanned,
        extensionsVersionId: _extensionsVersionId,
        workspace: workspace,
        language: language,
        sessionId: _sessionId,
        machineId: _machineId,
        extensionDevelopmentLocations: developmentLocations,
      ),
      actorsFor: (rpc) {
        context = MainThreadContext(
          rpc: rpc,
          services: {
            ...services,
            ExtensionHostService: this,
            ConfigurationService: configuration,
          },
        );
        return {
          for (final MapEntry(:key, :value)
              in unsupportedMainThreadActors.entries)
            key: value(),
          for (final MapEntry(:key, :value) in customers.entries)
            key: value(context),
        };
      },
    );
    _context = context;
    // What MainThreadConfiguration's and MainThreadWorkspace's
    // constructors send, before the host activates anything.
    final rpc = connection.rpc;
    unawaited(
      ExtHostConfigurationProxy(rpc)
          .$initializeConfiguration(configuration.initData())
          .catchError((Object _) {}),
    );
    unawaited(
      ExtHostWorkspaceProxy(rpc)
          .$initializeWorkspace(workspace.toJson(), trusted)
          .catchError((Object _) {}),
    );
    context.listen(
      configuration.changes.listen((event) {
        unawaited(
          ExtHostConfigurationProxy(rpc)
              .$acceptConfigurationChanged(event.data, event.change)
              .catchError((Object _) {}),
        );
      }),
    );
    unawaited(connection.closed.then((_) => context.dispose()));
    return connection;
  }

  List<Map<String, Object?>> _included(List<Map<String, Object?>> scanned) {
    final include = includeExtension;
    return include == null ? scanned : [...scanned.where(include)];
  }

  static String _idOf(Map<String, Object?> description) =>
      switch (description['identifier']) {
        {'value': final String value} => value,
        final Object? other => '$other',
      };

  /// What makes two scans of an extension the same one.
  static String _signatureOf(Map<String, Object?> description) =>
      '${description['version']}|${description['extensionLocation']}';

  /// The installed or enabled extensions changed: the running host gets
  /// them as `$deltaExtensions` (upstream's
  /// `AbstractExtensionService._deltaExtensions`); one that must drop an
  /// extension it activated (uninstalled, disabled, updated) is restarted,
  /// as upstream asks the user to. A host not running scans afresh as it
  /// starts.
  Future<void> refreshExtensions() async {
    final rpc = manager.rpc;
    if (rpc == null || manager.state != ExtensionHostState.running) return;
    final server = await pool.server;
    final scanned = _included(
      await server.scanExtensions(
        language: language,
        developmentLocations: developmentLocations,
      ),
    );
    final before = {
      for (final e in _extensions.value) _idOf(e).toLowerCase(): e,
    };
    final after = {for (final e in scanned) _idOf(e).toLowerCase(): e};
    final toRemove = <Map<String, Object?>>[
      for (final MapEntry(:key, :value) in before.entries)
        if (after[key] == null ||
            _signatureOf(after[key]!) != _signatureOf(value))
          value,
    ];
    final toAdd = <Map<String, Object?>>[
      for (final MapEntry(:key, :value) in after.entries)
        if (before[key] == null ||
            _signatureOf(before[key]!) != _signatureOf(value))
          value,
    ];
    if (toAdd.isEmpty && toRemove.isEmpty) return;
    if (toRemove.any((e) => isActivated(_idOf(e)))) {
      await manager.restart();
      return;
    }
    _extensionsVersionId++;
    _extensions.value = List.unmodifiable(scanned);
    configuration.setExtensions(scanned);
    Map<String, Object?> identifier(Map<String, Object?> e) {
      final id = _idOf(e);
      return {'value': id, '_lower': id.toLowerCase()};
    }

    await ExtHostExtensionServiceProxy(rpc).$deltaExtensions({
      'versionId': _extensionsVersionId,
      'toRemove': [for (final e in toRemove) identifier(e)],
      'toAdd': toAdd,
      'addActivationEvents': createActivationEventsMap(toAdd),
      'myToRemove': [for (final e in toRemove) identifier(e)],
      'myToAdd': [for (final e in toAdd) identifier(e)],
    });
  }

  /// Starts the host when needed and activates [event]'s extensions.
  Future<void> activateByEvent(String event) => manager.activateByEvent(event);

  /// `*` then `onStartupFinished`, as the workbench does once it is up.
  Future<void> startup() async {
    await activateByEvent('*');
    await activateByEvent('onStartupFinished');
  }

  @override
  void dispose() {
    manager
      ..removeListener(notifyListeners)
      ..dispose();
    unawaited(_context?.dispose());
    _extensions.dispose();
    super.dispose();
  }

  static String _randomId() {
    final r = Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }
}

/// Starts the app's server with [launch] once something needs it.
ExtensionServerPool extensionServerPool(
  Future<ExtensionServerLaunch> Function() launch,
) => ExtensionServerPool(launch);
