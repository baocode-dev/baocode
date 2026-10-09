// The app's extensions, put together: [ExtensionsApp] holds what the app
// shares (the runtime, the VS Code server, extension storage, secrets,
// URLs, the user's settings), and a [WorkspaceExtensions] per IDE workspace
// holds its extension host and everything the host's main-thread actors
// reach: its documents and editors, language features, commands, status
// bar items, quick inputs, output channels, progress and notifications.
//
// Follows VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0): the
// workbench services `AbstractExtensionService` starts the extension host
// with (src/vs/workbench/services/extensions/common/
// abstractExtensionService.ts) and the order it activates (`*`, then
// `onStartupFinished`; `onLanguage:` as documents open).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_editor/textmate/textmate_syntax.dart';
import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../debug/service/debug_host.dart' show DebugPickItem;
import '../../debug/service/debug_service.dart';
import '../../ide/ide_notifications.dart' show IdeSeverity;
import '../../ide/ide_workspace.dart';
import '../../ide/lsp/language_features.dart';
import '../../ide/lsp/lsp_protocol.dart' show LspPosition, LspRange;
import '../../ide/terminal/terminal_instance.dart' show TerminalBackend;
import '../../platform/data_dir.dart';
import '../../settings/jsonc.dart';
import '../../theme/file_icon_theme.dart';
import '../../theme/workbench_theme.dart' show WorkbenchThemeService;
import '../../settings/jsonc_file.dart';
import '../commands/builtin_commands.dart';
import '../commands/extension_command_palette.dart';
import '../commands/extension_command_registry.dart'
    show CommandActivation, ExtensionCommandRegistry;
import '../commands/host_command_activation_io.dart';
import '../commands/workbench_builtin_commands.dart';
import '../configuration/configuration_service.dart';
import '../configuration/core_configuration.dart';
import '../contextkey/context_key_service.dart';
import '../editors/document_registry.dart';
import '../editors/documents_and_editors_service.dart';
import '../editors/editor_ports.dart';
import '../extension_host_service_io.dart';
import '../files/disk_file_system_provider_io.dart';
import '../files/file_service.dart';
import '../files/file_types.dart';
import '../files/workspace_file_watcher.dart';
import '../gallery/extension_enablement.dart';
import '../gallery/extension_management_backend.dart';
import '../gallery/open_vsx_client.dart';
import '../gallery/server_extension_management.dart';
import '../host/extension_host_manager.dart' show ExtensionHostState;
import '../host/extension_server_io.dart';
import '../host/extension_server_pool_io.dart';
import '../host/init_data.dart';
import '../language/language_customers.dart';
import '../language/language_selector.dart';
import '../languages/language_registry.dart';
import '../languages/language_status.dart';
import '../main_thread/commands_customers.dart';
import '../menus/menu_service.dart';
import '../main_thread/documents_customers.dart';
import '../main_thread/main_thread_authentication.dart';
import '../main_thread/main_thread_bulk_edits.dart';
import '../main_thread/main_thread_configuration.dart';
import '../main_thread/main_thread_document_content_providers.dart';
import '../main_thread/main_thread_documents.dart';
import '../main_thread/main_thread_debug_service.dart';
import '../main_thread/main_thread_file_system.dart' show ExtensionActivator;
import '../main_thread/main_thread_decorations.dart';
import '../main_thread/main_thread_message_service.dart';
import '../main_thread/main_thread_scm.dart';
import '../main_thread/main_thread_task.dart';
import '../main_thread/main_thread_testing.dart';
import '../main_thread/main_thread_terminal_service.dart';
import '../main_thread/main_thread_terminal_shell_integration.dart';
import '../main_thread/main_thread_tree_views.dart';
import '../main_thread/window_customers.dart';
import '../main_thread/workspace_customers.dart';
import '../runtime/extension_runtime_service.dart';
import '../recommendations/recommendations.dart';
import '../scm/scm_service.dart';
import '../search/search_service.dart';
import '../testing/test_service.dart';
import '../tasks/task_service.dart';
import '../ui/extensions_model.dart';
import '../trust/trust_ui.dart';
import '../trust/workspace_trust.dart';
import '../trust/workspace_trust_storage_io.dart';
import '../decorations/explorer_decorations.dart';
import '../decorations/file_decorations_service.dart';
import '../views/views_service.dart';
import '../window/auth/authentication_app_services.dart';
import '../window/auth/authentication_extensions_service.dart';
import '../window/auth/authentication_ports.dart';
import '../window/auth/authentication_service.dart';
import '../window/auth/authentication_ui.dart';
import '../window/extension_storage.dart';
import '../terminal/environment_variable_service.dart';
import '../window/json_state_store.dart';
import '../window/label_service.dart';
import '../window/output/extension_output_service.dart';
import '../window/progress_service.dart';
import '../window/quick_input/quick_input_service.dart';
import '../window/runtime_extensions.dart';
import '../window/secrets/extension_secret_service.dart';
import '../window/secrets/secret_backend.dart';
import '../window/status_bar_service.dart';
import '../window/url_service.dart';
import '../window/webview_degradation.dart';
import '../window/webview_placeholders.dart';
import '../window/window_adapters.dart';
import '../window/window_ports.dart';
import '../workspace/workspace_context.dart';
import '../workspace/workspace_save.dart';
import 'editor_feature_driver.dart';
import 'ide_documents.dart';
import 'default_formatter.dart';
import 'save_participants.dart';
import 'ide_text_editors.dart';
import 'jsonc_settings_file.dart';
import 'workspace_debug_host.dart';
import 'workspace_tasks.dart';

/// What the whole app shares: one runtime, one VS Code server (and its
/// extensions folder), the user's settings and the extensions' storage.
final class ExtensionsApp {
  ExtensionsApp({
    required this.userSettings,
    ExtensionRuntimeService? runtime,
    String? dataDirectory,
    this.openExternal,
    this.filePickers,
    this.loadRuntime,
    Future<CoreConfiguration> Function()? coreConfiguration,
    this._language,
    this._gallery,
  }) : runtime = runtime ?? ExtensionRuntimeService.instance,
       dataDirectory = dataDirectory ?? DataDirectory.current.path,
       _loadCore = coreConfiguration ?? CoreConfiguration.load;

