import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/configuration/configuration_model.dart';
import 'package:baocode/extensions/configuration/configuration_registry.dart';
import 'package:baocode/extensions/configuration/configuration_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

final class _File extends ChangeNotifier implements SettingsFile {
  _File([Map<String, Object?>? values]) : values = values ?? {};

  @override
  Map<String, Object?> values;

  final writes = <List<Object?>>[];

  @override
  Future<void> write(List<String> path, Object? value) async {
    writes.add([...path, value]);
    if (path.length == 1) {
      if (value == null) {
        values.remove(path.single);
      } else {
        values[path.single] = value;
      }
    } else {
      final o = (values[path[0]] as Map<String, Object?>?) ?? {};
      o[path[1]] = value;
      values[path[0]] = o;
    }
    notifyListeners();
  }

  void set(Map<String, Object?> next) {
    values = next;
    notifyListeners();
  }
}

Map<String, Object?> _extension(Map<String, Object?> contributes) => {
  'identifier': {'value': 'pub.ext'},
  'contributes': contributes,
};

void main() {
  test('parses dotted keys and language overrides like upstream', () {
    final model = ConfigurationModel.parse({
      'editor.tabSize': 2,
      'editor.fontSize': 12,
      '[python][cython]': {'editor.tabSize': 4},
    });
    expect(model.contents, {
      'editor': {'tabSize': 2, 'fontSize': 12},
      '[python][cython]': {'editor.tabSize': 4},
    });
    expect(model.keys, ['editor.tabSize', 'editor.fontSize', '[python][cython]']);
    expect(model.overrides.single.identifiers, ['python', 'cython']);
    expect(model.overrides.single.contents, {
      'editor': {'tabSize': 4},
    });
  });

  test('defaults come from contributions, type defaults and overrides', () {
    final registry = ConfigurationRegistry(
      core: {
        'editor.tabSize': {'type': 'number', 'default': 4},
      },
      extensions: [
        _extension({
          'configuration': {
            'title': 'Ext',
            'properties': {
              'ext.enable': {'type': 'boolean', 'default': true},
              'ext.path': {'type': 'string', 'scope': 'machine'},
              'ext.list': {'type': ['array', 'null']},
            },
          },
          'configurationDefaults': {
            'editor.tabSize': 8,
            '[go]': {'editor.insertSpaces': false},
          },
        }),
      ],
    );
    final defaults = registry.defaults();
    expect(defaults.getValue('editor.tabSize'), 8);
    expect(defaults.getValue('ext.enable'), true);
    expect(defaults.getValue('ext.path'), '');
    expect(defaults.getValue('ext.list'), <Object?>[]);
    expect(defaults.overrides.single.identifiers, ['go']);
    expect(registry.properties['ext.path']!.scope, ConfigurationScope.machine);
    expect(
      registry.scopes(),
      anyElement(equals(['ext.enable', ConfigurationScope.window])),
    );
  });

  test('workspace settings cannot set machine settings', () {
    final registry = ConfigurationRegistry(
      extensions: [
        _extension({
          'configuration': {
            'properties': {
              'ext.path': {'type': 'string', 'scope': 'machine'},
              'ext.mode': {'type': 'string'},
              'ext.secret': {'type': 'string', 'restricted': true},
            },
          },
        }),
      ],
    );
    final service = ConfigurationService(
      registry: registry,
      user: _File({'ext.path': '/bin/x'}),
      workspace: _File({
        'ext.path': '/evil',
        'ext.mode': 'fast',
        'ext.secret': 's',
      }),
      trusted: false,
    );
    expect(service.getValue('ext.path'), '/bin/x');
    expect(service.getValue('ext.mode'), 'fast');
    expect(service.getValue('ext.secret'), '');
    final data = service.initData();
    expect((data['workspace']! as Map)['keys'], ['ext.mode']);
    service.dispose();
  });

  test('a change reports its keys and overrides', () async {
    final user = _File({'a.b': 1});
    final service = ConfigurationService(
      registry: ConfigurationRegistry(),
      user: user,
    );
    final events = <ConfigurationChangeEvent>[];
    service.changes.listen(events.add);
    user.set({
      'a.b': 2,
      '[rust]': {'editor.tabSize': 4},
    });
    await pumpEventQueue();
    expect(events.single.change, {
      'keys': ['a.b'],
      'overrides': [
        ['rust', ['editor.tabSize']],
      ],
    });
    expect(
      ((events.single.data['userLocal']! as Map)['contents'] as Map)['a'],
      {'b': 2},
    );
    service.dispose();
  });

  test('writes go where upstream writes them', () async {
    final user = _File();
    final workspace = _File({
      '[python]': {'x.y': 1},
    });
    final service = ConfigurationService(
      registry: ConfigurationRegistry(),
      user: user,
      workspace: workspace,
    );
    await service.update('x.y', 3, target: ConfigurationTarget.user);
    expect(user.writes.single, ['x.y', 3]);
    await service.update('x.y', 5, overrideIdentifier: 'python');
    expect(workspace.writes.single, ['[python]', 'x.y', 5]);
    await service.update(
      'x.z',
      6,
      overrideIdentifier: 'python',
      scopeToLanguage: false,
    );
    expect(workspace.writes.last, ['x.z', 6]);
    final none = ConfigurationService(
      registry: ConfigurationRegistry(),
      user: _File(),
    );
    expect(() => none.update('x', 1), throwsStateError);
    service.dispose();
    none.dispose();
  });

  test('folder settings apply to resources in the folder', () {
    final folder = VsUri.file('/w/a');
    final registry = ConfigurationRegistry(
      extensions: [
        _extension({
          'configuration': {
            'properties': {
              'ext.mode': {'type': 'string', 'scope': 'resource'},
              'ext.window': {'type': 'string'},
            },
          },
        }),
      ],
    );
    final service = ConfigurationService(
      registry: registry,
      user: _File(),
      workspace: _File({'ext.mode': 'ws'}),
      folders: {
        folder: _File({'ext.mode': 'folder', 'ext.window': 'no'}),
      },
    );
    expect(service.getValue('ext.mode'), 'ws');
    expect(
      service.getValue('ext.mode', resource: VsUri.file('/w/a/x.txt')),
      'folder',
    );
    expect(
      service.getValue('ext.window', resource: VsUri.file('/w/a/x.txt')),
      '',
    );
    unawaited(
      service.update('ext.mode', 'x', resource: VsUri.file('/w/a/x.txt')),
    );
    service.dispose();
  });
}
