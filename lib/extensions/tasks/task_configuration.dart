/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// tasks.json: its tasks (`shell`, `process`, and customizations of the
// extensions' tasks by type), each one's command for this platform, options,
// presentation, group, dependencies and problem matchers (named, inline, or
// declared in `declares`); and a customized extension task built of both.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/tasks/common/taskConfiguration.ts.
//
// Deviations: the 0.1.0 schema's global command is read as upstream reads
// it, but `isShellCommand` with a shell configuration and the `runner`
// engines other than the terminal are not; a task type's `when` is not
// evaluated.

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import '../host/init_data.dart';
import 'problem_matcher.dart';
import 'tasks.dart';

/// The platform tasks.json's `windows`, `osx` and `linux` are read for.
enum TaskPlatform {
  windows,
  mac,
  linux;

  static TaskPlatform get current => Platform.isWindows
      ? windows
      : Platform.isMacOS
      ? mac
      : linux;

  String get key => switch (this) {
    windows => 'windows',
    mac => 'osx',
    linux => 'linux',
  };
}

/// `UUIDMap`: the same label, the same id, parse after parse.
final class TaskIdMap {
  final _ids = <String, String>{};
  final _random = Random();

  String getUuid(String label) => _ids.putIfAbsent(label, _uuid);

  String _uuid() {
    String hex(int n) =>
        [for (var i = 0; i < n; i++) _random.nextInt(16).toRadixString(16)]
            .join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-${(8 + _random.nextInt(4)).toRadixString(16)}${hex(3)}-${hex(12)}';
  }
}

/// `IParseContext`.
final class TaskParseContext {
  TaskParseContext({
    required this.workspaceFolder,
    required this.patterns,
    required this.matchers,
    required this.definitions,
    required this.ids,
    this.platform,
    this.schemaVersion2 = true,
  });

  final ExtHostWorkspaceFolder workspaceFolder;
  final ProblemPatternRegistry patterns;
  final ProblemMatcherRegistry matchers;
  final TaskDefinitionRegistry definitions;
  final TaskIdMap ids;
  final TaskPlatform? platform;

  /// `"version": "2.0.0"`.
  final bool schemaVersion2;

  final reporter = ProblemReporter();
  Map<String, ProblemMatcher> namedProblemMatchers = {};
  var taskLoadIssues = <String>[];

  TaskPlatform get _platform => platform ?? TaskPlatform.current;
}

/// `ITaskParseResult`, and the problems parsing found.
typedef TaskParseResult = ({
  List<Task> custom,
  List<Task> configured,
  List<String> errors,
  List<String> warnings,
});

/// `parse`: tasks.json's [configuration] for [context]'s folder.
TaskParseResult parseTaskConfiguration(
  Map<String, Object?> configuration,
  TaskParseContext context,
) {
  final result = _createTaskRunnerConfiguration(configuration, context);
  return (
    custom: result.custom,
    configured: result.configured,
    errors: [...context.reporter.errors],
    warnings: [...context.reporter.warnings, ...context.reporter.infos],
  );
}

