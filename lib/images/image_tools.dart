import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../chat/chat_models.dart' show ToolKind;
import '../ide/file_service.dart' show IdeFileExistsException;
import '../kernel/claude_code/claude_sdk_tools.dart';
import '../models/image_api.dart';
import '../models/model_provider.dart';
import '../models/model_providers.dart';
import '../models/model_runtime.dart';
import '../platform/data_dir.dart';
import '../remote/remote_location.dart';
import '../remote/remote_services.dart';
import '../remote/ssh_host.dart';
import 'image_picks.dart';

/// The agents' tool for pictures: `mcp__baocode__generate_image`, given
/// while an upstream has an image model turned on (Settings → Models). It
/// asks the model (see image_api.dart), saves what it made where the agent
/// said (else in the app's folder), and answers with where, and the
/// pictures small: the conversation shows them as they come (see
/// image_steps.dart).
abstract final class ImageTools {
  static const name = 'generate_image';

  static ModelProviders? _providers;

  /// Gives the agents the tool while there is an image model to make
  /// pictures with, its list of them kept as they change.
  static void start() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    _providers?.removeListener(_sync);
    _providers = ModelProviders.current..addListener(_sync);
    _sync();
  }

  static void _sync() {
    final models = imageModels(ModelProviders.current);
    if (models.isEmpty) {
      ClaudeSdkTools.unregister(name);
    } else {
      ClaudeSdkTools.register(tool(models));
    }
  }

  /// The image models the tool makes pictures with: the one picked in
  /// Settings → Models first ([ModelProviders.imageModels]).
  static List<ImageModel> imageModels(ModelProviders providers) =>
      providers.imageModels;

  /// The tool, offering [models].
  static ClaudeSdkTool tool(List<ImageModel> models) => ClaudeSdkTool(
    name: name,
    description: _description(models),
    inputSchema: _schema(models),
    kind: ToolKind.image,
    summary: (input, output) => imageStepSummary(input),
    files: savedImageFiles,
    alwaysLoad: true,
    run: (input, call) => _run(input, call),
  );

  static String _description(List<ImageModel> models) {
    final list = [
      for (final (:provider, :model) in models)
        '- ${modelRef(provider.id, model.id)}: ${model.displayName} '
            '(${provider.name})',
    ].join('\n');
    return 'Generates or edits raster images (photos, illustrations, '
        'icons, textures, mockups, sprites) with an image model, and saves '
        'them as files. The user sees them in the conversation as they '
        'come: do not show them again in your reply. Give `path` when the '
        'image is for the project (e.g. "assets/hero.png"); otherwise it '
        "is kept in the app's folder, and its path is given. An existing "
        'file is never replaced: a numbered name is used instead. To edit '
        'images or work from them, give them as `reference_images`.\n\n'
        'When the user asks for a picture (an image, poster, illustration, '
        'photo, logo, cover, wallpaper...), make it with this tool: do not '
        'draw it with code (HTML, SVG, canvas) and screenshot or render it, '
        'unless they ask for that. Use code only for diagrams, simple '
        'shapes and icons that must match existing vector assets.\n\n'
        'Unless the user has picked a default image model, they are asked to '
        'pick the model when you call this: the call waits on them.\n\n'
        'Models:\n$list';
  }

  static Map<String, Object?> _schema(List<ImageModel> models) => {
    'type': 'object',
    'properties': {
      'prompt': {
        'type': 'string',
        'description':
            'What to draw, in detail: subject, composition, style, '
            'colors, lighting, and any text to render (quoted). For an '
            'edit: what to change, and what to keep as it is.',
      },
      'aspect_ratio': {
        'type': 'string',
        'enum': ['1:1', '3:2', '2:3', '4:3', '3:4', '16:9', '9:16', '21:9'],
        'description': 'Its shape; square when omitted.',
      },
      'size': {
        'type': 'string',
        'description':
            'An exact size, WIDTHxHEIGHT (e.g. "1536x1024"), only when '
            'it must be that; else leave it to aspect_ratio.',
      },
      'quality': {
        'type': 'string',
        'enum': ['low', 'medium', 'high', 'auto'],
        'description':
            'GPT Image models only: low for quick drafts, high for final '
            'assets.',
      },
      'background': {
        'type': 'string',
        'enum': ['auto', 'opaque', 'transparent'],
        'description': 'GPT Image models only: transparent for cutouts.',
      },
      'count': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 4,
        'description': 'How many variants; 1 when omitted.',
      },
      'reference_images': {
        'type': 'array',
        'items': {'type': 'string'},
        'description':
            'Image files (absolute, or relative to the working directory) '
            'to edit, or to follow for style or content.',
      },
      'path': {
        'type': 'string',
        'description':
            'Where to save it (absolute, or relative to the working '
            'directory), its extension the picture\'s own; with count > 1, '
            'numbered. Omit for previews and drafts.',
      },
      'model': {
        'type': 'string',
        'enum': [
          for (final (:provider, :model) in models)
            modelRef(provider.id, model.id),
        ],
        'description':
            'Only when the user asks for one; else omit it: the user '
            'picks it.',
      },
      'description': {
        'type': 'string',
        'description':
            'Optional. What this image is, in a few words, for the user: '
            'shown to them as the step. In the language you speak to them.',
      },
    },
    'required': ['prompt'],
  };

  static Future<Object> _run(
    Map<String, Object?> input,
    ClaudeSdkCall call,
  ) async {
    final prompt = _string(input['prompt']);
    if (prompt == null) throw const ImageToolError('Give a prompt.');
    final models = imageModels(ModelProviders.current);
    if (models.isEmpty) {
      throw const ImageToolError(
        'No image model is turned on (Settings → Models).',
      );
    }
    final (:provider, :model) = await _model(
      models,
      named: _string(input['model']),
      call: call,
    );
    final host = ImageHost(call.cwd);
    final references = [
      for (final path
          in (input['reference_images'] as List? ?? const [])
              .whereType<String>()
              .where((path) => path.trim().isNotEmpty)
              .take(8))
        await host.readImage(path.trim()),
    ];
    final request = ImageRequest(
      prompt: prompt,
      size: _string(input['size']),
      aspectRatio: _string(input['aspect_ratio']),
      quality: _string(input['quality']),
      background: _string(input['background']),
      count: switch (input['count']) {
        final num count => count.toInt().clamp(1, 4),
        _ => 1,
      },
      references: references,
    );
    final generating = generateImages(
      provider,
      model,
      request,
      session: call.sessionId,
    );
    final List<GeneratedImage> images;
    try {
      images = await switch (call.cancelled) {
        final cancelled? => Future.any([
          generating,
          cancelled.then<List<GeneratedImage>>(
            (_) => throw const ImageToolError('Cancelled.'),
          ),
        ]),
        null => generating,
      };
    } on UpstreamException catch (error) {
      throw ImageToolError('${model.displayName} failed: ${error.message}');
    }
    final asked = _string(input['path']);
    final saved = <SavedImage>[];
    for (final (i, image) in images.indexed) {
      final bytes = image.bytes!;
      saved.add(
        await host.save(
          bytes,
          asked: asked,
          prompt: prompt,
          index: images.length > 1 ? i + 1 : null,
        ),
      );
    }
    final revised = images
        .map((image) => image.revisedPrompt)
        .whereType<String>()
        .firstOrNull;
    return [
      claudeSdkText(
        describeSaved(
          saved,
          model: '${model.displayName} (${modelRef(provider.id, model.id)})',
          revisedPrompt: revised,
        ),
      ),
      for (final image in saved)
        claudeSdkImage(image.preview, image.previewType),
    ];
  }

  /// The model to make the pictures with: the one [named] (the user asked
  /// for it), else the default picked in Settings → Models, else as the
  /// user picks it in the call's step ([ImagePicks]).
  @visibleForTesting
  static Future<ImageModel> modelFor(
    List<ImageModel> models, {
    String? named,
    required ClaudeSdkCall call,
  }) => _model(models, named: named, call: call);

  static Future<ImageModel> _model(
    List<ImageModel> models, {
    String? named,
    required ClaudeSdkCall call,
  }) async {
    String refOf(ImageModel entry) =>
        modelRef(entry.provider.id, entry.model.id);
    // By its ref; by its id alone only where one upstream has it.
    ImageModel? find(String? ref) {
      if (ref == null) return null;
      if (models.where((entry) => refOf(entry) == ref).firstOrNull
          case final model?) {
        return model;
      }
      final same = [
        for (final entry in models)
          if (entry.model.id == ref) entry,
      ];
      if (same.length > 1) {
        throw ImageToolError(
          'More than one upstream has $ref: name it as one of '
          '${same.map(refOf).join(', ')}.',
        );
      }
      return same.firstOrNull;
    }

    if (named != null) {
      return find(named) ??
          (throw ImageToolError(
            'No image model $named. Use one of: '
            '${models.map(refOf).join(', ')}.',
          ));
    }
    if (find(ModelProviders.current.imageModel) case final model?) {
      return model;
    }
    // Without its id (an older Claude Code), its step cannot ask; nor is
    // there anyone to, for a bot's.
    final id = call.toolUseId;
    if (id == null || !ClaudeSdkTools.asksUser(call.cwd)) return models.first;
    final picked = await ImagePicks.instance.ask(id, cancelled: call.cancelled);
    if (picked == null) {
      throw const ImageToolError(
        'The user did not generate the image: do not try again unless they '
        'ask.',
      );
    }
    return find(picked) ??
        (throw ImageToolError('The image model $picked is gone.'));
  }

  static String? _string(Object? value) => switch (value) {
    final String text when text.trim().isNotEmpty => text.trim(),
    _ => null,
  };
}

