import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:monad/chat/widgets/activity_row.dart';
import 'package:monad/ide/editor/monaco/flutter/editor_keybindings.dart';
import 'package:monad/ide/ide_commands.dart';
import 'package:monad/ide/ide_quick_open.dart';
import 'package:monad/keybindings/default_keybindings.dart';
import 'package:monad/keybindings/keybinding_entry.dart';
import 'package:monad/keybindings/keybinding_service.dart';
import 'package:monad/keybindings/keybindings_editing.dart';
import 'package:monad/l10n/app_localizations_zh.dart';
import 'package:monad/l10n/command_titles.dart';
import 'package:monad/l10n/l10n.dart';
import 'package:monad/main.dart';
import 'package:monad/platform/data_dir.dart' show DataDirectoryProblem;
import 'package:monad/settings/app_locale.dart';
import 'package:monad/settings/data_dir_service.dart';
import 'package:monad/settings/jsonc.dart';
import 'package:monad/settings/jsonc_file.dart';
import 'package:monad/settings/pages/keybindings_page.dart';
import 'package:monad/settings/pages/language_page.dart';
import 'package:monad/workspace/workspace.dart';

/// A [LocaleStorage] that records what it was asked to keep.
class _RecordingStorage implements LocaleStorage {
  _RecordingStorage(this.value);

  String? value;
  final List<String?> writes = [];

  @override
  String? read() => value;

  @override
  Future<void> write(String? locale) async {
    writes.add(locale);
    value = locale;
  }
}

/// A store that changes under the app, as argv.json edited by hand.
class _NotifyingStorage extends ChangeNotifier implements LocaleStorage {
  String? value;

  @override
  String? read() => value;

  @override
  Future<void> write(String? locale) async => value = locale;

  void change(String? locale) {
    value = locale;
    notifyListeners();
  }
}

/// keybindings.json in memory: nothing on disk.
class _MemoryFile extends JsoncFile {
  _MemoryFile() : super('/memory/User/keybindings.json');

  String? text;

  @override
  Object? get value => switch (text) {
    final String text => parseJsonc(text),
    null => null,
  };

  @override
  Future<String?> readText() async => text;

  @override
  Future<void> writeText(String text) async {
    this.text = text;
    notifyListeners();
  }
}

const _delegates = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

Map<String, Object?> _arb(String name) =>
    jsonDecode(File('lib/l10n/$name').readAsStringSync())
        as Map<String, Object?>;

Set<String> _messages(Map<String, Object?> arb) => {
  for (final key in arb.keys)
    if (!key.startsWith('@')) key,
};

final AppLocalizations _zh = AppLocalizationsZh();