/// `ConfigurationParser.createTaskRunnerConfiguration`.
({List<Task> custom, List<Task> configured}) _createTaskRunnerConfiguration(
  Map<String, Object?> fileConfig,
  TaskParseContext context,
) {
  final globals = _Globals.from(fileConfig, context);
  context.namedProblemMatchers = _namedMatchersFrom(
    fileConfig['declares'],
    context,
  );
  List<Task>? globalTasks;
  final osConfig = fileConfig[context._platform.key];
  if (osConfig is Map && osConfig['tasks'] is List) {
    globalTasks = _parseTasks(
      osConfig['tasks'] as List,
      globals,
      context,
    ).custom;
    if (context.schemaVersion2 && globalTasks.isNotEmpty) {
      context.reporter.errors.add(
        "Task version 2.0.0 doesn't support global OS specific tasks. "
        'Convert them to a task with a OS specific command.',
      );
    }
  }
  var result = (custom: <Task>[], configured: <Task>[]);
  if (fileConfig['tasks'] case final List tasks) {
    result = _parseTasks(tasks, globals, context);
  }
  if (globalTasks != null) {
    result = (
      custom: _assignTasks(result.custom, globalTasks),
      configured: result.configured,
    );
  }
  final globalCommand = globals.command;
  if (result.custom.isEmpty && globalCommand?.name != null) {
    final matchers = _problemMatchersFrom(
      fileConfig['problemMatcher'],
      context,
    ).value;
    final isBackground = fileConfig['isBackground'] != null
        ? fileConfig['isBackground'] == true
        : fileConfig['isWatching'] != null
        ? fileConfig['isWatching'] == true
        : null;
    final name = commandStringValue(globalCommand!.name);
    final task = Task(
      kind: TaskKind.custom,
      id: context.ids.getUuid(name),
      source: TaskSource(
        kind: TaskSourceKind.workspace,
        label: _workspaceLabel,
        workspaceFolder: context.workspaceFolder,
        element: fileConfig,
        index: -1,
      ),
      label: name,
      type: customizedTaskType,
      command: CommandConfiguration(suppressTaskName: true),
      runOptions: RunOptions(reevaluateOnRerun: true),
      configurationProperties: ConfigurationProperties(
        name: name,
        identifier: name,
        group: TaskGroup.build,
        isBackground: isBackground,
        problemMatchers: matchers,
      ),
    );
    final group = TaskGroup.from(fileConfig['group']);
    if (group != null) {
      task.configurationProperties.group = group;
    } else if (fileConfig['group'] == 'none') {
      task.configurationProperties.group = null;
    }
    _CustomTask.fillGlobals(task, globals);
    _CustomTask.fillDefaults(task, context);
    result = (custom: [task], configured: result.configured);
  }
  return result;
}

const _workspaceLabel = 'Workspace';

/// `IGlobals`.
final class _Globals {
  CommandConfiguration? command;
  List<Object>? problemMatcher;
  bool? promptOnClose;
  bool? suppressTaskName;

  static _Globals from(Map<String, Object?> config, TaskParseContext context) {
    final result = _fromBase(config, context);
    final osConfig = config[context._platform.key];
    if (osConfig is Map) {
      final os = _fromBase(osConfig.cast<String, Object?>(), context);
      if (os.promptOnClose != null) result.promptOnClose = os.promptOnClose;
      if (os.suppressTaskName != null) {
        result.suppressTaskName = os.suppressTaskName;
      }
    }
    final command = _Command.from(config, context);
    if (command != null) result.command = command;
    _Command.fillDefaults(result.command, context);
    result
      ..suppressTaskName ??= context.schemaVersion2
      ..promptOnClose ??= true;
    return result;
  }

  static _Globals _fromBase(
    Map<String, Object?> config,
    TaskParseContext context,
  ) {
    final result = _Globals();
    if (config['suppressTaskName'] != null) {
      result.suppressTaskName = config['suppressTaskName'] == true;
    }
    if (config['promptOnClose'] != null) {
      result.promptOnClose = config['promptOnClose'] == true;
    }
    if (config['problemMatcher'] != null) {
      result.problemMatcher = _problemMatchersFrom(
        config['problemMatcher'],
        context,
      ).value;
    }
    return result;
  }
}

/// `CommandConfiguration`.
abstract final class _Command {
  static CommandConfiguration? from(Map config, TaskParseContext context) {
    var result = _fromBase(config, context);
    final osConfig = config[context._platform.key];
    if (osConfig is Map) {
      final os = _fromBase(osConfig, context);
      if (os != null) {
        result = assign(
          result ?? CommandConfiguration(),
          os,
          overwriteArgs: context.schemaVersion2,
        );
      }
    }
    return result == null || result.isEmpty ? null : result;
  }

