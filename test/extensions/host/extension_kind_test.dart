import 'package:baocode/extensions/host/extension_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deduces kinds like upstream', () {
    expect(extensionKindOf({'publisher': 'a', 'name': 'b', 'main': 'x.js'}), [
      ExtensionKind.workspace,
    ]);
    // A theme runs anywhere.
    expect(
      extensionKindOf({
        'publisher': 'a',
        'name': 'theme',
        'contributes': {'themes': <Object?>[]},
      }),
      ExtensionKind.values,
    );
    // An unknown extension point keeps it on the workspace side.
    expect(
      extensionKindOf({
        'publisher': 'a',
        'name': 'b',
        'contributes': {'typescriptServerPlugins': <Object?>[]},
      }),
      [ExtensionKind.workspace],
    );
    expect(
      extensionKindOf({
        'publisher': 'a',
        'name': 'b',
        'main': 'x.js',
        'extensionKind': 'ui',
      }),
      [ExtensionKind.ui, ExtensionKind.workspace],
    );
    expect(
      extensionKindOf(
        {'publisher': 'A', 'name': 'B', 'main': 'x.js'},
        userConfigured: {
          'a.b': ['ui'],
        },
      ),
      [ExtensionKind.ui],
    );
  });

  test('picks where it runs like nativeExtensionService', () {
    expect(
      pickRunningLocation(
        [ExtensionKind.workspace],
        installedLocally: true,
        installedRemotely: true,
        hasRemoteHost: true,
      ),
      ExtensionRunningLocation.remote,
    );
    expect(
      pickRunningLocation(
        [ExtensionKind.ui, ExtensionKind.workspace],
        installedLocally: true,
        installedRemotely: true,
        hasRemoteHost: true,
      ),
      ExtensionRunningLocation.local,
    );
    expect(
      pickRunningLocation(
        [ExtensionKind.workspace],
        installedLocally: true,
        installedRemotely: false,
        hasRemoteHost: true,
      ),
      isNull,
    );
    expect(
      pickRunningLocation(
        [ExtensionKind.workspace],
        installedLocally: true,
        installedRemotely: false,
        hasRemoteHost: false,
      ),
      ExtensionRunningLocation.local,
    );
  });
}
