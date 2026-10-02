import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/composer/composer_files.dart';
import 'package:baocode/icons/emoji_catalog.dart';
import 'package:baocode/icons/emoji_sheet.dart';
import 'package:baocode/icons/icon_library.dart';
import 'package:baocode/icons/icon_storage.dart';
import 'package:baocode/icons/project_icon.dart';
import 'package:baocode/icons/project_icon_picker.dart';
import 'package:baocode/icons/project_icon_view.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/mock_claude_code_transport.dart';
import 'package:baocode/main.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two projects, `/tmp/project` and `/tmp/other`, with a session each.
class _Catalog implements SessionCatalog {
  @override
  Future<List<ProjectRecord>> projects() async => [
    for (final (id, path, title) in [
      ('a1', '/tmp/project', 'Fix the build'),
      ('b2', '/tmp/other', 'Write the docs'),
    ])
      ProjectRecord(
        path: path,
        sessions: [
          SessionRecord(
            id: id,
            title: title,
            updatedAt: DateTime(2026, 9, 30),
            cwd: path,
          ),
        ],
      ),
  ];

  @override
  Future<List<SessionRecord>> sessionsIn(String cwd) async => const [];

  @override
  Future<void> delete(String id) async {}
}

final KernelDescriptor _claude = KernelDescriptor(
  id: 'claude-code',
  label: 'Claude Code',
  icon: Icons.auto_awesome_rounded,
  description: '',
  catalog: _Catalog(),
  create: (context) =>
      ClaudeCodeKernel(_claude, context, start: MockClaudeCodeTransport.start),
);

Uint8List fixture(String name) =>
    File('test/fixtures/icons/$name').readAsBytesSync();

/// The app, loaded, over [preferences] and the icons in [storage].
Future<Workspace> pumpApp(
  WidgetTester tester, {
  PreferenceStore? preferences,
  IconStorage? storage,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final workspace = Workspace(
    kernels: [_claude],
    preferences: preferences,
    icons: IconLibrary(storage: storage),
  );
  await tester.pumpWidget(BaoCodeApp(workspace: workspace));
  await tester.runAsync(workspace.load);
  await tester.runAsync(workspace.icons.load);
  await tester.pump();
  return workspace;
}

Project project(Workspace workspace) =>
    workspace.projects.firstWhere((p) => p.path == '/tmp/project');

Finder inSidebar(Finder finder) =>
    find.descendant(of: find.byType(Sidebar), matching: finder);

/// The icon in the project's header.
final Finder headerIcon = find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.label == 'Change icon of project',
);

/// What the header's icon shows.
ProjectIcon? headerShows(WidgetTester tester) => tester
    .widget<ProjectIconView>(
      find.descendant(of: headerIcon, matching: find.byType(ProjectIconView)),
    )
    .icon;

Finder get picker => find.byType(ProjectIconPicker);

Finder inPicker(Finder finder) => find.descendant(of: picker, matching: finder);

/// A cell of the picker, by what it is named.
Finder cell(String label) => inPicker(
  find.byWidgetPredicate(
    (widget) =>
        widget is Semantics &&
        widget.properties.button == true &&
        widget.properties.label == label,
  ),
);

Future<void> openPicker(WidgetTester tester) async {
  await tester.tap(headerIcon);
  await tester.pump();
  await tester.pump();
  expect(picker, findsOneWidget);
}