  static CommandConfiguration? _fromBase(Map config, TaskParseContext context) {
    final name = commandStringFrom(config['command']);
    RuntimeType? runtime;
    if (config['type'] == 'shell') runtime = RuntimeType.shell;
    if (config['type'] == 'process') runtime = RuntimeType.process;
    final isShellCommand = config['isShellCommand'];
    if (isShellCommand is bool || isShellCommand is Map) {
      runtime = RuntimeType.shell;
    } else if (isShellCommand != null) {
      runtime = RuntimeType.process;
    }
    final result = CommandConfiguration(
      name: name,
      runtime: runtime,
      presentation: PresentationOptions.fromConfig(config),
    );
    if (config['args'] case final List args) {
      result.args = [];
      for (final arg in args) {
        final converted = commandStringFrom(arg);
        if (converted != null) {
          result.args!.add(converted);
        } else {
          context.taskLoadIssues.add(
            'Error: command argument must either be a string or a quoted '
            'string. Provided value is:\n${jsonEncode(arg)}',
          );
        }
      }
    }
    if (config['options'] case final Map options) {
      result.options = _optionsFrom(options, context);
    }
    if (config['taskSelector'] is String) {
      result.taskSelector = config['taskSelector'] as String;
    }
    if (config['suppressTaskName'] is bool) {
      result.suppressTaskName = config['suppressTaskName'] as bool;
    }
    return result.isEmpty ? null : result;
  }

  /// `CommandConfiguration.assignProperties`.
  static CommandConfiguration assign(
    CommandConfiguration target,
    CommandConfiguration source, {
    required bool overwriteArgs,
  }) {
    if (source.isEmpty) return target;
    if (target.isEmpty) return source;
    if (source.name != null) target.name = source.name;
    if (source.runtime != null) target.runtime = source.runtime;
    if (source.taskSelector != null) target.taskSelector = source.taskSelector;
    if (source.suppressTaskName != null) {
      target.suppressTaskName = source.suppressTaskName;
    }
    if (source.args != null) {
      target.args = target.args == null || overwriteArgs
          ? source.args
          : [...target.args!, ...source.args!];
    }
    target
      ..presentation = PresentationOptions.assign(
        target.presentation,
        source.presentation,
      )
      ..options = CommandOptions.assign(target.options, source.options);
    return target;
  }

  /// `CommandConfiguration.fillGlobals`.
  static CommandConfiguration fillGlobals(
    CommandConfiguration? target,
    CommandConfiguration? source,
    String? taskName,
  ) {
    target ??= CommandConfiguration();
    if (source == null || source.isEmpty) return target;
    if (target.name == null) {
      target
        ..name = source.name
        ..taskSelector ??= source.taskSelector
        ..suppressTaskName ??= source.suppressTaskName;
      var args = <Object>[...?source.args];
      if (!(target.suppressTaskName ?? false) && taskName != null) {
        args.add(
          target.taskSelector != null
              ? '${target.taskSelector}$taskName'
              : taskName,
        );
      }
      if (target.args != null) args = [...args, ...target.args!];
      target.args = args;
    }
    target
      ..runtime ??= source.runtime
      ..presentation = PresentationOptions.fill(
        target.presentation,
        source.presentation,
      )
      ..options = CommandOptions.fill(target.options, source.options);
    return target;
  }

  /// `CommandConfiguration.fillDefaults`.
  static void fillDefaults(
    CommandConfiguration? value,
    TaskParseContext context,
  ) {
    if (value == null) return;
    if (value.name != null && value.runtime == null) {
      value.runtime = RuntimeType.process;
    }
    value.presentation = (value.presentation ?? PresentationOptions())
        .withDefaults();
    if (!value.isEmpty) {
      value.options = CommandOptions.fill(
        value.options,
        CommandOptions(cwd: r'${workspaceFolder}'),
      );
    }
    value
      ..args ??= const []
      ..suppressTaskName ??= context.schemaVersion2;
  }
}

