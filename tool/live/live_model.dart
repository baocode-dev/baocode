// What the live tests run on: OpenCode's gateway, as the user set it up
// in BaoCode (Settings → Models, its key in the keychain), not Claude's
// own models.
import 'dart:convert';
import 'dart:io';

import 'package:baocode/bots/bots.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/secret_store_io.dart';
import 'package:baocode/models/upstream.dart';

/// Points the app at the user's OpenCode provider: its main model, as a
/// [modelRef], for the bots to run on ([onModel]).
Future<String> useOpenCode() async {
  final home = Platform.environment['HOME']!;
  final file = File(
    '$home/Library/Application Support/baocode/User/settings.json',
  );
  final text = (await file.readAsString()).replaceAll(
    RegExp(r'^\s*//.*$', multiLine: true),
    '',
  );
  final settings = jsonDecode(text) as Map<String, Object?>;
  final provider = [
    for (final json in settings[ModelProviders.providersKey] as List)
      ?ModelProvider.fromJson(json),
  ].firstWhere(isOpenCode);
  ModelProviders.current = ModelProviders.memory(
    providers: [provider],
    secrets: KeychainSecretStore(),
  );
  final model = provider.roles.main ?? provider.models.first.id;
  stdout.writeln('model: ${provider.name} $model');
  return modelRef(provider.id, model);
}

/// Every bot of [bots] on [model], those made later too.
void onModel(Bots bots, String model) {
  void all() {
    for (final bot in bots.bots) {
      if (bot.model != model) bots.setModel(bot, model);
    }
  }

  bots.addListener(all);
  all();
}
