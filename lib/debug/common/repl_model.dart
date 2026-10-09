/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The Debug Console's content: output of the debuggee and the adapter
// (identical lines collapsed, groups), expressions typed and their
// results.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/common/replModel.ts.
//
// Deviations: the console settings (`debug.console.collapseIdenticalLines`,
// `debug.console.maximumLines`) are passed in as [ReplSettings].

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../base/event.dart';
import '../session/debug_session.dart';
import 'debug_model.dart';
import 'debug_types.dart';

/// An element of the console (`IReplElement`).
abstract interface class ReplElement implements DebugTreeElement {
  @override
  String toString();
}

/// An element with children (`INestingReplElement`).
abstract interface class NestingReplElement implements ReplElement {
  bool get hasChildren;
  Future<List<Object>> getChildren();
}

/// `debug.console.*` settings.
final class ReplSettings {
  const ReplSettings({this.collapseIdenticalLines = true, this.maximumLines = 10000});

  final bool collapseIdenticalLines;
  final int maximumLines;
}

int _topReplElementCounter = 0;
String _uniqueId() => 'topReplElement:${_topReplElementCounter++}';

/// Output of a DAP `output` event (`ReplOutputElement`).
class ReplOutputElement implements NestingReplElement {
  ReplOutputElement(
    this.session,
    this._id,
    this.value,
    this.severity, {
    this.sourceData,
    this.expression,
  });

  final DebugSession session;
  final String _id;
  final String value;
  final ReplSeverity severity;
  final ReplElementSource? sourceData;
  final DebugExpression? expression;
  int count = 1;

  @override
  String toString({bool includeSource = false}) {
    var withCount = value;
    for (var i = 1; i < count; i++) {
      withCount += (withCount.endsWith('\n') ? '' : '\n') + value;
    }
    return withCount;
  }

  @override
  String getId() => _id;

  @override
  Future<List<Object>> getChildren() async => await expression?.getChildren() ?? [];

  @override
  bool get hasChildren => expression?.hasChildren ?? false;
}

/// A variable logged without output text (`ReplVariableElement`).
class ReplVariableElement implements NestingReplElement {
  ReplVariableElement(this._session, this.expression, this.severity, [this.sourceData])
    : hasChildren = expression.hasChildren;

  final DebugSession _session;
  final DebugExpression expression;
  final ReplSeverity severity;
  final ReplElementSource? sourceData;
  @override
  final bool hasChildren;
  final String _id = generateUuid();

  DebugSession getSession() => _session;

  @override
  Future<List<Object>> getChildren() async => await expression.getChildren();

  @override
  String toString() => expression.toString();

  @override
  String getId() => _id;
}

/// A JSON value shown as a tree (`RawObjectReplElement`).
class RawObjectReplElement implements DebugExpression, NestingReplElement {
  RawObjectReplElement(this._id, this.name, this.valueObj, {this.sourceData, this.annotation});

  static const _maxChildren = 1000;

  final String _id;
  @override
  final String name;
  final Object? valueObj;
  final ReplElementSource? sourceData;
  final String? annotation;

  @override
  String getId() => _id;

  @override
  DebugSession? getSession() => null;

  @override
  String get value => switch (valueObj) {
    null => 'null',
    final List l => 'Array[${l.length}]',
    Map() => 'Object',
    final String s => '"$s"',
    final other => '$other',
  };

  @override
  bool get hasChildren => switch (valueObj) {
    final List l => l.isNotEmpty,
    final Map m => m.isNotEmpty,
    _ => false,
  };

  @override
  String? get type => null;
  @override
  bool get valueChanged => false;
  @override
  String? get memoryReference => null;
  @override
  Json? get presentationHint => null;

  @override
  Future<void> evaluateLazy() => throw UnimplementedError('Method not implemented.');

  @override
  Future<List<DebugExpression>> getChildren() async => switch (valueObj) {
    final List l => [
      for (final (i, v) in l.take(_maxChildren).indexed) RawObjectReplElement('$_id:$i', '$i', v),
    ],
    final Map m => [
      for (final (i, key) in m.keys.take(_maxChildren).indexed)
        RawObjectReplElement('$_id:$i', '$key', m[key]),
    ],
    _ => [],
  };

  @override
  String toString() => '$name\n$value';
}

/// What was typed in the console (`ReplEvaluationInput`).
class ReplEvaluationInput implements ReplElement {
  ReplEvaluationInput(this.value);

  final String value;
  final String _id = generateUuid();

  @override
  String toString() => value;

  @override
  String getId() => _id;
}

/// Its result (`ReplEvaluationResult`).
class ReplEvaluationResult extends ExpressionContainer implements ReplElement, DebugExpression {
  ReplEvaluationResult(this.originalExpression) : super(null, null, 0, generateUuid());

