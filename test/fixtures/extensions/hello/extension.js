const vscode = require('vscode');

exports.activate = function (context) {
  context.subscriptions.push(vscode.commands.registerCommand('hello.say', async (name) => {
    const picked = await vscode.window.showInformationMessage(`Hello, ${name ?? 'world'}!`, 'OK', 'Cancel');
    return `said hello to ${name ?? 'world'}: ${picked}`;
  }));
  vscode.window.showInformationMessage('Hello extension activated');
};