/// `CommandOptions.from`.
CommandOptions? _optionsFrom(Map options, TaskParseContext context) {
  final result = CommandOptions();
  if (options['cwd'] != null) {
    if (options['cwd'] is String) {
      result.cwd = options['cwd'] as String;
    } else {
      context.taskLoadIssues.add(
        'Warning: options.cwd must be of type string. Ignoring value '
        '${options['cwd']}\n',
      );
    }
  }
  if (options['env'] case final Map env) {
    result.env = {
      for (final MapEntry(:key, :value) in env.entries)
        '$key': value is String ? value : '$value',
    };
  }
  final shell = options['shell'];
  if (shell is Map &&
      (shell['executable'] is String ||
          (shell['args'] is List &&
              (shell['args'] as List).every((a) => a is String)))) {
    result.shell = ShellConfiguration(
      executable: shell['executable'] as String?,
      args: (shell['args'] as List?)?.cast<String>().toList(),
      quoting: ShellQuotingOptions.fromJson(shell['quoting']),
    );
  }
  return result.isEmpty ? null : result;
}

/// `ProblemMatcherConverter.namedFrom`.
Map<String, ProblemMatcher> _namedMatchersFrom(
  Object? declares,
  TaskParseContext context,
) {
  final result = <String, ProblemMatcher>{};
  if (declares is! List) return result;
  for (final value in declares) {
    if (value is! Map) continue;
    final matcher = ProblemMatcherParser(
      context.reporter,
      context.patterns,
      context.matchers,
    ).parse(value);
    if (matcher?.name case final name?) {
      result[name] = matcher!;
    } else {
      context.reporter.errors.add(
        'Error: Problem Matcher in declare scope must have a name:\n'
        '${jsonEncode(value)}\n',
      );
    }
  }
  return result;
}

/// `ProblemMatcherConverter.fromWithOsConfig`.
({List<Object>? value, List<String> errors}) _problemMatchersWithOsConfig(
  Map external,
  TaskParseContext context,
) {
  final os = external[context._platform.key];
  if (os is Map && os['problemMatcher'] != null) {
    return _problemMatchersFrom(os['problemMatcher'], context);
  }
  if (external['problemMatcher'] != null) {
    return _problemMatchersFrom(external['problemMatcher'], context);
  }
  return (value: null, errors: const []);
}

/// `ProblemMatcherConverter.from`: the matchers, each a [ProblemMatcher].
({List<Object> value, List<String> errors}) _problemMatchersFrom(
  Object? config,
  TaskParseContext context,
) {
  final result = <Object>[];
  final errors = <String>[];
  if (config == null) return (value: result, errors: errors);
  void add(Object? value) {
    final resolved = _resolveProblemMatcher(value, context);
    if (resolved.value case final matcher?) result.add(matcher);
    errors.addAll(resolved.errors);
  }

  if (config is String || config is Map) {
    add(config);
  } else if (config is List) {
    config.forEach(add);
  } else {
    context.reporter.warnings.add(
      'Warning: the defined problem matcher is unknown. Supported types are '
      'string | ProblemMatcher | Array<string | ProblemMatcher>.\n'
      '${jsonEncode(config)}\n',
    );
  }
  return (value: result, errors: errors);
}

({ProblemMatcher? value, List<String> errors}) _resolveProblemMatcher(
  Object? value,
  TaskParseContext context,
) {
  if (value is String) {
    if (value.length > 1 && value.startsWith(r'$')) {
      final name = value.substring(1);
      if (context.matchers.get(name) case final global?) {
        return (value: global.copy(), errors: const []);
      }
      if (context.namedProblemMatchers[name] case final local?) {
        return (value: local.copy()..name = null, errors: const []);
      }
    }
    return (
      value: null,
      errors: ['Error: Invalid problemMatcher reference: $value\n'],
    );
  }
  if (value is Map) {
    return (
      value: ProblemMatcherParser(
        context.reporter,
        context.patterns,
        context.matchers,
      ).parse(value),
      errors: const [],
    );
  }
  return (value: null, errors: const []);
}

