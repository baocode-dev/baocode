import 'dart:io';

import '../engine/session.dart';
import '../permissions/decision.dart';
import '../util/json.dart';
import 'tool.dart';

/// Puts questions to the user, with options to pick.
class AskUserQuestionTool extends Tool {
  const AskUserQuestionTool();

  /// Only with someone there to answer.
  @override
  bool isEnabled(AgentSession session) => session.options.canAsk;

  @override
  String get name => 'AskUserQuestion';

  @override
  String get description => '''Puts one to four multiple-choice questions to the user and waits for the answers: for a preference, a requirement left open, or a choice between ways of doing the work that is theirs to make. Do not ask what you can find out yourself, from the code or by running something.

- Give each question two to four options: a short label, and a line on what picking it means. The user can always answer in their own words instead, so leave out an "Other" option.
- With multiSelect, more than one option may be picked.
- If you would pick one of them, put it first and end its label with "(Recommended)".
- In plan mode, ask while the plan is still open. To have the plan approved, call ExitPlanMode; never ask whether it is ready.''';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'questions': {
        'type': 'array',
        'minItems': 1,
        'maxItems': 4,
        'description': 'One to four questions',
        'items': {
          'type': 'object',
          'properties': {
            'question': {
              'type': 'string',
              'description':
                  'The question in full, ending with a question mark',
            },
            'header': {
              'type': 'string',
              'description': 'A tag of at most 12 characters naming the question, such as "Database" or "Scope"',
            },
            'options': {
              'type': 'array',
              'minItems': 2,
              'maxItems': 4,
              'description': 'Two to four choices; the user may always write an answer of their own',
              'items': {
                'type': 'object',
                'properties': {
                  'label': {
                    'type': 'string',
                    'description': 'The choice, in one to five words',
                  },
                  'description': {
                    'type': 'string',
                    'description':
                        'What picking it means, or what happens then',
                  },
                  'preview': {
                    'type': 'string',
                    'description': 'Shown beside the option while it is focused: a sketch of a layout, a code sample',
                  },
                },
                'required': ['label', 'description'],
                'additionalProperties': false,
              },
            },
            'multiSelect': {
              'type': 'boolean',
              'default': false,
              'description': 'Whether more than one option may be picked',
            },
          },
          'required': ['question', 'header', 'options', 'multiSelect'],
          'additionalProperties': false,
        },
      },
      'answers': {
        'type': 'object',
        'description': 'The user\'s answers, filled in by the host',
        'propertyNames': {'type': 'string'},
        'additionalProperties': {'type': 'string'},
      },
      'annotations': {
        'type': 'object',
        'description': 'The user\'s notes on the questions, by question, filled in by the host',
        'propertyNames': {'type': 'string'},
        'additionalProperties': {
          'type': 'object',
          'properties': {
            'preview': {
              'type': 'string',
              'description': 'The preview of the option picked, if it had one',
            },
            'notes': {
              'type': 'string',
              'description': 'What the user wrote beside their answer',
            },
          },
          'additionalProperties': false,
        },
      },
      'metadata': {
        'type': 'object',
        'description': 'For the host\'s own use; not shown to the user',
        'properties': {
          'source': {
            'type': 'string',
            'description': 'What asked the questions, for the host\'s records',
          },
        },
        'additionalProperties': false,
      },
    },
    'required': ['questions'],
    'additionalProperties': false,
  };

  @override
  bool get requiresUserInteraction => true;

  @override
  bool isReadOnly(Map<String, Object?> input) => true;

  @override
  bool isConcurrencySafe(Map<String, Object?> input) => false;

  @override
  Future<PermissionDecision> checkPermissions(
    Map<String, Object?> input,
    ToolContext context,
  ) async => const PermissionAsk(
    message: 'Answer questions?',
    requiresUserInteraction: true,
    classifierApprovable: false,
  );

  @override
  Future<String?> validate(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final questions = asList(input['questions']);
    final texts = <String>{};
    for (final q in questions) {
      final question = '${asMap(q)['question'] ?? ''}';
      if (!texts.add(question)) return 'Question texts must be unique';
      final labels = <String>{};
      for (final option in asList(asMap(q)['options'])) {
        if (!labels.add('${asMap(option)['label'] ?? ''}')) {
          return 'Option labels must be unique within each question';
        }
      }
    }
    return null;
  }

  @override
  Future<ToolOutput> call(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final answers = asMap(input['answers']);
    if (answers.isEmpty) {
      return ToolOutput.error('The user did not answer the questions.');
    }
    final said = [
      for (final MapEntry(:key, :value) in answers.entries) '"$key"="$value"',
    ].join(', ');
    return ToolOutput(
      'The user answered: $said. Carry on with these answers.',
      result: {'questions': input['questions'], 'answers': answers},
    );
  }
}

/// Enters plan mode: the agent explores and plans before it changes
/// anything.
class EnterPlanModeTool extends Tool {
  const EnterPlanModeTool();