void main() {
  group('ARB files', () {
    test('en and zh have the same keys', () {
      final en = _messages(_arb('app_en.arb'));
      final zh = _messages(_arb('app_zh.arb'));
      expect(zh.difference(en), isEmpty, reason: 'only in zh');
      expect(en.difference(zh), isEmpty, reason: 'only in en');
    });

    test('every zh message is translated', () {
      final en = _arb('app_en.arb');
      final zh = _arb('app_zh.arb');
      for (final key in _messages(en)) {
        final value = zh[key];
        expect(value, isA<String>(), reason: key);
        expect((value! as String).trim(), isNotEmpty, reason: key);
      }
    });
  });

  group('AppLocale', () {
    test('reads the kept setting when made', () {
      expect(AppLocale(storage: MemoryLocaleStorage('zh-cn')).setting, 'zh-cn');
      expect(
        AppLocale(storage: MemoryLocaleStorage('zh-cn')).locale,
        const Locale('zh', 'CN'),
      );
      expect(AppLocale(storage: MemoryLocaleStorage()).locale, isNull);
    });

    test('normalizes VS Code locale values', () {
      expect(AppLocale.normalize('zh-CN'), 'zh-cn');
      expect(AppLocale.normalize('zh_Hans'), 'zh-cn');
      expect(AppLocale.normalize('EN-us'), 'en');
      expect(AppLocale.normalize('fr'), isNull);
      expect(AppLocale.normalize('  '), isNull);
      expect(AppLocale.normalize(null), isNull);
    });

    test('keeps a choice through its storage', () async {
      final storage = _RecordingStorage(null);
      final locale = AppLocale(storage: storage);
      var notified = 0;
      locale.addListener(() => notified++);

      await locale.select('zh-CN');
      expect(locale.setting, 'zh-cn');
      expect(storage.writes, ['zh-cn']);
      expect(notified, 1);

      // The same choice again is not written again.
      await locale.select('zh-cn');
      expect(storage.writes, ['zh-cn']);

      await locale.select(null);
      expect(storage.writes, ['zh-cn', null]);
      expect(locale.locale, isNull);

      // A new session starts in what was kept.
      await locale.select('en');
      expect(AppLocale(storage: storage).setting, 'en');
    });

    test('follows a storage that notifies', () {
      final storage = _NotifyingStorage();
      final locale = AppLocale(storage: storage);
      addTearDown(locale.dispose);
      var notified = 0;
      locale.addListener(() => notified++);

      storage.change('zh-cn');
      expect(locale.setting, 'zh-cn');
      expect(notified, 1);
      storage.change('zh-cn');
      expect(notified, 1);
    });

    test('the system locale resolves to a supported one', () {
      expect(
        AppLocale.systemLocale(const [Locale('zh', 'CN')]),
        const Locale('zh', 'CN'),
      );
      expect(
        AppLocale.systemLocale(const [Locale('fr'), Locale('zh')]),
        const Locale('zh', 'CN'),
      );
      expect(AppLocale.systemLocale(const [Locale('fr')]), const Locale('en'));
    });
  });

  group('switching the language', () {
    testWidgets('context.l10n is English without localizations', (
      tester,
    ) async {
      late AppLocalizations l10n;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            l10n = context.l10n;
            return const SizedBox();
          },
        ),
      );
      expect(l10n.settingsTitle, 'Settings');
    });

    testWidgets('the language page applies a choice at once', (tester) async {
      final storage = _RecordingStorage(null);
      final locale = AppLocale(storage: storage);
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: locale,
          builder: (context, _) => MaterialApp(
            locale: locale.locale ?? const Locale('en'),
            supportedLocales: AppLocale.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: Scaffold(body: LanguageSettingsPage(locale: locale)),
          ),
        ),
      );
      expect(find.text('Region & Language'), findsOneWidget);
      expect(find.text('Display Language'), findsOneWidget);

      await tester.tap(find.text('简体中文'));
      await tester.pump();
      expect(find.text('区域和语言'), findsOneWidget);
      expect(find.text('Region & Language'), findsNothing);
      expect(storage.writes, ['zh-cn']);

      await tester.tap(find.text('English'));
      await tester.pump();
      expect(find.text('Region & Language'), findsOneWidget);
      expect(storage.writes, ['zh-cn', 'en']);
    });

    testWidgets('the app follows the setting without restarting', (
      tester,
    ) async {
      final locale = AppLocale(storage: MemoryLocaleStorage('en'));
      await tester.pumpWidget(
        MonadApp(workspace: Workspace.mock(), appLocale: locale),
      );
      await tester.pump();
      expect(find.text('New Agent'), findsWidgets);
      expect(find.text('新建智能体'), findsNothing);

      await locale.select(AppLocale.simplifiedChinese);
      await tester.pump();
      expect(find.text('新建智能体'), findsWidgets);
      expect(find.text('New Agent'), findsNothing);

      await locale.select(AppLocale.english);
      await tester.pump();
      expect(find.text('New Agent'), findsWidgets);
    });
  });

  group('command titles', () {
    IdeCommand command(String id, String label, [String? category]) =>
        IdeCommand(id: id, label: label, category: category, run: () {});

    final commands = [
      command('workbench.action.files.save', 'Save', 'File'),
      command('workbench.action.openSettings', 'Open Settings', 'Preferences'),
      command(
        'workbench.action.openGlobalKeybindings',
        'Open Keyboard Shortcuts',
        'Preferences',
      ),
      command('editor.action.jumpToBracket', 'Go to Bracket', 'Editor'),
      command(
        'workbench.action.openEditorAtIndex3',
        'Open Editor at Index 3',
        'View',
      ),
    ];

    test('are localized with an English fallback', () {
      expect(localizedCommandTitle(_zh, commands[0]), '文件: 保存');
      expect(
        localizedCommandLabel(
          englishLocalizations,
          'editor.action.jumpToBracket',
          'Go to Bracket',
        ),
        'Go to Bracket',
      );
      expect(
        localizedCommandLabel(_zh, 'workbench.action.openEditorAtIndex3', 'x'),
        isNot('x'),
      );
      expect(
        localizedCommandLabel(_zh, 'unknown.command', 'Unknown'),
        'Unknown',
      );
      expect(localizedCommandCategory(_zh, 'Unknown'), 'Unknown');
    });

    test('cover the English titles in English', () {
      for (final command in commands) {
        expect(
          localizedCommandTitle(englishLocalizations, command),
          command.title,
          reason: command.id,
        );
      }
    });

    test("cover every editor command", () {
      for (final MapEntry(key: id, value: label) in {
        ...editorCommandLabels,
        ...editorLanguageCommandLabels,
      }.entries) {
        expect(
          localizedCommandLabel(englishLocalizations, id, label),
          label,
          reason: id,
        );
        expect(localizedCommandLabel(_zh, id, label), isNot(label), reason: id);
      }
    });

    test('the Chinese palette finds commands by their English titles', () {
      final items = commandQuickPicks(
        'save',
        commands: commands,
        recent: IdeRecentList(),
        onRun: (_) {},
        l10n: _zh,
      );
      final save = items.firstWhere((item) => item.label == '文件: 保存');
      expect(save.description, 'File: Save');
      expect(save.descriptionMatches, isNotEmpty);

      final bracket = commandQuickPicks(
        'go to bracket',
        commands: commands,
        recent: IdeRecentList(),
        onRun: (_) {},
        l10n: _zh,
      );
      expect(bracket.first.description, 'Editor: Go to Bracket');
    });

    test('the Chinese palette finds commands by their Chinese titles', () {
      final items = commandQuickPicks(
        '保存',
        commands: commands,
        recent: IdeRecentList(),
        onRun: (_) {},
        l10n: _zh,
      );
      expect(items.first.label, '文件: 保存');
      expect(items.first.labelMatches, isNotEmpty);
    });

    test('the English palette shows no alias', () {
      final items = commandQuickPicks(
        'save',
        commands: commands,
        recent: IdeRecentList(),
        onRun: (_) {},
        l10n: englishLocalizations,
      );
      expect(items.first.label, 'File: Save');
      expect(items.first.description, isNull);
    });
  });

  group('keyboard shortcuts page', () {
    Future<void> open(WidgetTester tester, Locale locale) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final file = _MemoryFile();
      final service = KeybindingService()
        ..debugPlatform = KeybindingPlatform.mac
        ..userEntries = KeybindingEntry.listFromJson(file.value);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocale.supportedLocales,
          localizationsDelegates: _delegates,
          home: Scaffold(
            body: KeybindingsSettingsPage(
              keybindings: service,
              editing: KeybindingsEditingService(
                file,
                platform: KeybindingPlatform.mac,
              ),
            ),
          ),
        ),
      );
    }

    Future<void> search(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField).first, text);
      await tester.pump();
    }

    const sidebar = 'workbench.action.toggleSidebarVisibility';

    testWidgets('is in Chinese, and finds commands by English titles', (
      tester,
    ) async {
      await open(tester, const Locale('zh', 'CN'));
      expect(find.text('键盘快捷方式'), findsOneWidget);
      expect(find.text('命令'), findsOneWidget);
      expect(find.text('快捷键'), findsOneWidget);
      expect(find.text('来源'), findsOneWidget);
      expect(find.text('Keyboard Shortcuts'), findsNothing);

      await search(tester, 'Toggle Primary Side Bar');
      expect(find.text('视图: 切换主侧边栏可见性'), findsOneWidget);
      // The id stays under the title, and the source is in Chinese.
      expect(find.text(sidebar), findsOneWidget);
      expect(find.text('默认'), findsWidgets);

      await search(tester, '切换主侧边栏');
      expect(find.text('视图: 切换主侧边栏可见性'), findsOneWidget);

      await search(tester, sidebar);
      expect(find.text('视图: 切换主侧边栏可见性'), findsOneWidget);
    });

    testWidgets('is in English by default', (tester) async {
      await open(tester, const Locale('en'));
      expect(find.text('Keyboard Shortcuts'), findsOneWidget);
      await search(tester, 'Toggle Primary Side Bar');
      expect(
        find.text('View: Toggle Primary Side Bar Visibility'),
        findsOneWidget,
      );
      expect(find.text('Default'), findsWidgets);
    });

    test('every command of the catalog has a Chinese title', () {
      for (final MapEntry(key: id, value: info) in commandCatalog.entries) {
        expect(
          localizedCommandTitleOf(
            englishLocalizations,
            id,
            info.title,
            category: info.category,
          ),
          info.label,
          reason: id,
        );
        expect(
          localizedCommandLabel(_zh, id, info.title),
          isNot(info.title),
          reason: id,
        );
      }
    });
  });

  test('data folder problems are localized', () {
    expect(
      localizedDataDirectoryProblem(
        _zh,
        DataDirectoryProblem.notWritable,
        '/x',
      ),
      '无法在 /x 中写入文件。',
    );
    expect(
      localizedDataDirectoryProblem(
        _zh,
        DataDirectoryProblem.missing,
        '/x',
        error: '/x is not a folder.',
      ),
      '/x 不是文件夹。',
    );
    const target = DataDirectoryTarget('/x', error: 'Choose a full path.');
    expect(target.localizedError(_zh), 'Choose a full path.');
    expect(
      DataDirectoryTarget(
        '/x',
        error: 'Choose a full path.',
        localize: (l10n) => l10n.dataDirFullPath,
      ).localizedError(_zh),
      '请选择完整路径。',
    );
  });

  test('the English musings are the activity row\'s', () {
    expect(ActivityRow.musingsFor(englishLocalizations), ActivityRow.musings);
    expect(ActivityRow.musingsFor(_zh), hasLength(ActivityRow.musings.length));
  });
}
