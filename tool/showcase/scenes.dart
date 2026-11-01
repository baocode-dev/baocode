// The showcase's scenes: each sets the app up as a picture or a video of
// it should show, and takes them (see showcase_app.dart).

import 'dart:async';
import 'dart:io';

import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/composer/composer_files.dart';
import 'package:baocode/icons/project_icon.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:flutter/services.dart';

import 'dart:ui' as ui;

import 'package:baocode/ide/git/ide_git_log_view.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/terminal/terminal_instance.dart';
import 'package:baocode/ide/terminal/terminal_view.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:baocode/workspace/chat_grid.dart';
import 'package:baocode/workspace/window_controls.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../perf/perf_input.dart';
import 'code.dart';
import 'scripts.dart';
import 'show_camera.dart';
import 'show_transport.dart';
import 'story.dart';

class ShowSceneSpec {
  const ShowSceneSpec(
    this.name,
    this.run, {
    this.window = const ShowWindow(Size(1360, 860)),
    this.setUp,
  });

  final String name;
  final ShowWindow window;

  /// Before the app starts: files written, settings set.
  final Future<void> Function(ShowScene scene)? setUp;
  final Future<void> Function(ShowScene scene) run;
}

const _light = ShowWindow(Size(1360, 860), dark: false);

final List<ShowSceneSpec> showScenes = [
  ShowSceneSpec('main', _main),
  ShowSceneSpec('ide', _ide),
  ShowSceneSpec('review', _review),
  ShowSceneSpec('goal', _goal),
  ShowSceneSpec('composer', _composer),
  ShowSceneSpec('models', _models, setUp: _withUpstreams),
  ShowSceneSpec('customize', _customize),
  ShowSceneSpec('notifications', _notifications),
  ShowSceneSpec('themes-light', _themesLight, window: _light),
  ShowSceneSpec('themes-dark', _themesDark),
  ShowSceneSpec('video-agents', _videoAgents),
  ShowSceneSpec('video-ide', _videoIde),
  ShowSceneSpec('video-themes', _videoThemes),
];

/// What a scene works with: the app's workspace, its window, its input,
/// and the camera.
class ShowScene {
  ShowScene({
    required this.name,
    required this.home,
    required this.out,
    required this.workspace,
    required this.window,
    required this.camera,
    required this.input,
    required this.video,
    required this.settings,
    required this.l10n,
  });

  final AppLocalizations l10n;

  final String name;
  final String home;
  final String out;
  final Workspace workspace;
  final ValueNotifier<ShowWindow> window;
  final ShowCamera camera;
  final PerfInput input;
  final bool video;
  final SettingsFiles settings;

  static void log(String message) =>
      stderr.writeln('BAOCODE_SHOWCASE_LOG $message');

  String code(String project) => p.join(home, 'code', project);

  String get hono => code('hono');

  // --- Time ------------------------------------------------------------------

