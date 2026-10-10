// Extensions' file decorations (mainThreadDecorations.ts,
// decorationsService.ts): asked for in batches, merged across providers,
// bubbling to folders, refreshed on change, and shown in the explorer.

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/decorations/explorer_decorations.dart';
import 'package:baocode/extensions/decorations/file_decorations_service.dart';
import 'package:baocode/extensions/main_thread/main_thread_context.dart';
import 'package:baocode/extensions/main_thread/main_thread_decorations.dart';
import 'package:baocode/ide/git/git_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/scripted_rpc.dart';

void main() {
  late ScriptedRpc rpc;
  late FileDecorationsService service;
  late MainThreadContext context;
  late RpcActor actor;

  /// The extension's decorations by path.
  late Map<String, List<Object?>> provided;

  setUp(() {
    rpc = ScriptedRpc();
    service = FileDecorationsService();
    provided = {};
    rpc.handlers[r'ExtHostDecorations.$provideDecorations'] = (args) {
      final reply = <String, Object?>{};
      for (final request in (args[1] as List).cast<Map<Object?, Object?>>()) {
        final uri = VsUri.revive((request['uri'] as Map).cast());
        if (provided[uri.path] case final data?) {
          reply['${request['id']}'] = data;
        }
      }
      return reply;
    };
    context = MainThreadContext(
      rpc: rpc.protocol,
      services: {FileDecorationsService: service},
    );
    actor = MainThreadDecorations.customer(context);
  });

  tearDown(() async {
    await context.dispose();
    service.dispose();
    rpc.dispose();
  });

  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await pumpEventQueue();
  }

  test('a resource\'s decoration is asked for once, in a batch, and kept', () async {
    provided['/w/a.ts'] = [
      false,
      'Has errors',
      'E',
      {'id': 'list.errorForeground'},
    ];
    await actor.invoke(r'$registerDecorationProvider', [1, 'Errors']);
    expect(service.getDecoration(VsUri.file('/w/a.ts')), isNull);
    expect(service.getDecoration(VsUri.file('/w/b.ts')), isNull);
    var notified = 0;
    service.addListener(() => notified++);
    await settle();
    final calls = rpc.callsTo(r'ExtHostDecorations.$provideDecorations');
    expect(calls, hasLength(1));
    expect((calls.single[1] as List), hasLength(2));
    expect(notified, 1);

    final decoration = service.getDecoration(VsUri.file('/w/a.ts'))!;
    expect(decoration.letter, 'E');
    expect(decoration.colorId, 'list.errorForeground');
    expect(decoration.tooltip, 'Has errors');
    expect(service.getDecoration(VsUri.file('/w/b.ts')), isNull);
    await settle();
    expect(rpc.callsTo(r'ExtHostDecorations.$provideDecorations'), hasLength(1));
  });

  test('changes ask again; providers merge; children bubble to folders', () async {
    await actor.invoke(r'$registerDecorationProvider', [1, 'One']);
    await actor.invoke(r'$registerDecorationProvider', [2, 'Two']);
    provided['/w/src/a.ts'] = [true, 'Changed', 'M', null];
    service.getDecoration(VsUri.file('/w/src/a.ts'));
    await settle();
    final a = service.getDecoration(VsUri.file('/w/src/a.ts'))!;
    // Both providers gave the same: the letters joined, one tooltip.
    expect(a.letter, 'M, M');
    expect(a.tooltip, 'Changed');

    final folder = service.getDecoration(
      VsUri.file('/w/src'),
      includeChildren: true,
    );
    await settle();
    expect(folder, isNotNull);
    expect(
      service
          .getDecoration(VsUri.file('/w/src'), includeChildren: true)!
          .bubbleOnly,
      isTrue,
    );

    provided['/w/src/a.ts'] = [false, 'Renamed', 'R', null];
    await actor.invoke(r'$onDidChange', [
      1,
      [VsUri.file('/w/src/a.ts')],
    ]);
    await settle();
    expect(service.getDecoration(VsUri.file('/w/src/a.ts'))!.letter, 'M, R');

    // All of a provider's: dropped, asked again when shown.
    await actor.invoke(r'$onDidChange', [2, null]);
    await settle();
    expect(service.getDecoration(VsUri.file('/w/src/a.ts'))!.letter, 'R');
    await settle();
    expect(service.getDecoration(VsUri.file('/w/src/a.ts'))!.letter, 'R, R');

    await actor.invoke(r'$unregisterDecorationProvider', [1]);
    await actor.invoke(r'$unregisterDecorationProvider', [2]);
    await settle();
    expect(service.getDecoration(VsUri.file('/w/src/a.ts')), isNull);
  });

  test('the explorer\'s rows: a letter, a folder\'s dot, merged with Git\'s', () async {
    final explorer = ExplorerFileDecorations(service);
    addTearDown(explorer.dispose);
    await actor.invoke(r'$registerDecorationProvider', [1, 'Acme']);
    provided['/w/src/a.ts'] = [
      true,
      'Acme says hi',
      'A',
      {'id': 'charts.blue'},
    ];
    explorer.decorationOf('/w/src/a.ts', isDirectory: false);
    await settle();
    final file = explorer.decorationOf('/w/src/a.ts', isDirectory: false)!;
    expect(file.letter, 'A');
    expect(file.colorId, 'charts.blue');
    final folder = explorer.decorationOf('/w/src', isDirectory: true);
    await settle();
    final dot = explorer.decorationOf('/w/src', isDirectory: true)!;
    expect(folder == null || folder.letter == '•', isTrue);
    expect(dot.letter, '•');
    expect(dot.tooltip, IdeGitDecoration.folderTooltip);

    const git = IdeGitDecoration(
      colorId: 'gitDecoration.modifiedResourceForeground',
      tooltip: 'Modified',
      letter: 'M',
    );
    final merged = git.merge(file);
    expect(merged.letter, 'M, A');
    expect(merged.colorId, 'gitDecoration.modifiedResourceForeground');
    expect(merged.tooltip, 'Modified • Acme says hi');
    expect(
      const IdeGitDecoration(colorId: 'x', tooltip: 't', letter: '•')
          .merge(dot)
          .letter,
      '•',
    );
  });
}