  final String originalExpression;
  bool _available = true;

  bool get available => _available;

  @override
  String get name => '';

  @override
  Future<bool> evaluateExpression(
    String expression,
    DebugSession? session,
    StackFrame? stackFrame,
    String context, {
    bool keepLazyVars = false,
    ({int line, int column, Json source})? location,
  }) async {
    final result = await super.evaluateExpression(expression, session, stackFrame, context);
    _available = result;
    return result;
  }

  @override
  String toString() => value;
}

/// Output grouped by `group: start` … `end` (`ReplGroup`).
class ReplGroup implements NestingReplElement {
  ReplGroup(this.session, this.name, this.autoExpand, [this.sourceData])
    : _id = 'replGroup:${counter++}';

  static int counter = 0;

  final DebugSession session;
  String name;
  final bool autoExpand;
  final ReplElementSource? sourceData;
  final String _id;
  final List<ReplElement> _children = [];
  bool _ended = false;

  @override
  bool get hasChildren => true;

  @override
  String getId() => _id;

  @override
  String toString({bool includeSource = false}) => name;

  void addChild(ReplElement child) {
    final last = _children.isNotEmpty ? _children.last : null;
    if (last is ReplGroup && !last.hasEnded) {
      last.addChild(child);
    } else {
      _children.add(child);
    }
  }

  @override
  Future<List<Object>> getChildren() async => _children;

  List<ReplElement> get children => _children;

  void end() {
    final last = _children.isNotEmpty ? _children.last : null;
    if (last is ReplGroup && !last.hasEnded) {
      last.end();
    } else {
      _ended = true;
    }
  }

  bool get hasEnded => _ended;
}

bool _areSourcesEqual(ReplElementSource? first, ReplElementSource? second) {
  if (first == null && second == null) return true;
  if (first != null && second != null) {
    return first.column == second.column &&
        first.lineNumber == second.lineNumber &&
        identical(first.source, second.source);
  }
  return false;
}

/// New output for the console (`INewReplElementData`).
final class NewReplElementData {
  const NewReplElementData({
    required this.output,
    this.expression,
    required this.sev,
    this.source,
  });

  final String output;
  final DebugExpression? expression;
  final ReplSeverity sev;
  final ReplElementSource? source;
}

class ReplModel extends ChangeNotifier {
  ReplModel([this.settings = _defaultSettings]);

  static ReplSettings _defaultSettings() => const ReplSettings();

  final ReplSettings Function() settings;
  List<ReplElement> _replElements = [];
  final Emitter<ReplElement?> _onDidChangeElements = Emitter();
  bool _disposed = false;

  DebugDisposable onDidChangeElements(void Function(ReplElement?) listener) =>
      _onDidChangeElements.listen(listener);

  void _changed(ReplElement? element) {
    _onDidChangeElements.fire(element);
    if (!_disposed) notifyListeners();
  }

  List<ReplElement> getReplElements() => _replElements;

  Future<void> addReplExpression(
    DebugSession session,
    StackFrame? stackFrame,
    String expression,
  ) async {
    _addReplElement(ReplEvaluationInput(expression));
    final result = ReplEvaluationResult(expression);
    await result.evaluateExpression(expression, session, stackFrame, 'repl');
    _addReplElement(result);
  }

  void appendToRepl(DebugSession session, NewReplElementData data) {
    var output = data.output;
    const clearAnsiSequence = '\u001b[2J';
    final clearIndex = output.lastIndexOf(clearAnsiSequence);
    if (clearIndex != -1) {
      removeReplExpressions();
      appendToRepl(
        session,
        const NewReplElementData(output: 'Console was cleared', sev: ReplSeverity.ignore),
      );
      output = output.substring(clearIndex + clearAnsiSequence.length);
    }
    final expression = data.expression;
    if (expression != null) {
      // The adapter's output text, where it has one, may be formatted.
      _addReplElement(
        output.isNotEmpty
            ? ReplOutputElement(
                session,
                _uniqueId(),
                output,
                data.sev,
                sourceData: data.source,
                expression: expression,
              )
            : ReplVariableElement(session, expression, data.sev, data.source),
      );
      return;
    }
    _appendOutputToRepl(session, output, data.sev, data.source);
  }

