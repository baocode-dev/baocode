/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Tasks: what a task runs (a shell command line, a process or an
// extension's custom execution), how its terminal shows, its group, its
// dependencies and problem matchers, where it came from (tasks.json or an
// extension), and the events of its runs; the task types extensions
// declare (`contributes.taskDefinitions`).
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/tasks/common/tasks.ts and
// taskDefinitionRegistry.ts.
//
// Deviations: `CustomTask`, `ContributedTask` and `ConfiguringTask` are
// one [Task] of a [TaskKind]; user and workspace-file tasks are not read,
// so a task's folder is the workspace's.

import 'dart:convert';

import 'package:bao_exthost/bao_exthost.dart';

import '../host/init_data.dart';
import 'problem_matcher.dart';

/// `ShellQuoting` (the wire's values).
enum ShellQuoting {
  escape(1),
  strong(2),
  weak(3);

  const ShellQuoting(this.wire);
  final int wire;

  static ShellQuoting from(Object? value) => switch (value) {
    1 || 'escape' => escape,
    3 || 'weak' => weak,
    _ => strong,
  };
}

/// `CommandString`: a string, or one quoted as [quoting] says.
final class QuotedString {
  const QuotedString(this.value, this.quoting);

  final String value;
  final ShellQuoting quoting;

  Map<String, Object?> toJson() => {'value': value, 'quoting': quoting.wire};
}

/// `CommandString.value`.
String commandStringValue(Object? value) => switch (value) {
  final QuotedString quoted => quoted.value,
  final String string => string,
  _ => '',
};

/// A command string from the wire or tasks.json (`ShellString.from`).
Object? commandStringFrom(Object? value) {
  if (value is String) return value;
  if (value is List && value.every((e) => e is String)) return value.join(' ');
  if (value is Map) {
    final inner = value['value'];
    final text = inner is String
        ? inner
        : inner is List && inner.every((e) => e is String)
        ? inner.join(' ')
        : null;
    if (text == null || text.isEmpty) return null;
    return QuotedString(text, ShellQuoting.from(value['quoting']));
  }
  return null;
}

Object? _commandStringToJson(Object? value) =>
    value is QuotedString ? value.toJson() : value;

/// `IShellQuotingOptions`.
final class ShellQuotingOptions {
  const ShellQuotingOptions({
    this.escapeChar,
    this.charsToEscape,
    this.strong,
    this.weak,
  });

  static ShellQuotingOptions? fromJson(Object? json) {
    if (json is! Map) return null;
    final escape = json['escape'];
    return ShellQuotingOptions(
      escapeChar: escape is String
          ? escape
          : escape is Map
          ? escape['escapeChar'] as String?
          : null,
      charsToEscape: escape is Map ? escape['charsToEscape'] as String? : null,
      strong: json['strong'] as String?,
      weak: json['weak'] as String?,
    );
  }

  /// The escape character; with [charsToEscape], only those are escaped,
  /// else spaces.
  final String? escapeChar;
  final String? charsToEscape;
  final String? strong;
  final String? weak;

  Map<String, Object?> toJson() => {
    if (escapeChar != null)
      'escape': charsToEscape == null
          ? escapeChar
          : {'escapeChar': escapeChar, 'charsToEscape': charsToEscape},
    'strong': ?strong,
    'weak': ?weak,
  };
}

/// `IShellConfiguration`.
final class ShellConfiguration {
  ShellConfiguration({this.executable, this.args, this.quoting});

  String? executable;
  List<String>? args;
  ShellQuotingOptions? quoting;

  ShellConfiguration copy() => ShellConfiguration(
    executable: executable,
    args: args == null ? null : [...args!],
    quoting: quoting,
  );
}

/// `CommandOptions`.
final class CommandOptions {
  CommandOptions({this.cwd, this.env, this.shell});

  String? cwd;
  Map<String, String>? env;
  ShellConfiguration? shell;

  bool get isEmpty => cwd == null && env == null && shell == null;

  CommandOptions copy() => CommandOptions(
    cwd: cwd,
    env: env == null ? null : {...env!},
    shell: shell?.copy(),
  );

  /// `CommandOptions.assignProperties`: [source]'s over this one's.
  static CommandOptions? assign(
    CommandOptions? target,
    CommandOptions? source,
  ) {
    if (source == null || source.isEmpty) return target;
    if (target == null || target.isEmpty) return source;
    if (source.cwd != null) target.cwd = source.cwd;
    if (target.env == null) {
      target.env = source.env;
    } else if (source.env != null) {
      target.env = {...target.env!, ...source.env!};
    }
    if (source.shell != null) {
      final shell = target.shell ??= ShellConfiguration();
      if (source.shell!.executable != null) {
        shell.executable = source.shell!.executable;
      }
      if (source.shell!.args != null) shell.args = source.shell!.args;
      if (source.shell!.quoting != null) shell.quoting = source.shell!.quoting;
    }
    return target;
  }

  /// `CommandOptions.fillProperties`: this one's, else [source]'s.
  static CommandOptions? fill(CommandOptions? target, CommandOptions? source) {
    if (source == null || source.isEmpty) return target;
    if (target == null) return source.copy();
    target.cwd ??= source.cwd;
    target.env ??= source.env;
    target.shell ??= source.shell?.copy();
    return target;
  }
}

/// `RuntimeType` (the wire's values).
enum RuntimeType {
  shell(1),
  process(2),
  customExecution(3);

  const RuntimeType(this.wire);
  final int wire;
}

/// `RevealKind`.
enum RevealKind {
  always(1),
  silent(2),
  never(3);

  const RevealKind(this.wire);
  final int wire;

  static RevealKind? from(Object? value) => switch (value) {
    1 || 'always' => always,
    2 || 'silent' => silent,
    3 || 'never' => never,
    final String s => switch (s.toLowerCase()) {
      'silent' => silent,
      'never' => never,
      _ => always,
    },
    _ => null,
  };
}

/// `RevealProblemKind`.
enum RevealProblemKind {
  never(1),
  onProblem(2),
  always(3);

  const RevealProblemKind(this.wire);
  final int wire;

  static RevealProblemKind? from(Object? value) => switch (value) {
    1 => never,
    2 => onProblem,
    3 => always,
    final String s => switch (s.toLowerCase()) {
      'always' => always,
      'onproblem' => onProblem,
      _ => never,
    },
    _ => null,
  };
}

/// `PanelKind`.
enum PanelKind {
  shared(1),
  dedicated(2),
  newPanel(3);

  const PanelKind(this.wire);
  final int wire;

  static PanelKind? from(Object? value) => switch (value) {
    1 => shared,
    2 => dedicated,
    3 => newPanel,
    final String s => switch (s.toLowerCase()) {
      'dedicated' => dedicated,
      'new' => newPanel,
      _ => shared,
    },
    _ => null,
  };
}

/// `IPresentationOptions`; null fields are not set.
final class PresentationOptions {
  PresentationOptions({
    this.echo,
    this.reveal,
    this.revealProblems,
    this.focus,
    this.panel,
    this.showReuseMessage,
    this.clear,
    this.group,
    this.close,
    this.preserveTerminalName,
  });

  /// `PresentationOptions.defaults`.
  factory PresentationOptions.defaults() => PresentationOptions(
    echo: true,
    reveal: RevealKind.always,
    revealProblems: RevealProblemKind.never,
    focus: false,
    panel: PanelKind.shared,
    showReuseMessage: true,
    clear: false,
    preserveTerminalName: false,
  );

  /// From tasks.json's `presentation` (or the legacy `terminal`,
  /// `echoCommand` and `showOutput`); null when none is there.
  static PresentationOptions? fromConfig(Map config) {
    var hasProps = false;
    final result = PresentationOptions();
    if (config['echoCommand'] is bool) {
      result.echo = config['echoCommand'] as bool;
      hasProps = true;
    }
    if (config['showOutput'] is String) {
      result.reveal = RevealKind.from(config['showOutput']);
      hasProps = true;
    }
    final presentation = config['presentation'] ?? config['terminal'];
    if (presentation is Map) {
      result
        ..echo = presentation['echo'] is bool
            ? presentation['echo'] as bool
            : result.echo
        ..reveal = presentation['reveal'] is String
            ? RevealKind.from(presentation['reveal'])
            : result.reveal
        ..revealProblems = presentation['revealProblems'] is String
            ? RevealProblemKind.from(presentation['revealProblems'])
            : null
        ..focus = presentation['focus'] as bool?
        ..panel = presentation['panel'] is String
            ? PanelKind.from(presentation['panel'])
            : null
        ..showReuseMessage = presentation['showReuseMessage'] as bool?
        ..clear = presentation['clear'] as bool?
        ..group = presentation['group'] as String?
        ..close = presentation['close'] as bool?
        ..preserveTerminalName = presentation['preserveTerminalName'] as bool?;
      hasProps = true;
    }
    return hasProps ? result : null;
  }

  /// From the wire (`ITaskPresentationOptionsDTO`), over the defaults.
  factory PresentationOptions.fromDto(Object? dto) {
    final result = PresentationOptions.defaults();
    if (dto is! Map) return result;
    return result
      ..echo = dto['echo'] as bool? ?? result.echo
      ..reveal = RevealKind.from(dto['reveal']) ?? result.reveal
      ..revealProblems =
          RevealProblemKind.from(dto['revealProblems']) ?? result.revealProblems
      ..focus = dto['focus'] as bool? ?? result.focus
      ..panel = PanelKind.from(dto['panel']) ?? result.panel
      ..showReuseMessage =
          dto['showReuseMessage'] as bool? ?? result.showReuseMessage
      ..clear = dto['clear'] as bool? ?? result.clear
      ..group = dto['group'] as String?
      ..close = dto['close'] as bool?;
  }

  bool? echo;
  RevealKind? reveal;
  RevealProblemKind? revealProblems;
  bool? focus;
  PanelKind? panel;
  bool? showReuseMessage;
  bool? clear;
  String? group;
  bool? close;
  bool? preserveTerminalName;

  PresentationOptions copy() => PresentationOptions(
    echo: echo,
    reveal: reveal,
    revealProblems: revealProblems,
    focus: focus,
    panel: panel,
    showReuseMessage: showReuseMessage,
    clear: clear,
    group: group,
    close: close,
    preserveTerminalName: preserveTerminalName,
  );

  /// `assignProperties`: [source]'s set ones over these.
  static PresentationOptions? assign(
    PresentationOptions? target,
    PresentationOptions? source,
  ) {
    if (source == null) return target;
    if (target == null) return source.copy();
    return target
      ..echo = source.echo ?? target.echo
      ..reveal = source.reveal ?? target.reveal
      ..revealProblems = source.revealProblems ?? target.revealProblems
      ..focus = source.focus ?? target.focus
      ..panel = source.panel ?? target.panel
      ..showReuseMessage = source.showReuseMessage ?? target.showReuseMessage
      ..clear = source.clear ?? target.clear
      ..group = source.group ?? target.group
      ..close = source.close ?? target.close
      ..preserveTerminalName =
          source.preserveTerminalName ?? target.preserveTerminalName;
  }

  /// `fillProperties`: these, else [source]'s.
  static PresentationOptions? fill(
    PresentationOptions? target,
    PresentationOptions? source,
  ) {
    if (source == null) return target;
    if (target == null) return source.copy();
    return target
      ..echo ??= source.echo
      ..reveal ??= source.reveal
      ..revealProblems ??= source.revealProblems
      ..focus ??= source.focus
      ..panel ??= source.panel
      ..showReuseMessage ??= source.showReuseMessage
      ..clear ??= source.clear
      ..group ??= source.group
      ..close ??= source.close
      ..preserveTerminalName ??= source.preserveTerminalName;
  }

  /// `fillDefaults`: unset ones as the defaults are; [echo] as the
  /// terminal engine's.
  PresentationOptions withDefaults() =>
      fill(this, PresentationOptions.defaults())!;

  /// `ITaskPresentationOptionsDTO`.
  Map<String, Object?> toDto() => {
    'echo': ?echo,
    'reveal': ?reveal?.wire,
    'revealProblems': ?revealProblems?.wire,
    'focus': ?focus,
    'panel': ?panel?.wire,
    'showReuseMessage': ?showReuseMessage,
    'clear': ?clear,
    'group': ?group,
    'close': ?close,
  };
}

/// `ICommandConfiguration`.
final class CommandConfiguration {
  CommandConfiguration({
    this.runtime,
    this.name,
    this.args,
    this.options,
    this.presentation,
    this.suppressTaskName,
    this.taskSelector,
  });

  RuntimeType? runtime;

  /// A `String` or a [QuotedString].
  Object? name;

  /// Each a `String` or a [QuotedString].
  List<Object>? args;
  CommandOptions? options;
  PresentationOptions? presentation;
  bool? suppressTaskName;
  String? taskSelector;

  bool get isEmpty =>
      runtime == null &&
      name == null &&
      args == null &&
      (options == null || options!.isEmpty) &&
      presentation == null &&
      suppressTaskName == null &&
      taskSelector == null;

  CommandConfiguration copy() => CommandConfiguration(
    runtime: runtime,
    name: name,
    args: args == null ? null : [...args!],
    options: options?.copy(),
    presentation: presentation?.copy(),
    suppressTaskName: suppressTaskName,
    taskSelector: taskSelector,
  );
}

/// `TaskGroup`.
final class TaskGroup {
  const TaskGroup(this.id, {this.isDefault = false});

  static const build = TaskGroup('build');
  static const test = TaskGroup('test');
  static const known = {'clean', 'build', 'rebuild', 'test'};

  final String id;

  /// `true`, `false` or a glob of the files it is the default for.
  final Object isDefault;

  bool get isDefaultTask => isDefault == true || isDefault is String;

  /// `GroupKind.from`.
  static TaskGroup? from(Object? external) {
    if (external is String) {
      return known.contains(external) ? TaskGroup(external) : null;
    }
    if (external is Map && external['kind'] is String) {
      final kind = external['kind'] as String;
      if (!known.contains(kind)) return null;
      final isDefault = external['isDefault'];
      return TaskGroup(
        kind,
        isDefault: isDefault is bool || isDefault is String
            ? isDefault!
            : false,
      );
    }
    return null;
  }

  /// `ITaskGroupDTO`.
  Map<String, Object?> toDto() => {
    '_id': id,
    'isDefault': isDefault is String ? false : isDefault,
  };
}

/// `DependsOrder`.
enum DependsOrder { parallel, sequence }

/// `ITaskDependency`: a label, or a task identifier ([KeyedTaskIdentifier]),
/// in a folder.
final class TaskDependency {
  const TaskDependency(this.uri, this.task);

  final VsUri? uri;

  /// A `String` or a [KeyedTaskIdentifier].
  final Object task;
}

/// `RunOnOptions`.
enum RunOnOptions { defaultRun, folderOpen }

/// `IRunOptions`.
final class RunOptions {
  RunOptions({
    this.reevaluateOnRerun,
    this.runOn,
    this.instanceLimit,
    this.instancePolicy,
  });

  /// `RunOptions.defaults`.
  factory RunOptions.defaults() => RunOptions(
    reevaluateOnRerun: true,
    runOn: RunOnOptions.defaultRun,
    instanceLimit: 1,
    instancePolicy: 'prompt',
  );

  /// `RunOptions.fromConfiguration`, and the wire's.
  factory RunOptions.from(Object? value) {
    final result = RunOptions.defaults();
    if (value is! Map) return result;
    return result
      ..reevaluateOnRerun =
          value['reevaluateOnRerun'] as bool? ?? result.reevaluateOnRerun
      ..runOn = value['runOn'] == 'folderOpen' || value['runOn'] == 2
          ? RunOnOptions.folderOpen
          : RunOnOptions.defaultRun
      ..instanceLimit =
          (value['instanceLimit'] as num?)?.toInt() ?? result.instanceLimit
      ..instancePolicy =
          value['instancePolicy'] as String? ?? result.instancePolicy;
  }

  bool? reevaluateOnRerun;
  RunOnOptions? runOn;
  int? instanceLimit;
  String? instancePolicy;

  RunOptions copy() => RunOptions(
    reevaluateOnRerun: reevaluateOnRerun,
    runOn: runOn,
    instanceLimit: instanceLimit,
    instancePolicy: instancePolicy,
  );

  Map<String, Object?> toDto() => {
    'reevaluateOnRerun': ?reevaluateOnRerun,
    if (runOn case final runOn?) 'runOn': runOn.index + 1,
    'instanceLimit': ?instanceLimit,
  };
}

/// `IConfigurationProperties`.
final class ConfigurationProperties {
  ConfigurationProperties({
    this.name,
    this.identifier,
    this.group,
    this.isBackground,
    this.promptOnClose,
    this.dependsOn,
    this.dependsOrder,
    this.presentation,
    this.options,
    this.problemMatchers,
    this.detail,
    this.icon,
    this.hide,
  });

  String? name;
  String? identifier;
  TaskGroup? group;
  bool? isBackground;
  bool? promptOnClose;
  List<TaskDependency>? dependsOn;
  DependsOrder? dependsOrder;
  PresentationOptions? presentation;
  CommandOptions? options;

  /// Each a `$name` (a `String`) or a [ProblemMatcher].
  List<Object>? problemMatchers;
  String? detail;
  Map<String, Object?>? icon;
  bool? hide;

  ConfigurationProperties copy() => ConfigurationProperties(
    name: name,
    identifier: identifier,
    group: group,
    isBackground: isBackground,
    promptOnClose: promptOnClose,
    dependsOn: dependsOn,
    dependsOrder: dependsOrder,
    presentation: presentation?.copy(),
    options: options?.copy(),
    problemMatchers: problemMatchers == null ? null : [...problemMatchers!],
    detail: detail,
    icon: icon,
    hide: hide,
  );
}

/// `TaskSourceKind`.
enum TaskSourceKind {
  workspace('workspace'),
  extension('extension'),
  inMemory('inMemory'),
  workspaceFile('workspaceFile'),
  user('user');

  const TaskSourceKind(this.id);
  final String id;
}

/// `TaskScope`.
enum TaskScope {
  global(1),
  workspace(2),
  folder(3);

  const TaskScope(this.wire);
  final int wire;
}

/// `TaskSource`: tasks.json's (with its element) or an extension's.
final class TaskSource {
  TaskSource({
    required this.kind,
    required this.label,
    this.extension,
    this.scope = TaskScope.folder,
    this.workspaceFolder,
    this.element,
    this.index,
    this.customizes,
  });

  final TaskSourceKind kind;
  final String label;

  /// The extension's id, for an extension's task.
  final String? extension;
  final TaskScope scope;
  final ExtHostWorkspaceFolder? workspaceFolder;

  /// tasks.json's object for it, and its index there.
  final Map<String, Object?>? element;
  final int? index;

  /// The extension's task a tasks.json one customizes.
  KeyedTaskIdentifier? customizes;

  TaskSource copyWith({KeyedTaskIdentifier? customizes}) => TaskSource(
    kind: kind,
    label: label,
    extension: extension,
    scope: scope,
    workspaceFolder: workspaceFolder,
    element: element,
    index: index,
    customizes: customizes ?? this.customizes,
  );

  /// `ITaskSourceDTO`.
  Map<String, Object?> toDto() => {
    'label': label,
    if (kind == TaskSourceKind.extension) ...{
      'extensionId': ?extension,
      'scope': workspaceFolder?.uri ?? scope.wire,
    } else if (kind == TaskSourceKind.workspace) ...{
      'extensionId': r'$core',
      'scope': workspaceFolder?.uri ?? TaskScope.global.wire,
    },
  };
}

/// `KeyedTaskIdentifier`: a task's definition with its `_key`.
final class KeyedTaskIdentifier {
  KeyedTaskIdentifier._(this.key, this.properties);

  /// `KeyedTaskIdentifier.create`.
  factory KeyedTaskIdentifier.create(Map<String, Object?> value) {
    final properties = Map<String, Object?>.of(value)..remove('_key');
    return KeyedTaskIdentifier._(_sortedStringify(properties), properties);
  }

  /// Not made from properties (a custom task's).
  KeyedTaskIdentifier.raw(this.key, this.properties);

  static String _sortedStringify(Map<String, Object?> literal) {
    final keys = literal.keys.toList()..sort();
    final result = StringBuffer();
    for (final key in keys) {
      Object? value = literal[key];
      if (value is Map) {
        value = _sortedStringify(value.cast<String, Object?>());
      } else if (value is List) {
        value = _sortedStringify({for (final (i, v) in value.indexed) '$i': v});
      } else if (value is String) {
        value = value.replaceAll(',', ',,');
      }
      result.write('$key,${value ?? 'null'},');
    }
    return result.toString();
  }

  /// `_key`.
  final String key;

  /// The definition: `type` and the rest.
  final Map<String, Object?> properties;

  String get type => properties['type'] as String? ?? '';

  /// `ITaskDefinitionDTO`.
  Map<String, Object?> toDto() => Map.of(properties);

  /// With its `_key`, as `KeyedTaskIdentifier` is.
  Map<String, Object?> toJson() => {'_key': key, ...properties};
}

/// `TaskDefinition` as an extension declares it
/// (`contributes.taskDefinitions`).
final class TaskDefinition {
  const TaskDefinition({
    required this.extensionId,
    required this.taskType,
    this.required = const [],
    this.properties = const {},
    this.when,
  });

  final String extensionId;
  final String taskType;
  final List<String> required;
  final Map<String, Map<String, Object?>> properties;
  final String? when;
}

/// `TaskDefinitionRegistry`: the task types extensions declare.
final class TaskDefinitionRegistry {
  final _definitions = <String, TaskDefinition>{};

  TaskDefinition? get(String type) => _definitions[type];

  Iterable<TaskDefinition> get all => _definitions.values;

  /// The `taskDefinitions` of [extensions] (scanned descriptions), in
  /// place of those before.
  void setExtensions(List<Map<String, Object?>> extensions) {
    _definitions.clear();
    for (final extension in extensions) {
      final contributes = extension['contributes'];
      if (contributes is! Map) continue;
      final definitions = contributes['taskDefinitions'];
      if (definitions is! List) continue;
      final id = _extensionId(extension);
      for (final definition in definitions) {
        if (definition is! Map || definition['type'] is! String) continue;
        final properties = definition['properties'];
        _definitions[definition['type'] as String] = TaskDefinition(
          extensionId: id,
          taskType: definition['type'] as String,
          required: [
            for (final r in definition['required'] as List? ?? const [])
              if (r is String) r,
          ],
          properties: {
            if (properties is Map)
              for (final MapEntry(:key, :value) in properties.entries)
                if (value is Map) '$key': value.cast<String, Object?>(),
          },
          when: definition['when'] as String?,
        );
      }
    }
  }

  /// `TaskDefinition.createTaskIdentifier`: [external] with the declared
  /// properties only, the required ones defaulted; null (and [error] told)
  /// when a required one has no default.
  KeyedTaskIdentifier? createTaskIdentifier(
    Map<String, Object?> external, {
    void Function(String message)? error,
  }) {
    final definition = get(external['type'] as String? ?? '');
    if (definition == null) {
      // We have no task definition so we can't sanitize the literal.
      return KeyedTaskIdentifier.create(external);
    }
    final literal = <String, Object?>{'type': definition.taskType};
    final required = definition.required.toSet();
    for (final MapEntry(key: property, value: schema)
        in definition.properties.entries) {
      final value = external[property];
      if (value != null) {
        literal[property] = value;
      } else if (required.contains(property)) {
        if (schema.containsKey('default')) {
          literal[property] = _clone(schema['default']);
        } else {
          switch (schema['type']) {
            case 'boolean':
              literal[property] = false;
            case 'number' || 'integer':
              literal[property] = 0;
            case 'string':
              literal[property] = '';
            default:
              error?.call(
                "Error: the task identifier '${jsonEncode(external)}' is "
                "missing the required property '$property'. The task "
                'identifier will be ignored.',
              );
              return null;
          }
        }
      }
    }
    return KeyedTaskIdentifier.create(literal);
  }
}

Object? _clone(Object? value) =>
    value == null ? null : jsonDecode(jsonEncode(value));

String _extensionId(Map<String, Object?> extension) {
  final identifier = extension['identifier'];
  if (identifier is Map && identifier['value'] is String) {
    return identifier['value'] as String;
  }
  return '${extension['publisher']}.${extension['name']}';
}

/// What kind of [Task] it is.
enum TaskKind {
  /// tasks.json's `shell`/`process` task, or an extension's it customizes
  /// (`CustomTask`).
  custom,

  /// An extension's (`ContributedTask`).
  contributed,

  /// tasks.json's customization of an extension's task, before the
  /// extension's is found (`ConfiguringTask`).
  configuring,
}

/// `CUSTOMIZED_TASK_TYPE`.
const customizedTaskType = r'$customized';

/// `USER_TASKS_GROUP_KEY`.
const userTasksGroupKey = 'settings';

/// `Task`: `CustomTask`, `ContributedTask` or `ConfiguringTask`.
final class Task {
  Task({
    required this.kind,
    required this.id,
    required this.source,
    required this.label,
    required this.configurationProperties,
    required this.runOptions,
    this.type,
    this.definition,
    this.command,
    this.hasDefinedMatchers = false,
  });

  final TaskKind kind;

  /// `_id`.
  final String id;

  /// `_label`.
  String label;
  String? type;
  TaskSource source;

  /// `defines` (a contributed task's) or `configures` (a configuring
  /// task's).
  KeyedTaskIdentifier? definition;
  CommandConfiguration? command;
  bool hasDefinedMatchers;
  RunOptions runOptions;
  ConfigurationProperties configurationProperties;

  /// Which run of it this is, when more than one may run.
  int? instance;

  /// Problems found loading it, for the output.
  final taskLoadMessages = <String>[];

  bool get isCustom => kind == TaskKind.custom;
  bool get isContributed => kind == TaskKind.contributed;
  bool get isConfiguring => kind == TaskKind.configuring;

  Task clone() => Task(
    kind: kind,
    id: id,
    source: source,
    label: label,
    type: type,
    definition: definition,
    command: command,
    hasDefinedMatchers: hasDefinedMatchers,
    runOptions: runOptions,
    configurationProperties: configurationProperties,
  )..taskLoadMessages.addAll(taskLoadMessages);

  ExtHostWorkspaceFolder? get workspaceFolder => source.workspaceFolder;

  /// `getDefinition`.
  KeyedTaskIdentifier? getDefinition({bool useSource = false}) {
    switch (kind) {
      case TaskKind.contributed || TaskKind.configuring:
        return definition;
      case TaskKind.custom:
        if (useSource && source.customizes != null) return source.customizes;
        final type = switch (command?.runtime) {
          RuntimeType.shell => 'shell',
          RuntimeType.process => 'process',
          RuntimeType.customExecution => 'customExecution',
          null => r'$composite',
        };
        return KeyedTaskIdentifier.raw(id, {'type': type, 'id': id});
    }
  }

  String? get _folderId => source.kind == TaskSourceKind.user
      ? userTasksGroupKey
      : kind == TaskKind.contributed
      ? (source.scope == TaskScope.folder
            ? workspaceFolder?.uri.toString()
            : null)
      : workspaceFolder?.uri.toString();

  /// `getMapKey`: which run it is, in the active tasks.
  String getMapKey() => switch (kind) {
    TaskKind.custom =>
      workspaceFolder != null
          ? '${workspaceFolder!.uri}|$id|$instance'
          : '$id|$instance',
    TaskKind.contributed =>
      workspaceFolder != null
          ? '${source.scope.wire}|${workspaceFolder!.uri}|$id|$instance'
          : '${source.scope.wire}|$id|$instance',
    TaskKind.configuring => id,
  };

  /// `getKey`: the same task across runs.
  String? getKey() {
    switch (kind) {
      case TaskKind.custom || TaskKind.configuring:
        final folder = _folderId;
        if (folder == null) return null;
        var id = configurationProperties.identifier ?? '';
        if (source.kind != TaskSourceKind.workspace) id += source.kind.id;
        return jsonEncode({
          'type': customizedTaskType,
          'folder': folder,
          'id': id,
        });
      case TaskKind.contributed:
        final folder = _folderId;
        return jsonEncode({
          'type': 'contributed',
          'scope': source.scope.wire,
          'id': id,
          'folder': ?folder,
        });
    }
  }

  /// `getCommonTaskId`.
  String getCommonTaskId() {
    final common = jsonEncode({'folder': _folderId, 'id': id});
    if (kind == TaskKind.custom && source.customizes == null) {
      return getKey() ?? common;
    }
    return common;
  }

  /// `getQualifiedLabel`.
  String getQualifiedLabel() =>
      workspaceFolder != null ? '$label (${workspaceFolder!.name})' : label;

  /// `matches`: by label or identifier ([key] a string, or by id with
  /// [compareId]), or by definition ([key] a [KeyedTaskIdentifier]).
  bool matches(Object? key, {bool compareId = false}) {
    if (key == null) return false;
    if (key is String) {
      return key == label ||
          key == configurationProperties.identifier ||
          (compareId && key == id);
    }
    if (key is KeyedTaskIdentifier) {
      return getDefinition(useSource: true)?.key == key.key;
    }
    return false;
  }

  /// `TaskDTO.from`: as the extension host sees it.
  Map<String, Object?>? toDto() {
    final definition = getDefinition(useSource: true);
    final command = this.command;
    return {
      '_id': id,
      'name': configurationProperties.name,
      'definition': definition?.toDto() ?? {'type': type},
      'source': source.toDto(),
      // Absent, not null, as upstream's `undefined` (the extension host
      // reads `group._id` of any group there).
      'execution': ?switch (command?.runtime) {
        RuntimeType.process => _processExecutionDto(command!),
        RuntimeType.shell => _shellExecutionDto(command!),
        RuntimeType.customExecution => {'customExecution': 'customExecution'},
        null => null,
      },
      'presentationOptions': ?command?.presentation?.toDto(),
      'isBackground': ?configurationProperties.isBackground,
      'problemMatchers': [
        for (final matcher
            in configurationProperties.problemMatchers ?? const <Object>[])
          if (matcher is String) matcher,
      ],
      'hasDefinedMatchers': kind == TaskKind.contributed && hasDefinedMatchers,
      'runOptions': runOptions.toDto(),
      'group': ?configurationProperties.group?.toDto(),
      if (configurationProperties.detail case final detail?
          when detail.isNotEmpty)
        'detail': detail,
    };
  }

  static Map<String, Object?> _processExecutionDto(CommandConfiguration c) => {
    'process': commandStringValue(c.name),
    'args': [for (final a in c.args ?? const <Object>[]) commandStringValue(a)],
    if (c.options case final options?)
      'options': {'cwd': ?options.cwd, 'env': ?options.env},
  };

  static Map<String, Object?> _shellExecutionDto(CommandConfiguration c) => {
    if (c.name is String && (c.args == null || c.args!.isEmpty))
      'commandLine': c.name
    else ...{
      'command': _commandStringToJson(c.name),
      'args': [
        for (final a in c.args ?? const <Object>[]) _commandStringToJson(a),
      ],
    },
    if (c.options case final options?)
      'options': {
        'cwd': options.cwd ?? r'${workspaceFolder}',
        'env': ?options.env,
        if (options.shell case final shell?) ...{
          'executable': ?shell.executable,
          'shellArgs': ?shell.args,
          'shellQuoting': ?shell.quoting?.toJson(),
        },
      },
  };

  /// `ITaskExecution` (`getTaskExecution`) as the extension host sees it.
  Map<String, Object?> executionDto() => {'id': id, 'task': toDto()};
}

/// `TaskEventKind`.
enum TaskEventKind {
  changed,
  processStarted,
  processEnded,
  terminated,
  start,
  acquiredInput,
  dependsOnStarted,
  active,
  inactive,
  end,
  problemMatcherStarted,
  problemMatcherEnded,
  problemMatcherFoundErrors,
}

/// `ITaskEvent`.
final class TaskEvent {
  const TaskEvent(
    this.kind, {
    this.task,
    this.terminalId,
    this.processId,
    this.exitCode,
    this.resolvedVariables,
    this.hasErrors,
  });

  final TaskEventKind kind;

  /// `__task`; none for [TaskEventKind.changed].
  final Task? task;
  final int? terminalId;
  final int? processId;
  final int? exitCode;
  final Map<String, String>? resolvedVariables;
  final bool? hasErrors;

  @override
  String toString() => 'TaskEvent(${kind.name}, ${task?.label})';
}

/// `ITaskSummary`.
typedef TaskSummary = ({int? exitCode});

/// `TaskError`.
final class TaskError implements Exception {
  const TaskError(this.message, {this.code = 'unknown'});

  final String message;

  /// `TaskErrors`: `notConfigured`, `runningTask`, `noBuildTask`,
  /// `noTestTask`, `configValidationError`, `taskNotFound`, `unknown`.
  final String code;

  @override
  String toString() => message;
}
