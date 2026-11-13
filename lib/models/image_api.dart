// What an image model is asked, and how its pictures come back: the
// Images API's (`/images/generations`, `/images/edits`: OpenAI's, and the
// upstreams that speak it: SiliconFlow, Volcengine Ark, Zhipu, relays),
// a conversation's that answers with pictures (OpenRouter's `modalities`),
// and the Responses API's `image_generation` tool (Codex's).

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'model_provider.dart';
import 'model_runtime.dart' show UpstreamException;
import 'upstream.dart';

/// A picture given with a request: one to edit, or to go by.
class ImageInput {
  const ImageInput(this.bytes, {required this.mediaType, this.name});

  final Uint8List bytes;
  final String mediaType;

  /// Its file's name, for a form's part.
  final String? name;

  String get dataUrl => 'data:$mediaType;base64,${base64Encode(bytes)}';
}

/// What a picture is asked to be.
class ImageRequest {
  const ImageRequest({
    required this.prompt,
    this.size,
    this.aspectRatio,
    this.quality,
    this.background,
    this.count = 1,
    this.references = const [],
  });

  final String prompt;

  /// `WIDTHxHEIGHT`, or `auto`, as asked; else from [aspectRatio].
  final String? size;

  /// `16:9`, `1:1`…: the size made of it, as the model takes sizes.
  final String? aspectRatio;

  /// `low`, `medium`, `high` or `auto` (GPT Image's).
  final String? quality;

  /// `transparent`, `opaque` or `auto` (GPT Image's).
  final String? background;

  /// How many pictures.
  final int count;

  /// Pictures to edit, or to go by: the request is then an edit.
  final List<ImageInput> references;
}

/// A picture an image model made: its bytes, or where to fetch them.
class GeneratedImage {
  const GeneratedImage({this.bytes, this.url, this.revisedPrompt});

  final Uint8List? bytes;
  final Uri? url;

  /// The prompt as the model rewrote it, where it says.
  final String? revisedPrompt;
}

/// [aspect] (`16:9`, `16/9`, `16x9`) as width over height; null when it is
/// not one.
double? parseAspectRatio(String? aspect) {
  final match = RegExp(r'^\s*(\d+(?:\.\d+)?)\s*[:/x×]\s*(\d+(?:\.\d+)?)\s*$')
      .firstMatch(aspect ?? '');
  if (match == null) return null;
  final width = double.parse(match[1]!);
  final height = double.parse(match[2]!);
  if (width <= 0 || height <= 0) return null;
  return width / height;
}

/// [size] (`1536x1024`) as its width and height; null when it is not one.
({int width, int height})? parseImageSize(String? size) {
  final match = RegExp(r'^\s*(\d+)\s*[x×*]\s*(\d+)\s*$').firstMatch(size ?? '');
  if (match == null) return null;
  final width = int.parse(match[1]!);
  final height = int.parse(match[2]!);
  if (width <= 0 || height <= 0) return null;
  return (width: width, height: height);
}

/// The size [request] goes as to [model], as it takes sizes: the one
/// asked; else of its aspect ratio, the nearest it offers (GPT Image 1,
/// DALL·E), or about a megapixel, each side a multiple of 16 (GPT Image 2,
/// and the others); null when neither is asked (the model's own).
String? imageSizeFor(String model, ImageRequest request) {
  if (request.size case final size? when size.trim().isNotEmpty) {
    return size.trim();
  }
  final ratio = parseAspectRatio(request.aspectRatio);
  if (ratio == null) return null;
  final name = model.toLowerCase().split('/').last;
  List<String>? fixed;
  if (name.startsWith('dall-e-3')) {
    fixed = const ['1024x1024', '1792x1024', '1024x1792'];
  } else if (name.startsWith('dall-e')) {
    fixed = const ['1024x1024'];
  } else if (RegExp(r'^(?:gpt-image-1|chatgpt-image)').hasMatch(name)) {
    fixed = const ['1024x1024', '1536x1024', '1024x1536'];
  }
  if (fixed != null) {
    String? nearest;
    var distance = double.infinity;
    for (final size in fixed) {
      final (:width, :height) = parseImageSize(size)!;
      final off = (width / height / ratio - 1).abs();
      if (off < distance) {
        distance = off;
        nearest = size;
      }
    }
    return nearest;
  }
  // Within GPT Image 2's bounds (3:1 at most), as most others take them.
  final bounded = ratio.clamp(1 / 3, 3.0);
  const pixels = 1048576;
  int round16(double value) => ((value / 16).round() * 16).clamp(256, 3840);
  final width = round16(math.sqrt(pixels * bounded));
  final height = round16(math.sqrt(pixels / bounded));
  return '${width}x$height';
}

