// The showcase app: BaoCodeApp, whole, on a made-up developer's machine
// (a home folder of its own with well-known open-source projects, their
// past Claude Code sessions, a Git identity and a shell), its agents
// playing scripts (show_transport.dart, scripts.dart), driven through its
// scenes (scenes.dart), each ending in pictures and videos of its window
// for the website. Built and run by tool/showcase/run.dart, which made the
// home folder first; see tool/showcase/README.md.
//
// Its settings come from the environment:
// - BAOCODE_SHOWCASE_HOME: the made-up home folder (also the process's
//   HOME, for Git and the shell).
// - BAOCODE_SHOWCASE_DATA: the app's data folder.
// - BAOCODE_SHOWCASE_OUT: where the pictures and videos go.
// - BAOCODE_SHOWCASE_LOCALE: `en` or `zh`.
// - BAOCODE_SHOWCASE_SCENES: the scenes to run, comma-separated; all by
//   default.
// - BAOCODE_SHOWCASE_VIDEO: `0` for pictures only.

import 'dart:async';
import 'dart:io';
import 'dart:ui' show ViewFocusState;

import 'package:bao_editor/monaco/flutter/language_assets.dart';
import 'package:bao_remote/local.dart' show ClaudeEnvironment;
import 'package:baocode/customize/customization_store.dart';
import 'package:baocode/icons/emoji_sheet.dart';
import 'package:baocode/ide/lsp/packs/language_packs.dart';
import 'package:baocode/ide/terminal/terminal_instance.dart';
import 'package:baocode/keybindings/keybindings_sync.dart';
import 'package:baocode/keybindings/keymap.dart';
import 'package:baocode/kernel/claude_code/claude_core_setting.dart';
import 'package:baocode/kernel/kernel_registry.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/main.dart' show BaoCodeApp, followSettingsFiles;
import 'package:baocode/platform/data_dir.dart';
import 'package:baocode/platform/memory_budget.dart';
import 'package:baocode/remote/project_host.dart';
import 'package:baocode/search/claude_conversation_search.dart';
import 'package:baocode/settings/app_locale.dart';
import 'package:baocode/settings/app_settings.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../perf/perf_input.dart';
import 'scenes.dart';
import 'show_camera.dart';
import 'show_transport.dart';
import 'story.dart';

String _env(String name, [String? fallback]) =>
    switch (Platform.environment[name]) {
      final value? when value.isNotEmpty => value,
      _ => fallback ?? (throw ArgumentError('$name is not set')),
    };

Future<void> main() async {
  HttpOverrides.global = _Offline();
  _ShowBinding();
  _isolateFromTheDesktop();
  Timer(const Duration(minutes: 40), () {
    ShowScene.log('timed out');
    exit(3);
  });
  try {
    await _run();
  } catch (error, stack) {
    ShowScene.log('failed: $error\n$stack');
    exit(1);
  }
  exit(0);
}

Future<void> _run() async {
  final home = _env('BAOCODE_SHOWCASE_HOME');
  final out = _env('BAOCODE_SHOWCASE_OUT');
  Story.locale = _env('BAOCODE_SHOWCASE_LOCALE', 'en');
  final wanted = Platform.environment['BAOCODE_SHOWCASE_SCENES']
      ?.split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();
  final video = Platform.environment['BAOCODE_SHOWCASE_VIDEO'] != '0';

  MemoryBudget.apply();
  DataDirectory.current = DataDirectory(_env('BAOCODE_SHOWCASE_DATA'));
  // Claude Code's folder, Git and the shell are the made-up home's.
  ClaudeEnvironment.use({
    ...Platform.environment,
    'HOME': home,
    'CLAUDE_CONFIG_DIR': p.join(home, '.claude'),
  });
  MonacoLanguageAssets.defaultPacks = () => LanguagePackRegistry.instance;
  final files = SettingsFiles.instance;
  await files.load();
  followSettingsFiles(files);
  EmojiSheet.start(EmojiSheetStore.cache());
  KernelRegistry.use([showClaudeCode]);
  ClaudeCore.current = () => ClaudeCore.cli;
  final themes = WorkbenchThemeService.instance;
  themes.restore(setting: ThemeSettingDefaults.colorThemeDark);
  await themes.initialize();
  await _bringWindowFront();

  final locale = AppLocale(
    storage: MemoryLocaleStorage(
      Story.zh ? AppLocale.simplifiedChinese : AppLocale.english,
    ),
  );
  final l10n = lookupAppLocalizations(locale.locale!);
  final catalog = KeymapCatalog(keymapsDir: DataDirectory.current.keymapsDir);
  final sync = KeybindingsSync(
    keybindings: files.keybindings,
    settings: files.settings,
    catalog: catalog,
  )..start();
  await sync.ready;

  for (final scene in showScenes) {
    if (wanted != null && !wanted.contains(scene.name)) continue;
    ShowScene.log('scene ${scene.name}');
    final shotKey = GlobalKey();
    final window = ValueNotifier(scene.window);
    final workspace = Workspace(
      preferences: PreferenceStore.file(
        p.join(DataDirectory.current.stateDir, 'scene-${scene.name}.json'),
      ),
      l10n: () => l10n,
    );
    final customizations = CustomizationStore();
    final settings = AppSettings(
      locale: locale,
      files: files,
      catalog: catalog,
      sync: sync,
      workspace: workspace,
      customizations: customizations,
    );
    final context = ShowScene(
      name: scene.name,
      home: home,
      out: p.join(out, Story.locale),
      workspace: workspace,
      window: window,
      camera: ShowCamera(shotKey),
      input: PerfInput(),
      video: video,
      settings: files,
      l10n: l10n,
    );
    await scene.setUp?.call(context);
    unawaited(workspace.load());
    runApp(
      ShowFrame(
        window: window,
        shotKey: shotKey,
        child: BaoCodeApp(
          key: UniqueKey(),
          workspace: workspace,
          appLocale: locale,
          settings: settings,
          gitFor: (folder) {
            final host = ProjectHost.of(folder);
            return host.git(host.pathOf(folder));
          },
          repositoriesIn: (folder, scan) {
            final host = ProjectHost.of(folder);
            return host.repositoriesIn(host.pathOf(folder), scan);
          },
          terminalBackend: TerminalBackend(settings: files.settings),
          conversations: ClaudeConversationSearch(),
          customizations: customizations,
        ),
      ),
    );
    try {
      await context.until(() => workspace.threads.isNotEmpty, 'the agents');
      await context.settle(const Duration(milliseconds: 1200));
      await scene.run(context);
    } catch (error, stack) {
      ShowScene.log('${scene.name} failed: $error\n$stack');
      exitCode = 1;
    }
    ShowScripts.clear();
    runApp(const SizedBox.shrink());
    await context.settle(const Duration(milliseconds: 400));
    workspace.dispose();
    await themes.setColorTheme(ThemeSettingDefaults.colorThemeDark);
  }
}