  Future<void> settle([
    Duration time = const Duration(milliseconds: 800),
  ]) async {
    // As long on the video's clock, while one is recorded.
    time *= ShowClock.dilation;
    final watch = Stopwatch()..start();
    while (watch.elapsed < time) {
      await nextFrame();
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  Future<void> until(
    bool Function() done,
    String what, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final watch = Stopwatch()..start();
    while (!done()) {
      if (watch.elapsed > timeout) throw TimeoutException('waiting for $what');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  // --- Agents ----------------------------------------------------------------

  Project project(String name) =>
      workspace.projects.firstWhere((project) => project.name == name);

  AgentThread? kept(String title) =>
      workspace.threads.where((thread) => thread.title == title).firstOrNull;

  /// A new agent in [project] sent [prompt], answered by [script], titled
  /// [title].
  Future<AgentThread> start(
    String project,
    String prompt,
    ShowScript script, {
    String? title,
  }) async {
    final thread = workspace.create(project: this.project(project));
    ShowScripts.register(prompt, script);
    final session = thread.session;
    await until(() => session.canSend, 'the agent to take a message');
    session.send(ComposerMessage(text: prompt));
    if (title != null) workspace.rename(thread, title);
    return thread;
  }

  /// The projects' icons, and the past conversations the story pins.
  void decorate() {
    for (final project in Story.projects) {
      if (workspace.projects.where((p) => p.name == project.name).firstOrNull
          case final listed?) {
        workspace.setIcon(listed, EmojiIcon(project.emoji));
      }
    }
    for (final project in Story.projects) {
      for (final session in project.sessions) {
        if (!session.pinned) continue;
        if (kept(session.title) case final thread?) {
          workspace.setPinned(thread, true);
        }
      }
    }
  }

  // --- The view ----------------------------------------------------------------

  /// The state of the first [T] in the app.
  T? state<T extends State>() {
    T? found;
    void visit(Element element) {
      if (found != null) return;
      if (element case StatefulElement(:final T state)) {
        found = state;
        return;
      }
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return found;
  }

  /// The first [T] widget in the app.
  T? widget<T extends Widget>() {
    T? found;
    void visit(Element element) {
      if (found != null) return;
      if (element.widget case final T widget) {
        found = widget;
        return;
      }
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return found;
  }

  /// Runs [args] with Git in [project], as the user would.
  Future<void> git(String project, List<String> args) async {
    final result = await Process.run(
      'git',
      args,
      workingDirectory: code(project),
    );
    if (result.exitCode != 0) throw StateError('git $args: ${result.stderr}');
  }

  /// [project] as committed: what a scene before changed undone.
  Future<void> reset(String project) async {
    await git(project, ['checkout', '--', '.']);
    await git(project, ['clean', '-fdq']);
  }

  /// Shows the IDE on [project], [thread] in its chat; its workbench.
  Future<IdeWorkbenchState> openIde(
    String project, {
    AgentThread? thread,
  }) async {
    final folder = code(project);
    workspace.openIdeFolder(folder);
    if (thread != null) workspace.openIdeChat(folder, thread);
    workspace.layout = WorkspaceLayout.ide;
    await until(() => state<IdeWorkbenchState>() != null, 'the IDE');
    await settle();
    return state<IdeWorkbenchState>()!;
  }

  /// The IDE's terminal, opened if none is.
  Future<TerminalInstance> terminal(IdeWorkbenchState ide) async {
    if (widget<TerminalView>() == null) {
      ide.runCommand('workbench.action.terminal.new');
    }
    await until(() => widget<TerminalView>() != null, 'a terminal');
    await settle(const Duration(milliseconds: 1500));
    return widget<TerminalView>()!.instance;
  }

  /// The text on screen that has [text] in it (or is [text], if
  /// [exact]), where it is; the first.
  Rect? textRect(String text, {bool exact = false}) {
    Rect? found;
    void visit(RenderObject object) {
      if (found != null) return;
      if (object is RenderParagraph &&
          object.attached &&
          object.hasSize &&
          switch (object.text.toPlainText()) {
            final shown when exact => shown.trim() == text,
            final shown => shown.contains(text),
          }) {
        found = object.localToGlobal(Offset.zero) & object.size;
        return;
      }
      object.visitChildren(visit);
    }

    for (final view in WidgetsBinding.instance.renderViews) {
      view.visitChildren(visit);
    }
    return found;
  }

  /// Clicks the text that has [text] in it, or is [text] if [exact].
  Future<void> tapText(String text, {bool exact = false}) async {
    await until(() => textRect(text, exact: exact) != null, '“$text” to show');
    await input.click(textRect(text, exact: exact)!.center);
    await settle(const Duration(milliseconds: 300));
    // Nothing left hovered, no tooltip in the pictures.
    input.leave();
    await settle(const Duration(milliseconds: 200));
  }

  /// Presses [key], with ⌘ if [meta], ⇧ if [shift].
  Future<void> press(
    LogicalKeyboardKey key, {
    bool meta = false,
    bool shift = false,
  }) async {
    input.press(key, meta: meta, shift: shift);
    await settle(const Duration(milliseconds: 300));
  }

  /// Opens the settings on [section], its label.
  Future<void> openSettings(String section) async {
    // As the app menu's Settings… does it.
    WindowControls.onMenuCommand?.call('workbench.action.openSettings');
    await settle(const Duration(milliseconds: 600));
    // Its label alone: a page's text may have the word too.
    await tapText(section, exact: true);
    await settle(const Duration(milliseconds: 1200));
  }

  /// Sets the color theme, [dark] or not as the window's frame draws it.
  Future<void> theme(String id, {required bool dark}) async {
    await WorkbenchThemeService.instance.setColorTheme(id);
    window.value = ShowWindow(window.value.size, dark: dark);
    await settle(const Duration(milliseconds: 600));
  }

  // --- Pictures ----------------------------------------------------------------

  Future<void> shot(String name) async {
    await settle(const Duration(milliseconds: 600));
    final path = p.join(out, '$name.png');
    await camera.shot(path, window.value);
    log('shot $path');
  }

  Future<void> record(String name, Future<void> Function() body) async {
    if (!video) return;
    final path = p.join(out, '$name.mp4');
    await camera.record(
      path,
      window.value,
      body,
      dilation: 4,
      dilate: (dilation) {
        ShowClock.dilation = dilation;
        timeDilation = dilation;
      },
    );
    log('video $path');
  }
}

// --- The scenes ----------------------------------------------------------------

/// The main window: the projects and their conversations in the sidebar,
/// two agents side by side, one with three subagents and a command in
/// the background, the other writing its answer.
Future<void> _main(ShowScene scene) async {
  scene.decorate();
  await scene.reset('hono');
  final agents = await scene.start(
    'hono',
    rateLimitPrompt,
    (run) => rateLimitScript(run, scene.hono),
    title: rateLimitTitle,
  );
  final answer = await scene.start(
    'hono',
    jsxPrompt,
    (run) => jsxScript(run, scene.hono),
    title: jsxTitle,
  );
  scene.workspace
    ..select(agents)
    ..openBeside(answer, agents, PaneSide.right);
  await Future.wait([
    ShowScripts.reached('agents'),
    ShowScripts.reached('answer'),
  ]);
  await scene.tapText(Story.t('background tasks running', '个后台任务'));
  await scene.settle(const Duration(milliseconds: 1200));
  await scene.shot('main');
}

/// Fast IDE on hono with the agent docked beside it: the middleware it
/// wrote in the editor, its tests in the terminal (`main-ide`); then
/// Source Control, a commit message drafted, the graph (`ide`).
Future<void> _ide(ShowScene scene) async {
  scene.decorate();
  await scene.reset('hono');
  final thread = await scene.start('hono', rateLimitPrompt, (run) async {
    await rateLimitScript(run, scene.hono);
  }, title: rateLimitTitle);
  ShowScripts.release('agents');
  await ShowScripts.reached('written');
  final ide = await scene.openIde('hono', thread: thread);
  await ide.widget.workspace.open(p.join(scene.hono, rateLimiterPath));
  final terminal = await scene.terminal(ide);
  terminal.sendText(
    'bun test src/middleware/rate-limiter',
    shouldExecute: true,
  );
  await scene.settle(const Duration(seconds: 3));
  await scene.shot('main-ide');

  ide.runCommand('workbench.view.scm');
  await scene.until(
    () => scene.widget<IdeGitLogView>() != null,
    'Source Control',
  );
  scene.widget<IdeGitLogView>()!.session.message.text = Story.t(
    'feat(rate-limiter): count in a sliding window\n\n'
        'Counts with a pluggable store (in memory or Workers KV) and sends\n'
        'the IETF RateLimit and RateLimit-Policy headers for X-RateLimit-*.',
    'feat(rate-limiter): 改成滑动窗口计数\n\n'
        '计数存储可替换（内存或 Workers KV），响应头从 X-RateLimit-*\n'
        '换成 IETF 的 RateLimit 和 RateLimit-Policy。',
  );
  await scene.settle(const Duration(seconds: 2));
  await scene.shot('ide');
}

/// The rate limiter done: its changes in the side panel, a file's diff
/// open, Keep and Undo for each.
Future<void> _review(ShowScene scene) async {
  scene.decorate();
  await scene.reset('hono');
  final thread = await scene.start(
    'hono',
    rateLimitPrompt,
    (run) => rateLimitScript(run, scene.hono),
    title: rateLimitTitle,
  );
  ShowScripts.release('agents');
  ShowScripts.release('written');
  await scene.until(
    () => !thread.session.isStreaming && thread.session.fileChanges.isNotEmpty,
    'the rate limiter to be written',
    timeout: const Duration(seconds: 90),
  );
  await scene.settle(const Duration(seconds: 1));
  // The changes above the input, opened; a file of them in the side
  // panel, each part to keep or undo.
  await scene.tapText(scene.l10n.stripFilesChanged(5));
  await scene.settle(const Duration(seconds: 1));
  await scene.tapText('package.json');
  await scene.settle(const Duration(seconds: 2));
  await scene.shot('review');
}

/// A goal set with /goal, the agent working toward it: the goal above
/// the input, in progress.
Future<void> _goal(ShowScene scene) async {
  scene.decorate();
  await scene.reset('hono');
  final condition = Story.t(
    'every middleware test passes on Bun, Node and Deno, with no type errors',
    '所有中间件测试在 Bun、Node 和 Deno 上都通过，且没有类型错误',
  );
  await scene.start(
    'hono',
    '/goal $condition',
    (run) => goalScript(run, scene.hono),
    title: Story.t('Green on every runtime', '全运行时通过'),
  );
  await ShowScripts.reached('goal');
  await scene.settle(const Duration(seconds: 2));
  await scene.shot('goal');
}

/// The input as a rich-text editor: a message with pictures and a code
/// reference in its sentence, while another waits in the queue.
Future<void> _composer(ShowScene scene) async {
  scene.decorate();
  await scene.reset('hono');
  final thread = await scene.start(
    'hono',
    rateLimitPrompt,
    (run) => rateLimitScript(run, scene.hono),
    title: rateLimitTitle,
  );
  await ShowScripts.reached('agents');
  thread.session.send(
    ComposerMessage(
      text: Story.t('Also let health checks skip the limit.', '另外，健康检查不要计入限流。'),
    ),
  );
  final images = [
    for (var i = 0; i < 3; i++) (await _mockup(i)).withNumber(i + 1),
  ];
  final tags = [for (final image in images) imageReference(image.number!)];
  thread.session.draft.restore(
    Story.t(
      'When the limit is hit, answer with a page like these mockups ${tags.join(' ')} instead of plain text, and keep the headers from ',
      '超限时不要只返回纯文本，按这几张设计稿 ${tags.join(' ')} 返回一个页面，并保留这里设置的响应头：',
    ),
    images,
  );
  await scene.settle(const Duration(milliseconds: 600));
  // The headers it sets, and the 429.
  final start = lineOf(rateLimiterSource, '    if (standardHeaders) {');
  thread.session.draft.insertCode([
    CodeReference(
      path: p.join(scene.hono, rateLimiterPath),
      start: start,
      end: start + 7,
      code: rateLimiterSource
          .split('\n')
          .sublist(start - 1, start + 7)
          .join('\n'),
    ),
  ]);
  await scene.settle(const Duration(seconds: 2));
  await scene.shot('composer');
}

/// A made-up design for the 429 page, as a picture pasted in.
Future<ImageAttachment> _mockup(int variant) async {
  const size = Size(480, 320);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final colors = [
    (const Color(0xFFFFF4E8), const Color(0xFFE8833A)),
    (const Color(0xFF14161F), const Color(0xFF7C8CFF)),
    (const Color(0xFFEFF7F1), const Color(0xFF2F9E5B)),
  ][variant];
  canvas.drawRect(Offset.zero & size, Paint()..color = colors.$1);
  final dark = variant == 1;
  final ink = dark ? const Color(0xFFE8E8F0) : const Color(0xFF22252B);
  void text(
    String value,
    Offset at,
    double size,
    Color color, {
    bool bold = false,
  }) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: size))
      ..pushStyle(
        ui.TextStyle(
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      )
      ..addText(value);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 420));
    canvas.drawParagraph(paragraph, at);
  }

  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(40, 40, 64, 64),
      const Radius.circular(16),
    ),
    Paint()..color = colors.$2,
  );
  text('429', const Offset(40, 124), 56, colors.$2, bold: true);
  text('Too Many Requests', const Offset(40, 196), 24, ink, bold: true);
  text(
    'Slow down a little — try again in 12 seconds.',
    const Offset(40, 232),
    15,
    ink.withValues(alpha: 0.7),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(40, 266, 120, 34),
      const Radius.circular(8),
    ),
    Paint()..color = colors.$2,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return ImageAttachment(
    bytes: bytes!.buffer.asUint8List(),
    mediaType: 'image/png',
    name: 'mockup-${variant + 1}.png',
  );
}

