/// magpie (usemagpie.ai, github.com/yetone/magpie): an app that serves
/// every model the user has in it (API keys, subscriptions, routing groups
/// that fail over between them) at one local gateway, Anthropic's Messages
/// API among the ones it speaks. An upstream that follows it takes its
/// address and its models as magpie has them; BaoCode never writes
/// magpie's files (docs/integrating.md in its repository).
library;

import 'model_provider.dart';
import 'upstream.dart';

abstract final class Magpie {
  /// [ModelProvider.follows] of an upstream that follows it.
  static const follow = 'magpie';

  /// Its name, as the upstream is first named.
  static const name = 'magpie';

  /// Where the gateway listens unless its settings.json names a `port`.
  static const defaultPort = 3425;

  /// The key BaoCode's calls go with: on this machine the gateway takes
  /// any, and counts the calls of `magpie-<app>` under that app.
  static const key = 'magpie-baocode';

  static String baseUrl(int port) => 'http://127.0.0.1:$port';

  /// Its list of conversation and image models (the bare list holds the
  /// conversation models alone).
  static String modelsUrl(int port) =>
      '${baseUrl(port)}/v1/models?kind=chat,image';

  /// The port magpie's settings.json ([settings], decoded) names, else
  /// [defaultPort].
  static int portOf(Object? settings) => switch (settings) {
    {'port': final int port} when port > 0 && port < 65536 => port,
    _ => defaultPort,
  };

  /// magpie's version, as `GET /api/hello` answers ([json], decoded); null
  /// when what answered is not magpie.
  static String? versionOf(Object? json) => switch (json) {
    {'name': 'magpie', 'version': final String version} => version,
    {'name': 'magpie'} => '',
    _ => null,
  };

  /// A new upstream [id] following the gateway at [port].
  static ModelProvider provider(String id, {int port = defaultPort}) =>
      ModelProvider(
        id: id,
        name: name,
        baseUrl: baseUrl(port),
        modelsUrl: modelsUrl(port),
        auth: ProviderAuth.bearer,
        disableNonessentialTraffic: true,
        follows: follow,
      );

  /// [provider] at the gateway at [port]: itself when it is there already.
  static ModelProvider at(ModelProvider provider, int port) =>
      provider.baseUrl == baseUrl(port) && provider.modelsUrl == modelsUrl(port)
      ? provider
      : provider.copyWith(
          baseUrl: baseUrl(port),
          modelsUrl: () => modelsUrl(port),
        );

  /// Whether [id] is a routing group's: one magpie found (`auto/<model>`,
  /// a model several providers serve) or the user made (`group/<id>`).
  static bool isGroup(String id) =>
      id.startsWith('auto/') || id.startsWith('group/');

  /// The models Claude Code is set to, by [ProviderRoles] role, when magpie
  /// set it up: its settings.json ([settings], decoded) sending it to the
  /// gateway at [port]. As written there; see [match].
  static Map<String, String> claudePicks(Object? settings, int port) {
    if (settings is! Map) return const {};
    final env = switch (settings['env']) {
      final Map env => env,
      _ => const {},
    };
    final base = Uri.tryParse('${env['ANTHROPIC_BASE_URL'] ?? ''}');
    if (base == null || !_loopback.contains(base.host) || base.port != port) {
      return const {};
    }
    String? read(Object? value) =>
        value is String && value.trim().isNotEmpty ? value.trim() : null;
    return {
      'main': ?(read(settings['model']) ?? read(env['ANTHROPIC_MODEL'])),
      'opus': ?read(env['ANTHROPIC_DEFAULT_OPUS_MODEL']),
      'sonnet': ?read(env['ANTHROPIC_DEFAULT_SONNET_MODEL']),
      'haiku':
          ?(read(env['ANTHROPIC_DEFAULT_HAIKU_MODEL']) ??
          read(env['ANTHROPIC_SMALL_FAST_MODEL'])),
      'subagent': ?read(env['CLAUDE_CODE_SUBAGENT_MODEL']),
    };
  }

  static const _loopback = {'127.0.0.1', 'localhost', '::1', '[::1]'};

  /// The efforts magpie may fix on a model it gives Claude Code
  /// (`deepseek/deepseek-v4-pro:high`).
  static const _efforts = {
    'none',
    'minimal',
    'low',
    'medium',
    'high',
    'xhigh',
    'max',
  };

  /// The one of [ids] Claude Code's model [pick] is: its effort and its
  /// `[1m]` mark aside, as written, else the one alone that is it with
  /// the dots of its version dashes (magpie gives Claude Code
  /// `claude-opus-4-6` for `claude-opus-4.6`).
  static String? match(String pick, Iterable<String> ids) {
    var id = pick.trim();
    if (id.endsWith('[1m]')) id = id.substring(0, id.length - 4);
    final colon = id.lastIndexOf(':');
    if (colon > 0 && _efforts.contains(id.substring(colon + 1).toLowerCase())) {
      id = id.substring(0, colon);
    }
    final list = ids.toList();
    if (list.contains(id)) return id;
    String dashed(String text) => text.replaceAll('.', '-');
    final alike = [
      for (final candidate in list)
        if (dashed(candidate) == dashed(id)) candidate,
    ];
    return alike.length == 1 ? alike.single : null;
  }

  /// [provider] with magpie's [listed] models: those it had taking what
  /// magpie says of them, those gone marked, new ones added, on when they
  /// are routing groups, image models or Claude Code's ([picks],
  /// [claudePicks]). As it is first listed, with none of those, every
  /// conversation model is on; its roles, unset, are Claude Code's.
  static ModelProvider synced(
    ModelProvider provider,
    List<RemoteModel> listed,
    Map<String, String> picks,
  ) {
    final ids = [for (final model in listed) model.id];
    final picked = {
      for (final MapEntry(key: role, value: pick) in picks.entries)
        role: ?match(pick, ids),
    };
    bool image(RemoteModel model) =>
        (model.kind ?? guessModelKind(model.id)).generatesImages;
    final chat = {
      for (final model in listed)
        if (!image(model)) model.id,
    };
    final wanted = {
      for (final id in chat)
        if (isGroup(id)) id,
      ...picked.values.where(chat.contains),
    };
    final images = {
      for (final model in listed)
        if (image(model)) model.id,
    };
    final first = provider.models.isEmpty;
    final known = {for (final model in provider.models) model.id};
    final enable = first
        ? {...(wanted.isEmpty ? chat : wanted), ...images}
        : {...wanted, ...images}.difference(known);
    var roles = provider.roles;
    if (first && roles == const ProviderRoles()) {
      for (final MapEntry(key: role, value: id) in picked.entries) {
        if (chat.contains(id)) roles = roles.copyWith(role, id);
      }
    }
    return provider.copyWith(
      models: mergeModelList(
        provider.models,
        listed,
        enable: enable,
        follow: true,
      ),
      roles: roles,
    );
  }
}

/// What was found of magpie on this machine.
class MagpieStatus {
  const MagpieStatus({
    this.installed = false,
    this.port = Magpie.defaultPort,
    this.version,
  });

  /// Its settings are here, or its gateway answers.
  final bool installed;

  /// Where its gateway listens.
  final int port;

  /// Its version, as its gateway answers; null while it does not.
  final String? version;

  /// Whether its gateway answers.
  bool get running => version != null;
}
