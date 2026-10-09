// Drives the workspace area's main thread actors the way the extension
// host does: a pair of [RpcProtocol]s over an in-memory message passing
// protocol, our actors on one side, and the raw `RpcProtocol.call` on the
// other for what the extension host sends (`$startFileSearch`, `$watch`,
// the file service's `$stat`…). Also the app-side services the actors
// need, with no Flutter workbench.

import 'dart:async';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/configuration/configuration_registry.dart';
import 'package:baocode/extensions/configuration/configuration_service.dart';
import 'package:baocode/extensions/files/disk_file_system_provider_io.dart';
import 'package:baocode/extensions/files/file_operation_participants.dart';
import 'package:baocode/extensions/files/file_service.dart';
import 'package:baocode/extensions/host/init_data.dart';
import 'package:baocode/extensions/main_thread/main_thread_context.dart';
import 'package:baocode/extensions/main_thread/workspace_customers.dart';
import 'package:baocode/extensions/search/query_builder.dart';
import 'package:baocode/extensions/search/search_service.dart';
import 'package:baocode/extensions/trust/workspace_trust.dart';
import 'package:baocode/extensions/workspace/encoding_oracle.dart';
import 'package:baocode/extensions/workspace/workspace_context.dart';
import 'package:flutter/foundation.dart';

/// `MessagePassingProtocol` over two protocols in one isolate.
final class TestMessagePassing implements MessagePassingProtocol {
  TestMessagePassing? peer;
  void Function(Uint8List message)? _listener;

  @override
  void send(Uint8List message) {
    final to = peer;
    if (to == null) throw StateError('No peer');
    scheduleMicrotask(() => to._listener?.call(message));
  }

  @override
  set onMessage(void Function(Uint8List message)? listener) =>
      _listener = listener;

  /// Two protocols, each delivering to the other.
  static (TestMessagePassing, TestMessagePassing) pair() {
    final a = TestMessagePassing();
    final b = TestMessagePassing();
    a.peer = b;
    b.peer = a;
    return (a, b);
  }
}

/// In-memory settings file.
final class TestSettings extends ChangeNotifier implements SettingsFile {
  TestSettings([Map<String, Object?>? values]) : values = values ?? {};

  @override
  Map<String, Object?> values;

  final writes = <List<Object?>>[];

  @override
  Future<void> write(List<String> path, Object? value) async {
    writes.add([...path, value]);
    if (path.length == 1) {
      if (value == null) {
        values.remove(path.single);
      } else {
        values[path.single] = value;
      }
    } else {
      final o = (values[path[0]] as Map<String, Object?>?) ?? {};
      o[path[1]] = value;
      values[path[0]] = o;
    }
    notifyListeners();
  }

  void set(Map<String, Object?> next) {
    values = next;
    notifyListeners();
  }
}

/// In-memory trust storage.
final class TestTrustStorage implements WorkspaceTrustStorage {
  String? contents;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String contents) async => this.contents = contents;
}

/// The app side of one extension host session, for tests: the services
/// the workspace area's actors use, and the extension host's end of the
/// RPC.
final class MainThreadHarness {
  MainThreadHarness({
    required this.folder,
    Map<String, Object?> settings = const {},
    Map<String, Object?> userSettings = const {},
    bool trusted = true,
    this.isMultiRoot = false,
    WorkspaceFoldersPort? folders,
    bool withParticipants = true,
    this.activationTimeout = const Duration(milliseconds: 300),
  }) {
    final (hostSide, appSide) = TestMessagePassing.pair();
    host = RpcProtocol(hostSide, actorNames: proxyIdentifierNames);
    app = RpcProtocol(appSide, actorNames: proxyIdentifierNames);
    workspace = WorkspaceContextService(
      ExtHostWorkspace.folder(folder.path),
      isMultiRoot: isMultiRoot,
      folders: folders,
    );
    configuration = ConfigurationService(
      registry: ConfigurationRegistry(),
      user: TestSettings(userSettings),
      workspace: TestSettings(settings),
    )..trusted = trusted;
    disk = DiskFileSystemProvider();
    files = FileService(batchDelay: Duration.zero);
    files
      ..registerProvider('file', disk)
      ..addActivator(_activate);
    search = SearchService();
    queryBuilder = QueryBuilder(
      configuration: configuration,
      workspace: workspace,
    );
    encodings = EncodingOracle(
      configuration: configuration,
      workspace: workspace,
    );
    trust = WorkspaceTrustService(
      store: WorkspaceTrustStore(trustStorage),
      workspaceUris: _workspaceUris,
      workspaceId: 'test',
      isMultiRoot: isMultiRoot,
      setting: userSettings.containsKey('__none__')
          ? (_) => null
          : (key) => userSettings[key],
    );
    if (withParticipants) {
      participants = FileOperationParticipants();
    }
    context = MainThreadContext(rpc: app, services: {
      ConfigurationService: configuration,
      WorkspaceContextService: workspace,
      FileService: files,
      SearchService: search,
      QueryBuilder: queryBuilder,
      EncodingOracle: encodings,
      WorkspaceTrustService: trust,
      FileOperationParticipants: ?participants,
    });
    // The extension host's actors, so what the main thread sends while
    // the actors are made (`$acceptProviderInfos`) and later
    // (`$acceptWorkspaceData`, `$handleTextSearchResult`,
    // `$onFileEvent`…) is recorded instead of failing.
    for (final proxy in const [
      ExtHostContext.extHostWorkspace,
      ExtHostContext.extHostSearch,
      ExtHostContext.extHostFileSystem,
      ExtHostContext.extHostFileSystemInfo,
      ExtHostContext.extHostFileSystemEventService,
    ]) {
      host.set(proxy.nid, _extHostActors[proxy.nid] = _RecordingActor());
    }
    actors = {
      for (final MapEntry(:key, :value) in workspaceCustomers.entries)
        key: value(context),
    };
    for (final MapEntry(:key, :value) in actors.entries) {
      app.set(key, value);
    }
  }