  /// `User/settings.json`.
  final SettingsFile userSettings;
  final ExtensionRuntimeService runtime;

  /// Gives the runtime in place of [runtime] (tests).
  final Future<ExtHostRuntime> Function()? loadRuntime;

  Future<ExtHostRuntime> _runtime() =>
      loadRuntime?.call() ?? runtime.ensureReady();

  /// The data folder (`<data>`).
  final String dataDirectory;

  /// Opens a URL in the system's browser (a file in its app).
  final Future<bool> Function(String target)? openExternal;

  /// The native open and save panels.
  final ExtensionFilePickers? filePickers;

  final Future<CoreConfiguration> Function() _loadCore;

  final String Function()? _language;

  /// The display language, as VS Code names it (`en`, `zh-cn`): the
  /// extensions' localized manifests and `vscode.env.language`.
  String get language => _language?.call() ?? 'en';

  final OpenVsxClient? _gallery;

  /// Open VSX.
  late final OpenVsxClient gallery =
      _gallery ??
      OpenVsxClient(cacheDir: p.join(dataDirectory, 'cache', 'open-vsx'));

  /// `<data>/extensions/`: the user's extensions, VS Code's layout.
  String get extensionsDirectory => p.join(dataDirectory, 'extensions');

  /// `<data>/exthost-data/`: the server's own data.
  String get serverDataDirectory => p.join(dataDirectory, 'exthost-data');

  String get userDirectory => p.join(dataDirectory, 'User');

  /// The one VS Code server, started on the runtime once it is there.
  late final ExtensionServerPool pool = ExtensionServerPool(_launch);

  final _changes = StreamController<ExtensionManagementEvent>.broadcast();

  /// Extensions installed, uninstalled, enabled or disabled, from any
  /// workspace.
  Stream<ExtensionManagementEvent> get changes => _changes.stream;

  Future<ExtensionServerLaunch> _launch() async {
    final installed = await _runtime();
    return ExtensionServerLaunch(
      node: installed.nodeExecutable,
      serverMain: installed.serverMain,
      commit: installed.productCommit,
      serverDataDir: serverDataDirectory,
      extensionsDir: extensionsDirectory,
    );
  }

  /// The runtime's `product.json`.
  Future<ExtHostProduct> product() async {
    final installed = await _runtime();
    final json = jsonDecode(await File(installed.productJson).readAsString());
    return ExtHostProduct.fromJson((json as Map).cast());
  }

  CoreConfiguration? _core;
  Future<CoreConfiguration>? _coreLoading;

  /// VS Code's own settings' schemas (core_configuration.json).
  Future<CoreConfiguration> coreConfiguration() async =>
      _core ??= await (_coreLoading ??= _loadCore());

  late final ExtensionStorageService storage = ExtensionStorageService(
    userDir: userDirectory,
  );

  late final ExtensionSecretService secrets = ExtensionSecretService(
    backend: SecretBackend.forPlatform(
      fallbackDirectory: p.join(userDirectory, 'globalStorage', 'secrets'),
    ),
    keyIndexPath: p.join(userDirectory, 'globalStorage', 'secret-keys.json'),
  );

  late final ExtensionUrlService urls = ExtensionUrlService();

  late final WorkbenchWindowFocus focus = WorkbenchWindowFocus();

  /// Which extensions are disabled, globally and per workspace.
  late final ExtensionEnablementStore enablement = ExtensionEnablementStore(
    JsonStateStore(
      p.join(userDirectory, 'globalStorage', 'extension-enablement.json'),
    ),
  );

  late final WorkspaceTrustStore trustStore = WorkspaceTrustStore(
    FileWorkspaceTrustStorage(p.join(userDirectory, 'workspaceTrust.json')),
    ignorePathCase: Platform.isMacOS || Platform.isWindows,
  );

  Future<void>? _loading;

  /// Reads enablement and trust before a workspace can run extensions.
  Future<void> load() =>
      _loading ??= Future.wait([enablement.load(), trustStore.load()])
          .then((_) {});

  /// The installed extensions as the server's `extensions.json` lists them
  /// (no server needed): each one's id, folder and manifest, enabled
  /// globally. For what must show before any extension host runs (the
  /// kept color theme).
  Future<List<Map<String, Object?>>> installedManifests() async {
    await load();
    final List<Object?> entries;
    try {
      entries = switch (jsonDecode(
        await File(p.join(extensionsDirectory, 'extensions.json'))
            .readAsString(),
      )) {
        final List<Object?> list => list,
        _ => const [],
      };
    } on Object {
      return const [];
    }
    final manifests = <Map<String, Object?>>[];
    for (final entry in entries) {
      if (entry
          case {
            'identifier': {'id': final String id},
            'relativeLocation': final String relative,
          }
          when enablement.isEnabled(id)) {
        final folder = p.join(extensionsDirectory, relative);
        try {
          final manifest = parseJsonc(
            await File(p.join(folder, 'package.json')).readAsString(),
          );
          if (manifest is! Map) continue;
          manifests.add({
            ...manifest.cast<String, Object?>(),
            'identifier': {'value': id},
            'extensionLocation': VsUri.file(folder).toJson(),
          });
        } on Object {
          // A folder gone or unreadable: not installed as far as this goes.
        }
      }
    }
    return manifests;
  }

  /// The installed extensions' color themes, before any host runs.
  Future<void> applyInstalledThemes() async {
    WorkbenchThemeService.instance.waitsForExtensionThemes = true;
    final manifests = await installedManifests();
    await Future.wait([
      WorkbenchThemeService.instance.setExtensionThemes(
        WorkspaceExtensions._contributions(manifests, 'themes'),
      ),
      FileIconThemeService.instance.setExtensionThemes(
        WorkspaceExtensions._contributions(manifests, 'iconThemes'),
      ),
    ]);
  }

  /// A workspace's extensions; [root] is its folder.
  WorkspaceExtensions workspace(String root) =>
      WorkspaceExtensions(app: this, root: root);

