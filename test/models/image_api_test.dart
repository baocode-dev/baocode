import 'dart:convert';
import 'dart:typed_data';

import 'package:baocode/images/image_tools.dart';
import 'package:baocode/models/image_api.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/model_runtime.dart' show UpstreamException;
import 'package:baocode/models/upstream.dart';
import 'package:flutter_test/flutter_test.dart';

final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 1, 0, 0, 0, 1,
]);

void main() {
  group('what a model is for', () {
    test('goes by its name', () {
      for (final id in [
        'gpt-image-1',
        'gpt-image-2',
        'dall-e-3',
        'imagen-4.0-generate-001',
        'doubao-seedream-4-0-250828',
        'cogview-4',
        'black-forest-labs/FLUX.1-schnell',
        'Kwai-Kolors/Kolors',
        'qwen-image',
        'grok-imagine-image',
        'grok-imagine-image-quality',
        'grok-2-image-1212',
        'gpt-image-2-4k',
      ]) {
        expect(guessModelKind(id), ModelKind.image, reason: id);
      }
      for (final id in [
        'gemini-2.5-flash-image',
        'google/gemini-2.5-flash-image-preview',
        'gemini-3-pro-image-preview',
        'nana-banana-2',
        'nano-banana-pro',
      ]) {
        expect(guessModelKind(id), ModelKind.imageChat, reason: id);
      }
      for (final id in [
        'gpt-5.4',
        'claude-sonnet-5-5',
        'gemini-2.5-pro',
        'qwen-vl-max',
        // Not pictures: not made here.
        'grok-imagine-video',
      ]) {
        expect(guessModelKind(id), ModelKind.chat, reason: id);
      }
    });

    test('as an upstream lists it, kept only where its name tells else', () {
      final listed = parseModelList({
        'data': [
          {
            'id': 'acme/painter',
            'architecture': {
              'output_modalities': ['image'],
            },
          },
          {
            'id': 'acme/talker',
            'architecture': {
              'output_modalities': ['text', 'image'],
            },
          },
          {
            'id': 'acme/writer',
            'architecture': {
              'output_modalities': ['text'],
            },
          },
          {'id': 'Kwai-Kolors/Kolors', 'type': 'image'},
        ],
      });
      expect(listed.map((model) => model.kind), [
        ModelKind.image,
        ModelKind.imageChat,
        ModelKind.chat,
        ModelKind.image,
      ]);
      final merged = mergeModelList(const [], listed);
      expect(merged.map((model) => model.kindSet), [
        ModelKind.image,
        ModelKind.imageChat,
        // Their names tell.
        null,
        null,
      ]);
      expect(merged.map((model) => model.kind), [
        ModelKind.image,
        ModelKind.imageChat,
        ModelKind.chat,
        ModelKind.image,
      ]);
    });

    test('is kept, and keeps image models out of the picker', () {
      const provider = ModelProvider(
        id: 'p',
        name: 'P',
        models: [
          ProviderModel(id: 'gpt-5.4'),
          ProviderModel(id: 'gpt-image-2'),
          ProviderModel(id: 'painter', kind: ModelKind.image),
          ProviderModel(id: 'dall-e-3', kind: ModelKind.chat),
        ],
      );
      final read = ModelProvider.fromJson(
        jsonDecode(jsonEncode(provider.toJson())),
      )!;
      expect(read.models, provider.models);
      expect(read.toJson()['models'], [
        {'id': 'gpt-5.4'},
        {'id': 'gpt-image-2'},
        {'id': 'painter', 'kind': 'image'},
        {'id': 'dall-e-3', 'kind': 'chat'},
      ]);
      // By name.
      expect(read.enabledModels.map((model) => model.id), [
        'dall-e-3',
        'gpt-5.4',
      ]);
      expect(read.imageModels.map((model) => model.id), [
        'gpt-image-2',
        'painter',
      ]);
      // A session or default once on an image model goes on the main one.
      final providers = ModelProviders.memory(
        providers: [read.copyWith(roles: const ProviderRoles(main: 'gpt-5.4'))],
      );
      expect(providers.resolve('@p/gpt-image-2')?.$2.id, 'gpt-5.4');
      expect(providers.resolve('@p/dall-e-3')?.$2.id, 'dall-e-3');
    });
  });

  group('sizes', () {
    test('as asked, else of the aspect ratio as the model takes them', () {
      ImageRequest asked({String? size, String? aspect}) =>
          ImageRequest(prompt: 'x', size: size, aspectRatio: aspect);
      expect(imageSizeFor('gpt-image-1', asked()), isNull);
      expect(imageSizeFor('flux', asked(size: '800x600')), '800x600');
      expect(imageSizeFor('gpt-image-1', asked(aspect: '16:9')), '1536x1024');
      expect(imageSizeFor('gpt-image-1.5', asked(aspect: '2:3')), '1024x1536');
      expect(imageSizeFor('dall-e-3', asked(aspect: '9:16')), '1024x1792');
      expect(imageSizeFor('gpt-image-2', asked(aspect: '1:1')), '1024x1024');
      final wide = parseImageSize(
        imageSizeFor('gpt-image-2', asked(aspect: '16:9')),
      )!;
      expect(wide.width % 16, 0);
      expect(wide.height % 16, 0);
      expect(wide.width / wide.height, closeTo(16 / 9, .02));
      expect(wide.width * wide.height, greaterThan(921600));
    });
  });

  group('the Images API', () {
    test("a generation's body has only what the model takes", () {
      const request = ImageRequest(
        prompt: 'a fox',
        aspectRatio: '3:2',
        quality: 'high',
        background: 'transparent',
        count: 2,
      );
      expect(imageGenerationBody('gpt-image-1', request), {
        'model': 'gpt-image-1',
        'prompt': 'a fox',
        'size': '1536x1024',
        'n': 2,
        'quality': 'high',
        'background': 'transparent',
      });
      expect(imageGenerationBody('flux-dev', request), {
        'model': 'flux-dev',
        'prompt': 'a fox',
        'size': '1248x832',
        'n': 2,
      });
      expect(
        imageGenerationBody('dall-e-3', request)['response_format'],
        'b64_json',
      );
      final edit = ImageRequest(
        prompt: 'redder',
        references: [ImageInput(_png, mediaType: 'image/png')],
      );
      expect(
        imageGenerationBody('doubao-seedream-4', edit, referencesInBody: true),
        containsPair('image', [startsWith('data:image/png;base64,')]),
      );
    });

    test("an edit's form has its fields and pictures", () {
      final form = multipartForm(
        {'model': 'gpt-image-1', 'prompt': 'redder'},
        [('image[]', ImageInput(_png, mediaType: 'image/png', name: 'a.png'))],
      );
      final text = latin1.decode(form.body);
      expect(text, contains('name="prompt"\r\n\r\nredder\r\n'));
      expect(
        text,
        contains('name="image[]"; filename="a.png"\r\nContent-Type: image/png'),
      );
      expect(text.trimRight(), endsWith('--${form.boundary}--'));
    });

    test('its pictures: bytes, links and data URLs', () {
      final data = base64Encode(_png);
      final images = parseImagesResponse({
        'data': [
          {'b64_json': data, 'revised_prompt': 'A fox.'},
          {'url': 'https://cdn.example/a.png'},
          {'url': 'data:image/png;base64,$data'},
        ],
      });
      expect(images[0].bytes, _png);
      expect(images[0].revisedPrompt, 'A fox.');
      expect(images[1].url, Uri.parse('https://cdn.example/a.png'));
      expect(images[2].bytes, _png);
      // SiliconFlow's.
      expect(
        parseImagesResponse({
          'images': [
            {'url': 'https://x.example/b.png'},
          ],
        }).single.url!.host,
        'x.example',
      );
      expect(
        () => parseImagesResponse({'data': <Object>[]}),
        throwsA(isA<UpstreamException>()),
      );
    });
  });

  group('a conversation', () {
    test('asks for pictures, and finds them in the answer', () {
      expect(
        chatImageBody(
          'google/gemini-2.5-flash-image',
          const ImageRequest(prompt: 'a fox', aspectRatio: '16:9'),
        ),
        allOf(
          containsPair('modalities', ['image', 'text']),
          containsPair('image_config', {'aspect_ratio': '16:9'}),
        ),
      );
      final data = 'data:image/png;base64,${base64Encode(_png)}';
      expect(
        parseChatImages({
          'choices': [
            {
              'message': {
                'content': 'Here it is.',
                'images': [
                  {
                    'type': 'image_url',
                    'image_url': {'url': data},
                  },
                ],
              },
            },
          ],
        }).single.bytes,
        _png,
      );
      expect(
        parseChatImages({
          'choices': [
            {
              'message': {'content': 'Done: ![fox]($data)'},
            },
          ],
        }).single.bytes,
        _png,
      );
      expect(
        () => parseChatImages({
          'choices': [
            {
              'message': {'content': 'I cannot draw that.'},
            },
          ],
        }),
        throwsA(
          isA<UpstreamException>().having(
            (e) => e.message,
            'message',
            contains('I cannot draw that.'),
          ),
        ),
      );
    });
  });

  group("the Responses API's tool", () {
    test('is forced, and its calls are the pictures', () {
      final body = responsesImageBody(
        'gpt-5.4',
        const ImageRequest(prompt: 'x'),
      );
      expect(body['tool_choice'], {'type': 'image_generation'});
      final events = [
        'event: response.output_item.done',
        'data: ${jsonEncode({
          'type': 'response.output_item.done',
          'item': {'type': 'image_generation_call', 'result': base64Encode(_png), 'revised_prompt': 'A fox.'},
        })}',
        '',
      ].join('\n');
      final image = parseResponsesImages(events).single;
      expect(image.bytes, _png);
      expect(image.revisedPrompt, 'A fox.');
      expect(
        () => parseResponsesImages(
          'data: ${jsonEncode({
            'type': 'response.failed',
            'response': {
              'error': {'message': 'Not allowed.'},
            },
          })}',
        ),
        throwsA(
          isA<UpstreamException>().having(
            (e) => e.message,
            'message',
            'Not allowed.',
          ),
        ),
      );
    });
  });

  group("Antigravity's image generation", () {
    test('builds Gemini contents, references and imageConfig', () {
      final body = antigravityImageRequest(
        ImageRequest(
          prompt: 'A red fox',
          aspectRatio: '16:9',
          references: [ImageInput(_png, mediaType: 'image/png')],
        ),
      );
      expect(body['contents'], [
        {
          'role': 'user',
          'parts': [
            {'text': 'A red fox'},
            {
              'inlineData': {
                'mimeType': 'image/png',
                'data': base64Encode(_png),
              },
            },
          ],
        },
      ]);
      expect(body['generationConfig'], {
        'responseModalities': ['TEXT', 'IMAGE'],
        'imageConfig': {'aspectRatio': '16:9'},
      });

      final sized = antigravityImageRequest(
        const ImageRequest(prompt: 'A poster', size: '2048x1365'),
      );
      expect(sized['generationConfig'], {
        'responseModalities': ['TEXT', 'IMAGE'],
        'imageConfig': {'aspectRatio': '3:2', 'imageSize': '2K'},
      });
    });

    test('parses SSE inlineData, skips thought parts, surfaces errors', () {
      final events = [
        'data: ${jsonEncode({
          'response': {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'thought': true,
                      'inlineData': {
                        'mimeType': 'image/png',
                        'data': base64Encode([1, 2, 3]),
                      },
                    },
                    {'text': 'Here it is.'},
                  ],
                },
              },
            ],
          },
        })}',
        '',
        'data: ${jsonEncode({
          'response': {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'inlineData': {'mimeType': 'image/png', 'data': base64Encode(_png)},
                    },
                  ],
                },
              },
            ],
          },
        })}',
        '',
      ].join('\n');
      expect(parseAntigravityImages(events).single.bytes, _png);

      expect(
        () => parseAntigravityImages(
          'data: ${jsonEncode({
            'response': {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'I cannot draw that.'},
                    ],
                  },
                },
              ],
            },
          })}',
        ),
        throwsA(
          isA<UpstreamException>().having(
            (e) => e.message,
            'message',
            contains('I cannot draw that.'),
          ),
        ),
      );
    });
  });

  group('the tool', () {
    test('says where it saved them, which the step reads back', () {
      final text = describeSaved(
        const [
          SavedImage(
            path: '/p/assets/fox.png',
            width: 1536,
            height: 1024,
            preview: '',
            previewType: 'image/png',
          ),
          SavedImage(
            path: '/p/assets/fox 2.png',
            width: null,
            height: null,
            preview: '',
            previewType: 'image/png',
          ),
        ],
        model: 'GPT Image 2 (@codex/gpt-image-2)',
        revisedPrompt: 'A fox.',
      );
      expect(savedImageFiles(text), [
        '/p/assets/fox.png',
        '/p/assets/fox 2.png',
      ]);
    });

    test("names a file of its prompt's first words", () {
      expect(
        imageSlug('A red fox, in the snow at dawn!'),
        'a-red-fox-in-the-snow',
      );
      expect(imageSlug('一只狐狸'), 'image');
    });

    test('knows a picture by its header', () {
      expect(imageMediaType(_png), 'image/png');
      expect(
        imageMediaType(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0])),
        'image/jpeg',
      );
      expect(imageMediaType(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });
}
