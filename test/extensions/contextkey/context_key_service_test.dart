// The context key service: the global context with `config.*`, scoped
// contexts, overlays and their change events.

import 'package:baocode/extensions/contextkey/configuration_context.dart';
import 'package:baocode/extensions/contextkey/context_key_service.dart';
import 'package:baocode/extensions/contextkey/contextkey.dart';
import 'package:baocode/extensions/contextkey/workbench_context_keys.dart';
import 'package:baocode/extensions/configuration/configuration_model.dart';
import 'package:baocode/extensions/configuration/configuration_registry.dart';
import 'package:baocode/extensions/configuration/configuration_service.dart';
import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Settings extends ChangeNotifier implements SettingsFile {
  @override
  final Map<String, Object?> values = {};

  @override
  Future<void> write(List<String> path, Object? value) async {
    if (value == null) {
      values.remove(path.last);
    } else {
      values[path.last] = value;
    }
    notifyListeners();
  }
}

void main() {
  test('set, read, remove, and the change events', () {
    final keys = ContextKeyService();
    final events = <String>[];
    keys.onDidChangeContext((e) {
      events.add(e.allKeysContainedIn({'a', 'b'}) ? 'both' : 'other');
    });
    keys.setContext('a', true);
    keys.setContext('a', true); // unchanged: no event
    keys.setContext('b', 'x');
    expect(keys.getContextKeyValue('a'), true);
    expect(keys.getContextKeyValue('b'), 'x');
    keys.removeContext('a');
    expect(keys.getContextKeyValue('a'), isNull);
    expect(events, ['both', 'both', 'both']);
    expect(
      keys.contextMatchesRules(ContextKeyExpr.deserialize("b == 'x'")),
      isTrue,
    );
  });

  test('the platform constants are set', () {
    final keys = ContextKeyService();
    expect(keys.getContextKeyValue('isMac'), isNotNull);
    expect(keys.getContextKeyValue('isWeb'), isFalse);
  });

  test('a scoped service hides the parent\'s keys and forwards changes', () {
    final root = ContextKeyService()..setContext('view', 'explorer');
    final scoped = root.createScoped()..setContext('view', 'search');
    final events = <String>[];
    scoped.onDidChangeContext((e) => events.add('scoped'));
    expect(scoped.getContextKeyValue('view'), 'search');
    expect(root.getContextKeyValue('view'), 'explorer');
    // A key the scoped one sets hides the parent's...
    expect(scoped.contextMatchesRules(ContextKeyExpr.deserialize("view == 'search'")), isTrue);
    // ...and the parent's changes reach it.
    root.setContext('other', 1);
    expect(events, hasLength(1));
    scoped.dispose();
    expect(scoped.getContextKeyValue('view'), isNull);
  });

  test('an overlay replaces values for one evaluation', () {
    final keys = ContextKeyService()
      ..setContext('viewItem', 'file')
      ..setContext('scmResourceState', 'modified');
    final overlay = keys.createOverlay({
      'viewItem': 'folder',
      'scmResourceState': 'untracked',
    });
    expect(
      overlay.contextMatchesRules(
        ContextKeyExpr.deserialize("viewItem == 'folder'"),
      ),
      isTrue,
    );
    expect(keys.getContextKeyValue('viewItem'), 'file');
    expect(
      overlay.contextMatchesRules(
        ContextKeyExpr.deserialize("scmResourceState == 'untracked'"),
      ),
      isTrue,
    );
  });

  test('bufferChangeEvents: one event for many keys', () {
    final keys = ContextKeyService();
    var count = 0;
    keys.onDidChangeContext((_) => count++);
    keys.bufferChangeEvents(() {
      keys.setContext('a', 1);
      keys.setContext('b', 2);
    });
    expect(count, 1);
  });

  test('config.* keys come from the settings, and change', () async {
    final configuration = ConfigurationService(
      registry: ConfigurationRegistry(),
      user: _Settings(),
    );
    final keys = ContextKeyService(
      configuration: ConfigurationContextKeys(configuration),
    );
    final events = <bool>[];
    keys.onDidChangeContext(
      (e) => events.add(e.affectsSome({'config.editor.fontSize'})),
    );
    expect(keys.getContextKeyValue('config.editor.fontSize'), isNull);
    await configuration.update('editor.fontSize', 15, target: ConfigurationTarget.user);
    expect(keys.getContextKeyValue('config.editor.fontSize'), 15);
    expect(events, contains(true));
    expect(
      keys.contextMatchesRules(
        ContextKeyExpr.deserialize('config.editor.fontSize == 15'),
      ),
      isTrue,
    );
    await configuration.update('editor.fontSize', 17, target: ConfigurationTarget.user);
    expect(keys.getContextKeyValue('config.editor.fontSize'), 17);
  });

  test('config.* keys from settings given after construction', () async {
    final configuration = ConfigurationService(
      registry: ConfigurationRegistry(),
      user: _Settings(),
    );
    await configuration.update('ext.views', {
      'commits': true,
    }, target: ConfigurationTarget.user);
    final keys = ContextKeyService();
    final changed = <bool>[];
    keys.onDidChangeContext(
      (e) => changed.add(e.affectsSome({'config.ext.views.commits'})),
    );
    expect(keys.getContextKeyValue('config.ext.views.commits'), isNull);

    keys.configuration = ConfigurationContextKeys(configuration);
    expect(changed, [true]);
    // A property of an object setting, as upstream's `getValue` reads it.
    expect(keys.getContextKeyValue('config.ext.views.commits'), isTrue);
    await configuration.update('ext.views', {
      'commits': false,
    }, target: ConfigurationTarget.user);
    expect(keys.getContextKeyValue('config.ext.views.commits'), isFalse);

    keys.configuration = null;
    expect(keys.getContextKeyValue('config.ext.views.commits'), isNull);
  });

  test('arrays in settings read as JSON text', () async {
    final configuration = ConfigurationService(
      registry: ConfigurationRegistry(),
      user: _Settings(),
    );
    final keys = ContextKeyService(
      configuration: ConfigurationContextKeys(configuration),
    );
    await configuration.update('ext.list', ['a', 'b'], target: ConfigurationTarget.user);
    expect(keys.getContextKeyValue('config.ext.list'), '["a","b"]');
  });

  test('the workbench feeds the well-known keys', () {
    final keys = ContextKeyService();
    final feed = WorkbenchContextKeys(keys);
    feed.setWorkspace(folderCount: 2, state: 'workspace');
    feed.setActiveEditor(
      resource: VsUri.file('/proj/src/main.dart'),
      languageId: 'dart',
      editorId: 'workbench.editors.files.textFileEditor',
      dirty: true,
    );
    feed.setFocus(editorTextFocus: true, editorFocus: true, textInputFocus: true);
    feed.setEditorSelection(hasSelection: true);
    feed.setLayout(
      sideBarVisible: true,
      panelVisible: false,
      activeViewlet: 'workbench.view.explorer',
    );
    feed.setDebug(inDebugMode: true, debugType: 'dart', debugState: 'running');
    bool when(String clause) =>
        keys.contextMatchesRules(ContextKeyExpr.deserialize(clause));
    expect(when("workspaceFolderCount == 2 && workbenchState == 'workspace'"), isTrue);
    expect(when("resourceFilename == 'main.dart'"), isTrue);
    expect(when("resourceExtname == '.dart'"), isTrue);
    expect(when("resourceDirname == '/proj/src'"), isTrue);
    expect(when("resourceLangId == 'dart' && editorLangId == 'dart'"), isTrue);
    expect(when('editorTextFocus && editorFocus && textInputFocus'), isTrue);
    expect(when('editorHasSelection && activeEditorIsDirty'), isTrue);
    expect(when('explorerViewletVisible && sideBarVisible && !panelVisible'), isTrue);
    expect(when("activeViewlet == 'workbench.view.explorer'"), isTrue);
    expect(when("inDebugMode && debugType == 'dart' && debugState == 'running'"), isTrue);
    expect(when('isFileSystemResource && resourceSet'), isTrue);
    expect(when("resourceScheme == 'file'"), isTrue);
    // Closing the editor clears them.
    feed.setActiveEditor();
    expect(keys.getContextKeyValue('resourceSet'), isFalse);
    expect(keys.getContextKeyValue('editorLangId'), isNull);
  });

  test('the fallback reads what the workbench computes lazily', () {
    final keys = ContextKeyService();
    final state = <String, Object?>{'editorReadonly': true};
    keys.fallback = (key) => state[key];
    var changes = 0;
    keys.onDidChangeContext((_) => changes++);
    expect(
      keys.contextMatchesRules(ContextKeyExpr.deserialize('editorReadonly')),
      isTrue,
    );
    keys.notifyExternalChange();
    expect(changes, 1);
    // What this service holds wins over the fallback.
    keys.setContext('editorReadonly', false);
    expect(
      keys.contextMatchesRules(ContextKeyExpr.deserialize('editorReadonly')),
      isFalse,
    );
  });

  test('resourceContextKeys of an explorer item', () {
    expect(
      resourceContextKeys(VsUri.file('/proj/README.md')),
      containsPair('resourceFilename', 'README.md'),
    );
    expect(
      resourceContextKeys(null)[WorkbenchContextKeyNames.resourceSet],
      isFalse,
    );
  });

  test('stringifyUris turns marshalled URIs into strings', () {
    expect(
      stringifyUris(VsUri.file('/tmp/a b').toJson()),
      'file:///tmp/a%20b',
    );
    expect(
      stringifyUris({
        'uri': VsUri.file('/x').toJson(),
        'list': [
          VsUri.file('/y').toJson(),
        ],
      }),
      {
        'uri': 'file:///x',
        'list': ['file:///y'],
      },
    );
  });

  test('change events say which keys they affect', () {
    final keys = ContextKeyService();
    ContextKeyChangeEvent? event;
    keys.onDidChangeContext((e) => event = e);
    keys.setContext('a', 1);
    expect(event!.affectsSome({'a'}), isTrue);
    expect(event!.affectsSome({'b'}), isFalse);
    expect(event!.allKeysContainedIn({'a', 'b'}), isTrue);
  });
}
