import 'dart:async';
import 'dart:math';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';

import 'configuration/configuration_service.dart';
import 'host/ext_host_connection.dart';
import 'host/extension_host_manager.dart';
import 'host/extension_server_io.dart';
import 'host/extension_server_pool_io.dart';
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
    required this.product,
    required this.workspace,
    required this.configuration,
    required this.customers,
    this.services = const {},
    this.language = 'en',
    this.trusted = true,
    this.developmentLocations = const [],
    this.logger,
  }) {
    manager = ExtensionHostManager(
      start: _startSession,
      extensionServiceId: ExtHostContext.extHostExtensionService.nid,
    )..addListener(notifyListeners);
  }

  final ExtensionServerPool pool;
  final ExtHostProduct product;
  final ExtHostWorkspace workspace;
  final ConfigurationService configuration;

  /// The main thread actors this app implements, by `MainContext` id; every
  /// other shape answers each call as unsupported.
  final Map<int, MainThreadCustomer> customers;

  /// The app's services the actors use ([MainThreadContext.service]).
  final Map<Type, Object> services;
  final String language;
  final bool trusted;

  /// Folders loaded as extensions under development.
  final List<VsUri> developmentLocations;
  final RpcLogger? logger;

  late final ExtensionHostManager manager;

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
    final environment = await server.environment();
    final scanned = await server.scanExtensions(
      language: language,
      developmentLocations: developmentLocations,
    );
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
        workspace: workspace,
        language: language,
        sessionId: _sessionId,
        machineId: _machineId,
        extensionDevelopmentLocations: developmentLocations,
      ),
      actorsFor: (rpc) {
        context = MainThreadContext(rpc: rpc, services: {
          ...services,
          ExtensionHostService: this,
          ConfigurationService: configuration,
        });
        return {
          for (final MapEntry(:key, :value) in unsupportedMainThreadActors.entries)
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
      for (var i = 0; i < 16; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }
}

/// Starts the app's server with [launch] once something needs it.
ExtensionServerPool extensionServerPool(
  Future<ExtensionServerLaunch> Function() launch,
) => ExtensionServerPool(launch);