/// Lets real work (decoding, isolates) go on, a step at a time, building
/// what each changed.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await EmojiCatalog.load();
    // A sheet with a picture of every emoji: the fixture's first cell.
    final json = jsonEncode([
      for (final emoji in EmojiCatalog.loaded!.all)
        {'unified': EmojiSheet.key(emoji.emoji), 'sheet_x': 0, 'sheet_y': 0},
      {'unified': 'FFFF', 'sheet_x': 1, 'sheet_y': 1},
    ]);
    EmojiSheet.start(
      MemoryEmojiSheetStore()
        ..files['emoji.json'] = utf8.encode(json)
        ..files['sheet.png'] = fixture('emoji_sheet.png'),
    );
    await EmojiSheet.request();
    expect(EmojiSheet.loaded.value, isNotNull);
  });

  setUp(() {
    ProjectIconPicker.pickFiles = () async => const [];
    ProjectIconPicker.pasteboardImages = () async => const [];
    ProjectIconPicker.pasteboardFiles = () async => const [];
  });

  group('emoji', () {
    test('are searched by English and Chinese words, names first', () {
      final catalog = EmojiCatalog.loaded!;
      expect(catalog.all.length, greaterThan(1500));
      expect(catalog.all.first.emoji, '😀');
      // Skin tone components are left out.
      expect(catalog.all.any((e) => e.group == 2), isFalse);

      expect(catalog.search('rocket').first.emoji, '🚀');
      expect(catalog.search('火箭').first.emoji, '🚀');
      expect(catalog.search('ROCKET').first.emoji, '🚀');
      // Every word has to match: by name or by a tag.
      expect(catalog.search('dog face').first.emoji, '🐶');
      expect(catalog.search('小狗').map((e) => e.emoji), contains('🐶'));
      expect(catalog.search('zzzz nothing'), isEmpty);
    });
  });

  group('library', () {
    testWidgets('pictures are kept square and small, GIF and SVG as given', (
      tester,
    ) async {
      final storage = MemoryIconStorage(
        userFiles: {
          for (final name in [
            'wide.jpg',
            'wide.webp',
            'tall.png',
            'blink.gif',
            'logo.svg',
          ])
            '/in/$name': fixture(name),
        },
      );
      final library = IconLibrary(storage: storage);
      final images = (await tester.runAsync(
        () async => [
          for (final name in [
            'wide.jpg',
            'wide.webp',
            'tall.png',
            'blink.gif',
            'logo.svg',
          ])
            await library.addFile('/in/$name'),
        ],
      ))!;
      expect(images.map((image) => image.kind), [
        IconImageKind.png,
        IconImageKind.png,
        IconImageKind.png,
        IconImageKind.gif,
        IconImageKind.svg,
      ]);
      expect(images.map((image) => image.name), [
        'wide',
        'wide',
        'tall',
        'blink',
        'logo',
      ]);
      // Square, the shorter side's size (all under 128 pixels here), but
      // never more than 128.
      for (final (image, side) in [
        (images[0], 128),
        (images[1], 128),
        (images[2], 60),
      ]) {
        final size = (await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(image.bytes);
          final frame = (await codec.getNextFrame()).image;
          return Size(frame.width.toDouble(), frame.height.toDouble());
        }))!;
        expect(size, Size.square(side.toDouble()));
      }
      expect(images[3].bytes, fixture('blink.gif'));
      expect(images[4].bytes, fixture('logo.svg'));
      // The last uploaded first; each file by its content's hash.
      expect(library.images.first.id, images[4].id);
      expect(storage.files.keys, {for (final image in images) image.file});
      expect(storage.index, hasLength(5));

      // Read again, the next run.
      final next = IconLibrary(storage: storage);
      await tester.runAsync(next.load);
      expect(next.images.map((image) => image.id), [
        for (final image in images.reversed) image.id,
      ]);
      expect(next.images.last.bytes, images.first.bytes);
    });

    testWidgets('the same picture uploaded again is kept once, to the front', (
      tester,
    ) async {
      final storage = MemoryIconStorage();
      final library = IconLibrary(storage: storage);
      await tester.runAsync(() async {
        final gif = await library.add(fixture('blink.gif'), name: 'blink');
        await library.add(fixture('logo.svg'));
        final again = await library.add(fixture('blink.gif'), name: 'other');
        expect(again.id, gif.id);
      });
      expect(library.images.map((image) => image.kind), [
        IconImageKind.gif,
        IconImageKind.svg,
      ]);
      expect(storage.files, hasLength(2));
      expect(storage.index, hasLength(2));
    });

    testWidgets('what is too large, not an image or unreadable is refused', (
      tester,
    ) async {
      final storage = MemoryIconStorage(
        userFiles: {
          '/big.png': Uint8List(IconLibrary.maxBytes + 1)
            ..setAll(0, [0x89, 0x50, 0x4E, 0x47]),
          '/notes.txt': Uint8List.fromList('hello'.codeUnits),
          '/broken.png': Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2]),
        },
      );
      final library = IconLibrary(storage: storage);
      Future<IconUploadError?> upload(String path) async {
        try {
          await library.addFile(path);
          return null;
        } on IconUploadException catch (e) {
          return e.error;
        }
      }

      await tester.runAsync(() async {
        expect(await upload('/big.png'), IconUploadError.tooLarge);
        expect(await upload('/notes.txt'), IconUploadError.unsupported);
        expect(await upload('/broken.png'), IconUploadError.unsupported);
        expect(await upload('/missing.png'), IconUploadError.unreadable);
      });
      expect(library.images, isEmpty);
      expect(storage.files, isEmpty);
    });
  });

  group('picker', () {
    testWidgets('an emoji picked shows in the header, and the next run', (
      tester,
    ) async {
      final preferences = MemoryPreferenceStore();
      var workspace = await pumpApp(tester, preferences: preferences);
      // A folder, as before, until one is picked.
      expect(headerShows(tester), isNull);
      expect(
        find.descendant(of: headerIcon, matching: find.byType(Icon)),
        findsOneWidget,
      );

      await openPicker(tester);
      // Emoji first, searched as soon as it opens.
      expect(cell('grinning face'), findsOneWidget);
      final search = tester.widget<TextField>(inPicker(find.byType(TextField)));
      expect(search.focusNode!.hasFocus, isTrue);

      await tester.tap(cell('grinning face'));
      await tester.pump();
      expect(picker, findsNothing);
      expect(headerShows(tester), const EmojiIcon('😀'));
      expect(workspace.iconOf(project(workspace)), const EmojiIcon('😀'));
      expect((await preferences.read())['projectIcons'], {
        '/tmp/project': {'type': 'emoji', 'emoji': '😀'},
      });

      await tester.pumpWidget(const SizedBox());
      workspace = await pumpApp(tester, preferences: preferences);
      expect(headerShows(tester), const EmojiIcon('😀'));
      expect(workspace.recentIcons, [const EmojiIcon('😀')]);
    });

    testWidgets('searching in English or Chinese finds the emoji', (
      tester,
    ) async {
      await pumpApp(tester);
      await openPicker(tester);
      await tester.enterText(inPicker(find.byType(TextField)), 'rocket');
      await tester.pump();
      expect(cell('rocket'), findsOneWidget);
      expect(cell('grinning face'), findsNothing);
      // No headings: what is found.
      expect(inPicker(find.text('Smileys & Emotion')), findsNothing);

      await tester.enterText(inPicker(find.byType(TextField)), '火箭');
      await tester.pump();
      expect(cell('rocket'), findsOneWidget);

      await tester.enterText(inPicker(find.byType(TextField)), 'qqqqzz');
      await tester.pump();
      expect(inPicker(find.text('No results')), findsOneWidget);
    });

    testWidgets('icons are picked in a color of the theme', (tester) async {
      final workspace = await pumpApp(tester);
      await openPicker(tester);
      await tester.tap(inPicker(find.text('Icons')));
      await tester.pump();
      await tester.enterText(inPicker(find.byType(TextField)), 'rocket');
      await tester.pump();
      await tester.tap(
        inPicker(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.label == 'charts.red',
          ),
        ),
      );
      await tester.pump();
      await tester.tap(cell('rocket'));
      await tester.pump();
      expect(
        workspace.iconOf(project(workspace)),
        const CodiconIcon('rocket', color: 'charts.red'),
      );
      final shown = tester.widget<Icon>(
        find.descendant(of: headerIcon, matching: find.byType(Icon)),
      );
      expect(shown.color, themeColors['charts.red']);
    });

    testWidgets('the last 16 picked are kept, the last first; random and '
        'removing are not', (tester) async {
      final workspace = await pumpApp(tester);
      final catalog = EmojiCatalog.loaded!;
      for (final emoji in catalog.all.take(18)) {
        workspace.setIcon(project(workspace), EmojiIcon(emoji.emoji));
      }
      workspace.setIcon(project(workspace), EmojiIcon(catalog.all[3].emoji));
      expect(workspace.recentIcons, hasLength(16));
      expect(workspace.recentIcons.first, EmojiIcon(catalog.all[3].emoji));
      expect(workspace.recentIcons[1], EmojiIcon(catalog.all[17].emoji));
      expect(
        workspace.recentIcons,
        isNot(contains(EmojiIcon(catalog.all[0].emoji))),
      );
      await tester.pump();

      await openPicker(tester);
      expect(inPicker(find.text('Recent')), findsOneWidget);
      final recent = [...workspace.recentIcons];
      await tester.tap(
        inPicker(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.label == 'Random',
          ),
        ),
      );
      await tester.pump();
      // Tried, the picker still open to try another: not one picked.
      expect(picker, findsOneWidget);
      expect(workspace.recentIcons, recent);
      expect(workspace.iconOf(project(workspace)), isA<EmojiIcon>());

      await tester.tap(inPicker(find.text('Remove')));
      await tester.pump();
      expect(picker, findsNothing);
      expect(workspace.iconOf(project(workspace)), isNull);
      expect(workspace.recentIcons, recent);
    });

    testWidgets('keys move through the grid, Enter picks, Escape closes', (
      tester,
    ) async {
      final workspace = await pumpApp(tester);
      final catalog = EmojiCatalog.loaded!;
      await openPicker(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      // Row 2, column 2, the footer naming it.
      final expected = catalog.all[ProjectIconPicker.columns + 1];
      expect(inPicker(find.text(expected.name)), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(picker, findsNothing);
      expect(workspace.iconOf(project(workspace)), EmojiIcon(expected.emoji));

      // Enter picks the first found.
      await openPicker(tester);
      await tester.enterText(inPicker(find.byType(TextField)), 'dog face');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(workspace.iconOf(project(workspace)), const EmojiIcon('🐶'));

      await openPicker(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(picker, findsNothing);
      expect(workspace.iconOf(project(workspace)), const EmojiIcon('🐶'));

      // A click on the icon opens it, and another closes it.
      await openPicker(tester);
      await tester.tap(headerIcon);
      await tester.pump();
      expect(picker, findsNothing);
    });

    testWidgets('until the emoji sheet is there, no emoji: not to pick, '
        'and a project\'s shows as its folder', (tester) async {
      final sheet = EmojiSheet.loaded.value;
      EmojiSheet.loaded.value = null;
      addTearDown(() => EmojiSheet.loaded.value = sheet);
      final workspace = await pumpApp(tester);
      workspace.setIcon(project(workspace), const EmojiIcon('😀'));
      await tester.pump();
      expect(
        find.descendant(
          of: headerIcon,
          matching: find.byIcon(Icons.folder_outlined),
        ),
        findsOneWidget,
      );

      await openPicker(tester);
      expect(inPicker(find.text('Emoji')), findsNothing);
      await tester.enterText(inPicker(find.byType(TextField)), 'rocket');
      await tester.pump();
      expect(cell('rocket'), findsOneWidget);

      // Fetched while it is open: there they are.
      EmojiSheet.loaded.value = sheet;
      await tester.pump();
      expect(inPicker(find.text('Emoji')), findsOneWidget);
      expect(
        find.descendant(
          of: headerIcon,
          matching: find.byIcon(Icons.folder_outlined),
        ),
        findsNothing,
      );
    });

    testWidgets('the project menu opens it too', (tester) async {
      await pumpApp(tester);
      await tester.tap(
        inSidebar(find.text('project')),
        buttons: kSecondaryButton,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Change Icon…'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(picker, findsOneWidget);
      expect(inPicker(find.text('Emoji')), findsOneWidget);
    });

    testWidgets('an image uploaded is the project\'s; deleted from the '
        'library, the project has its folder back', (tester) async {
      final storage = MemoryIconStorage(
        userFiles: {'/in/logo.svg': fixture('logo.svg')},
      );
      final preferences = MemoryPreferenceStore();
      var workspace = await pumpApp(
        tester,
        preferences: preferences,
        storage: storage,
      );
      ProjectIconPicker.pickFiles = () async => [
        const ComposerFile('/in/logo.svg'),
      ];
      await openPicker(tester);
      await tester.tap(inPicker(find.text('Custom')));
      await tester.pump();
      await tester.tap(cell('Upload an image'));
      await settle(tester);
      expect(picker, findsNothing);
      final icon = workspace.iconOf(project(workspace))! as LibraryIcon;
      expect(workspace.icons[icon.id]!.kind, IconImageKind.svg);
      await settle(tester);
      expect(
        find.descendant(of: headerIcon, matching: find.byType(SvgPicture)),
        findsOneWidget,
      );

      // The next run, the picture with it.
      await tester.pumpWidget(const SizedBox());
      workspace = await pumpApp(
        tester,
        preferences: preferences,
        storage: storage,
      );
      expect(headerShows(tester), icon);
      expect(workspace.recentIcons, [icon]);

      await openPicker(tester);
      // Opens on the tab of the icon it has.
      expect(cell('logo'), findsOneWidget);
      await tester.tap(cell('logo'), buttons: kSecondaryButton);
      await tester.pump();
      await tester.tap(inPicker(find.text('Delete from Library')));
      await tester.pump();
      expect(cell('logo'), findsNothing);
      expect(workspace.icons.images, isEmpty);
      expect(workspace.iconOf(project(workspace)), isNull);
      expect(workspace.recentIcons, isEmpty);
      await settle(tester);
      expect(storage.files, isEmpty);
      expect((await preferences.read())['projectIcons'], isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(headerShows(tester), isNull);
    });

    testWidgets('an image pasted is uploaded; a file too large is refused', (
      tester,
    ) async {
      final workspace = await pumpApp(
        tester,
        storage: MemoryIconStorage(
          userFiles: {'/big.gif': Uint8List(IconLibrary.maxBytes + 1)},
        ),
      );
      ProjectIconPicker.pasteboardFiles = () async => [
        const ComposerFile('/big.gif'),
      ];
      await openPicker(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await settle(tester);
      expect(picker, findsOneWidget);
      expect(inPicker(find.text('The file is larger than 5 MB')), findsOne);
      expect(workspace.icons.images, isEmpty);

      ProjectIconPicker.pasteboardImages = () async => [
        ImageAttachment(
          bytes: fixture('wide.webp'),
          mediaType: 'image/webp',
          name: 'shot.webp',
        ),
      ];
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await settle(tester);
      expect(picker, findsNothing);
      final icon = workspace.iconOf(project(workspace))! as LibraryIcon;
      expect(workspace.icons[icon.id]!.kind, IconImageKind.png);
    });
  });

  group('shown', () {
    testWidgets('each kind of picture draws, a GIF as it is', (tester) async {
      final library = IconLibrary();
      final images = (await tester.runAsync(
        () async => [
          await library.add(fixture('tall.png')),
          await library.add(fixture('wide.jpg')),
          await library.add(fixture('wide.webp')),
          await library.add(fixture('blink.gif')),
          await library.add(fixture('logo.svg')),
        ],
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            children: [
              for (final image in images)
                ProjectIconView(
                  icon: LibraryIcon(image.id),
                  library: library,
                  size: 16,
                ),
              ProjectIconView(
                icon: const LibraryIcon('gone'),
                library: library,
                size: 16,
              ),
              ProjectIconView(icon: null, library: library, size: 16),
            ],
          ),
        ),
      );
      await settle(tester);
      expect(find.byType(Image), findsNWidgets(4));
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      // A picture deleted, and none: the folder.
      expect(find.byIcon(Icons.folder_outlined), findsNWidgets(2));
      final gif = tester.widget<Image>(find.byType(Image).at(3));
      expect(
        ((gif.image as ResizeImage).imageProvider as MemoryImage).bytes,
        fixture('blink.gif'),
      );
    });

    testWidgets('the icon shows where the project is picked or listed', (
      tester,
    ) async {
      final workspace = await pumpApp(tester);
      workspace.setIcon(project(workspace), const EmojiIcon('🚀'));
      // Pinned, the agent's row names its project.
      workspace.setPinned(
        workspace.threads.firstWhere((t) => t.title == 'Fix the build'),
        true,
      );
      await tester.pump();
      Finder rocket(Finder within) => find.descendant(
        of: within,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ProjectIconView && widget.icon == const EmojiIcon('🚀'),
        ),
      );
      // The header's, and the pinned row's.
      expect(rocket(find.byType(Sidebar)), findsNWidgets(2));

      // A new agent's folder.
      workspace.create(project: project(workspace));
      await tester.pump();
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ProjectIconView &&
              widget.icon == const EmojiIcon('🚀') &&
              widget.size == 16,
        ),
        findsWidgets,
      );
    });
  });
}