bool _isGptImage(String model) =>
    RegExp(r'^(?:gpt-image|chatgpt-image)')
        .hasMatch(model.toLowerCase().split('/').last);

/// The body of an Images API generation (`/images/generations`) of
/// [request] by [model]: only the fields a model of its family takes, as
/// OpenAI's refuses others. [references] go in it, as data URLs, for the
/// upstreams that take them so ([referencesInBody]: Volcengine Ark's).
Map<String, Object?> imageGenerationBody(
  String model,
  ImageRequest request, {
  bool referencesInBody = false,
}) {
  final gptImage = _isGptImage(model);
  final dalle = model.toLowerCase().split('/').last.startsWith('dall-e');
  return {
    'model': model,
    'prompt': request.prompt,
    'size': ?imageSizeFor(model, request),
    if (request.count > 1) 'n': request.count,
    if (gptImage) ...{
      'quality': ?request.quality,
      'background': ?request.background,
    },
    if (dalle) ...{
      if (request.quality case 'high' || 'hd') 'quality': 'hd',
      'response_format': 'b64_json',
    },
    if (referencesInBody && request.references.isNotEmpty)
      'image': [for (final image in request.references) image.dataUrl],
  };
}

/// Whether an upstream at [host] takes the pictures to edit in a
/// generation's body (Volcengine Ark's Seedream), not as an edit's form.
bool referencesInBody(String host) =>
    host.endsWith('volces.com') || host.endsWith('bytepluses.com');

/// The text fields of an Images API edit's form (`/images/edits`), beside
/// its pictures ([imageEditField]).
Map<String, String> imageEditFields(String model, ImageRequest request) {
  final gptImage = _isGptImage(model);
  return {
    'model': model,
    'prompt': request.prompt,
    'size': ?imageSizeFor(model, request),
    if (request.count > 1) 'n': '${request.count}',
    if (gptImage) ...{
      'quality': ?request.quality,
      'background': ?request.background,
    },
  };
}

/// The name of an edit's form's picture fields: GPT Image takes several
/// (`image[]`), the others one (`image`).
String imageEditField(String model) => _isGptImage(model) ? 'image[]' : 'image';

/// A multipart form of [fields] and [files] (each of a field's name), and
/// its boundary, for an edit.
({Uint8List body, String boundary}) multipartForm(
  Map<String, String> fields,
  List<(String, ImageInput)> files,
) {
  final boundary =
      '----baocode${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
  final out = BytesBuilder(copy: false);
  void line(String text) => out.add(utf8.encode('$text\r\n'));
  for (final MapEntry(:key, :value) in fields.entries) {
    line('--$boundary');
    line('Content-Disposition: form-data; name="$key"');
    line('');
    line(value);
  }
  for (final (i, (field, image)) in files.indexed) {
    final extension = switch (image.mediaType) {
      'image/jpeg' => 'jpg',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      _ => 'png',
    };
    final name = (image.name ?? 'image-${i + 1}.$extension').replaceAll(
      '"',
      '',
    );
    line('--$boundary');
    line('Content-Disposition: form-data; name="$field"; filename="$name"');
    line('Content-Type: ${image.mediaType}');
    line('');
    out.add(image.bytes);
    line('');
  }
  line('--$boundary--');
  return (body: out.takeBytes(), boundary: boundary);
}