  Future<void> dispose() async {
    await _changes.close();
    await pool.dispose();
    trustStore.dispose();
  }
}

/// The Test Results output channel's id.
const testResultsOutputChannelId = 'testing';

/// One IDE workspace's extensions: its extension host and the main-thread
/// services the host's actors reach. Made before the workspace (it gives
/// the workspace its [languages]), then [attach]ed to it.
final class WorkspaceExtensions extends ChangeNotifier {
  WorkspaceExtensions({
    required this.app,
    required this.root,
    this._management,
    this._terminalBackend = const TerminalBackend(),
  });

  final ExtensionManagementBackend? _management;

  /// Where the terminals extensions make before the workbench binds its
  /// own start.
  final TerminalBackend _terminalBackend;

  final ExtensionsApp app;

  /// The workspace's folder.
  final String root;

  late final ExtHostWorkspace extHostWorkspace = ExtHostWorkspace.folder(root);

  /// The extensions' environment variable collections, the persistent ones
  /// kept in the workspace's storage.
  late final EnvironmentVariableService terminalEnvironment =
      EnvironmentVariableService(
        store: JsonStateStore(
          p.join(
            app.userDirectory,
            'workspaceStorage',
            extHostWorkspace.id,
            'terminal.json',
          ),
        ),
      );

  /// The terminals extensions see: the workbench's once it binds its own.
  late final ExtensionTerminals terminals = ExtensionTerminals(
    root: root,
    environment: terminalEnvironment,
    backend: _terminalBackend,
  );

  /// The documents the extension host has.
  final ExtensionDocumentRegistry documents = ExtensionDocumentRegistry();

  /// The language features the extensions provide.
  late final LanguageFeatureRoot languageRoot = LanguageFeatureRoot()
    ..documents = documents;

  /// What the editor asks for completions, hovers, diagnostics….
  LanguageFeatures get languages => languageRoot.language;

  /// The language ids of files.
  final LanguageRegistry languageRegistry = LanguageRegistry();

  /// The language id [path]'s document opens as.
  String languageIdFor(String path) {
    final id = languageRegistry.languageIdFor(path);
    return id == unknownLanguageId ? 'plaintext' : id;
  }

  final ExtensionCommandRegistry commands = ExtensionCommandRegistry(
    builtins: BuiltinCommands(),
  );
  final ContextKeyService contextKeys = ContextKeyService();

  /// The extensions' menu items (`contributes.menus`).
  late final MenuService menus = MenuService(commands);

  /// The extensions' commands in the Command Palette.
  late final ExtensionCommandPalette palette = ExtensionCommandPalette(
    registry: commands,
    contextKeys: contextKeys,
    menuService: menus,
  );
  final ExtensionStatusBarService statusBar = ExtensionStatusBarService();

  /// The file decorations extensions provide.
  final FileDecorationsService decorations = FileDecorationsService();

  /// Those, as the explorer's rows show them.
  late final ExplorerFileDecorations explorerDecorations =
      ExplorerFileDecorations(decorations);

  /// The extensions' view containers and views (`contributes.views`).
  late final ExtensionViewsService views = ExtensionViewsService(
    contextKeys: contextKeys,
    activate: (event) async => _host?.activateByEvent(event),
  );
  final ExtensionQuickInputService quickInput = ExtensionQuickInputService();
  final ExtensionOutputService output = ExtensionOutputService();
  final RunningExtensionsService running = RunningExtensionsService();
  final LanguageStatusService languageStatus = LanguageStatusService();
  late final ExtensionWebviewPlaceholders webviews =
      ExtensionWebviewPlaceholders()..onLogLine = output.logWarning;

  /// The source controls extensions register.
  final ScmService scm = ScmService();
  final SearchService search = SearchService();
  late final FileService files = FileService()
    ..registerProvider('file', DiskFileSystemProvider());
  late final WorkspaceContextService workspaceContext = WorkspaceContextService(
    extHostWorkspace,
    ignorePathCase: Platform.isMacOS || Platform.isWindows,
  );
  late final ExtensionLabelService labels = ExtensionLabelService(
    userHome:
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'],
    windows: Platform.isWindows,
  );

  /// The workbench's dialog context, set while its IDE is built.
  BuildContext? Function()? dialogContext;

  /// The user's extensions as this workspace manages them: installed by
  /// the server, enabled or disabled here or everywhere.
  late final ExtensionManagementBackend management =
      _management ??
      _AppManagement(
        ServerExtensionManagement(
          server: () => app.pool.server,
          gallery: app.gallery,
          enablement: app.enablement,
          workspaceId: extHostWorkspace.id,
          language: app.language,
        ),
        app,
      );

  ExtensionsModel? _extensionsModel;

  /// The Extensions view's state, kept while other views show.
  ExtensionsModel get extensionsModel => _extensionsModel ??= ExtensionsModel(
    backend: management,
    gallery: app.gallery,
    locale: app.language,
  );

  /// The Open VSX extensions to recommend for [documents] (the open
  /// files): those of their languages no installed extension provides
  /// (recommendations.dart), best first.
  List<String> recommendations(Iterable<IdeDocument> documents) {
    final installed = {
      for (final extension
          in _extensionsModel?.installed ?? const <InstalledExtension>[])
        extension.key,
    };
    final ids = <String>{};
    for (final doc in documents) {
      if (!doc.isFile) continue;
      ids.addAll(
        recommendationsFor(
          doc.path,
          installed: installed,
          providesLanguage: languageRegistry.installed.containsKey,
        ),
      );
    }
    return ids.toList();
  }

  IdeWorkspace? _workspace;
  IdeTextEditors? _editors;
  DocumentsAndEditorsService? _documentsAndEditors;
  IdeDocumentsPort? _documentsPort;
  ExtensionHostService? _host;
  ConfigurationService? _configuration;
  JsoncSettingsFile? _folderSettings;
  ExtensionProgressService? _progress;
  WorkspaceFileWatcher? _watcher;
  ExtensionEditorFeatureDriver? _editorFeatures;
  DebugService? _debug;
  WorkspaceDebugHost? _debugHost;
  WorkspaceTasks? _tasks;
  TestService? _testing;
  JsonStateStore? _debugState;
  WorkspaceTrustService? _trust;
  Future<void>? _trustPrompt;
  Future<void>? _debugShutdown;

