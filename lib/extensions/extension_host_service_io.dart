import 'dart:async';
import 'dart:math';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';

import 'configuration/configuration_service.dart';
import 'host/ext_host_connection.dart';
import 'host/extension_host_manager.dart';
import 'host/extension_server_io.dart';
import 'host/extension_server_pool_io.dart';
import 'host/extensions_delta.dart';
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
    bool trusted = true,
    this.workspaceTrusted,
    this.developmentLocations = const [],
    this.logger,
    this.includeExtension,
    // Keep the public named argument `trusted` while storing its fallback.
    // ignore: prefer_initializing_formals
  }) : _trusted = trusted {
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
  final bool _trusted;

  /// Read as each session initializes, including a restart after trust changes.
  final bool Function()? workspaceTrusted;
  bool get trusted => workspaceTrusted?.call() ?? _trusted;

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

  /// The extensions the running session started activating (lowercase
  /// ids), told by `MainThreadExtensionService` (upstream's
  /// `activationStarted`).
  final _activated = <String>{};

  /// [id]'s activation started in the running session.
  void didActivate(String id) => _activated.add(id.toLowerCase());

  bool isActivated(String id) => _activated.contains(id.toLowerCase());

  /// Extensions updated, uninstalled or disabled after their activation
  /// started (lowercase ids): the host runs what it activated until it
  /// restarts (upstream's `ExtensionRuntimeActionType.RestartExtensions`).
  ValueListenable<Set<String>> get pendingRestart => _pendingRestart;
  final _pendingRestart = ValueNotifier<Set<String>>(const {});

  /// Whether [id] installed at [version] in [folder] needs the extensions
  /// restarted to run: its activation started here at another version or
  /// from another folder (upstream's runtime state).
  bool needsRestartFor(
    String id, {
    required String version,
    required String folder,
  }) {
    if (!isActivated(id)) return false;
    final running = _extensions.value.where(
      (e) => _idOf(e).toLowerCase() == id.toLowerCase(),
    );
    if (running.isEmpty) return false;
    final location = switch (running.first['extensionLocation']) {
      final Map<String, Object?> json => VsUri.revive(json).fsPath(),
      _ => null,
    };
    return running.first['version'] != version || location != folder;
  }

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
    _checkNotDisposed();
    _activated.clear();
    _pendingRestart.value = const {};
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
        _checkNotDisposed();
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

  /// The installed or enabled extensions changed: the running host gets
  /// them as `$deltaExtensions` (upstream's
  /// `AbstractExtensionService._deltaExtensions`). An extension whose
  /// activation started is neither removed nor replaced
  /// (`canRemoveExtension`): it waits in [pendingRestart] for the user to
  /// restart the extensions. A host not running scans afresh as it starts.
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
    final (:toAdd, :toRemove, :kept, running: runs) = extensionsDelta(
      before: _extensions.value,
      after: scanned,
      activated: isActivated,
    );
    if (kept.isNotEmpty) {
      _pendingRestart.value = {..._pendingRestart.value, ...kept};
    }
    if (toAdd.isEmpty && toRemove.isEmpty) return;
    final running = List<Map<String, Object?>>.unmodifiable(runs);
    _extensionsVersionId++;
    _extensions.value = running;
    configuration.setExtensions(running);
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
  /// Only `*` is waited for: upstream's host activates the
  /// `onStartupFinished` extensions without waiting for them
  /// (`_activateOneStartupFinished`), and one may wait on its user (a
  /// welcome message) for as long as they like.
  Future<void> startup() async {
    await activateByEvent('*');
    unawaited(activateByEvent('onStartupFinished').catchError((Object _) {}));
  }

  bool _disposed = false;

  /// Disposed while a session was starting: its services are gone.
  void _checkNotDisposed() {
    if (_disposed) {
      throw const ExtHostStartException('disposed while starting');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    manager
      ..removeListener(notifyListeners)
      ..dispose();
    unawaited(_context?.dispose());
    _extensions.dispose();
    _pendingRestart.dispose();
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