/// The pictures in an Images API answer: OpenAI's `data` (each a
/// `b64_json` or a `url`), SiliconFlow's `images`; a data URL as its
/// bytes. Throws [UpstreamException] when it has none.
List<GeneratedImage> parseImagesResponse(Object? json) {
  final list = switch (json) {
    {'data': final List data} => data,
    {'images': final List images} => images,
    {'output': {'results': final List results}} => results,
    _ => const [],
  };
  final images = <GeneratedImage>[
    for (final item in list.whereType<Map>()) ?_image(item),
  ];
  if (images.isEmpty) {
    throw UpstreamException(
      'No picture in the answer: ${_clip(jsonEncode(json))}',
    );
  }
  return images;
}

GeneratedImage? _image(Map item) {
  final revised = switch (item['revised_prompt']) {
    final String text when text.trim().isNotEmpty => text.trim(),
    _ => null,
  };
  for (final key in const ['b64_json', 'b64', 'base64', 'result']) {
    if (item[key] case final String data when data.isNotEmpty) {
      if (_bytes(data) case final bytes?) {
        return GeneratedImage(bytes: bytes, revisedPrompt: revised);
      }
    }
  }
  if (item['url'] case final String url when url.isNotEmpty) {
    return _ofUrl(url, revised);
  }
  return null;
}

/// A picture at [url]: a data URL's bytes, or where to fetch it.
GeneratedImage? _ofUrl(String url, [String? revised]) {
  if (url.startsWith('data:')) {
    final comma = url.indexOf(',');
    if (comma < 0) return null;
    final bytes = _bytes(url.substring(comma + 1));
    return bytes == null
        ? null
        : GeneratedImage(bytes: bytes, revisedPrompt: revised);
  }
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    return null;
  }
  return GeneratedImage(url: uri, revisedPrompt: revised);
}

Uint8List? _bytes(String base64) {
  try {
    return base64Decode(base64.replaceAll(RegExp(r'\s'), ''));
  } on FormatException {
    return null;
  }
}

/// A conversation's request (Chat Completions) for [request]'s pictures,
/// as OpenRouter takes it: answered with images and text, of the aspect
/// ratio asked.
Map<String, Object?> chatImageBody(String model, ImageRequest request) => {
  'model': model,
  'messages': [
    {
      'role': 'user',
      'content': [
        {'type': 'text', 'text': request.prompt},
        for (final image in request.references)
          {
            'type': 'image_url',
            'image_url': {'url': image.dataUrl},
          },
      ],
    },
  ],
  'modalities': ['image', 'text'],
  if (request.aspectRatio case final aspect?
      when parseAspectRatio(aspect) != null)
    'image_config': {'aspect_ratio': aspect.trim()},
  'stream': false,
};

/// The pictures in a conversation's answer: OpenRouter's
/// `message.images`, content parts of images, or images in its markdown
/// (data URLs, links). Throws [UpstreamException] when it has none.
List<GeneratedImage> parseChatImages(Object? json) {
  final message = switch (json) {
    {'choices': [{'message': final Map message}, ...]} => message,
    _ => null,
  };
  final images = <GeneratedImage>[];
  void addUrl(Object? url) {
    if (url is String) {
      if (_ofUrl(url) case final image?) images.add(image);
    }
  }

  for (final item in (message?['images'] as List? ?? const [])) {
    if (item case {'image_url': {'url': final url}}) addUrl(url);
    if (item case {'url': final url}) addUrl(url);
  }
  switch (message?['content']) {
    case final List parts:
      for (final part in parts.whereType<Map>()) {
        if (part case {'image_url': {'url': final url}}) addUrl(url);
        if (part case {'type': 'output_image', 'image_url': final url}) {
          addUrl(url);
        }
        if (part case {
          'inline_data': {'data': final String data, 'mime_type': _},
        }) {
          if (_bytes(data) case final bytes?) {
            images.add(GeneratedImage(bytes: bytes));
          }
        }
      }
    case final String text when images.isEmpty:
      for (final match in RegExp(
        r'!\[[^\]]*\]\(((?:data:image/[^)\s]+)|(?:https?://[^)\s]+))\)',
      ).allMatches(text)) {
        addUrl(match[1]);
      }
  }
  if (images.isEmpty) {
    final said = switch (message?['content']) {
      final String text when text.trim().isNotEmpty => text.trim(),
      _ => jsonEncode(json),
    };
    throw UpstreamException('No picture in the answer: ${_clip(said)}');
  }
  return images;
}