  DebugService? get debug => _debug;
  WorkspaceDebugHost? get debugHost => _debugHost;

  /// The workspace's tasks, once [attach]ed.
  WorkspaceTasks? get tasks => _tasks;

  /// The extensions' tests, once [attach]ed.
  TestService? get testing => _testing;
  WorkspaceTrustService? get trust => _trust;

  /// Completion of debug-session cleanup and the final state write after dispose.
  Future<void> get debugShutdown => _debugShutdown ?? Future.value();

  /// Asked once the real workbench has a dialog context; headless stays restricted.
  Future<void> showStartupTrustPrompt() async {
    if (_disposed || _trust == null || dialogContext?.call() == null) return;
    await (_trustPrompt ??= _trust!.showStartupPromptIfNeeded(label: root));
  }

  /// The extensions' CodeLenses, inlay hints and inline completions in the
  /// editor on screen, once [attach]ed.
  ExtensionEditorFeatureDriver? get editorFeatures => _editorFeatures;
  final _stops = <void Function()>[];
  bool _disposed = false;

  /// The extension host, once [attach]ed.
  ExtensionHostService? get host => _host;

  /// The workspace's settings as extensions read them, once [attach]ed.
  ConfigurationService? get configuration => _configuration;

  /// The editors' and documents' state, once [attach]ed.
  DocumentsAndEditorsService? get documentsAndEditors => _documentsAndEditors;

  /// The window's progress (notifications and the status bar).
  ExtensionProgressService? get progress => _progress;

