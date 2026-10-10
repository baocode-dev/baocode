
import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/host/init_data.dart';
import 'package:baocode/extensions/workspace/workspace_context.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Ports implements WorkspaceFoldersPort {
  List<WorkspaceFolderToAdd>? set;
  List<WorkspaceFolderToAdd>? entered;
  final status = <(String, int, int)>[];

  @override
  Future<void> setFolders(List<WorkspaceFolderToAdd> folders) async =>
      set = folders;

  @override
  Future<void> enterWorkspace(List<WorkspaceFolderToAdd> folders) async =>
      entered = folders;

  @override
  void showStatus(String extensionName, int added, int removed) =>
      status.add((extensionName, added, removed));
}

void main() {
  test('a folder\'s project is state folder, an empty one empty', () {
    final folder = WorkspaceContextService(
      ExtHostWorkspace.folder('/work/one'),
    );
    expect(folder.state, WorkbenchState.folder);
    expect(folder.toWorkspaceData()!['folders'], hasLength(1));
    expect(folder.isMultiRoot, isFalse);

    expect(WorkspaceContextService(null).state, WorkbenchState.empty);
    expect(WorkspaceContextService(null).toWorkspaceData(), isNull);
    expect(
      WorkspaceContextService(
        ExtHostWorkspace(
          id: 'id',
          name: 'w',
          folders: [ExtHostWorkspaceFolder(VsUri.file('/w/one'), 'one', 0)],
        ),
        isMultiRoot: true,
      ).state,
      WorkbenchState.workspace,
    );
  });

  test('getWorkspaceFolder answers the innermost folder', () {
    final w = WorkspaceContextService(
      ExtHostWorkspace(
        id: 'id',
        name: 'w',
        folders: [
          ExtHostWorkspaceFolder(VsUri.file('/work'), 'work', 0),
          ExtHostWorkspaceFolder(VsUri.file('/work/one'), 'one', 1),
        ],
      ),
      isMultiRoot: true,
    );
    expect(w.getWorkspaceFolder(VsUri.file('/work/one/a.txt'))!.name, 'one');
    expect(w.getWorkspaceFolder(VsUri.file('/work/two/a.txt'))!.name, 'work');
    expect(w.getWorkspaceFolder(VsUri.file('/elsewhere')), isNull);
    expect(w.getWorkspaceFolder(VsUri('untitled', path: 'Untitled-1')), isNull);
  });

  test('setFolders keeps the workspace\'s id and name', () {
    final w = WorkspaceContextService(ExtHostWorkspace.folder('/work/one'));
    var changes = 0;
    w.addListener(() => changes++);
    w.setFolders([
      (uri: VsUri.file('/work/one'), name: 'one'),
      (uri: VsUri.file('/work/two'), name: 'two'),
    ]);
    expect(changes, 1);
    expect(w.workspace!.id, ExtHostWorkspace.folderWorkspaceId('/work/one'));
    expect(w.workspace!.folders.map((f) => f.index), [0, 1]);
    // The same folders again: no change.
    w.setFolders([
      (uri: VsUri.file('/work/one'), name: 'one'),
      (uri: VsUri.file('/work/two'), name: 'two'),
    ]);
    expect(changes, 1);
  });

  test('adding a folder to a multi-folder workspace keeps the order', () async {
    final ports = _Ports();
    final w = WorkspaceContextService(
      ExtHostWorkspace(
        id: 'id',
        name: 'w',
        folders: [
          ExtHostWorkspaceFolder(VsUri.file('/w/one'), 'one', 0),
          ExtHostWorkspaceFolder(VsUri.file('/w/two'), 'two', 1),
        ],
      ),
      isMultiRoot: true,
      folders: ports,
    );
    await w.updateFolders(1, 0, [(uri: VsUri.file('/w/three'), name: 'three')]);
    expect(ports.set!.map((f) => f.uri.path), ['/w/one', '/w/three', '/w/two']);
    // An index past the end appends.
    await w.updateFolders(9, 0, [(uri: VsUri.file('/w/four'), name: 'four')]);
    expect(ports.set!.last.uri.path, '/w/four');
  });

  test('removing folders of a multi-folder workspace', () async {
    final ports = _Ports();
    final w = WorkspaceContextService(
      ExtHostWorkspace(
        id: 'id',
        name: 'w',
        folders: [
          ExtHostWorkspaceFolder(VsUri.file('/w/one'), 'one', 0),
          ExtHostWorkspaceFolder(VsUri.file('/w/two'), 'two', 1),
          ExtHostWorkspaceFolder(VsUri.file('/w/three'), 'three', 2),
        ],
      ),
      isMultiRoot: true,
      folders: ports,
    );
    await w.updateFolders(0, 2, const []);
    expect(ports.set!.map((f) => f.uri.path), ['/w/three']);
  });

  test('a folder\'s window enters a workspace to hold more folders', () async {
    final ports = _Ports();
    final w = WorkspaceContextService(
      ExtHostWorkspace.folder('/w/one'),
      folders: ports,
    );
    await w.updateFolders(1, 0, [(uri: VsUri.file('/w/two'), name: 'two')]);
    expect(ports.entered!.map((f) => f.uri.path), ['/w/one', '/w/two']);
    expect(ports.set, isNull);

    // Its only folder replaced by another: also a workspace.
    await w.updateFolders(0, 1, [(uri: VsUri.file('/w/two'), name: 'two')]);
    expect(ports.entered!.single.uri.path, '/w/two');
  });

  test('without a port, changing folders fails', () async {
    final w = WorkspaceContextService(
      ExtHostWorkspace.folder('/w/one'),
      isMultiRoot: true,
    );
    await expectLater(
      w.updateFolders(0, 0, [(uri: VsUri.file('/w/two'), name: 'two')]),
      throwsA(isA<StateError>()),
    );
  });

  test('the same folder added twice is kept once', () async {
    final ports = _Ports();
    final w = WorkspaceContextService(
      ExtHostWorkspace(
        id: 'id',
        name: 'w',
        folders: [ExtHostWorkspaceFolder(VsUri.file('/w/one'), 'one', 0)],
      ),
      isMultiRoot: true,
      folders: ports,
    );
    await w.updateFolders(1, 0, [
      (uri: VsUri.file('/w/two'), name: 'two'),
      (uri: VsUri.file('/w/two'), name: 'twice'),
    ]);
    expect(ports.set!.map((f) => f.uri.path), ['/w/one', '/w/two']);
  });

  test('a trailing slash is taken off an added folder', () async {
    final ports = _Ports();
    final w = WorkspaceContextService(
      ExtHostWorkspace(
        id: 'id',
        name: 'w',
        folders: [ExtHostWorkspaceFolder(VsUri.file('/w/one'), 'one', 0)],
      ),
      isMultiRoot: true,
      folders: ports,
    );
    await w.updateFolders(1, 0, [
      (uri: VsUri.file('/w/two/'), name: 'two'),
    ]);
    expect(ports.set!.last.uri.path, '/w/two');
  });
}