  final Directory folder;
  final bool isMultiRoot;

  /// How long an `onFileSystem:<scheme>` activation waits for the test's
  /// [registered] call.
  final Duration activationTimeout;

  final trustStorage = TestTrustStorage();
  late final RpcProtocol host;
  late final RpcProtocol app;
  late final WorkspaceContextService workspace;
  late final ConfigurationService configuration;
  late final FileService files;
  late final DiskFileSystemProvider disk;
  late final SearchService search;
  late final QueryBuilder queryBuilder;
  late final EncodingOracle encodings;
  late final WorkspaceTrustService trust;
  late final FileOperationParticipants? participants;
  late final MainThreadContext context;
  late final Map<int, RpcActor> actors;

  List<VsUri> _workspaceUris() => [
    for (final f in workspace.workspaceFolders) f.uri,
  ];

  final _activations = <String, Completer<void>>{};

  Future<void> _activate(String scheme) async {
    final completer = _activations[scheme] = Completer<void>();
    final registered = await Future.any([
      completer.future.then((_) => true),
      Future<void>.delayed(activationTimeout).then((_) => false),
    ]);
    if (!registered) _activations.remove(scheme);
  }

  /// Finishes an activation an extension's registration was waiting for
  /// (as `MainThreadFileSystem.$registerFileSystemProvider`'s promise
  /// does).
  void registered(String scheme) => _activations.remove(scheme)?.complete();

  Future<void> initialize() => trust.initialize();

  /// Replaces the actor of one `MainContext` id (for one built with
  /// another service).
  void setActor(int nid, RpcActor actor) {
    actors[nid] = actor;
    app.set(nid, actor);
  }

  /// Lets the test answer one `ExtHost…` method as the extension host
  /// would (a fake host's `$provideFileSearchResults` sends
  /// `$handleFileMatch` back). Other methods keep recording.
  void answer(
    ProxyIdentifier proxy,
    String method,
    Future<Object?> Function(List<Object?> args) answer,
  ) {
    final actor = _extHostActors[proxy.nid] ??= _RecordingActor();
    actor.answers[method] = answer;
    host.set(proxy.nid, actor);
  }

  /// What we send the extension host: the `ExtHost…` actor of [proxy]
  /// records the call (`ExtHostWorkspace.$initializeWorkspace`, the
  /// `$handleTextSearchResult`s…).
  Future<Object?> extHostCall(
    ProxyIdentifier proxy,
    String method,
    List<Object?> args,
  ) {
    final actor = _extHostActors[proxy.nid] ??= _RecordingActor();
    host.set(proxy.nid, actor);
    return app.call(proxy.nid, method, args);
  }

  /// What the extension host sends, arriving at the actor of [proxy]: the
  /// main thread's side of the pair. A cancellable request's token travels
  /// beside the arguments, as upstream appends one.
  Future<Object?> call(
    ProxyIdentifier proxy,
    String method,
    List<Object?> args, {
    CancellationToken? token,
  }) => host.call(proxy.nid, method, args, token: token);

  final _extHostActors = <int, _RecordingActor>{};

  /// The calls made to the extension host's actor [nid], as
  /// `(method, args)`.
  List<(String, List<Object?>)> callsTo(int nid) =>
      List.unmodifiable(_extHostActors[nid]?.calls ?? const []);

  /// Every call made to the extension host, `(nid, method, args)`.
  List<(int, String, List<Object?>)> get allHostCalls => [
    for (final MapEntry(:key, :value) in _extHostActors.entries)
      for (final (method, args) in value.calls) (key, method, args),
  ];

  /// `$registerFileSystemProvider` awaited by the extension host's
  /// file system consumer.
  Future<Object?> registerProvider(
    int handle,
    String scheme,
    int capabilities,
  ) => call(
    MainContext.mainThreadFileSystem,
    r'$registerFileSystemProvider',
    [handle, scheme, capabilities],
  );

  /// The `$onFileEvent` the extension host's watchers were sent.
  List<Map<String, Object?>> fileEvents() => [
    for (final (nid, method, args) in allHostCalls)
      if (nid == ExtHostContext.extHostFileSystemEventService.nid &&
          method == r'$onFileEvent')
        (args.single as Map).cast<String, Object?>(),
  ];

  Future<void> dispose() async {
    await context.dispose();
    participants?.dispose();
    files.dispose();
    disk.dispose();
    trust.dispose();
    configuration.dispose();
    workspace.dispose();
    host.dispose();
    app.dispose();
  }
}

/// Records what the main thread was sent, so `$watch`, `$onFileEvent`
/// and the like can be inspected.
final class _RecordingActor implements RpcActor {
  final calls = <(String, List<Object?>)>[];
  final answers = <String, Future<Object?> Function(List<Object?> args)>{};

  @override
  Future<Object?> invoke(String method, List<Object?> args) async {
    calls.add((method, args));
    final answer = answers[method];
    return answer == null ? null : await answer(args);
  }
}