  /// Gives the extensions [workspace]'s documents and editors, and starts
  /// its extension host (`*`, then `onStartupFinished`) unless [start] is
  /// false.
  Future<void> attach(IdeWorkspace workspace, {bool start = true}) async {
    if (_disposed || _workspace != null) return;
    _workspace = workspace;
    await app.load();
    final core = await app.coreConfiguration();
    try {
      // The bundled languages' associations, before a document is told
      // its language.
      await TextMateSyntax.loadLanguages();
    } on Object {
      // Without them, files open as plain text until an extension says.
    }
    if (_disposed) return;
    final folderSettings = _folderSettings = JsoncSettingsFile(
      JsoncFile(p.join(root, '.vscode', 'settings.json'))..watch(),
    );
    unawaited(folderSettings.file.load());
    final configuration = _configuration = ConfigurationService(
      registry: core.registry(),
      user: app.userSettings,
      workspace: folderSettings,
    );
    languageRegistry.configuration = configuration;
    final trust = _trust = WorkspaceTrustService(
      store: app.trustStore,
      workspaceUris: () => [
        for (final folder in workspaceContext.workspaceFolders) folder.uri,
      ],
      workspaceId: extHostWorkspace.id,
      setting: (key) => configuration.getValue(key),
      prompt: IdeWorkspaceTrustPrompt(
        contextOf: () =>
            dialogContext?.call() ??
            (throw StateError('No window to request workspace trust in')),
      ),
    );
    await trust.initialize();
    if (_disposed) return;
    configuration.trusted = trust.isWorkspaceTrusted;

    final editors = _editors = IdeTextEditors(workspace);
    final documentsAndEditors = _documentsAndEditors =
        DocumentsAndEditorsService(
          documents: documents,
          editors: editors,
          decorations: null,
        );
    final state = documentsAndEditors.state;
    state.attachTabs(editors);
    final port = _documentsPort = IdeDocumentsPort(
      workspace: workspace,
      state: state,
      languageIdFor: languageIdFor,
    );
    final progress = _progress = ExtensionProgressService(
      notifications: workspace.notifications,
    );
    views.reportError = (message) =>
        workspace.notifications.notify(IdeSeverity.error, message);
    final dialogs = WorkbenchDialogs(
      context: () =>
          dialogContext?.call() ??
          (throw StateError('No window to show a dialog in')),
    );
    final authenticationApp = AuthenticationAppServices.at(
      p.join(app.userDirectory, 'globalStorage', 'authentication.json'),
      secrets: _AuthSecrets(app.secrets),
    );
    final authentication = AuthenticationService(
      access: authenticationApp.access,
    );
    final authenticationUi = AuthenticationUi(
      dialogs: dialogs,
      quickInput: DialogAuthQuickInput(
        () =>
            dialogContext?.call() ??
            (throw StateError('No window to show a dialog in')),
      ),
      clipboard: FunctionAuthClipboard(
        (text) => Clipboard.setData(ClipboardData(text: text)),
      ),
      opener: WorkbenchExternalOpener(app.openExternal ?? (_) async => false),
      notifications: workspace.notifications,
    );
    final messageUi = ExtensionMessageUi(
      notifications: workspace.notifications,
      dialogs: dialogs,
      commands: WorkbenchCommandExecutor(commands),
    );
    await terminalEnvironment.load();
    if (_disposed) return;
    final debugState = _debugState = JsonStateStore(
      p.join(
        app.userDirectory,
        'workspaceStorage',
        extHostWorkspace.id,
        'debug.json',
      ),
    );
    await debugState.load();
    if (_disposed) return;
    final debugHost = _debugHost = WorkspaceDebugHost(
      workspace: workspace,
      configuration: configuration,
      context: workspaceContext,
      keys: contextKeys,
      commands: commands,
      inputs: quickInput,
      dialogs: dialogs,
      trust: trust,
      activate: (event) async {
        final host = _host;
        if (host == null) {
          throw StateError('Workspace extensions are not attached');
        }
        await host.activateByEvent(event);
      },
      extensions: () => _host?.extensions.value ?? const [],
      language: app.language,
    );
    final debug = _debug = DebugService(
      host: debugHost,
      storage: WorkspaceDebugStorage(debugState),
      fileStore: WorkspaceLaunchFiles(files),
    );
    await debug.configurationManager.initialize();
    if (_disposed) return;
    final tasks = _tasks = WorkspaceTasks(
      workspace: workspace,
      configuration: configuration,
      context: workspaceContext,
      trust: trust,
      output: output,
      terminals: terminals,
      markers: languageRoot.markers,
      dialogs: dialogs,
      debugHost: debugHost,
      debug: debug,
      state: debugState,
      commands: commands.builtins,
      activate: (event) async => _host?.activateByEvent(event),
      extensions: () => _host?.extensions.value ?? const [],
      progress: progress,
    );
    final testResults = output.registerWorkbenchChannel(
      testResultsOutputChannelId,
      'Test Results',
    );
    final testing = _testing = TestService(
      requestTrust: () async =>
          await trust.requestWorkspaceTrust(
            message: 'Running tests may execute code in your workspace.',
          ) ==
          true,
      saveAll: () => IdeWorkspaceSave(workspace).saveAll(),
    )..onOutput = testResults.append;
    // The workbench shows the Testing view once a controller registers.
    var hadControllers = false;
    void testingChanged() {
      final has = testing.controllers.isNotEmpty;
      if (has == hadControllers) return;
      hadControllers = has;
      notifyListeners();
    }

    testing.addListener(testingChanged);
    // `editor.defaultFormatter`, and the pick when several formatters
    // could format a document.
    final defaultFormatter = DefaultFormatter(
      configuration: configuration,
      notifications: workspace.notifications,
      pick: (items, placeholder) => debugHost.pick([
        for (final (i, item) in items.indexed)
          DebugPickItem(item.label, i, description: item.description),
      ], placeholder: placeholder),
      languageName: (id) => languageRegistry.languageName(id) ?? id,
    );
    languageRoot.language
      ..defaultFormatterId = defaultFormatter.id
      ..onFormatterConflict = defaultFormatter.resolve;
    _stops.add(() {
      languageRoot.language
        ..defaultFormatterId = null
        ..onFormatterConflict = null;
    });
    final editApplier = IdeWorkspaceEditApplier(
      workspace: workspace,
      state: state,
      refactoringAutoSave: () =>
          configuration.getValue('files.refactoring.autoSave') != false,
    );
    // Trimming, code actions and format on save, final newlines and the
    // extensions' onWillSaveTextDocument, before each save.
    final saveParticipants = ExtensionSaveParticipants(
      configuration: configuration,
      languages: languageRoot.language,
      edits: editApplier,
      executeCommand: commands.executeCommand,
      languageIdFor: languageIdFor,
      editorOptions: (model) {
        final view = workspace.editorViews.active;
        if (view == null || !identical(view.controller.document, model)) {
          return null;
        }
        return (
          tabSize: view.controller.tabSize,
          insertSpaces: view.controller.insertSpaces,
        );
      },
      log: output.logWarning,
    );
    final IdeSaveParticipant participate = saveParticipants.participate;
    workspace.saveParticipants.add(participate);
    _stops.add(() => workspace.saveParticipants.remove(participate));
    final host = _host = ExtensionHostService(
      pool: app.pool,
      workspaceTrusted: () => trust.isWorkspaceTrusted,
      loadProduct: app.product,
      language: app.language,
      workspace: extHostWorkspace,
      configuration: configuration,
      customers: {
        ...windowCustomers(),
        ...commandsCustomers(),
        ...workspaceCustomers,
        ...documentsAndEditorsCustomers,
        ...languageCustomers(
          languageRoot,
          activation: (selector) => _activateLanguages(_languagesOf(selector)),
        ),
        MainContext.mainThreadConfiguration.nid:
            MainThreadConfiguration.customer,
        MainContext.mainThreadTreeViews.nid: MainThreadTreeViews.customer,
        MainContext.mainThreadDecorations.nid: MainThreadDecorations.customer,
        MainContext.mainThreadDebugService.nid: MainThreadDebugService.customer,
        MainContext.mainThreadTerminalService.nid:
            MainThreadTerminalService.customer,
        MainContext.mainThreadTerminalShellIntegration.nid:
            MainThreadTerminalShellIntegration.customer,
        MainContext.mainThreadTask.nid: MainThreadTask.customer,
        MainContext.mainThreadSCM.nid: MainThreadSCM.customer,
        MainContext.mainThreadTesting.nid: MainThreadTesting.customer,
      },
      services: {
        DebugService: debug,
        TaskService: tasks.service,
        ScmService: scm,
        TestService: testing,
        ExtensionTerminals: terminals,
        WorkspaceTrustService: trust,
        ExtensionCommandRegistry: commands,
        ContextKeyService: contextKeys,
        CommandActivation: _LazyCommandActivation(this),
        DocumentsAndEditorsService: documentsAndEditors,
        DocumentsPort: port,
        TextContentProvidersPort: port,
        EditorTabsHost: editors,
        WorkspaceEditApplier: editApplier,
        ExtensionSaveParticipants: saveParticipants,
        WorkspaceSavePort: IdeWorkspaceSave(workspace),
        LanguageRegistry: languageRegistry,
        LanguageStatusService: languageStatus,
        WorkspaceContextService: workspaceContext,
        SearchService: search,
        FileService: files,
        ExtensionOutputService: output,
        RunningExtensionsService: running,
        ExtensionStatusBarService: statusBar,
        ExtensionViewsService: views,
        FileDecorationsService: decorations,
        ExtensionQuickInputService: quickInput,
        ExtensionProgressService: progress,
        ExtensionMessageUi: messageUi,
        ExtensionCommandExecutor: WorkbenchCommandExecutor(commands),
        ExtensionLabelService: labels,
        ExtensionStorageService: app.storage,
        ExtensionSecretService: app.secrets,
        ExtensionUrlService: app.urls,
        ExtensionWindowFocus: app.focus,
        ExtensionExternalOpener: WorkbenchExternalOpener(
          app.openExternal ?? (_) async => false,
        ),
        ExtensionFilePickers: app.filePickers ?? const _NoFilePickers(),
        ExtensionWebviewPlaceholders: webviews,
        ExtensionWebviewUi: ExtensionWebviewUi(
          placeholders: webviews,
          notifications: workspace.notifications,
          commands: WorkbenchCommandExecutor(commands),
          opener: WorkbenchExternalOpener(
            app.openExternal ?? (_) async => false,
          ),
          onOutput: () => output.showChannel(
            ExtensionOutputService.extensionHostChannelId,
          ),
        ),
        ExtensionAuthenticationUi: ExtensionAuthenticationUi(
          authentication: authentication,
          app: authenticationApp,
          extensions: AuthenticationExtensionsService(
            authentication: authentication,
            app: authenticationApp,
            ui: authenticationUi,
          ),
          ui: authenticationUi,
          urls: app.urls,
        ),
        ExtensionHostLog: ExtensionHostLog(
          (message) => output.logExtensionHostMessage({
            'type': r'__$console',
            'severity': 'warn',
            'arguments': jsonEncode([message]),
          }),
        ),
      },
      includeExtension: (description) =>
          app.enablement.isEnabled(
            _idOf(description),
            workspaceId: extHostWorkspace.id,
          ) &&
          runsInWorkspace(
            description,
            trusted: trust.isWorkspaceTrusted,
            trustEnabled: trust.isWorkspaceTrustEnabled,
            configured: (configuration.getValue(
              'extensions.supportUntrustedWorkspaces',
            ) as Map?)?.cast(),
          ),
    );
    void updateTrust() {
      trust.update();
      configuration.trusted = trust.isWorkspaceTrusted;
    }

    configuration.addListener(updateTrust);
    workspaceContext.addListener(updateTrust);
    _stops.add(() {
      configuration.removeListener(updateTrust);
      workspaceContext.removeListener(updateTrust);
    });
    final trustChanges = trust.onDidChangeTrust.listen((trusted) {
      configuration.trusted = trusted;
      contextKeys.setContext('isWorkspaceTrusted', trusted);
      // JS trust can only be granted in place; revocation needs a fresh host.
      if (!trusted && host.manager.rpc != null) {
        unawaited(host.manager.restart());
      } else {
        unawaited(_refreshExtensions());
      }
      notifyListeners();
    });
    contextKeys.setContext('isWorkspaceTrusted', trust.isWorkspaceTrusted);
    final saved = state.saved.listen((uri) {
      debug.onFilesSaved([uri]);
      if (_isLaunchFile(uri)) unawaited(_reloadDebugLaunches());
    });
    final fileChanges = files.onDidFilesChange.listen((changes) {
      debug.onFilesDeleted([
        for (final change in changes)
          if (change.type == FileChangeType.deleted) change.resource,
      ]);
      if (changes.any((change) => _isLaunchFile(change.resource))) {
        unawaited(_reloadDebugLaunches());
      }
    });
    _stops.add(() {
      unawaited(trustChanges.cancel());
      unawaited(saved.cancel());
      unawaited(fileChanges.cancel());
    });
    commands.activation = ExtensionHostCommandActivation(host);
    _stops.add(
      registerWorkbenchBuiltinCommands(
        commands.builtins,
        contextKeys: contextKeys,
      ),
    );
    _stops.add(registerLanguageCommands(languageRoot, commands.builtins));
    languageRoot.commandExecutor = (command) async {
      if (command case {'id': final String id}) {
        final args = switch (command['arguments']) {
          final List<Object?> args => args,
          _ => const <Object?>[],
        };
        await commands.executeCommand(id, args);
      }
    };
    _editorFeatures = ExtensionEditorFeatureDriver(
      views: workspace.editorViews,
      languages: languageRoot.language,
      service: languageRoot.service,
      executeCommand: commands.executeCommand,
      openLocation: (uri, range) async {
        if (uri.scheme != 'file') return;
        await workspace.openAt(
          uri.fsPath(),
          LspRange(
            LspPosition(range.startLineNumber - 1, range.startColumn - 1),
            LspPosition(range.endLineNumber - 1, range.endColumn - 1),
          ),
        );
      },
      openLink: (uri) async {
        if (uri.scheme == 'file') {
          await workspace.open(uri.fsPath());
        } else if (uri.scheme == app.urls.scheme) {
          await app.urls.open(uri);
        } else if (uri.scheme == 'http' || uri.scheme == 'https') {
          await app.openExternal?.call(uri.toString());
        }
      },
      languageIdOf: languageIdFor,
      setting: (key, languageId) =>
          configuration.getValue(key, languageId: languageId),
    );
    host.extensions.addListener(_extensionsChanged);
    host.addListener(notifyListeners);
    // Installed, uninstalled, enabled or disabled anywhere: the running
    // host is told (restarted when it must drop an extension it runs).
    final changes = app.changes.listen((_) => unawaited(_refreshExtensions()));
    _stops.add(() => unawaited(changes.cancel()));
    _watcher = WorkspaceFileWatcher(
      files: files,
      workspace: workspaceContext,
      configuration: configuration,
    );

    // File icon themes that map languages ask the last workspace opened.
    FileIconThemeService.instance.languageIdOf = languageIdFor;
    _stops.add(() {
      final icons = FileIconThemeService.instance;
      if (icons.languageIdOf == languageIdFor) icons.languageIdOf = null;
    });

    // The documents the workspace has open, and those it opens from now.
    workspace
      ..extensionDocuments = state
      ..syncExtensionDocuments();
    documents.addListener(_documentsChanged);
    notifyListeners();
    if (start) unawaited(startHost());
    unawaited(showStartupTrustPrompt());
  }

