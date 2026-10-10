import 'package:baocode/kernel/claude_code/claude_elicitation.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fields = elicitationFields({
    'type': 'object',
    'properties': {
      'name': {'type': 'string', 'title': 'Name', 'description': 'Your name'},
      'size': {
        'type': 'string',
        'oneOf': [
          {'const': 's', 'title': 'Small'},
          {'const': 'l', 'title': 'Large'},
        ],
      },
      'legacy': {
        'type': 'string',
        'enum': ['x', 'y'],
        'enumNames': ['Ex', 'Why'],
      },
      'tags': {
        'type': 'array',
        'items': {
          'anyOf': [
            {'const': 'red', 'title': 'Red'},
            {'const': 'blue', 'title': 'Blue'},
          ],
        },
      },
      'ratio': {'type': 'number'},
      'ok': {'type': 'boolean'},
    },
    'required': ['name', 'size'],
  });

  test('the form\'s fields, of each kind', () {
    expect(fields.map((f) => (f.name, f.kind, f.required)), [
      ('name', ElicitationKind.text, true),
      ('size', ElicitationKind.choice, true),
      ('legacy', ElicitationKind.choice, false),
      ('tags', ElicitationKind.choices, false),
      ('ratio', ElicitationKind.number, false),
      ('ok', ElicitationKind.boolean, false),
    ]);
    expect(fields[1].options.map((o) => (o.value, o.label)), [
      ('s', 'Small'),
      ('l', 'Large'),
    ]);
    expect(fields[2].options.map((o) => o.label), ['Ex', 'Why']);
    expect(elicitationFields(null), isEmpty);
    expect(elicitationFields({'type': 'object'}), isEmpty);
  });

  test('as questions: words typed, choices picked, optional ones left '
      'blank', () {
    final questions = elicitationQuestions('Tell me more', fields);
    expect(questions.first.prompt, 'Tell me more\n\nYour name');
    expect(questions.first.header, 'Name *');
    expect(questions.first.options, isEmpty);
    expect(questions.first.allowOther, isTrue);
    expect(questions.first.otherLabel, elicitationTypeHere);
    expect(questions[1].prompt, 'size');
    expect(questions[1].options.map((o) => o.label), ['Small', 'Large']);
    expect(questions[1].allowOther, isFalse);
    expect(questions[3].allowMultiple, isTrue);
    expect(questions[3].options.map((o) => o.label), [
      'Red',
      'Blue',
      elicitationBlank,
    ]);
  });

  test('the answers as the server takes them', () {
    expect(
      elicitationResult(
        fields,
        const QuestionAnswer([
          ['Ada'],
          ['Large'],
          [elicitationBlank],
          ['Red', 'Blue'],
          ['0.5'],
          ['No'],
        ]),
      ),
      {
        'action': 'accept',
        'content': {
          'name': 'Ada',
          'size': 'l',
          'tags': ['red', 'blue'],
          'ratio': 0.5,
          'ok': false,
        },
      },
    );
    // Typed nothing where it must: not sent as given.
    expect(
      elicitationResult(
        fields,
        const QuestionAnswer([
          [elicitationTypeHere],
          ['Small'],
        ]),
      ),
      {'action': 'cancel'},
    );
    expect(elicitationResult(fields, const QuestionAnswer([], skipped: true)), {
      'action': 'cancel',
    });
  });

  test('a confirmation: accepted or declined', () {
    final questions = elicitationQuestions('Proceed?', const []);
    expect(questions.single.options.map((o) => o.label), ['Accept', 'Decline']);
    expect(
      elicitationResult(
        const [],
        const QuestionAnswer([
          ['Accept'],
        ]),
      ),
      {'action': 'accept'},
    );
    expect(
      elicitationResult(
        const [],
        const QuestionAnswer([
          ['Decline'],
        ]),
      ),
      {'action': 'decline'},
    );
  });
}