/// `TaskDependency.from`.
TaskDependency? _dependencyFrom(Object? external, TaskParseContext context) {
  final uri = context.workspaceFolder.uri;
  if (external is String) return TaskDependency(uri, external);
  if (external is Map && external['type'] is String) {
    final identifier = context.definitions.createTaskIdentifier(
      external.cast<String, Object?>(),
      error: context.reporter.errors.add,
    );
    return identifier == null ? null : TaskDependency(uri, identifier);
  }
  return null;
}

/// `ConfigurationProperties.from`.
({ConfigurationProperties? value, List<String> errors})
_configurationPropertiesFrom(
  Map external,
  TaskParseContext context, {
  required bool includeCommandOptions,
}) {
  final result = ConfigurationProperties();
  if (external['taskName'] is String) {
    result.name = external['taskName'] as String;
  }
  if (external['label'] is String && context.schemaVersion2) {
    result.name = external['label'] as String;
  }
  if (external['identifier'] is String) {
    result.identifier = external['identifier'] as String;
  }
  result
    ..icon = (external['icon'] as Map?)?.cast<String, Object?>()
    ..hide = external['hide'] as bool?;
  if (external['isBackground'] != null) {
    result.isBackground = external['isBackground'] == true;
  }
  if (external['promptOnClose'] != null) {
    result.promptOnClose = external['promptOnClose'] == true;
  }
  result.group = TaskGroup.from(external['group']);
  final dependsOn = external['dependsOn'];
  if (dependsOn != null) {
    if (dependsOn is List) {
      result.dependsOn = [
        for (final item in dependsOn) ?_dependencyFrom(item, context),
      ];
    } else {
      final dependency = _dependencyFrom(dependsOn, context);
      result.dependsOn = dependency == null ? null : [dependency];
    }
  }
  result.dependsOrder = external['dependsOrder'] == 'sequence'
      ? DependsOrder.sequence
      : DependsOrder.parallel;
  if (includeCommandOptions &&
      (external['presentation'] != null || external['terminal'] != null)) {
    result.presentation = PresentationOptions.fromConfig(external);
  }
  if (includeCommandOptions && external['options'] is Map) {
    result.options = _optionsFrom(external['options'] as Map, context);
  }
  final matchers = _problemMatchersWithOsConfig(external, context);
  if (matchers.value != null) result.problemMatchers = matchers.value;
  if (external['detail'] case final String detail when detail.isNotEmpty) {
    result.detail = detail;
  }
  return (value: result, errors: matchers.errors);
}

/// `CustomTask`.
abstract final class _CustomTask {
  static Task? from(Map external, TaskParseContext context, int index) {
    final type = external['type'] ?? customizedTaskType;
    if (type != customizedTaskType && type != 'shell' && type != 'process') {
      context.reporter.errors.add(
        'Error: tasks is not declared as a custom task. The configuration '
        'will be ignored.\n${jsonEncode(external)}\n',
      );
      return null;
    }
    var taskName = external['taskName'] as String?;
    if (external['label'] is String && context.schemaVersion2) {
      taskName = external['label'] as String;
    }
    if (taskName == null || taskName.isEmpty) {
      context.reporter.errors.add(
        'Error: a task must provide a label property. The task will be '
        'ignored.\n${jsonEncode(external)}\n',
      );
      return null;
    }
    final result = Task(
      kind: TaskKind.custom,
      id: context.ids.getUuid(taskName),
      source: TaskSource(
        kind: TaskSourceKind.workspace,
        label: _workspaceLabel,
        workspaceFolder: context.workspaceFolder,
        element: external.cast<String, Object?>(),
        index: index,
      ),
      label: taskName,
      type: customizedTaskType,
      runOptions: RunOptions.from(external['runOptions']),
      configurationProperties: ConfigurationProperties(
        name: taskName,
        identifier: taskName,
      ),
    );
    final configuration = _configurationPropertiesFrom(
      external,
      context,
      includeCommandOptions: false,
    );
    result.taskLoadMessages.addAll(configuration.errors);
    if (configuration.value case final value?) {
      _assignConfiguration(result.configurationProperties, value);
    }
    // Legacy properties.
    final props = result.configurationProperties;
    if (props.isBackground == null && external['isWatching'] != null) {
      props.isBackground = external['isWatching'] == true;
    }
    if (props.group == null) {
      if (external['isBuildCommand'] == true) {
        props.group = TaskGroup.build;
      } else if (external['isTestCommand'] == true) {
        props.group = TaskGroup.test;
      }
    }
    final command = _Command.from(external, context);
    if (command != null) result.command = command;
    if (external['command'] != null) {
      // A task with its own command suppresses the task name.
      (result.command ??= CommandConfiguration()).suppressTaskName = true;
    }
    return result;
  }