/// No request leaves the machine: the pictures are of what the showcase
/// made up, not of what a server answers (the upstreams baocode.dev lists,
/// say), and the app asks no one anything for them. Only the app's own
/// servers on this machine answer (its model proxy, say); each request
/// refused is in the log.
class _Offline extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..connectionFactory = (url, proxyHost, proxyPort) {
          final host = url.host;
          if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
            return Socket.startConnect(host, url.port);
          }
          ShowScene.log('refused a request to $url');
          return Future.error(SocketException('offline: $host'));
        };
}

/// The app's binding, but for what it would do to the machine beyond its
/// window's content, which is the installed app's as much as its own (the
/// same bundle, the same defaults): the window's appearance and size, the
/// clipboard, the recent files, the trash.
class _ShowBinding extends WidgetsFlutterBinding {
  @override
  BinaryMessenger createBinaryMessenger() =>
      _KeptMessenger(super.createBinaryMessenger());
}

class _KeptMessenger implements BinaryMessenger {
  _KeptMessenger(this._messenger);

  final BinaryMessenger _messenger;

  static const _kept = {
    'baocode/window': {
      'growWindow',
      'setAlwaysOnTop',
      'setAppearance',
      'setRecentItems',
      'trashItem',
      'windowRoom',
      'writePasteboardFiles',
      'writePasteboardImage',
    },
    'flutter/platform': {'Clipboard.setData'},
  };

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    if (_kept[channel] case final methods? when message != null) {
      final codec = channel == 'flutter/platform'
          ? const JSONMethodCodec()
          : const StandardMethodCodec();
      final call = codec.decodeMethodCall(message);
      if (methods.contains(call.method)) {
        if (call.method == 'windowRoom') {
          return Future.value(
            codec.encodeSuccessEnvelope({'width': 4000.0, 'height': 4000.0}),
          );
        }
        return Future.value(codec.encodeSuccessEnvelope(null));
      }
    }
    return _messenger.send(channel, message);
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) =>
      _messenger.setMessageHandler(channel, handler);

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) =>
      // ignore: deprecated_member_use
      _messenger.handlePlatformMessage(channel, data, callback);
}

/// Only the scenes' input counts, and the app stays in front as far as it
/// can tell: the user's mouse over the window would hover and show
/// tooltips; another app in front would take the focus.
void _isolateFromTheDesktop() {
  final binding = WidgetsBinding.instance;
  binding.platformDispatcher.onPointerDataPacket = (_) {};
  SystemChannels.lifecycle.setMessageHandler((message) async => null);
  binding.platformDispatcher.onViewFocusChange = (event) {
    if (event.state == ViewFocusState.focused) {
      binding.handleViewFocusChanged(event);
    }
  };
  // ignore: invalid_use_of_protected_member
  binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

Future<void> _bringWindowFront() async {
  final view = WidgetsBinding.instance.platformDispatcher.implicitView;
  try {
    await const MethodChannel('baocode/windows')
        .invokeMethod('focus', view?.viewId ?? 0);
  } on Object catch (error) {
    ShowScene.log('could not bring the window to the front: $error');
  }
  await Future<void>.delayed(const Duration(milliseconds: 500));
}