  bool _isLaunchFile(VsUri uri) => workspaceContext.workspaceFolders.any(
    (folder) => uriEqual(
      uri,
      folder.uri.joinPath(['.vscode', 'launch.json']),
      ignoreCase: Platform.isMacOS || Platform.isWindows,
    ),
  );

  Future<void> _reloadDebugLaunches() async {
    if (_disposed) return;
    try {
      await _debug?.configurationManager.reload();
    } on Object catch (error) {
      if (!_disposed) {
        _workspace?.notifications.notify(IdeSeverity.error, '$error');
      }
    }
  }

  /// Runs the extension in [folder] as one under development
  /// (`--extensionDevelopmentPath`): the host starts again with it.
  Future<void> loadDevelopmentExtension(String folder) async {
    final host = _host;
    if (host == null) return;
    final location = VsUri.file(folder);
    if (!host.developmentLocations.contains(location)) {
      host.developmentLocations = [...host.developmentLocations, location];
    }
    await host.manager.restart();
  }

  Future<void> _refreshExtensions() async {
    try {
      await _host?.refreshExtensions();
    } on Object catch (error) {
      output.logExtensionHostMessage({
        'type': r'__$console',
        'severity': 'error',
        'arguments': jsonEncode(['Could not update the extensions: $error']),
      });
    }
  }