  void _appendOutputToRepl(
    DebugSession session,
    String output,
    ReplSeverity sev,
    ReplElementSource? source,
  ) {
    final config = settings();
    final previous = _replElements.isNotEmpty ? _replElements.last : null;

    // An incomplete line goes on with this output.
    if (previous is ReplOutputElement &&
        previous.severity == sev &&
        _areSourcesEqual(previous.sourceData, source)) {
      if (!previous.value.endsWith('\n') && previous.count == 1) {
        final combined = previous.value + output;
        _replElements[_replElements.length - 1] = ReplOutputElement(
          session,
          _uniqueId(),
          combined,
          sev,
          sourceData: source,
        );
        _changed(null);
        if (config.collapseIdenticalLines && combined.endsWith('\n')) {
          _tryCollapseCompleteLine(sev, source);
        }
        if (config.collapseIdenticalLines && combined.contains('\n')) {
          if (_splitIntoLines(combined).length > 1) {
            _applyLineLevelCollapsing(session, sev, source);
          }
        }
        return;
      }
    }

    if (config.collapseIdenticalLines && output.contains('\n')) {
      _processMultiLineOutput(session, output, sev, source);
    } else {
      if (previous is ReplOutputElement &&
          previous.severity == sev &&
          _areSourcesEqual(previous.sourceData, source) &&
          previous.value == output &&
          config.collapseIdenticalLines) {
        previous.count++;
        _changed(null);
        return;
      }
      _addReplElement(ReplOutputElement(session, _uniqueId(), output, sev, sourceData: source));
    }
  }

  void _tryCollapseCompleteLine(ReplSeverity sev, ReplElementSource? source) {
    if (_replElements.length < 2) return;
    final last = _replElements[_replElements.length - 1];
    final secondToLast = _replElements[_replElements.length - 2];
    if (last is ReplOutputElement &&
        secondToLast is ReplOutputElement &&
        last.severity == sev &&
        secondToLast.severity == sev &&
        _areSourcesEqual(last.sourceData, source) &&
        _areSourcesEqual(secondToLast.sourceData, source) &&
        last.value == secondToLast.value &&
        last.count == 1 &&
        last.value.endsWith('\n')) {
      secondToLast.count += last.count;
      _replElements.removeLast();
      _changed(null);
    }
  }

  void _processMultiLineOutput(
    DebugSession session,
    String output,
    ReplSeverity sev,
    ReplElementSource? source,
  ) {
    for (final line in _splitIntoLines(output)) {
      if (line.isEmpty) continue;
      final previous = _replElements.isNotEmpty ? _replElements.last : null;
      if (previous is ReplOutputElement &&
          previous.severity == sev &&
          _areSourcesEqual(previous.sourceData, source) &&
          previous.value == line) {
        previous.count++;
        _changed(null);
      } else {
        _addReplElement(ReplOutputElement(session, _uniqueId(), line, sev, sourceData: source));
      }
    }
  }

  List<String> _splitIntoLines(String text) {
    final lines = <String>[];
    var start = 0;
    while (start < text.length) {
      final nextLF = text.indexOf('\n', start);
      if (nextLF == -1) {
        lines.add(text.substring(start));
        break;
      }
      lines.add(text.substring(start, nextLF + 1));
      start = nextLF + 1;
    }
    return lines;
  }

  void _applyLineLevelCollapsing(DebugSession session, ReplSeverity sev, ReplElementSource? source) {
    final last = _replElements.isNotEmpty ? _replElements.last : null;
    if (last is! ReplOutputElement || last.severity != sev || !_areSourcesEqual(last.sourceData, source)) {
      return;
    }
    final lines = _splitIntoLines(last.value);
    if (lines.length <= 1) return;
    _replElements.removeLast();
    for (final line in lines) {
      if (line.isEmpty) continue;
      final previous = _replElements.isNotEmpty ? _replElements.last : null;
      if (previous is ReplOutputElement &&
          previous.severity == sev &&
          _areSourcesEqual(previous.sourceData, source) &&
          previous.value == line) {
        previous.count++;
      } else {
        _replElements.add(ReplOutputElement(session, _uniqueId(), line, sev, sourceData: source));
      }
    }
    _changed(null);
  }

  void startGroup(DebugSession session, String name, bool autoExpand, [ReplElementSource? sourceData]) {
    _addReplElement(ReplGroup(session, name, autoExpand, sourceData));
  }

  void endGroup() {
    final last = _replElements.isNotEmpty ? _replElements.last : null;
    if (last is ReplGroup) {
      last.end();
      _changed(null);
    }
  }

  void _addReplElement(ReplElement element) {
    final last = _replElements.isNotEmpty ? _replElements.last : null;
    if (last is ReplGroup && !last.hasEnded) {
      last.addChild(element);
    } else {
      _replElements.add(element);
      final max = settings().maximumLines;
      if (_replElements.length > max) {
        _replElements.removeRange(0, _replElements.length - max);
      }
    }
    _changed(element);
  }

  void removeReplExpressions() {
    if (_replElements.isNotEmpty) {
      _replElements = [];
      _changed(null);
    }
  }

  /// A copy of this model (`clone`).
  ReplModel clone() => ReplModel(settings).._replElements = List.of(_replElements);

  @override
  void dispose() {
    _disposed = true;
    _onDidChangeElements.dispose();
    super.dispose();
  }
}
