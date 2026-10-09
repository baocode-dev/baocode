import 'dart:convert';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/trust/workspace_trust.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Storage implements WorkspaceTrustStorage {
  _Storage([this.contents]);

  String? contents;
  int writes = 0;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String contents) async {
    this.contents = contents;
    writes++;
  }
}

final class _Prompt implements WorkspaceTrustPrompt {
  bool startupTrust = true;
  bool trustParent = false;

  /// The button type [request] answers with.
  String? answer = 'ContinueWithTrust';
  bool resourceTrust = true;

  @override
  bool canManage = true;
  bool managed = false;
  final startupLabels = <String?>[];
  final requests = <List<WorkspaceTrustRequestButton>>[];
  final resources = <VsUri>[];

  @override
  void manage() => managed = true;

  @override
  Future<({bool trust, bool trustParent})> startup({
    required bool workspace,
    required String label,
    String? parentFolderName,
  }) async {
    startupLabels.add(parentFolderName);
    return (trust: startupTrust, trustParent: trustParent);
  }

  @override
  Future<String?> request({
    required bool workspace,
    String? message,
    required List<WorkspaceTrustRequestButton> buttons,
  }) async {
    requests.add(buttons);
    return answer;
  }

  @override
  Future<bool> resource(VsUri uri, {String? message}) async {
    resources.add(uri);
    return resourceTrust;
  }
}

