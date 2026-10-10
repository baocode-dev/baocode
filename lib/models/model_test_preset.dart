import 'model_test.dart' show modelTestPrompt;

/// Only user presets are serialized. Built-in IDs are reserved so imported
/// settings cannot replace or delete the two stable connectivity prompts.
class ModelTestPreset {
  const ModelTestPreset({
    required this.id,
    required this.name,
    required this.prompt,
  });

  static const numbersId = 'builtin-numbers';
  static const shortId = 'builtin-short';
  static const builtins = [
    ModelTestPreset(id: numbersId, name: '', prompt: modelTestPrompt),
    ModelTestPreset(id: shortId, name: '', prompt: 'Reply with exactly: OK'),
  ];
  final String id;
  final String name;
  final String prompt;
  bool get builtin => id == numbersId || id == shortId;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'prompt': prompt};

  static ModelTestPreset? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final prompt = json['prompt'];
    if (id is! String ||
        id.isEmpty ||
        id == numbersId ||
        id == shortId ||
        name is! String ||
        name.trim().isEmpty ||
        prompt is! String ||
        prompt.trim().isEmpty) {
      return null;
    }
    return ModelTestPreset(id: id, name: name.trim(), prompt: prompt.trim());
  }
}