/// Upstreams beside Claude Code's own: DeepSeek, Kimi, GLM over
/// Anthropic's API, OpenRouter over OpenAI's, and ChatGPT's Codex.
Future<void> _withUpstreams(ShowScene scene) async {
  Map<String, Object?> provider(
    String id,
    String name,
    String protocol,
    String baseUrl,
    List<String> models,
  ) => {
    'id': id,
    'name': name,
    'protocol': protocol,
    'baseUrl': baseUrl,
    'models': [
      for (final model in models) {'id': model},
    ],
  };
  await scene.settings.settings.update('models.providers', [
    provider(
      'deepseek',
      'DeepSeek',
      'anthropic',
      'https://api.deepseek.com/anthropic',
      ['deepseek-v4.1', 'deepseek-v4.1-flash'],
    ),
    provider(
      'moonshot',
      'Kimi',
      'anthropic',
      'https://api.moonshot.ai/anthropic',
      ['kimi-k3', 'kimi-k3-turbo'],
    ),
    provider(
      'zhipu',
      'GLM',
      'anthropic',
      'https://open.bigmodel.cn/api/anthropic',
      ['glm-5.1', 'glm-5.1-air'],
    ),
    provider(
      'openrouter',
      'OpenRouter',
      'openai-chat',
      'https://openrouter.ai/api/v1',
      ['google/gemini-3-pro', 'x-ai/grok-5', 'qwen/qwen4-coder'],
    ),
    provider(
      'chatgpt',
      'ChatGPT',
      'codex',
      'https://chatgpt.com/backend-api/codex',
      ['gpt-6-astra', 'gpt-6-codex'],
    ),
  ]);
}