  /// The language ids [selector] names (`*` and filters without one
  /// name none).
  static Set<String> _languagesOf(LanguageSelector selector) =>
      switch (selector) {
        LanguageIdSelector(:final languageId) when languageId != '*' => {
          languageId,
        },
        LanguageIdSelector() => const {},
        LanguageFilter(:final language)
            when language != null && language != '*' =>
          {language},
        LanguageFilter() => const {},
        LanguageSelectorList(:final selectors) => {
          for (final item in selectors) ..._languagesOf(item),
        },
      };

  static String _idOf(Map<String, Object?> description) =>
      switch (description['identifier']) {
        {'value': final String value} => value,
        final Object? other => '$other',
      };

  /// Starts the extension host and runs the startup activation events;
  /// what went wrong is in the extension host's output.
  Future<void> startHost() async {
    final host = _host;
    if (host == null) return;
    try {
      await host.startup();
      _documentsChanged();
    } on Object catch (error) {
      output.logExtensionHostMessage({
        'type': r'__$console',
        'severity': 'error',
        'arguments': jsonEncode(['Extension host failed to start: $error']),
      });
    }
  }

  /// The languages `onLanguage:` was sent for.
  final Set<String> _activatedLanguages = {};

  /// A document opened in a language not seen before: its extensions
  /// activate (`onLanguage:<id>`, and `onLanguage`).
  void _documentsChanged() {
    final host = _host;
    if (host == null) return;
    final languages = {
      for (final document in documents.documents) document.mirror.languageId,
    };
    unawaited(_activateLanguages(languages));
  }

  Future<void> _activateLanguages(Iterable<String> languages) async {
    final host = _host;
    if (host == null) return;
    final fresh = [
      for (final language in languages)
        if (_activatedLanguages.add(language)) language,
    ];
    if (fresh.isEmpty) return;
    try {
      // Upstream fires both without waiting on either.
      await Future.wait([
        for (final language in fresh)
          host.activateByEvent('onLanguage:$language'),
        host.activateByEvent('onLanguage'),
      ]);
    } on Object {
      // Logged by the host's output; the editor carries on without. When
      // the host could not start (no runtime yet), the next start asks
      // again.
      if (host.manager.state == ExtensionHostState.failed) {
        _activatedLanguages.removeAll(fresh);
      }
    }
  }

  /// The installed extensions changed (the host scanned them): their
  /// commands, menus, status bar items and languages.
  void _extensionsChanged() {
    final host = _host;
    if (host == null) return;
    final extensions = host.extensions.value;
    // Those of extensions gone go with them.
    terminalEnvironment.retain({
      for (final extension in extensions) _idOf(extension),
    });
    _debug?.registry.setExtensions(debuggerExtensions(extensions));
    _tasks?.extensionsChanged();
    commands.setExtensions(extensions);
    statusBar.setContributions(extensions);
    views.setExtensions(commands.extensions);
    for (final message in views.messages) {
      if (_viewMessages.add(message)) {
        output.logExtensionHostMessage({
          'type': r'__$console',
          'severity': 'warn',
          'arguments': jsonEncode([message]),
        });
      }
    }
    unawaited(_registerLanguages(extensions));
    // The app's themes are the running extensions' (the same in every
    // workspace: the installed and enabled ones).
    unawaited(
      WorkbenchThemeService.instance.setExtensionThemes(
        _contributions(extensions, 'themes'),
      ),
    );
    unawaited(
      FileIconThemeService.instance.setExtensionThemes(
        _contributions(extensions, 'iconThemes'),
      ),
    );
    notifyListeners();
  }

  /// Each of [extensions]' `contributes.<point>` entries, with the
  /// extension's id and folder.
  static List<
    ({String extensionId, String location, Map<String, Object?> theme})
  >
  _contributions(List<Map<String, Object?>> extensions, String point) => [
    for (final extension in extensions)
      if (extension['contributes'] case final Map<Object?, Object?> contributes)
        if (contributes[point] case final List<Object?> entries)
          if (extension['extensionLocation']
              case final Map<Object?, Object?> location)
            for (final entry in entries)
              if (entry case final Map<Object?, Object?> theme)
                (
                  extensionId: _idOf(extension),
                  location: VsUri.revive(location.cast()).fsPath(),
                  theme: theme.cast<String, Object?>(),
                ),
  ];

  final Set<String> _languageExtensions = {};

  /// The contribution problems logged already.
  final Set<String> _viewMessages = {};