  static void fillGlobals(Task task, _Globals globals) {
    final props = task.configurationProperties;
    // A global command only when there is no dependsOn, or a command.
    if (task.command?.name != null || props.dependsOn == null) {
      task.command = _Command.fillGlobals(
        task.command,
        globals.command,
        props.name,
      );
    }
    if (props.problemMatchers == null && globals.problemMatcher != null) {
      props.problemMatchers = [...globals.problemMatcher!];
      task.hasDefinedMatchers = true;
    }
    // promptOnClose is inferred from isBackground if available.
    if (props.promptOnClose == null &&
        props.isBackground == null &&
        globals.promptOnClose != null) {
      props.promptOnClose = globals.promptOnClose;
    }
  }

  static void fillDefaults(Task task, TaskParseContext context) {
    _Command.fillDefaults(task.command, context);
    final props = task.configurationProperties;
    props
      ..promptOnClose ??= props.isBackground != null
          ? !props.isBackground!
          : true
      ..isBackground ??= false
      ..problemMatchers ??= const [];
  }
}

void _assignConfiguration(
  ConfigurationProperties target,
  ConfigurationProperties source,
) {
  target
    ..name = source.name ?? target.name
    ..identifier = source.identifier ?? target.identifier
    ..group = source.group ?? target.group
    ..isBackground = source.isBackground ?? target.isBackground
    ..promptOnClose = source.promptOnClose ?? target.promptOnClose
    ..dependsOn = source.dependsOn ?? target.dependsOn
    ..dependsOrder = source.dependsOrder ?? target.dependsOrder
    ..presentation = source.presentation ?? target.presentation
    ..options = source.options ?? target.options
    ..problemMatchers = source.problemMatchers ?? target.problemMatchers
    ..detail = source.detail ?? target.detail
    ..icon = source.icon ?? target.icon
    ..hide = source.hide ?? target.hide;
}