/// Any model: the upstreams in Settings → Models, then the model picker
/// with them beside Claude's own.
Future<void> _models(ShowScene scene) async {
  scene.decorate();
  await scene.openSettings(scene.l10n.settingsSectionModels);
  await scene.shot('models');
  await scene.press(LogicalKeyboardKey.escape);
  await scene.settle(const Duration(milliseconds: 800));
  // A conversation's, its input at the bottom: the whole list above it.
  final thread = scene.kept(Story.projects.first.sessions.first.title)!;
  scene.workspace.select(thread);
  await scene.settle(const Duration(seconds: 2));
  await scene.tapText('Default');
  await scene.settle(const Duration(seconds: 1));
  await scene.shot('model-picker');
}

/// Settings → Customize: the skills in ~/.claude.
Future<void> _customize(ShowScene scene) async {
  scene.decorate();
  await scene.openSettings(scene.l10n.settingsSectionCustomize);
  await scene.settle(const Duration(seconds: 1));
  await scene.shot('customize');
}

/// Settings → Notifications.
Future<void> _notifications(ShowScene scene) async {
  scene.decorate();
  await scene.openSettings(scene.l10n.settingsSectionNotifications);
  await scene.shot('notifications');
}

/// The main window in Bao Light, the search palette open on what the
/// agents talked of.
Future<void> _themesLight(ShowScene scene) async {
  scene.decorate();
  await scene.reset('hono');
  await scene.theme(ThemeSettingDefaults.colorThemeLight, dark: false);
  final agents = await scene.start(
    'hono',
    rateLimitPrompt,
    (run) => rateLimitScript(run, scene.hono),
    title: rateLimitTitle,
  );
  scene.workspace.select(agents);
  await ShowScripts.reached('agents');
  await scene.settle(const Duration(seconds: 1));
  await scene.tapText(scene.l10n.sidebarSearch);
  await scene.settle(const Duration(milliseconds: 600));
  await scene.input.type(Story.t('router', '路由'));
  await scene.settle(const Duration(seconds: 2));
  await scene.shot('themes-light');
}