/// An image model of an upstream.
typedef ImageModel = ({ModelProvider provider, ProviderModel model});

class ImageToolError implements Exception {
  const ImageToolError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A picture saved: where (absolute, on the project's host), its size, and
/// it small, for the agent and the conversation.
class SavedImage {
  const SavedImage({
    required this.path,
    required this.width,
    required this.height,
    required this.preview,
    required this.previewType,
  });

  final String path;
  final int? width;
  final int? height;

  /// Base64.
  final String preview;
  final String previewType;
}

/// What the tool answers of [saved]: a line for each file (which
/// [savedImageFiles] reads back), then what the agent is to do of them.
String describeSaved(
  List<SavedImage> saved, {
  required String model,
  String? revisedPrompt,
}) {
  final one = saved.length == 1;
  return [
    'Generated ${one ? 'an image' : '${saved.length} images'} with $model, '
        'saved to:',
    for (final image in saved)
      '- ${image.path}'
          '${image.width == null ? '' : ' (${image.width}×${image.height})'}',
    if (revisedPrompt != null) 'The model revised the prompt: $revisedPrompt',
    'The user sees ${one ? 'it' : 'them'} in the conversation already: do '
        'not show ${one ? 'it' : 'them'} again in your reply.',
  ].join('\n');
}

/// The files [output] (the tool's answer) says the pictures were saved to,
/// in order.
List<String> savedImageFiles(String output) => [
  for (final line in const LineSplitter().convert(output))
    ?_savedLine.firstMatch(line)?[1],
];

final _savedLine = RegExp(r'^- (.+?)(?: \(\d+×\d+\))?$');

/// What an image step is about, in a few words: its prompt's first line.
String imageStepSummary(Map<String, Object?> input) {
  final prompt = switch (input['prompt']) {
    final String text => text.trim().split('\n').first,
    _ => '',
  };
  return prompt.length > 80 ? '${prompt.substring(0, 80)}…' : prompt;
}

/// Where an agent's pictures are read and saved: on this machine, or on a
/// remote project's host, by its working directory [cwd].
class ImageHost {
  ImageHost(this.cwd);

  /// As the workspace has it: `ssh://host/path` for a remote one.
  final String cwd;

  bool get _remote => RemoteLocation.isRemote(cwd);

  p.Context get _paths => RemoteLocation.pathsOf(cwd);

  String get _root => RemoteLocation.pathOf(cwd);

  /// Where a remote host keeps pictures saved without a path.
  static const remoteFolder = '/tmp/baocode-images';

  /// Past this a reference is not read.
  static const _maxBytes = 20 << 20;

  RemoteIdeFileService get _files => RemoteIdeFileService(
    SshHosts.instance[RemoteLocation.hostOf(cwd)!],
    _root,
  );

  String _absolute(String path) => _paths.normalize(
    _paths.isAbsolute(path) ? path : _paths.join(_root, path),
  );

  /// The picture at [path], to send with a request.
  Future<ImageInput> readImage(String path) async {
    final full = _absolute(path);
    final Uint8List bytes;
    try {
      bytes = _remote
          ? await _files.readBytes(full)
          : await File(full).readAsBytes();
    } on Object catch (error) {
      throw ImageToolError('Could not read $full: $error');
    }
    if (bytes.length > _maxBytes) {
      throw ImageToolError('$full is too large (over 20 MB).');
    }
    final type = imageMediaType(bytes);
    if (type == null) {
      throw ImageToolError('$full is not a PNG, JPEG, WebP or GIF picture.');
    }
    return ImageInput(bytes, mediaType: type, name: _paths.basename(full));
  }

  /// Saves [bytes]: at [asked] (its extension the picture's, numbered
  /// [index] of several), else in the app's folder (a remote host's
  /// [remoteFolder]) named after [prompt]; never over a file, numbered
  /// past those there.
  Future<SavedImage> save(
    Uint8List bytes, {
    String? asked,
    required String prompt,
    int? index,
    DateTime? now,
  }) async {
    final type = imageMediaType(bytes) ?? 'image/png';
    final extension = imageExtension(type);
    final String base;
    if (asked != null) {
      final full = _absolute(asked);
      base = _paths.withoutExtension(full);
    } else {
      final time = now ?? DateTime.now();
      String two(int n) => '$n'.padLeft(2, '0');
      final day = '${time.year}-${two(time.month)}-${two(time.day)}';
      final folder = _remote
          ? _paths.join(remoteFolder, day)
          : p.join(DataDirectory.current.imagesDir, day);
      base = _paths.join(
        folder,
        '${imageSlug(prompt)}-${two(time.hour)}${two(time.minute)}'
        '${two(time.second)}',
      );
    }
    final stem = index == null ? base : '$base-$index';
    final path = await _write(stem, extension, bytes);
    final preview = await imagePreview(bytes, type);
    return SavedImage(
      path: path,
      width: preview.width,
      height: preview.height,
      preview: preview.base64,
      previewType: preview.type,
    );
  }

  /// Writes [bytes] at [stem] with [extension], or numbered past what is
  /// there: where.
  Future<String> _write(String stem, String extension, Uint8List bytes) async {
    for (var n = 1; n < 1000; n++) {
      final path = n == 1 ? '$stem$extension' : '$stem-$n$extension';
      if (_remote) {
        final files = _files;
        final folder = _paths.dirname(path);
        await _makeFolders(files, folder);
        try {
          await files.writeBytes(path, bytes);
          return path;
        } on IdeFileExistsException {
          continue;
        }
      }
      final file = File(path);
      await file.parent.create(recursive: true);
      try {
        // Not over one there.
        await file.create(exclusive: true);
      } on FileSystemException {
        if (await file.exists()) continue;
        rethrow;
      }
      await file.writeAsBytes(bytes, flush: true);
      return path;
    }
    throw ImageToolError('Could not find a free name for $stem$extension.');
  }

  /// [folder] and those above it, on the host.
  Future<void> _makeFolders(RemoteIdeFileService files, String folder) async {
    final parts = _paths.split(folder);
    for (var i = 1; i <= parts.length; i++) {
      final path = _paths.joinAll(parts.take(i));
      if (path == '/' || path.isEmpty) continue;
      try {
        await files.create(path, directory: true);
      } on IdeFileExistsException {
        // There already.
      } on Object {
        // Not ours to make (e.g. `/tmp`): there, or the write says why.
      }
    }
  }
}

/// [prompt]'s first words, as a file's name: `a-red-fox-in-snow`.
String imageSlug(String prompt) {
  final words = RegExp(r'[a-z0-9]+')
      .allMatches(prompt.toLowerCase())
      .map((match) => match[0]!)
      .take(6)
      .join('-');
  if (words.isEmpty) return 'image';
  return words.length > 48 ? words.substring(0, 48) : words;
}

/// The longest side of a picture the agent is given: the API's images are
/// cut to about this anyway, and a bigger one is megabytes for nothing.
const imagePreviewSide = 1024;

/// [bytes] (of [type]) small enough for the agent, and its size: as it is
/// when it already is, else no side over [imagePreviewSide], as PNG.
Future<({String base64, String type, int? width, int? height})> imagePreview(
  Uint8List bytes,
  String type,
) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;
    final longest = width > height ? width : height;
    if (longest <= imagePreviewSide && bytes.length <= 1536 * 1024) {
      return (
        base64: base64Encode(bytes),
        type: type,
        width: width,
        height: height,
      );
    }
    final scale = imagePreviewSide / longest;
    final codec = await descriptor.instantiateCodec(
      targetWidth: (width * scale).round(),
      targetHeight: (height * scale).round(),
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (png == null) {
      return (
        base64: base64Encode(bytes),
        type: type,
        width: width,
        height: height,
      );
    }
    return (
      base64: base64Encode(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      ),
      type: 'image/png',
      width: width,
      height: height,
    );
  } on Object {
    // Not one it can decode: as it is.
    return (base64: base64Encode(bytes), type: type, width: null, height: null);
  } finally {
    descriptor?.dispose();
    buffer.dispose();
  }
}
