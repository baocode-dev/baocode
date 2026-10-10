const vscode = require('vscode');
exports.activate = () => {
  vscode.workspace.registerNotebookSerializer('fixture-nb', {});
  vscode.notebooks.createNotebookController('fixture', 'fixture-nb', 'Fixture');
};
