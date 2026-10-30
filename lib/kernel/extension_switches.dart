import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Skills, MCP servers and MCP tools the user switched off in Settings →
/// Customize: the `claudeCode.disabledSkills`, `claudeCode.disabledMcpServers`
/// and `claudeCode.disabledMcpTools` settings. All on while unset. Given the
/// agent as flag settings (permission rules and `skillOverrides`), at start
/// and again as they change, so a running session follows at once.
@immutable
class ExtensionSwitches {
  const ExtensionSwitches({
    this.disabledSkills = const {},
    this.disabledServers = const {},
    this.disabledTools = const {},
  });

  static const skillsKey = 'claudeCode.disabledSkills';
  static const serversKey = 'claudeCode.disabledMcpServers';
  static const toolsKey = 'claudeCode.disabledMcpTools';

  static const none = ExtensionSwitches();

  /// Skills by name: the user's, a project's, those synced from claude.ai
  /// (not a plugin's, which Claude Code keeps on).
  final Set<String> disabledSkills;

  /// MCP servers by name, as configured.
  final Set<String> disabledServers;

  /// MCP tools by server, then by the tool's own name.
  final Map<String, Set<String>> disabledTools;

  /// As [settings] (`User/settings.json`'s values) have them.
  factory ExtensionSwitches.parse(Map<String, Object?> settings) {
    Set<String> names(Object? value) => switch (value) {
      final List<Object?> list => {
        for (final name in list)
          if (name is String && name.isNotEmpty) name,
      },
      _ => const {},
    };
    return ExtensionSwitches(
      disabledSkills: names(settings[skillsKey]),
      disabledServers: names(settings[serversKey]),
      disabledTools: switch (settings[toolsKey]) {
        final Map<Object?, Object?> map => {
          for (final MapEntry(:key, :value) in map.entries)
            if (key is String && names(value).isNotEmpty) key: names(value),
        },
        _ => const {},
      },
    );
  }

  bool skillEnabled(String name) => !disabledSkills.contains(name);

  bool serverEnabled(String server) => !disabledServers.contains(server);

  bool toolEnabled(String server, String tool) =>
      !(disabledTools[server]?.contains(tool) ?? false);

  ExtensionSwitches withSkills(Iterable<String> names, bool enabled) =>
      _copy(disabledSkills: _toggled(disabledSkills, names, enabled));

  ExtensionSwitches withServer(String server, bool enabled) =>
      _copy(disabledServers: _toggled(disabledServers, [server], enabled));

  ExtensionSwitches withTool(String server, String tool, bool enabled) {
    final tools = _toggled(disabledTools[server] ?? const {}, [tool], enabled);
    return _copy(
      disabledTools: {
        for (final MapEntry(:key, :value) in disabledTools.entries)
          if (key != server) key: value,
        if (tools.isNotEmpty) server: tools,
      },
    );
  }

  static Set<String> _toggled(
    Set<String> off,
    Iterable<String> names,
    bool enabled,
  ) => enabled ? off.difference(names.toSet()) : {...off, ...names};

  ExtensionSwitches _copy({
    Set<String>? disabledSkills,
    Set<String>? disabledServers,
    Map<String, Set<String>>? disabledTools,
  }) => ExtensionSwitches(
    disabledSkills: disabledSkills ?? this.disabledSkills,
    disabledServers: disabledServers ?? this.disabledServers,
    disabledTools: disabledTools ?? this.disabledTools,
  );

  /// The settings as they are written, by key; null for one left out
  /// (nothing off).
  Map<String, Object?> toSettings() => {
    skillsKey: disabledSkills.isEmpty ? null : _sorted(disabledSkills),
    serversKey: disabledServers.isEmpty ? null : _sorted(disabledServers),
    toolsKey: disabledTools.isEmpty
        ? null
        : {
            for (final server in _sorted(disabledTools.keys))
              server: _sorted(disabledTools[server]!),
          },
  };

  static List<String> _sorted(Iterable<String> names) => [...names]..sort();

  /// The name Claude Code gives an MCP server or tool in a tool's name:
  /// anything but letters, digits, `_` and `-` as `_`.
  static String normalize(String name) =>
      name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  /// The permission rules that turn them off: a server's tools all
  /// (`mcp__server`), a tool (`mcp__server__tool`).
  List<String> get denyRules => [
    for (final server in _sorted(disabledServers)) 'mcp__${normalize(server)}',
    for (final server in _sorted(disabledTools.keys))
      if (serverEnabled(server))
        for (final tool in _sorted(disabledTools[server]!))
          'mcp__${normalize(server)}__${normalize(tool)}',
  ];

  /// `skillOverrides`: each skill off, from the model and from `/name`.
  Map<String, String> get skillOverrides => {
    for (final skill in _sorted(disabledSkills)) skill: 'off',
  };

  @override
  bool operator ==(Object other) =>
      other is ExtensionSwitches &&
      jsonEncode(other.toSettings()) == jsonEncode(toSettings());

  @override
  int get hashCode => jsonEncode(toSettings()).hashCode;

  /// The settings as they are now, what tells they changed, and what
  /// writes them; main() points them at settings.json.
  static ExtensionSwitches Function() current = () => none;
  static Listenable? changes;
  static Future<void> Function(ExtensionSwitches switches)? save;
}