/// `ConfiguringTask.from`.
Task? _configuringTaskFrom(Map external, TaskParseContext context, int index) {
  final type = external['type'];
  final customize = external['customize'];
  if (type == null && customize == null) {
    context.reporter.errors.add(
      'Error: tasks configuration must have a type property. The '
      'configuration will be ignored.\n${jsonEncode(external)}\n',
    );
    return null;
  }
  final typeDeclaration = type is String ? context.definitions.get(type) : null;
  if (typeDeclaration == null) {
    context.reporter.errors.add(
      "Error: there is no registered task type '$type'. Did you miss "
      'installing an extension that provides a corresponding task provider?',
    );
    return null;
  }
  Map<String, Object?>? identifier;
  if (customize is String) {
    for (final (prefix, build)
        in <(String, Map<String, Object?> Function(String))>[
          ('grunt.', (rest) => {'type': 'grunt', 'task': rest}),
          ('jake.', (rest) => {'type': 'jake', 'task': rest}),
          ('gulp.', (rest) => {'type': 'gulp', 'task': rest}),
          (
            'vscode.npm.',
            (rest) => {'type': 'npm', 'script': rest.substring(4)},
          ),
          (
            'vscode.typescript.',
            (rest) => {'type': 'typescript', 'tsconfig': rest.substring(6)},
          ),
        ]) {
      if (customize.startsWith(prefix)) {
        identifier = build(customize.substring(prefix.length));
        break;
      }
    }
  } else if (type is String) {
    identifier = external.cast<String, Object?>();
  }
  if (identifier == null) {
    context.reporter.errors.add(
      "Error: the task configuration '${jsonEncode(external)}' is missing "
      "the required property 'type'. The task configuration will be ignored.",
    );
    return null;
  }
  final taskIdentifier = context.definitions.createTaskIdentifier(
    identifier,
    error: context.reporter.errors.add,
  );
  if (taskIdentifier == null) {
    context.reporter.errors.add(
      "Error: the task configuration '${jsonEncode(external)}' is using an "
      'unknown type. The task configuration will be ignored.',
    );
    return null;
  }
  final result = Task(
    kind: TaskKind.configuring,
    id: '${typeDeclaration.extensionId}.${taskIdentifier.key}',
    source: TaskSource(
      kind: TaskSourceKind.workspace,
      label: _workspaceLabel,
      workspaceFolder: context.workspaceFolder,
      element: external.cast<String, Object?>(),
      index: index,
    ),
    label: '',
    type: type as String?,
    definition: taskIdentifier,
    runOptions: RunOptions.from(external['runOptions']),
    configurationProperties: ConfigurationProperties(
      hide: external['hide'] as bool?,
    ),
  );
  final configuration = _configurationPropertiesFrom(
    external,
    context,
    includeCommandOptions: true,
  );
  result.taskLoadMessages.addAll(configuration.errors);
  if (configuration.value case final value?) {
    _assignConfiguration(result.configurationProperties, value);
    if (result.configurationProperties.name case final name?) {
      result.label = name;
    } else {
      var label = taskIdentifier.type;
      for (final required in typeDeclaration.required) {
        final value = taskIdentifier.properties[required];
        if (value != null && value != '' && value != false && value != 0) {
          label = '$label: $value';
          break;
        }
      }
      result.label = label;
    }
    result.configurationProperties.identifier ??= taskIdentifier.key;
  }
  return result;
}

/// `TaskParser.from`.
({List<Task> custom, List<Task> configured}) _parseTasks(
  List externals,
  _Globals globals,
  TaskParseContext context,
) {
  final custom = <Task>[];
  final configured = <Task>[];
  Task? defaultBuildTask;
  var buildRank = -1;
  Task? defaultTestTask;
  var testRank = -1;
  final baseLoadIssues = [...context.taskLoadIssues];
  for (final (index, external) in externals.indexed) {
    if (external is! Map) continue;
    final type = external['type'];
    final customize = external['customize'];
    final isCustom =
        customize == null &&
        (type == null ||
            type == customizedTaskType ||
            type == 'shell' ||
            type == 'process');
    if (isCustom) {
      final task = _CustomTask.from(external, context, index);
      if (task != null) {
        _CustomTask.fillGlobals(task, globals);
        _CustomTask.fillDefaults(task, context);
        final props = task.configurationProperties;
        if (context.schemaVersion2) {
          if (task.command?.name == null &&
              (props.dependsOn == null || props.dependsOn!.isEmpty)) {
            context.reporter.errors.add(
              "Error: the task '${props.name}' neither specifies a command "
              'nor a dependsOn property. The task will be ignored. Its '
              'definition is:\n${jsonEncode(external)}',
            );
            context.taskLoadIssues = [...baseLoadIssues];
            continue;
          }
        } else if (task.command?.name == null) {
          context.reporter.warnings.add(
            "Error: the task '${props.name}' doesn't define a command. The "
            'task will be ignored. Its definition is:\n'
            '${jsonEncode(external)}',
          );
          context.taskLoadIssues = [...baseLoadIssues];
          continue;
        }
        if (props.group?.id == 'build' && buildRank < 2) {
          defaultBuildTask = task;
          buildRank = 2;
        } else if (props.group?.id == 'test' && testRank < 2) {
          defaultTestTask = task;
          testRank = 2;
        } else if (props.name == 'build' && buildRank < 1) {
          defaultBuildTask = task;
          buildRank = 1;
        } else if (props.name == 'test' && testRank < 1) {
          defaultTestTask = task;
          testRank = 1;
        }
        task.taskLoadMessages.addAll(context.taskLoadIssues);
        custom.add(task);
      }
    } else {
      final task = _configuringTaskFrom(external, context, index);
      if (task != null) {
        task.taskLoadMessages.addAll(context.taskLoadIssues);
        configured.add(task);
      }
    }
    context.taskLoadIssues = [...baseLoadIssues];
  }
  // Tasks labelled "build" and "test" are in those groups unless already
  // grouped as such.
  if (defaultBuildTask != null &&
      defaultBuildTask.configurationProperties.group?.id != 'build' &&
      buildRank > -1 &&
      buildRank < 2) {
    defaultBuildTask.configurationProperties.group = TaskGroup.build;
  } else if (defaultTestTask != null &&
      defaultTestTask.configurationProperties.group?.id != 'test' &&
      testRank > -1 &&
      testRank < 2) {
    defaultTestTask.configurationProperties.group = TaskGroup.test;
  }
  return (custom: custom, configured: configured);
}

