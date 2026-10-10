const vscode = require('vscode');
exports.activate = (c) => {
  vscode.window.registerTreeDataProvider('tp.items', { getChildren: () => [] });
  vscode.window.registerWebviewViewProvider('tp.home', { resolveWebviewView() {} });
};