/// Fast IDE in Kimbie Dark, the color theme list open.
Future<void> _themesDark(ShowScene scene) async {
  scene.decorate();
  await scene.reset('hono');
  await scene.theme('Kimbie Dark', dark: true);
  final ide = await scene.openIde('hono');
  await ide.widget.workspace.open(p.join(scene.hono, 'src/hono-base.ts'));
  await scene.settle(const Duration(seconds: 2));
  ide.runCommand('workbench.action.selectTheme');
  await scene.settle(const Duration(seconds: 1));
  await scene.shot('themes-dark');
  await scene.press(LogicalKeyboardKey.escape);
}

// --- Videos ------------------------------------------------------------------------

/// The agent at work: three subagents fanned out, a command in the
/// background, the middleware written and tested.
Future<void> _videoAgents(ShowScene scene) async {
  scene.decorate();
  await scene.reset('hono');
  final thread = scene.workspace.create(project: scene.project('hono'));
  await scene.until(() => thread.session.canSend, 'the agent');
  ShowScripts.register(rateLimitPrompt, (run) async {
    await run.pause(400);
    await rateLimitScript(run, scene.hono);
  });
  ShowScripts.register(jsxPrompt, (run) => jsxScript(run, scene.hono));
  ShowScripts.release('answer');
  await scene.settle(const Duration(seconds: 1));
  late final AgentThread beside;
  await scene.record('agents', () async {
    await scene.settle(const Duration(milliseconds: 1200));
    thread.session.send(ComposerMessage(text: rateLimitPrompt));
    scene.workspace.rename(thread, rateLimitTitle);
    await scene.settle(const Duration(milliseconds: 1400));
    // A second agent beside it: a new chat once the first is no longer
    // one, or it would be the same.
    beside = scene.workspace.create(project: scene.project('hono'));
    scene.workspace
      ..select(thread)
      ..openBeside(beside, thread, PaneSide.right);
    await scene.until(() => beside.session.canSend, 'the agent beside');
    await scene.settle(const Duration(milliseconds: 600));
    beside.session.send(ComposerMessage(text: jsxPrompt));
    scene.workspace.rename(beside, jsxTitle);
    await ShowScripts.reached('agents');
    await scene.settle(const Duration(milliseconds: 1200));
    ShowScripts.release('agents');
    await ShowScripts.reached('written');
    ShowScripts.release('written');
    await scene.until(
      () => !thread.session.isStreaming && !beside.session.isStreaming,
      'the turn to end',
      timeout: const Duration(minutes: 3),
    );
    await scene.settle(const Duration(seconds: 3));
  });
}

