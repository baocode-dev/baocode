import 'dart:convert';

import '../kernel/claude_code/claude_path_setting.dart';
import '../models/model_provider.dart';
import '../models/model_providers.dart';
import 'jsonc.dart';
import 'jsonc_file.dart';
import 'user_settings.dart';

/// The user's settings carried to another computer (#911), as one file:
/// settings.json (the upstreams and their models among them),
/// keybindings.json and, where the user says so, the upstreams' keys
/// (otherwise in the system's keychain, not in any file).
abstract final class SettingsTransfer {
  /// What the file says it is, and the shape it has.
  static const kind = 'baocode-settings';
  static const version = 1;

  /// The name a file is offered under.
  static const fileName = 'baocode-settings.json';

  /// Settings of this computer's alone: not carried.
  static const machineKeys = {ClaudePathSetting.settingKey};

  /// The file's text: [settings]' values, [keybindings]' entries and, with
  /// [keys], each upstream's key that [providers] has.
  static Future<String> export({
    required UserSettings settings,
    required JsoncFile keybindings,
    required ModelProviders providers,
    required bool keys,
    DateTime? now,
  }) async {
    final bindings = parseJsonc(await keybindings.readText() ?? '');
    return const JsonEncoder.withIndent('  ').convert({
      'kind': kind,
      'version': version,
      'exportedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'settings': {
        for (final MapEntry(:key, :value) in settings.values.entries)
          if (!machineKeys.contains(key)) key: value,
      },
      if (bindings is List && bindings.isNotEmpty) 'keybindings': bindings,
      if (keys)
        'keys': {
          for (final provider in providers.providers)
            if (await providers.key(provider.id) case final key?
                when key.isNotEmpty)
              provider.id: key,
        },
    });
  }

  /// [text] as a file made by [export]; null when it is not one.
  static SettingsFile? parse(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, Object?> ||
        json['kind'] != kind ||
        json['settings'] is! Map) {
      return null;
    }
    return SettingsFile(
      settings: {
        for (final MapEntry(:key, :value) in (json['settings']! as Map).entries)
          if (key is String && !machineKeys.contains(key)) key: value,
      },
      keybindings: switch (json['keybindings']) {
        final List list => list,
        _ => null,
      },
      keys: {
        for (final MapEntry(:key, :value) in switch (json['keys']) {
          final Map keys => keys,
          _ => const {},
        }.entries)
          if (key is String && value is String && value.isNotEmpty) key: value,
      },
    );
  }

  /// Takes [file] up: its settings over these (those it has not left as
  /// they are), its keybindings in place of these, its keys kept for the
  /// upstreams it has.
  static Future<void> import(
    SettingsFile file, {
    required UserSettings settings,
    required JsoncFile keybindings,
    required ModelProviders providers,
  }) async {
    for (final MapEntry(:key, :value) in file.settings.entries) {
      await settings.update(key, value);
    }
    if (file.keybindings case final bindings?) {
      await keybindings.writeText(
        '${const JsonEncoder.withIndent('\t').convert(bindings)}\n',
      );
    }
    final ids = {
      for (final provider in file.upstreams) provider.id,
      for (final provider in providers.providers) provider.id,
    };
    for (final MapEntry(key: id, value: key) in file.keys.entries) {
      if (ids.contains(id)) await providers.setKey(id, key);
    }
  }
}

/// A file of [SettingsTransfer]'s, read.
class SettingsFile {
  const SettingsFile({
    required this.settings,
    this.keybindings,
    this.keys = const {},
  });

  final Map<String, Object?> settings;
  final List<Object?>? keybindings;

  /// Upstream keys by upstream id.
  final Map<String, String> keys;

  /// The upstreams it has.
  List<ModelProvider> get upstreams => [
    for (final json in switch (settings[ModelProviders.providersKey]) {
      final List list => list,
      _ => const [],
    })
      ?ModelProvider.fromJson(json),
  ];
}
