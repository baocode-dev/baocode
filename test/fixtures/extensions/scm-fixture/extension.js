// A source control of its own (shown by BaoCode), and the built-in Git
// extension's API (whose provider BaoCode receives but does not show).
const vscode = require('vscode');
const path = require('path');

exports.activate = async (context) => {
  const root = vscode.workspace.workspaceFolders[0].uri;
  const scm = vscode.scm.createSourceControl('fixture', 'Fixture', root);
  scm.inputBox.placeholder = 'Fixture message';
  scm.acceptInputCommand = { command: 'scmFixture.commit', title: 'Commit' };
  scm.count = 2;
  const changes = scm.createResourceGroup('changes', 'Fixture Changes');
  const opened = [];
  const staged = [];
  changes.resourceStates = ['one.txt', 'sub/two.txt'].map((name) => ({
    resourceUri: vscode.Uri.joinPath(root, name),
    contextValue: 'file',
    decorations: { strikeThrough: name === 'one.txt', tooltip: 'Changed' },
    command: { command: 'scmFixture.open', title: 'Open', arguments: [name] },
  }));
  const commits = [];
  context.subscriptions.push(
    scm,
    vscode.commands.registerCommand('scmFixture.open', (name) => {
      opened.push(name);
    }),
    vscode.commands.registerCommand('scmFixture.stage', (...states) => {
      for (const s of states) staged.push(path.basename(s.resourceUri.fsPath));
    }),
    vscode.commands.registerCommand('scmFixture.commit', () => {
      commits.push(scm.inputBox.value);
      scm.inputBox.value = '';
    }),
    vscode.commands.registerCommand('scmFixture.state', async () => {
      const git = vscode.extensions.getExtension('vscode.git');
      const api = (await git.activate()).getAPI(1);
      return {
        input: scm.inputBox.value,
        opened,
        staged,
        commits,
        gitState: api.state,
        repositories: api.repositories.map((r) => ({
          root: r.rootUri.fsPath,
          head: r.state.HEAD && r.state.HEAD.name,
          changes: r.state.workingTreeChanges.map((c) =>
            path.basename(c.uri.fsPath),
          ),
        })),
      };
    }),
  );
};