/// Fast IDE beside the agent: the tests run in the terminal as the agent
/// finishes.
Future<void> _videoIde(ShowScene scene) async {
  scene.decorate();
  await scene.reset('hono');
  final thread = await scene.start(
    'hono',
    rateLimitPrompt,
    (run) => rateLimitScript(run, scene.hono),
    title: rateLimitTitle,
  );
  ShowScripts.release('agents');
  await ShowScripts.reached('written');
  final ide = await scene.openIde('hono', thread: thread);
  await ide.widget.workspace.open(p.join(scene.hono, rateLimiterPath));
  final terminal = await scene.terminal(ide);
  await scene.settle(const Duration(seconds: 1));
  await scene.record('ide', () async {
    await scene.settle(const Duration(milliseconds: 1200));
    await ide.widget.workspace.open(p.join(scene.hono, rateLimiterTestPath));
    await scene.settle(const Duration(milliseconds: 1500));
    terminal.sendText(
      'bun test src/middleware/rate-limiter',
      shouldExecute: true,
    );
    ShowScripts.release('written');
    await scene.until(
      () => !thread.session.isStreaming,
      'the turn to end',
      timeout: const Duration(minutes: 3),
    );
    await scene.settle(const Duration(seconds: 3));
  });
}

/// The color themes, previewed one after another from the list.
Future<void> _videoThemes(ShowScene scene) async {
  scene.decorate();
  await scene.reset('hono');
  final ide = await scene.openIde('hono');
  await ide.widget.workspace.open(p.join(scene.hono, 'src/hono-base.ts'));
  await scene.settle(const Duration(seconds: 2));
  await scene.record('themes', () async {
    await scene.settle(const Duration(milliseconds: 800));
    ide.runCommand('workbench.action.selectTheme');
    await scene.settle(const Duration(milliseconds: 900));
    // From Bao Dark down through the dark ones (Dark Modern, Dark+,
    // Kimbie Dark, Monokai Dimmed), quickly back up to Bao Light, then
    // down the light ones.
    Future<void> step(LogicalKeyboardKey key, int times, int ms) async {
      for (var i = 0; i < times; i++) {
        scene.input.press(key);
        await scene.settle(Duration(milliseconds: ms));
      }
    }

    await step(LogicalKeyboardKey.arrowDown, 4, 1000);
    await step(LogicalKeyboardKey.arrowUp, 7, 120);
    await scene.settle(const Duration(milliseconds: 900));
    await step(LogicalKeyboardKey.arrowDown, 2, 1000);
    await scene.settle(const Duration(milliseconds: 400));
  });
}