/// `TaskParser.assignTasks`: [source]'s over [target]'s, by name.
List<Task> _assignTasks(List<Task> target, List<Task> source) {
  if (source.isEmpty) return target;
  if (target.isEmpty) return source;
  final map = <String?, Task>{
    for (final task in target) task.configurationProperties.name: task,
  };
  for (final task in source) {
    map[task.configurationProperties.name] = task;
  }
  final result = <Task>[];
  for (final task in target) {
    result.add(map.remove(task.configurationProperties.name)!);
  }
  result.addAll(map.values);
  return result;
}

/// `createCustomTask`: an extension's [contributed] task as tasks.json's
/// [configured] one customizes it.
Task createCustomTask(Task contributed, Task configured) {
  final configuredProps = configured.configurationProperties;
  final contributedProps = contributed.configurationProperties;
  final result = Task(
    kind: TaskKind.custom,
    id: configured.id,
    source: configured.source.copyWith(customizes: contributed.definition),
    label: configuredProps.name ?? contributed.label,
    type: customizedTaskType,
    command: contributed.command?.copy(),
    runOptions: contributed.runOptions.copy(),
    configurationProperties: ConfigurationProperties(
      name: configuredProps.name ?? contributedProps.name,
      identifier: configuredProps.identifier ?? contributedProps.identifier,
      icon: configuredProps.icon,
      hide: configuredProps.hide,
    ),
  )..taskLoadMessages.addAll(configured.taskLoadMessages);
  final props = result.configurationProperties;
  props
    ..group = configuredProps.group ?? contributedProps.group
    ..isBackground =
        configuredProps.isBackground ?? contributedProps.isBackground
    ..dependsOn = configuredProps.dependsOn ?? contributedProps.dependsOn
    ..problemMatchers =
        configuredProps.problemMatchers ?? contributedProps.problemMatchers
    ..promptOnClose =
        configuredProps.promptOnClose ?? contributedProps.promptOnClose
    ..detail = configuredProps.detail ?? contributedProps.detail;
  final command = result.command ??= CommandConfiguration();
  command
    ..presentation = PresentationOptions.fill(
      PresentationOptions.assign(
        command.presentation,
        configuredProps.presentation,
      ),
      contributedProps.presentation,
    )
    ..options = CommandOptions.fill(
      CommandOptions.assign(command.options, configuredProps.options),
      contributedProps.options,
    );
  final configuredRun = configured.source.element?['runOptions'];
  if (configuredRun is Map) result.runOptions = RunOptions.from(configuredRun);
  if (contributed.hasDefinedMatchers) result.hasDefinedMatchers = true;
  return result;
}
