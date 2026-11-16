import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/widgets/content_image.dart';
import 'package:baocode/chat/widgets/copy_button.dart';
import 'package:baocode/images/image_picks.dart';
import 'package:baocode/images/image_steps.dart';
import 'package:baocode/images/image_tools.dart';
import 'package:baocode/kernel/claude_code/claude_code_translator.dart';
import 'package:baocode/kernel/claude_code/claude_sdk_tools.dart';
import 'package:baocode/kernel/transcript.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// A 1×1 PNG.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  group('a call of generate_image', () {
    setUp(() => ClaudeSdkTools.register(ImageTools.tool(const [])));
    tearDown(() => ClaudeSdkTools.unregister(ImageTools.name));

    late Transcript transcript;
    late ClaudeTranslator translator;
    setUp(() {
      transcript = Transcript();
      var seq = 0;
      translator = ClaudeTranslator(
        emit: transcript.apply,
        nextSeq: () => ++seq,
      );
    });

    test('is a picture step; its files are where the tool saved them', () {
      translator.translate({
        'type': 'assistant',
        'message': {
          'id': 'm1',
          'role': 'assistant',
          'content': [
            {
              'type': 'tool_use',
              'id': 'g1',
              'name': 'mcp__baocode__generate_image',
              'input': {'prompt': 'A red fox\nin snow', 'aspect_ratio': '16:9'},
            },
          ],
        },
      });
      var step = transcript.itemAt(0) as ToolCallItem;
      expect(step.kind, ToolKind.image);
      expect(step.callId, 'g1', reason: 'what its call is asked by');
      expect(step.status, ToolStatus.running);
      expect(step.target, 'A red fox');
      translator.translate({
        'type': 'user',
        'message': {
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': 'g1',
              'content': [
                {
                  'type': 'text',
                  'text':
                      'Generated an image with X, saved to:\n'
                      '- /p/fox.png (1×1)\n'
                      'The user sees it in the conversation already.',
                },
                {
                  'type': 'image',
                  'source': {
                    'type': 'base64',
                    'data': _png,
                    'media_type': 'image/png',
                  },
                },
              ],
            },
          ],
        },
      });
      step = transcript.itemAt(0) as ToolCallItem;
      expect(step.status, ToolStatus.succeeded);
      expect(step.images.single.bytes, base64Decode(_png));
      expect(step.imageFiles, ['/p/fox.png']);
    });
  });

  group('the step', () {
    Future<void> pump(WidgetTester tester, ToolCallItem item) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ImageStep(item: item, onToggle: () {}),
              ),
            ),
          ),
        );

    testWidgets('holds the places of the pictures being made', (tester) async {
      await pump(
        tester,
        const ToolCallItem(
          kind: ToolKind.image,
          target: 'a fox',
          status: ToolStatus.running,
          input: {'prompt': 'a fox', 'size': '1600x900', 'count': 2},
        ),
      );
      expect(find.text('Generating image a fox', findRichText: true), findsOne);
      final places = find.byType(ContentImagePlaceholder);
      expect(places, findsNWidgets(2));
      final size = tester.getSize(places.first);
      expect(size.width / size.height, closeTo(16 / 9, .01));
      // The light sweeps across them.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ImageShimmer), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('shows them whole once made', (tester) async {
      await pump(
        tester,
        ToolCallItem(
          kind: ToolKind.image,
          target: 'a fox',
          input: const {'prompt': 'a fox'},
          output: 'Generated an image with X, saved to:\n- /p/fox.png',
          images: [
            ImageAttachment(bytes: base64Decode(_png), mediaType: 'image/png'),
          ],
          imageFiles: const ['/p/fox.png'],
        ),
      );
      expect(find.text('Generated image a fox', findRichText: true), findsOne);
      expect(find.byType(ContentImagePlaceholder), findsNothing);
      expect(find.byType(ContentImage), findsOneWidget);
      // What it answered, only as it opens.
      expect(find.textContaining('saved to'), findsNothing);
    });

    testWidgets('copies its prompt from a button shown while hovered', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pump(
        tester,
        ToolCallItem(
          kind: ToolKind.image,
          target: 'a fox',
          input: const {'prompt': 'a fox\nin snow, at dusk'},
          output: 'Generated an image with X, saved to:\n- /p/fox.png',
          images: [
            ImageAttachment(bytes: base64Decode(_png), mediaType: 'image/png'),
          ],
        ),
      );
      final button = find.byType(CopyButton);
      double opacity() => tester
          .widget<AnimatedOpacity>(
            find.ancestor(of: button, matching: find.byType(AnimatedOpacity)),
          )
          .opacity;
      expect(opacity(), 0, reason: 'out of sight till hovered');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(
        location: tester.getCenter(find.byType(ImageStep)),
      );
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      await tester.tap(button);
      await tester.pump();
      expect(copied, 'a fox\nin snow, at dusk', reason: 'the whole prompt');
      await mouse.removePointer();
      await tester.pumpAndSettle();
    });

    testWidgets('says it failed, and opens to why', (tester) async {
      await pump(
        tester,
        const ToolCallItem(
          kind: ToolKind.image,
          target: 'a fox',
          status: ToolStatus.failed,
          output: 'GPT Image 2 failed: HTTP 400: rejected',
        ),
      );
      expect(
        find.text('Image not generated a fox', findRichText: true),
        findsOne,
      );
      expect(find.byType(ContentImagePlaceholder), findsNothing);
    });
  });

  group('saving', () {
    late Directory folder;
    setUp(() => folder = Directory.systemTemp.createTempSync('images-test'));
    tearDown(() => folder.deleteSync(recursive: true));

    testWidgets('at the path asked, its extension the picture\'s, never over '
        'a file', (tester) async {
      await tester.runAsync(() async {
        final host = ImageHost(folder.path);
        final bytes = base64Decode(_png);
        final first = await host.save(
          bytes,
          asked: 'assets/fox.jpg',
          prompt: 'a fox',
        );
        expect(first.path, p.join(folder.path, 'assets', 'fox.png'));
        expect(File(first.path).readAsBytesSync(), bytes);
        expect((first.width, first.height), (1, 1));
        expect(first.preview, _png);
        final second = await host.save(
          bytes,
          asked: 'assets/fox.png',
          prompt: 'a fox',
        );
        expect(second.path, p.join(folder.path, 'assets', 'fox-2.png'));
        final numbered = await host.save(
          bytes,
          asked: 'assets/fox.png',
          prompt: 'a fox',
          index: 2,
        );
        expect(numbered.path, p.join(folder.path, 'assets', 'fox-2-2.png'));
      });
    });
  });

  group('the model', () {
    const openai = ModelProvider(
      id: 'oa',
      name: 'OpenAI',
      protocol: ProviderProtocol.openaiChat,
      baseUrl: 'https://api.openai.com/v1',
      models: [
        ProviderModel(id: 'gpt-5.4'),
        ProviderModel(id: 'gpt-image-1'),
        ProviderModel(id: 'gpt-image-2'),
      ],
    );
    late ModelProviders before;
    setUp(() {
      before = ModelProviders.current;
      ModelProviders.current = ModelProviders.memory(providers: [openai]);
    });
    tearDown(() => ModelProviders.current = before);

    Future<String> pick({
      String? named,
      String? callId,
      Future<void>? stop,
    }) async {
      final (:provider, :model) = await ImageTools.modelFor(
        ModelProviders.current.imageModels,
        named: named,
        call: ClaudeSdkCall(cwd: '/p', toolUseId: callId, cancelled: stop),
      );
      return modelRef(provider.id, model.id);
    }

    test('named by the agent, or the default, is not asked', () async {
      expect(await pick(named: 'gpt-image-2', callId: 'a'), '@oa/gpt-image-2');
      await ModelProviders.current.setImageModel('@oa/gpt-image-2');
      expect(
        ModelProviders.current.imageModels.first.model.id,
        'gpt-image-2',
        reason: 'the default first',
      );
      expect(await pick(callId: 'b'), '@oa/gpt-image-2');
      expect(ImagePicks.instance.waiting('b'), isFalse);
    });

    test('of the same id at two upstreams, is told by its ref', () async {
      const relay = ModelProvider(
        id: 'relay',
        name: 'Relay',
        protocol: ProviderProtocol.openaiChat,
        baseUrl: 'https://relay.example/v1',
        models: [ProviderModel(id: 'gpt-image-1')],
      );
      ModelProviders.current = ModelProviders.memory(
        providers: [openai, relay],
      );
      expect(
        await pick(named: '@relay/gpt-image-1', callId: 'r1'),
        '@relay/gpt-image-1',
      );
      // Its id alone: only where one upstream has it.
      expect(await pick(named: 'gpt-image-2', callId: 'r2'), '@oa/gpt-image-2');
      await expectLater(
        pick(named: 'gpt-image-1', callId: 'r3'),
        throwsA(
          isA<ImageToolError>().having(
            (e) => e.message,
            'message',
            allOf(contains('@oa/gpt-image-1'), contains('@relay/gpt-image-1')),
          ),
        ),
      );
    });

    test('else waits for the user to pick it in the step', () async {
      final picked = pick(callId: 'c');
      await Future<void>.delayed(Duration.zero);
      expect(ImagePicks.instance.waiting('c'), isTrue);
      ImagePicks.instance.pick('c', '@oa/gpt-image-1');
      expect(await picked, '@oa/gpt-image-1');
      expect(ImagePicks.instance.waiting('c'), isFalse);
      expect(ImagePicks.instance.picked('c'), '@oa/gpt-image-1');
    });

    test('and fails as the user declines, or the turn stops', () async {
      final declined = pick(callId: 'd');
      await Future<void>.delayed(Duration.zero);
      ImagePicks.instance.decline('d');
      await expectLater(declined, throwsA(isA<ImageToolError>()));
      final stop = Completer<void>();
      final stopped = pick(callId: 'e', stop: stop.future);
      await Future<void>.delayed(Duration.zero);
      stop.complete();
      await expectLater(stopped, throwsA(isA<ImageToolError>()));
      expect(ImagePicks.instance.waiting('e'), isFalse);
    });

    testWidgets('is asked for as the step shows, before its call comes', (
      tester,
    ) async {
      Future<void> show(ToolCallItem item) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ImageStep(item: item)),
        ),
      );
      // Its line streamed in, its input not yet: nothing under it.
      await show(
        const ToolCallItem(
          kind: ToolKind.image,
          target: '',
          status: ToolStatus.running,
          callId: 'early',
        ),
      );
      expect(find.text('Pick the model to generate it with'), findsNothing);
      expect(find.byType(ContentImagePlaceholder), findsNothing);
      // Its input in, its call not yet come to the tool.
      await show(
        const ToolCallItem(
          kind: ToolKind.image,
          target: 'a fox',
          status: ToolStatus.running,
          callId: 'early',
          input: {'prompt': 'a fox'},
        ),
      );
      expect(find.text('Pick the model to generate it with'), findsOneWidget);
      expect(find.byType(ContentImagePlaceholder), findsNothing);
      await tester.tap(find.text('Generate'));
      await tester.pump();
      expect(find.byType(ContentImagePlaceholder), findsOneWidget);
      // The call, as it comes, takes what was picked.
      expect(await ImagePicks.instance.ask('early'), '@oa/gpt-image-1');
      // Named by the agent, or with a default, nothing is asked.
      await show(
        const ToolCallItem(
          kind: ToolKind.image,
          target: 'a fox',
          status: ToolStatus.running,
          callId: 'named',
          input: {'prompt': 'a fox', 'model': '@oa/gpt-image-2'},
        ),
      );
      expect(find.text('Pick the model to generate it with'), findsNothing);
      expect(find.byType(ContentImagePlaceholder), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    test('declined before its call comes, the call fails at once', () async {
      ImagePicks.instance.decline('gone');
      expect(await ImagePicks.instance.ask('gone'), isNull);
    });

    testWidgets('is picked in the step, then offered as the default', (
      tester,
    ) async {
      Future<void> show(ToolCallItem item) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ImageStep(item: item)),
        ),
      );
      const waiting = ToolCallItem(
        kind: ToolKind.image,
        target: 'a fox',
        status: ToolStatus.running,
        callId: 'w1',
        input: {'prompt': 'a fox'},
      );
      final asked = ImagePicks.instance.ask('w1');
      await show(waiting);
      expect(find.text('Pick the model to generate it with'), findsOneWidget);
      expect(find.text('OpenAI · GPT-Image-1'), findsNothing);
      expect(find.byType(ContentImagePlaceholder), findsNothing);
      await tester.tap(find.text('Generate'));
      await tester.pump();
      expect(await asked, '@oa/gpt-image-1');
      // Being made.
      expect(find.byType(ContentImagePlaceholder), findsOneWidget);
      expect(find.text('Set as default'), findsOneWidget);
      await tester.tap(find.text('Set as default'));
      await tester.pump();
      await tester.pump();
      expect(ModelProviders.current.imageModel, '@oa/gpt-image-1');
      expect(find.text('Set as default image model'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