void main() {
  final folder = VsUri.file('/work/project');
  final parent = VsUri.file('/work');

  ({WorkspaceTrustService trust, _Storage storage, _Prompt prompt}) build({
    String? stored,
    List<VsUri>? folders,
    Object? Function(String)? setting,
    bool isMultiRoot = false,
  }) {
    final storage = _Storage(stored);
    final prompt = _Prompt();
    final trust = WorkspaceTrustService(
      store: WorkspaceTrustStore(storage),
      workspaceUris: () => folders ?? [folder],
      workspaceId: 'id',
      isMultiRoot: isMultiRoot,
      setting: setting ?? (_) => null,
    )..prompt = prompt;
    return (trust: trust, storage: storage, prompt: prompt);
  }

  test('an unknown folder is untrusted; a trusted parent makes it trusted',
      () async {
    final b = build();
    await b.trust.initialize();
    expect(b.trust.isWorkspaceTrusted, isFalse);

    await b.trust.setWorkspaceTrust(true);
    expect(b.trust.isWorkspaceTrusted, isTrue);
    expect(
      jsonDecode(b.storage.contents!)['uriTrustInfo'],
      [
        {'uri': folder.toJson(), 'trusted': true},
      ],
    );

    // A folder under a trusted parent is trusted too.
    final under = build(
      stored: jsonEncode({
        'uriTrustInfo': [
          {'uri': parent.toJson(), 'trusted': true},
        ],
      }),
      folders: [VsUri.file('/work/other')],
    );
    await under.trust.initialize();
    expect(under.trust.isWorkspaceTrusted, isTrue);
    expect(
      under.trust.getUriTrustInfo(VsUri.file('/elsewhere')).trusted,
      isFalse,
    );
  });

  test('a multi-folder workspace is trusted when all its folders are',
      () async {
    final storage = _Storage(
      jsonEncode({
        'uriTrustInfo': [
          {'uri': folder.toJson(), 'trusted': true},
        ],
      }),
    );
    final trust = WorkspaceTrustService(
      store: WorkspaceTrustStore(storage),
      workspaceUris: () => [folder, VsUri.file('/work/other')],
      workspaceId: 'id',
      isMultiRoot: true,
    );
    await trust.initialize();
    expect(trust.isWorkspaceTrusted, isFalse);

    await trust.setWorkspaceTrust(true);
    expect(trust.isWorkspaceTrusted, isTrue);
  });

  test('an untrusted workspace asks at startup, once by default', () async {
    final b = build();
    b.prompt.startupTrust = false;
    await b.trust.initialize();
    await b.trust.showStartupPromptIfNeeded(label: 'project');
    expect(b.trust.isWorkspaceTrusted, isFalse);
    expect(b.prompt.startupLabels.single, 'work');
    expect(jsonDecode(b.storage.contents!)['startupPromptShown'], ['id']);

    // Again: not asked a second time.
    final again = build(stored: b.storage.contents);
    again.prompt.startupTrust = false;
    await again.trust.initialize();
    await again.trust.showStartupPromptIfNeeded(label: 'project');
    expect(again.prompt.startupLabels, isEmpty);

    // With `always`, asked every time.
    final always = build(
      stored: b.storage.contents,
      setting: (key) => key == 'security.workspace.trust.startupPrompt'
          ? 'always'
          : null,
    );
    await always.trust.initialize();
    await always.trust.showStartupPromptIfNeeded(label: 'project');
    expect(always.prompt.startupLabels, hasLength(1));

    // With `never`, not asked.
    final never = build(
      setting: (key) =>
          key == 'security.workspace.trust.startupPrompt' ? 'never' : null,
    );
    never.prompt.startupTrust = false;
    await never.trust.initialize();
    await never.trust.showStartupPromptIfNeeded(label: 'project');
    expect(never.prompt.startupLabels, isEmpty);
  });

  test('the startup checkbox trusts the parent folder instead', () async {
    final b = build();
    b.prompt
      ..startupTrust = true
      ..trustParent = true;
    await b.trust.initialize();
    await b.trust.showStartupPromptIfNeeded(label: 'project');
    expect(b.trust.isWorkspaceTrusted, isTrue);
    final info = jsonDecode(b.storage.contents!)['uriTrustInfo'] as List;
    expect((info.single as Map)['uri'], parent.toJson());
  });

  test('trust can be turned off (the feature disabled)', () async {
    final b = build(
      setting: (key) => key == 'security.workspace.trust.enabled' ? false : null,
    );
    await b.trust.initialize();
    expect(b.trust.isWorkspaceTrusted, isTrue);
    expect(b.trust.canSetWorkspaceTrust, isFalse);
  });

  test('an extension\'s request asks, then remembers', () async {
    final b = build();
    await b.trust.initialize();
    final first = b.trust.requestWorkspaceTrust(message: 'Want to run tests?');
    await pumpEventQueue();
    expect(b.prompt.requests.single.map((button) => button.type), [
      'ContinueWithTrust',
      'Manage',
      'Cancel',
    ]);
    expect(await first, isTrue);
    expect(b.trust.isWorkspaceTrusted, isTrue);

    // A second request answers true at once.
    expect(await b.trust.requestWorkspaceTrust(), isTrue);
    expect(b.prompt.requests, hasLength(1));
  });

  test('a cancelled request answers null, and leaves trust as it was',
      () async {
    final b = build();
    b.prompt.answer = 'Cancel';
    await b.trust.initialize();
    expect(await b.trust.requestWorkspaceTrust(), isNull);
    expect(b.trust.isWorkspaceTrusted, isFalse);
  });

  test('"Manage" answers null and opens the settings', () async {
    final b = build();
    b.prompt.answer = 'Manage';
    await b.trust.initialize();
    expect(await b.trust.requestWorkspaceTrust(), isNull);
    expect(b.prompt.managed, isTrue);
  });

  test('two requests at once share one dialog', () async {
    final b = build();
    await b.trust.initialize();
    final one = b.trust.requestWorkspaceTrust();
    final two = b.trust.requestWorkspaceTrust();
    await pumpEventQueue();
    expect(b.prompt.requests, hasLength(1));
    expect(await one, isTrue);
    expect(await two, isTrue);
  });

  test('trusting a resource adds it to the trusted folders', () async {
    final b = build();
    await b.trust.initialize();
    final outside = VsUri.file('/elsewhere/data');
    expect(await b.trust.requestResourcesTrust(outside, message: 'Open?'), isTrue);
    expect(b.prompt.resources, [outside]);
    expect(b.trust.getUriTrustInfo(outside).trusted, isTrue);
    // Already trusted: not asked again.
    expect(await b.trust.requestResourcesTrust(outside), isTrue);
    expect(b.prompt.resources, hasLength(1));

    // Declining answers null and trusts nothing.
    b.prompt.resourceTrust = false;
    final declined = VsUri.file('/elsewhere/other');
    expect(await b.trust.requestResourcesTrust(declined), isNull);
    expect(b.trust.getUriTrustInfo(declined).trusted, isFalse);
  });

  test('a broken storage file trusts nothing', () async {
    final b = build(stored: 'not json at all');
    await b.trust.initialize();
    expect(b.trust.isWorkspaceTrusted, isFalse);
    expect(b.trust.getUriTrustInfo(folder).trusted, isFalse);
  });

  test('untrusting removes the folder again', () async {
    final b = build();
    await b.trust.initialize();
    await b.trust.setWorkspaceTrust(true);
    await b.trust.setWorkspaceTrust(false);
    expect(b.trust.isWorkspaceTrusted, isFalse);
    expect(jsonDecode(b.storage.contents!)['uriTrustInfo'], isEmpty);
  });

  test('extensions are filtered by capabilities.untrustedWorkspaces', () {
    Map<String, Object?> extension(Map<String, Object?>? capabilities) => {
      'publisher': 'pub',
      'name': 'ext',
      'version': '1.0.0',
      'main': './out/extension.js',
      'capabilities': ?capabilities,
    };

    // Without an entry point, an extension always runs.
    expect(
      untrustedWorkspaceSupportType({'publisher': 'pub', 'name': 'ext'}),
      isTrue,
    );
    // `supported: false` (and the default) do not.
    expect(
      untrustedWorkspaceSupportType(
        extension({
          'untrustedWorkspaces': {'supported': false},
        }),
      ),
      isFalse,
    );
    expect(untrustedWorkspaceSupportType(extension(null)), isFalse);
    // `true` and `limited` do.
    expect(
      untrustedWorkspaceSupportType(
        extension({
          'untrustedWorkspaces': {'supported': true},
        }),
      ),
      isTrue,
    );
    expect(
      untrustedWorkspaceSupportType(
        extension({
          'untrustedWorkspaces': {'supported': 'limited'},
        }),
      ),
      'limited',
    );
    // Settings override the manifest (`extensions.supportUntrustedWorkspaces`).
    expect(
      untrustedWorkspaceSupportType(
        extension({
          'untrustedWorkspaces': {'supported': false},
        }),
        configured: {
          'pub.ext': {'supported': true},
        },
      ),
      isTrue,
    );
    // …but only for the version they name.
    expect(
      untrustedWorkspaceSupportType(
        extension({
          'untrustedWorkspaces': {'supported': false},
        }),
        configured: {
          'pub.ext': {'supported': true, 'version': '2.0.0'},
        },
      ),
      isFalse,
    );
    // The product's overrides, when there is no setting.
    expect(
      untrustedWorkspaceSupportType(
        extension({
          'untrustedWorkspaces': {'supported': false},
        }),
        product: {
          'pub.ext': {'override': true},
        },
      ),
      isTrue,
    );
    // With trust off, everything runs.
    expect(
      untrustedWorkspaceSupportType(
        extension({
          'untrustedWorkspaces': {'supported': false},
        }),
        trustEnabled: false,
      ),
      isTrue,
    );

    // What the init data should filter on.
    final manifest = extension({
      'untrustedWorkspaces': {'supported': false},
    });
    expect(runsInWorkspace(manifest, trusted: false), isFalse);
    expect(runsInWorkspace(manifest, trusted: true), isTrue);
  });

  test('the status item shows Restricted Mode while untrusted', () async {
    final b = build();
    await b.trust.initialize();
    expect(b.trust.isWorkspaceTrustEnabled, isTrue);
    expect(b.trust.isWorkspaceTrusted, isFalse);
    await b.trust.setWorkspaceTrust(true);
    expect(b.trust.isWorkspaceTrusted, isTrue);
  });
}