  Future<void> _registerLanguages(List<Map<String, Object?>> extensions) async {
    final seen = <String>{};
    for (final extension in extensions) {
      final id = _idOf(extension);
      seen.add(id);
      final contributes = extension['contributes'];
      if (contributes is! Map) continue;
      final languages = contributes['languages'];
      if (languages is! List || languages.isEmpty) continue;
      final location = switch (extension['extensionLocation']) {
        final Map<Object?, Object?> uri => VsUri.revive(uri.cast()),
        _ => null,
      };
      final contributions = [
        for (final language in languages)
          if (language is Map) language.cast<String, Object?>(),
      ];
      final configurations = <String, Map<String, Object?>>{};
      final configurationPaths = <String, String>{};
      if (location != null && location.scheme == 'file') {
        for (final language in contributions) {
          final languageId = language['id'];
          final relative = language['configuration'];
          if (languageId is! String || relative is! String) continue;
          final path = p.normalize(p.join(location.fsPath(), relative));
          try {
            final json = parseJsonc(await File(path).readAsString());
            if (json is Map) {
              configurations[languageId] = json.cast();
              configurationPaths[languageId] = path;
            }
          } on Object {
            // A missing or broken file: the language has no configuration.
          }
        }
      }
      if (_disposed) return;
      languageRegistry.unregisterExtension(id);
      languageRegistry.registerExtensionLanguages(
        id,
        contributions,
        configurations: configurations,
        configurationPaths: configurationPaths,
      );
      _languageExtensions.add(id);
    }
    for (final id in _languageExtensions.difference(seen).toList()) {
      languageRegistry.unregisterExtension(id);
      _languageExtensions.remove(id);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final stop in _stops) {
      stop();
    }
    documents.removeListener(_documentsChanged);
    final workspace = _workspace;
    if (workspace != null &&
        identical(workspace.extensionDocuments, _documentsAndEditors?.state)) {
      workspace.extensionDocuments = null;
    }
    _tasks?.dispose();
    _testing?.dispose();
    scm.dispose();
    _debugHost?.dispose();
    _debugShutdown = () async {
      await _host?.context?.dispose();
      _debug?.dispose();
      await _debugState?.dispose();
    }();
    _host
      ?..extensions.removeListener(_extensionsChanged)
      ..removeListener(notifyListeners)
      ..dispose();
    _watcher?.dispose();
    terminals.dispose();
    unawaited(terminalEnvironment.store?.dispose());
    _editorFeatures?.dispose();
    _documentsPort?.dispose();
    _documentsAndEditors?.dispose();
    _editors?.dispose();
    _progress?.dispose();
    _trust?.dispose();
    _configuration?.dispose();
    _folderSettings
      ?..file.dispose()
      ..dispose();
    _extensionsModel?.dispose();
    if (management case final _AppManagement management) management.dispose();
    languageRoot.dispose();
    menus.dispose();
    views.dispose();
    explorerDecorations.dispose();
    decorations.dispose();
    commands.dispose();
    contextKeys.dispose();
    statusBar.dispose();
    quickInput.dispose();
    output.dispose();
    running.dispose();
    languageStatus.dispose();
    webviews.dispose();
    languageRegistry.dispose();
    documents.dispose();
    super.dispose();
  }
}

/// No open or save panel (a headless app): every pick is cancelled.
/// A workspace's [ServerExtensionManagement], told of the changes any
/// workspace makes ([ExtensionsApp.changes]).
final class _AppManagement implements ExtensionManagementBackend {
  _AppManagement(this._inner, this._app) {
    _inner.onDidChange.listen((event) {
      if (!_app._changes.isClosed) _app._changes.add(event);
    });
  }

  final ServerExtensionManagement _inner;
  final ExtensionsApp _app;

  @override
  Stream<ExtensionManagementEvent> get onDidChange => _app.changes;

  @override
  Future<List<InstalledExtension>> getInstalled() async {
    await _app.load();
    return _inner.getInstalled();
  }

  @override
  Future<InstalledExtension> install(
    String vsixPath, {
    ExtensionInstallOptions options = const ExtensionInstallOptions(),
  }) => _inner.install(vsixPath, options: options);

  @override
  Future<InstalledExtension> installFromGallery(
    String id, {
    String? version,
    bool preRelease = false,
    CancellationToken cancel = CancellationToken.none,
  }) => _inner.installFromGallery(
    id,
    version: version,
    preRelease: preRelease,
    cancel: cancel,
  );

  @override
  Future<InstalledExtension> installFromFolder(String path) =>
      _inner.installFromFolder(path);

  @override
  Future<void> uninstall(String id) async {
    await _app.load();
    return _inner.uninstall(id);
  }

  @override
  Future<void> setEnabled(
    String id,
    bool enabled, {
    EnablementScope scope = EnablementScope.global,
  }) async {
    await _app.load();
    return _inner.setEnabled(id, enabled, scope: scope);
  }

  void dispose() => _inner.dispose();
}

final class _NoFilePickers implements ExtensionFilePickers {
  const _NoFilePickers();

  @override
  Future<List<String>?> pickOpen({
    required bool files,
    required bool folders,
    required bool many,
    String? directory,
    String? title,
    String? openLabel,
    Map<String, List<String>> filters = const {},
  }) async => null;

  @override
  Future<String?> pickSave({
    String? directory,
    String? name,
    String? title,
    String? saveLabel,
    Map<String, List<String>> filters = const {},
  }) async => null;
}

/// The authentication's secrets in the app's secret storage.
final class _AuthSecrets implements AuthSecretStore {
  _AuthSecrets(this.secrets);

  final ExtensionSecretService secrets;

  static const _owner = 'baocode.authentication';

  @override
  Future<String?> get(String key) => secrets.get(_owner, key);

  @override
  Future<void> set(String key, String value) => secrets.set(_owner, key, value);

  @override
  Future<void> delete(String key) => secrets.delete(_owner, key);

  @override
  Stream<String> get onDidChange => secrets.changes
      .where((change) => change.extensionId == _owner)
      .map((change) => change.key);
}

/// The commands' activation once the host exists ([CommandActivation]).
final class _LazyCommandActivation implements CommandActivation {
  _LazyCommandActivation(this.extensions);

  final WorkspaceExtensions extensions;

  @override
  Future<void> activateByEvent(String activationEvent) =>
      extensions.host?.activateByEvent(activationEvent) ?? Future.value();

  @override
  bool activationEventIsDone(String activationEvent) =>
      extensions.host?.manager.activatedOn(activationEvent) ?? false;

  @override
  bool get extensionHostIsReady =>
      extensions.host?.manager.state == ExtensionHostState.running;
}

/// `ExtensionActivator` for the file system actors.
ExtensionActivator extensionActivatorOf(WorkspaceExtensions extensions) =>
    ExtensionActivator(
      (event) => extensions.host?.activateByEvent(event) ?? Future.value(),
    );
