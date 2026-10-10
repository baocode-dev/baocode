import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/host/workspace_contains.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Host implements ExtensionActivationHost {
  _Host({this.files = const {}, this.globMatches = false});

  final Set<String> files;
  final bool globMatches;
  final searched = <List<String>>[];

  @override
  List<VsUri> get folders => [VsUri.file('/a'), VsUri.file('/b')];

  @override
  bool get forceUsingSearch => false;

  @override
  Future<bool> exists(VsUri uri) async => files.contains(uri.path);

  @override
  Future<bool> checkExists(
    List<VsUri> folders,
    List<String> includes,
    CancellationToken token,
  ) async {
    searched.add(includes);
    return globMatches;
  }
}

void main() {
  test('a file name is looked for in each folder', () async {
    final host = _Host(files: {'/b/Cargo.toml'});
    expect(
      await checkActivateWorkspaceContainsExtension(host, [
        'onLanguage:rust',
        'workspaceContains:Cargo.toml',
      ]),
      'workspaceContains:Cargo.toml',
    );
    expect(host.searched, isEmpty);
  });

  test('globs go through the search together', () async {
    final host = _Host(globMatches: true);
    expect(
      await checkActivateWorkspaceContainsExtension(host, [
        'workspaceContains:**/*.go',
        'workspaceContains:go.?od',
      ]),
      'workspaceContains:**/*.go,go.?od',
    );
    expect(host.searched, [
      ['**/*.go', 'go.?od'],
    ]);
  });

  test('nothing found, or no workspaceContains, is null', () async {
    expect(
      await checkActivateWorkspaceContainsExtension(_Host(), [
        'workspaceContains:pom.xml',
        'workspaceContains:**/*.java',
      ]),
      isNull,
    );
    expect(
      await checkActivateWorkspaceContainsExtension(_Host(), ['*']),
      isNull,
    );
  });
}