  @override
  String get name => 'EnterPlanMode';

  @override
  String get description => '''Switches the session to plan mode, once the user agrees: you explore and write a plan, and change nothing else until they approve it (ExitPlanMode).

Worth it before work whose shape is not settled: a feature that needs design decisions, a change across several files or to how existing code behaves, a task with more than one sensible approach, or one you must look into before you can say what it involves. Not for a small, clear fix, for instructions that already say exactly what to do, or for questions that only need reading.

In plan mode, read the code to see how things are done now, decide on an approach, ask with AskUserQuestion where the choice is the user's, write the plan to the plan file, and call ExitPlanMode.''';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{},
    'additionalProperties': false,
  };

  @override
  bool get changesMode => true;

  @override
  bool isEnabled(AgentSession session) =>
      session.options.canAsk && session.permissionMode != 'plan';

  @override
  bool isReadOnly(Map<String, Object?> input) => true;

  @override
  Future<PermissionDecision> checkPermissions(
    Map<String, Object?> input,
    ToolContext context,
  ) async => const PermissionAsk(message: 'Enter plan mode?');

  @override
  Future<ToolOutput> call(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    if (!context.run.isMain) {
      return ToolOutput.error('Only the main agent can enter plan mode.');
    }
    context.session.setPermissionMode('plan', byModel: true);
    return ToolOutput(
      'Plan mode is on. Explore and design, changing nothing but the plan '
      'file: read the code, see how similar things are done here, weigh the '
      'approaches, ask the user where a choice is theirs (AskUserQuestion), '
      'then write the plan to the plan file and call ExitPlanMode.',
      result: {'message': 'Entered plan mode'},
    );
  }
}

/// Puts the plan written to the user, to be started.
class ExitPlanModeTool extends Tool {
  const ExitPlanModeTool();

  /// Only with someone there to answer.
  @override
  bool isEnabled(AgentSession session) => session.options.canAsk;

  @override
  String get name => 'ExitPlanMode';

  @override
  String get description => '''Asks the user to approve the plan you wrote to the plan file (named in the plan mode reminder); once they do, plan mode ends. The plan is read from that file, so write it there first: the file is what the user sees.

Call it only when the plan is finished, and only for work that will change code, not to report what you found while researching. Settle open questions with AskUserQuestion beforehand, and never ask whether the plan is ready: calling this tool is how you ask.''';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'allowedPrompts': {
        'type': 'array',
        'description': 'No longer used.',
        'items': {
          'type': 'object',
          'properties': {
            'tool': {
              'type': 'string',
              'enum': ['Bash'],
              'description': 'The tool it is for',
            },
            'prompt': {
              'type': 'string',
              'description':
                  'What the action does, in a few words ("run the tests")',
            },
          },
          'required': ['tool', 'prompt'],
          'additionalProperties': false,
        },
      },
    },
    'additionalProperties': <String, Object?>{},
  };

  @override
  bool get changesMode => true;

  @override
  bool isReadOnly(Map<String, Object?> input) => true;

  /// The plan written, and where, for the user to see.
  @override
  Map<String, Object?> observableInput(
    Map<String, Object?> input,
    AgentSession session,
  ) {
    if (input['plan'] is String && input['planFilePath'] is String) {
      return input;
    }
    final path = session.planFilePath;
    String? plan = asString(input['plan']);
    if (plan == null) {
      try {
        plan = File(path).readAsStringSync();
      } on FileSystemException {
        plan = null;
      }
    } else {
      _keep(path, plan);
    }
    return {...input, 'plan': ?plan, 'planFilePath': path};
  }

  /// [plan], sent rather than written, kept in its file: the file is what
  /// the user is shown, and what starting the plan names (#298).
  static void _keep(String path, String plan) {
    final file = File(path);
    try {
      if (file.existsSync() && file.readAsStringSync() == plan) return;
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(plan);
    } on FileSystemException {
      // Shown from the call's input all the same.
    }
  }

  @override
  Future<PermissionDecision> checkPermissions(
    Map<String, Object?> input,
    ToolContext context,
  ) async => const PermissionAsk(
    message: 'Exit plan mode?',
    requiresUserInteraction: true,
    classifierApprovable: false,
  );

  @override
  Future<ToolOutput> call(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final session = context.session;
    final path = session.planFilePath;
    String? plan = asText(input['plan']);
    final file = File(path);
    if (plan == null && file.existsSync()) plan = file.readAsStringSync();
    if (session.permissionMode == 'plan') {
      session.setPermissionMode(
        session.modeBeforePlan ?? 'default',
        byModel: true,
      );
    }
    return ToolOutput(
      plan == null
          ? 'Plan mode is over: go ahead.'
          : 'The user approved your plan. Carry it out.\n\n'
                'The plan is kept at $path for reference.\n\n'
                '## The approved plan\n$plan',
      result: {'plan': plan, 'isAgent': !context.run.isMain, 'filePath': path},
    );
  }
}
