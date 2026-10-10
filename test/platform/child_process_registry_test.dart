import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/platform/child_process_registry.dart';
import 'package:path/path.dart' as p;

/// The list is written aside and renamed over; nothing written aside is
/// left behind, whatever happens.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('baocode-registry');
    file = File(p.join(dir.path, 'claude-processes.json'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ChildProcessRegistry registry({int ownPid = 4242}) => ChildProcessRegistry(
    file: file,
    ownPid: ownPid,
    lookup: (_) async => null,
    signal: (_) => false,
  );

  List<String> names() =>
      [for (final entity in dir.listSync()) p.basename(entity.path)]..sort();

  test('writes leave nothing aside', () async {
    final processes = registry();
    await processes.add(7, command: 'sleep 30');
    await processes.add(8, command: 'sleep 31');
    await processes.remove(7);
    expect(names(), ['claude-processes.json']);
    expect(jsonDecode(file.readAsStringSync()), [
      {'pid': 8, 'parent': 4242, 'command': 'sleep 31'},
    ]);
  });

  test('a write that fails leaves nothing aside', () async {
    // The list's name taken by a folder: neither rename nor write can do.
    Directory(file.path).createSync();
    File(p.join(file.path, 'inside')).writeAsStringSync('');
    final processes = registry();
    await processes.add(7, command: 'sleep 30');
    await processes.flush();
    expect(names(), ['claude-processes.json']);
  });

  test('files left aside by ended runs are swept, not those being '
      'written', () async {
    final old = DateTime.now().subtract(const Duration(hours: 1));
    File aside(String name, {DateTime? modified}) {
      final aside = File(p.join(dir.path, name))..writeAsStringSync('[]');
      if (modified != null) aside.setLastModifiedSync(modified);
      return aside;
    }

    aside('claude-processes.json.111.tmp', modified: old);
    aside('claude-processes.json.333.4.tmp', modified: old);
    // This process's own, however recent: it is not writing it now.
    aside('claude-processes.json.4242.tmp');
    // Another copy of the app, writing just now.
    aside('claude-processes.json.222.tmp');
    // Not the list's.
    aside('lsp-processes.json.111.tmp', modified: old);
    aside('claude-processes.json.bak', modified: old);

    await registry().reaped;
    expect(names(), [
      'claude-processes.json.222.tmp',
      'claude-processes.json.bak',
      'lsp-processes.json.111.tmp',
    ]);
  });

  test('flush waits for a removal under way', () async {
    final processes = registry();
    await processes.add(7, command: 'sleep 30');
    // As a process's exit does: not awaited.
    processes.remove(7).ignore();
    await processes.flush();
    expect(jsonDecode(file.readAsStringSync()), isEmpty);
  });

  test('flush of a list never used writes nothing', () async {
    await registry().flush();
    expect(names(), isEmpty);
  });
}