/// A Responses request (Codex's) that makes [request]'s pictures with the
/// `image_generation` tool, by conversation model [model].
Map<String, Object?> responsesImageBody(String model, ImageRequest request) {
  final size = imageSizeFor(codexFallbackImageModel, request);
  return {
    'model': model,
    'instructions': '',
    'input': [
      {
        'type': 'message',
        'role': 'user',
        'content': [
          {'type': 'input_text', 'text': request.prompt},
          for (final image in request.references)
            // `detail` spelled out: strict servers ask for it (#974).
            {
              'type': 'input_image',
              'image_url': image.dataUrl,
              'detail': 'auto',
            },
        ],
      },
    ],
    'tools': [
      {
        'type': 'image_generation',
        'size': ?size,
        'quality': ?request.quality,
        'background': ?request.background,
      },
    ],
    'tool_choice': {'type': 'image_generation'},
    'stream': true,
    'store': false,
  };
}

/// The image model the Responses tool makes pictures with, for their
/// sizes: GPT Image 1's.
const codexFallbackImageModel = 'gpt-image-1';

/// The pictures in a Responses stream's events ([text], `data:` lines):
/// its `image_generation_call` items' results. Throws [UpstreamException]
/// with what failed, or when there is none.
List<GeneratedImage> parseResponsesImages(String text) {
  final images = <GeneratedImage>[];
  String? error;
  for (final line in const LineSplitter().convert(text)) {
    if (!line.startsWith('data:')) continue;
    final Object? event;
    try {
      event = jsonDecode(line.substring(5).trim());
    } on FormatException {
      continue;
    }
    switch (event) {
      case {
        'type': 'response.output_item.done',
        'item': {'type': 'image_generation_call'} && final Map item,
      }:
        if (_image(item) case final image?) images.add(image);
      case {'type': 'response.failed', 'response': {'error': final Map e}}:
        error = '${e['message'] ?? jsonEncode(e)}';
      case {'type': 'error', 'error': final Map e}:
        error = '${e['message'] ?? jsonEncode(e)}';
      case {'type': 'error', 'message': final String message}:
        error = message;
    }
  }
  if (images.isNotEmpty) return images;
  throw UpstreamException(error ?? 'No picture in the answer.');
}

/// The kind of picture [bytes] is, by its header: `image/png`,
/// `image/jpeg`, `image/webp` or `image/gif`; null for another.
String? imageMediaType(Uint8List bytes) {
  bool at(int offset, List<int> signature) {
    if (bytes.length < offset + signature.length) return false;
    for (final (i, byte) in signature.indexed) {
      if (bytes[offset + i] != byte) return false;
    }
    return true;
  }

  if (at(0, const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (at(0, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (at(0, 'RIFF'.codeUnits) && at(8, 'WEBP'.codeUnits)) return 'image/webp';
  if (at(0, 'GIF8'.codeUnits)) return 'image/gif';
  return null;
}

/// The extension of a file of [mediaType]'s.
String imageExtension(String? mediaType) => switch (mediaType) {
  'image/jpeg' => '.jpg',
  'image/webp' => '.webp',
  'image/gif' => '.gif',
  _ => '.png',
};

/// The base the Images API's paths go under for [provider]: its OpenAI
/// base, or for an Anthropic-compatible one, that of its host's.
String? imagesBase(ModelProvider provider) => switch (provider.protocol) {
  ProviderProtocol.anthropic => switch (UpstreamUrls.anthropicBase(
    provider.baseUrl,
  )) {
    final base? => UpstreamUrls.openaiBase(base),
    null => null,
  },
  _ => UpstreamUrls.openaiBase(provider.baseUrl),
};

String _clip(String text) =>
    text.length > 300 ? '${text.substring(0, 300)}…' : text;
