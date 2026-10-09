// A fixture exercising commands, context keys, menus and keybindings from
// the extension host's side: `setContext`, `commands.executeCommand` both
// ways, and the `type` command.

const vscode = require('vscode');

const typed = [];

exports.activate = function (context) {
  context.subscriptions.push(vscode.commands.registerCommand('fixture.say', async (what) => {
    return `said ${what}`;
  }));

  // Sets a context key the fixture's menus and keybindings gate on.
  context.subscriptions.push(vscode.commands.registerCommand('fixture.setContext', async (value) => {
    await vscode.commands.executeCommand('setContext', 'fixture.on', value !== false);
    return vscode.commands.executeCommand('getCommands', false) ? 'set' : 'set';
  }));

  // Runs a built-in command of the main thread and returns what it gave.
  context.subscriptions.push(vscode.commands.registerCommand('fixture.runBuiltin', async () => {
    await vscode.commands.executeCommand('_fixture.echo', 'hello');
    return 'ran';
  }));

  // Lists the commands the main thread knows (`$getCommands`).
  context.subscriptions.push(vscode.commands.registerCommand('fixture.listCommands', async () => {
    return vscode.commands.getCommands(false);
  }));

  // The `type` command: an extension (Vim-like) intercepting typing.
  context.subscriptions.push(vscode.commands.registerCommand('type', async (args) => {
    typed.push(args.text);
  }));

  context.subscriptions.push(vscode.commands.registerCommand('fixture.typeText', async (text) => {
    await vscode.commands.executeCommand('type', { text });
    return typed.join('');
  }));

  vscode.window.showInformationMessage('commands fixture activated');
};
