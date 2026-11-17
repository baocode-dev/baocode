// A conversation coordinating others, rendered offscreen with real fonts:
// its session_* steps by the others' names, their reports as cards (a
// long one folded, one waiting on the user offering to answer it), and
// the strip of those it handed work to. Written to $SHOTS (a folder);
// skipped without it.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/panels/activity_strip.dart';
import 'package:baocode/chat/session_links.dart';
import 'package:baocode/chat/widgets/chat_item_view.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/code_font.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _out = Platform.environment['SHOTS'];

Future<void> _fonts(WidgetTester tester) async {
  await tester.runAsync(() async {
    Future<void> load(List<String> families, String path) async {
      final file = File(path);
      if (!file.existsSync()) return;
      final bytes = file.readAsBytesSync();
      for (final family in families) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
      }
    }

    await load([
      'Roboto',
      '.SF UI Text',
      '.SF UI Display',
      '.AppleSystemUIFont',
      'FlutterTest',
      'Ahem',
    ], '/System/Library/Fonts/Hiragino Sans GB.ttc');
    await load(['Menlo'], '/System/Library/Fonts/Menlo.ttc');
    await load(
      ['MaterialIcons'],
      '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    final codicon = FontLoader('codicon')
      ..addFont(rootBundle.load('assets/codicons/codicon.ttf'));
    await codicon.load();
  });
}

const _report = '''登录页重构完成了，改动如下：

- 把表单拆成 `LoginForm` 和 `LoginFooter` 两个组件
- 密码框加了显示/隐藏切换
- 记住账号改用安全存储，不再写明文
- 错误提示统一走 `AuthError`，文案中英文都补齐了
- 补了 6 个组件测试，全部通过

另外发现注册页也在用旧的表单写法，这次没动，要不要一起改由你定。
跑了一遍 `flutter analyze`，没有新问题。''';

class _Host implements SessionLinkHost {
  final _titles = {'s-login': '登录页重构', 's-dark': '设置页深色模式', 's-docs': '接口文档'};
  final _statuses = {
    's-login': HandedStatus.done,
    's-dark': HandedStatus.waiting,
    's-docs': HandedStatus.running,
  };

  final _models = {
    's-login': 'Sonnet 5',
    's-dark': 'Haiku 4.5',
    's-docs': 'GLM-5',
  };

  @override
  String? titleOf(String id) => _titles[id];

  @override
  String? modelOf(String id) => _models[id];

  @override
  HandedStatus? statusOf(String id) => _statuses[id];

  @override
  Listenable get statuses => const _Never();

  @override
  void open(String id) {}

  List<HandedConversation> get handed => [
    for (final id in _titles.keys)
      HandedConversation(
        id: id,
        title: _titles[id]!,
        status: _statuses[id]!,
        model: _models[id],
      ),
  ];

  @override
  ValueListenable<List<HandedConversation>> handedFrom(ChatSession session) =>
      ValueNotifier(handed);
}

class _Never implements Listenable {
  const _Never();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

ToolCallItem _step(
  String tool,
  Map<String, Object?> input, {
  String output = '',
  ToolStatus status = ToolStatus.succeeded,
}) => ToolCallItem(
  kind: ToolKind.other,
  tool: tool,
  target: '${input['session'] ?? ''}',
  input: input,
  output: output,
  status: status,
);

void main() {
  testWidgets('a conversation coordinating others', (tester) async {
    await _fonts(tester);
    // As the app has it by default.
    await tester.runAsync(
      () => WorkbenchThemeService.instance.applyColorThemeSettings(
        setting: 'Bao Dark',
        autoDetectColorScheme: false,
      ),
    );
    CodeFont.families.value = ['Menlo', 'Roboto'];
    tester.view.physicalSize = const Size(760, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final host = _Host();
    final items = <(ChatItem, bool)>[
      (const UserMessageItem(text: '把登录页和设置页的改动分给两个对话做，做完给我汇总'), false),
      (const AssistantTextItem('好，我开两个对话分头做，它们做完会自动回报给我。'), false),
      (
        _step('session_new', {
          'title': '登录页重构',
          'text': '重构登录页…',
        }, output: 'Started: s-login in app.'),
        false,
      ),
      (
        _step('session_new', {
          'title': '设置页深色模式',
          'text': '设置页加深色模式…',
        }, output: 'Started: s-dark in app.'),
        false,
      ),
      (
        _step('session_send', {
          'session': 's-docs',
          'text': '登录接口的返回结构改了，顺手把接口文档里 /auth/login 那节更新一下。',
        }, output: 'Sent: it is on it, and reports back to you by itself.'),
        true,
      ),
      (
        const UserMessageItem(
          text: _report,
          fromAgent: '登录页重构',
          fromSession: 's-login',
        ),
        false,
      ),
      (_step('session_changes', {'session': 's-login'}), false),
      (
        const UserMessageItem(
          text: '深色模式的主色用哪种？\n- 沙金\n- 冷灰',
          fromAgent: '设置页深色模式',
          fromSession: 's-dark',
        ),
        false,
      ),
      (
        _step('session_wait', {
          'sessions': ['s-dark', 's-docs'],
        }, status: ToolStatus.running),
        false,
      ),
    ];
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        locale: const Locale('zh'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: RepaintBoundary(
          key: key,
          child: SessionLinks(
            host: host,
            child: Material(
              color: AppColors.conversationSurface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (item, expanded) in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: switch (item) {
                          UserMessageItem(fromAgent: null) => Align(
                            alignment: Alignment.centerRight,
                            child: ChatItemView(item: item),
                          ),
                          _ => ChatItemView(
                            item: item,
                            expanded: expanded,
                            onToggle: () {},
                          ),
                        },
                      ),
                    const SizedBox(height: 8),
                    ActivityStrip(
                      tasks: const [],
                      changes: const [],
                      onKeep: () {},
                      handed: host.handed,
                      onOpenHanded: (_) {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final layer = boundary.debugLayer! as OffsetLayer;
      final image = await layer.toImage(
        Offset.zero & boundary.size,
        pixelRatio: 2,
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_out/session_links.png')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }, skip: _out == null);
}
