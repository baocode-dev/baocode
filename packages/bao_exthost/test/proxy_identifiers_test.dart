// The generated proxy identifiers against the shipped extension host: its
// compiled `createProxyIdentifier` calls, in the order they run, are the
// numbers on the wire.

import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:test/test.dart';

/// The pinned REH's compiled extension host (override with EXTHOST_BUNDLE).
final _bundle =
    Platform.environment['EXTHOST_BUNDLE'] ??
    '/tmp/exthost-dl/reh-darwin-arm64/out/vs/workbench/api/node/extensionHostProcess.js';

void main() {
  test('numbers are 1.., MainContext then ExtHostContext', () {
    final all = [...MainContext.all, ...ExtHostContext.all];
    expect(
      [for (final id in all) id.nid],
      [for (var i = 1; i <= all.length; i++) i],
    );
    expect(proxyIdentifierNames, {for (final id in all) id.nid: id.sid});
    expect(all, hasLength(168));
    expect(MainContext.mainThreadCommands.nid, 10);
    // Keys and names can differ.
    expect(
      MainContext.mainThreadLanguageModelTools.sid,
      'MainThreadChatSkills',
    );
    expect(
      MainContext.mainThreadLanguageModelTools.key,
      'MainThreadLanguageModelTools',
    );
  });

  test(
    'numbers match the compiled extension host',
    () {
      final text = File(_bundle).readAsStringSync();
      // `KEY:N("SID")`, all with one factory, in the two literals.
      final calls = RegExp(
        r'''[{,]((?:MainThread|ExtHost)\w*):([\w$]+)\("((?:MainThread|ExtHost)\w*)"\)''',
      ).allMatches(text).toList();
      final factories = {for (final m in calls) m[2]};
      expect(factories, hasLength(1), reason: 'one createProxyIdentifier');
      // The factory numbers identifiers in creation order.
      expect(
        text.replaceAll(RegExp(r'\s'), ''),
        contains('_proxyIdentifierBrand=void0'),
      );
      expect(text, matches(RegExp(r'this\.nid=\+\+\w+\.count')));
      final bundle = [
        for (final (i, m) in calls.indexed) (i + 1, m[1]!, m[3]!),
      ];
      final ours = [
        for (final id in [...MainContext.all, ...ExtHostContext.all])
          (id.nid, id.key, id.sid),
      ];
      expect(ours, bundle);
    },
    skip: File(_bundle).existsSync()
        ? false
        : 'No extension host bundle at $_bundle (download the pinned VSCodium '
              'REH, see docs/extensions/PROGRESS.md, or set EXTHOST_BUNDLE)',
  );
}
