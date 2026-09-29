import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/vs/platform/undo_redo/common/undo_redo_service.dart';

class Operation implements UndoRedoResourceElement {
  Operation(this.resource, this.label, this.log);
  @override
  final Uri resource;
  @override
  final String label;
  final List<String> log;
  bool fail = false;

  @override
  void undo() {
    if (fail) throw StateError('undo failed');
    log.add('undo $label');
  }

  @override
  void redo() {
    if (fail) throw StateError('redo failed');
    log.add('redo $label');
  }
}

void main() {
  test('grouped resource elements undo newest-first and redo oldest-first', () {
    final service = UndoRedoService();
    final log = <String>[];
    final one = Uri.parse('file:///one');
    final two = Uri.parse('file:///two');
    final group = UndoRedoGroup();
    service.pushElement(Operation(one, 'first', log), group: group);
    service.pushElement(Operation(two, 'second', log), group: group);
    service.pushElement(Operation(one, 'third', log), group: group);
    expect(service.undo(two), isTrue);
    expect(log, ['undo third', 'undo second', 'undo first']);
    expect(service.getElements(one).past, isEmpty);
    expect(service.getElements(two).future, hasLength(1));
    expect(service.redo(one), isTrue);
    expect(log.sublist(3), ['redo first', 'redo second', 'redo third']);
    expect(service.getElements(one).future, isEmpty);
  });

  test(
    'ungrouped elements undo individually and resource keys use URI value',
    () {
      final service = UndoRedoService();
      final log = <String>[];
      final uri = Uri.parse('file:///resource');
      service.pushElement(Operation(uri, 'one', log));
      service.pushElement(Operation(Uri.parse('file:///resource'), 'two', log));
      expect(service.getLastElement(uri)!.label, 'two');
      expect(service.undo(uri), isTrue);
      expect(log, ['undo two']);
      expect(service.getLastElement(uri), isNull);
      expect(service.getElements(uri).past.single.label, 'one');
      expect(service.redo(uri), isTrue);
      expect(log, ['undo two', 'redo two']);
      service.removeElements(uri);
      expect(service.canUndo(uri), isFalse);
      expect(service.undo(uri), isFalse);
    },
  );

  test('divergent redo history is discarded only for the pushed resource', () {
    final service = UndoRedoService();
    final log = <String>[];
    final one = Uri.parse('file:///one');
    final two = Uri.parse('file:///two');
    service.pushElement(Operation(one, 'first', log));
    service.pushElement(Operation(two, 'second', log));
    service.undo(one);
    service.undo(two);
    service.pushElement(Operation(one, 'fork', log));
    expect(service.canRedo(one), isFalse);
    expect(service.canRedo(two), isTrue);
  });

  test('claimed resources cannot accept unrelated elements', () {
    final service = UndoRedoService();
    final resource = Uri.parse('file:///owned');
    final other = Uri.parse('file:///other');
    final owner = Object();
    final log = <String>[];
    service.claimResource(resource, owner);
    expect(() => service.claimResource(resource, Object()), throwsStateError);
    expect(
      () => service.pushElement(Operation(resource, 'intruder', log)),
      throwsStateError,
    );
    service.pushElement(Operation(resource, 'mine', log), owner: owner);
    service.pushElement(Operation(other, 'unrelated', log));
    service.removeElements(resource);
    expect(() => service.claimResource(resource, Object()), throwsStateError);
    service.releaseResource(resource, owner);
    service.claimResource(resource, Object());
    expect(service.canUndo(other), isTrue);
  });

  test('failed callbacks keep history in place', () {
    final service = UndoRedoService();
    final log = <String>[];
    final uri = Uri.parse('file:///error');
    final operation = Operation(uri, 'first', log)..fail = true;
    service.pushElement(operation);
    expect(() => service.undo(uri), throwsStateError);
    expect(service.canUndo(uri), isTrue);
    expect(service.canRedo(uri), isFalse);
    operation.fail = false;
    expect(service.undo(uri), isTrue);
    operation.fail = true;
    expect(() => service.redo(uri), throwsStateError);
    expect(service.canRedo(uri), isTrue);
  });
}
