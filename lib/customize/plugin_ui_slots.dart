import 'dart:convert';

import 'package:path/path.dart' as p;

import 'customization_store.dart';
import 'customizations.dart';
import 'plugin_slot_http_stub.dart'
    if (dart.library.io) 'plugin_slot_http_io.dart'
    as slot_http;

enum PluginSlotKind { toggle, button }

/// Declarative action (`writeFile` under `~/.claude` or loopback `http`).
class PluginSlotAction {
  const PluginSlotAction.writeFile(this.file, this.content)
    : url = null,
      method = 'POST',
      headers = const {},
      body = null;
  const PluginSlotAction.http(
    this.url, {
    this.method = 'POST',
    this.headers = const {},
    this.body,
  }) : file = null,
       content = null;
  final String? file, content, body;
  final Uri? url;
  final String method;
  final Map<String, String> headers;

  static PluginSlotAction? parse(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    if (raw['type'] == 'writeFile') {
      final (f, c) = (raw['file'], raw['content']);
      return f is String && f.isNotEmpty && c is String
          ? PluginSlotAction.writeFile(f, c)
          : null;
    }
    if (raw['type'] != 'http') return null;
    final url = raw['url'] is String
        ? Uri.tryParse(raw['url']! as String)
        : null;
    if (url == null || !isLoopbackHttpUri(url)) return null;
    final m = raw['method'];
    return PluginSlotAction.http(
      url,
      method: m is String && m.isNotEmpty ? m.toUpperCase() : 'POST',
      headers: {
        if (raw['headers'] case final Map<String, Object?> h)
          for (final MapEntry(:key, :value) in h.entries)
            if (value is String) key: value,
      },
      body: raw['body'] is String ? raw['body']! as String : null,
    );
  }
}

/// Declarative `abovePrompt` control declared in `plugin.json` (`ui.slots`).
class PluginUiSlot {
  const PluginUiSlot(
    this.pluginName,
    this.kind,
    this.onLabel,
    this.offLabel, {
    this.stateFile,
    this.stateKey,
    this.stateDefault = false,
    this.onAction,
    this.offAction,
    this.action,
  });
  final String pluginName, onLabel, offLabel;
  final PluginSlotKind kind;
  final String? stateFile, stateKey;
  final bool stateDefault;
  final PluginSlotAction? onAction, offAction, action;
  String labelFor({required bool on}) => on ? onLabel : offLabel;

  static List<PluginUiSlot> parseAbovePrompt(
    String plugin,
    Map<String, Object?> manifest,
  ) {
    final ui = manifest['ui'];
    final raw = ui is Map<String, Object?> ? ui['slots'] : null;
    if (raw is! List<Object?>) return const [];
    final out = <PluginUiSlot>[];
    for (final e in raw.whereType<Map<String, Object?>>()) {
      if (e['slot'] != 'abovePrompt') continue;
      if (e['type'] == 'toggle') {
        final (onL, offL) = switch (e['label']) {
          final String s when s.trim().isNotEmpty => (s.trim(), s.trim()),
          {'on': final String a, 'off': final String b}
              when a.trim().isNotEmpty && b.trim().isNotEmpty =>
            (a.trim(), b.trim()),
          _ => (null, null),
        };
        final onAct = PluginSlotAction.parse(e['on']);
        final offAct = PluginSlotAction.parse(e['off']);
        if (onL == null || offL == null || (onAct ?? offAct) == null) continue;
        final st = e['state'] is Map<String, Object?>
            ? e['state']! as Map<String, Object?>
            : null;
        final (f, k, d) = (st?['file'], st?['key'], st?['default']);
        out.add(
          PluginUiSlot(
            plugin,
            PluginSlotKind.toggle,
            onL,
            offL,
            stateFile: f is String && f.isNotEmpty ? f : null,
            stateKey: k is String && k.isNotEmpty ? k : null,
            stateDefault: d is bool ? d : false,
            onAction: onAct,
            offAction: offAct,
          ),
        );
      } else if (e['type'] == 'button') {
        final (l, act) = (e['label'], PluginSlotAction.parse(e['action']));
        if (l is! String || l.trim().isEmpty || act == null) continue;
        final t = l.trim();
        out.add(PluginUiSlot(plugin, PluginSlotKind.button, t, t, action: act));
      }
    }
    return out;
  }
}

bool isLoopbackHttpUri(Uri uri) =>
    (uri.scheme == 'http' || uri.scheme == 'https') &&
    const {'localhost', '127.0.0.1', '::1'}.contains(uri.host.toLowerCase());

/// Resolves [raw] strictly within [configDir], or null if it escapes.
String? resolvePluginConfigPath(
  String raw, {
  required String configDir,
  required String? homeDir,
  required p.Context paths,
}) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  final home = t == '~' || t.startsWith('~/') || t.startsWith(r'~\');
  if (home && (homeDir == null || homeDir.isEmpty)) return null;
  final exp = home
      ? (t.length <= 2 ? homeDir! : paths.join(homeDir!, t.substring(2)))
      : (paths.isAbsolute(t) ? t : paths.join(configDir, t));
  final target = paths.normalize(paths.absolute(exp));
  return paths.isWithin(paths.normalize(paths.absolute(configDir)), target)
      ? target
      : null;
}

typedef PluginHttpSender = Future<void> Function(
  Uri url, {
  String method,
  Map<String, String> headers,
  String? body,
});

class PluginUiSlotRunner {
  PluginUiSlotRunner({CustomizationStore? store, PluginHttpSender? sendHttp})
    : _store = store ?? CustomizationStore(),
      _sendHttp = sendHttp ?? slot_http.sendPluginSlotHttp;
  final CustomizationStore _store;
  final PluginHttpSender _sendHttp;

  Future<List<PluginUiSlot>> loadAbovePrompt({String? project}) async {
    if (!_store.supported) return const [];
    final slots = <PluginUiSlot>[];
    final list = await _store.list(CustomizationKind.plugins, project: project);
    for (final p in list) {
      if (p.enabled != true || !p.path.endsWith('plugin.json')) continue;
      try {
        final json = jsonDecode(await _store.read(p.path));
        if (json is Map<String, Object?>) {
          slots.addAll(PluginUiSlot.parseAbovePrompt(p.name, json));
        }
      } on Object {
        // Ignore unreadable manifests.
      }
    }
    return slots;
  }

  Future<bool> readToggleState(PluginUiSlot s) async {
    final (file, key) = (s.stateFile, s.stateKey);
    if (file == null || key == null || !_store.supported) return s.stateDefault;
    final path = await _resolve(file);
    if (path == null) return s.stateDefault;
    try {
      final json = jsonDecode(await _store.read(path));
      if (json is Map<String, Object?> && json[key] is bool) {
        return json[key]! as bool;
      }
    } on Object {
      // Missing or unreadable state file falls back to stateDefault.
    }
    return s.stateDefault;
  }

  Future<void> runAction(PluginSlotAction act) async {
    if (act.file case final file?) {
      if (!_store.supported) return;
      final path = await _resolve(file);
      if (path == null) throw ArgumentError.value(file, 'file');
      await _store.write(path, act.content ?? '');
    } else if (act.url case final url?) {
      if (!isLoopbackHttpUri(url)) throw ArgumentError.value(url, 'url');
      await _sendHttp(
        url,
        method: act.method,
        headers: act.headers,
        body: act.body,
      );
    }
  }

  Future<String?> _resolve(String raw) async => resolvePluginConfigPath(
    raw,
    configDir: await _store.config(),
    homeDir: await _store.home(),
    paths: _store.paths,
  );
}
