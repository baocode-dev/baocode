// A fixture exercising the window area's APIs (see
// test/extensions/window/window_real_test.dart): what a real extension host
// sends the main thread, and what it gets back.
const vscode = require('vscode');

const context = { extensionPath: '' };
const secretsChanged = [];
const statusItems = new Map();
let lastUri = null;

function showMessage(kind, message, ...items) {
  switch (kind) {
    case 'error': return vscode.window.showErrorMessage(message, ...items);
    case 'warning': return vscode.window.showWarningMessage(message, ...items);
    default: return vscode.window.showInformationMessage(message, ...items);
  }
}

function activate(extensionContext) {
  context.extensionPath = extensionContext.extensionPath;
  extensionContext.secrets.onDidChange(e => secretsChanged.push(e.key));

  const commands = {
    'window.say': () => showMessage('warning', 'Hello from the fixture', 'Yes', 'No'),
    'window.ask': async () => showMessage('info', 'Non modal with buttons', 'First', 'Second'),
    'window.askModal': async () => {
      const answer = await showMessage('error', 'Really?', { modal: true, detail: 'A detail line' }, 'Yes', 'No');
      return `answer=${answer}`;
    },
    'window.pick': async () => {
      const picked = await vscode.window.showQuickPick(
        [
          { label: 'One', description: 'first' },
          { label: 'Two', detail: 'the second' },
          { label: 'Three', picked: true }
        ],
        { placeHolder: 'Pick one', title: 'A pick' }
      );
      return `picked=${picked ? picked.label : 'none'}`;
    },
    'window.pickMany': async () => {
      const picked = await vscode.window.showQuickPick(
        ['Alpha', 'Beta', 'Gamma'],
        { canPickMany: true }
      );
      return `picked=${(picked || []).map(p => typeof p === 'string' ? p : p.label).join(',')}`;
    },
    'window.input': async () => {
      const value = await vscode.window.showInputBox({
        title: 'Name',
        prompt: 'What is your name?',
        placeHolder: 'name',
        value: 'seed',
        validateInput: value => value.length < 2 ? { message: 'Too short', severity: vscode.InputBoxValidationSeverity.Warning } : undefined
      });
      return `input=${value}`;
    },
    'window.quickPickObject': async () => {
      const pick = vscode.window.createQuickPick();
      pick.title = 'Object pick';
      pick.placeholder = 'Choose';
      pick.canSelectMany = true;
      pick.items = [{ label: 'A' }, { label: 'B' }, { label: 'C' }];
      const seen = [];
      pick.onDidChangeValue(value => seen.push(`value:${value}`));
      pick.onDidChangeSelection(items => seen.push(`selection:${items.length}`));
      pick.onDidTriggerButton(button => seen.push(`button:${button.tooltip}`));
      pick.onDidHide(() => seen.push('hidden'));
      const done = new Promise(resolve => {
        pick.onDidAccept(() => {
          resolve(`selected=${pick.selectedItems.map(i => i.label).join(',')}`);
          pick.hide();
        });
      });
      pick.buttons = [{ iconPath: new vscode.ThemeIcon('add'), tooltip: 'Add' }];
      pick.show();
      const result = await done;
      pick.dispose();
      return `${result} events=${seen.join('|')}`;
    },
    'window.statusItem': () => {
      const item = vscode.window.createStatusBarItem('window-fixture.status', vscode.StatusBarAlignment.Left, 100);
      item.name = 'Window Fixture';
      item.text = '$(beaker) 3';
      item.tooltip = 'A tooltip';
      item.command = { title: 'Say', command: 'window.say' };
      item.color = '#ff0000';
      item.show();
      statusItems.set('item', item);
      return 'shown';
    },
    'window.statusItemHide': () => {
      const item = statusItems.get('item');
      if (item) { item.hide(); statusItems.delete('item'); }
      return 'hidden';
    },
    'window.output': (args) => {
      const channel = vscode.window.createOutputChannel('Fixture Output');
      channel.appendLine(`line one ${args}`);
      channel.append('no newline ');
      channel.appendLine('and the rest');
      channel.show(true);
      return 'written';
    },
    'window.log': () => {
      const channel = vscode.window.createOutputChannel('Fixture Log', { log: true });
      channel.info('an info line');
      channel.warn('a warning line');
      channel.error('an error line');
      return 'logged';
    },
    'window.state': async (args) => {
      const key = `key-${args}`;
      await context.globalState.update(key, { args, n: 1 });
      await context.workspaceState.update(key, [args]);
      const global = context.globalState.get(key);
      const workspace = context.workspaceState.get(key);
      context.globalState.setKeysForSync(['key']);
      return `global=${JSON.stringify(global)} workspace=${JSON.stringify(workspace)} keys=${context.globalState.keys().length}`;
    },
    'window.secret': async (args) => {
      const first = await context.secrets.get('a-key');
      await context.secrets.store('a-key', `secret-${args}`);
      const second = await context.secrets.get('a-key');
      const keys = await context.secrets.keys();
      if (args === 'delete') await context.secrets.delete('a-key');
      const third = await context.secrets.get('a-key');
      return `first=${first} second=${second} third=${third} keys=${keys.join(',')} changed=${secretsChanged.join(',')}`;
    },
    'window.progress': async () => {
      const cancelled = await vscode.window.withProgress(
        { location: vscode.ProgressLocation.Notification, title: 'Working', cancellable: true },
        (progress) => {
          progress.report({ message: 'step one', increment: 10 });
          return new Promise(resolve => {
            progress.onDidReport ? null : null;
            setTimeout(() => { progress.report({ message: 'step two', increment: 20 }); resolve('done'); }, 50);
          });
        },
        choice => `cancelled=${choice}`
      );
      await vscode.window.withProgress(
        { location: vscode.ProgressLocation.Window, title: 'Quiet work' },
        () => new Promise(resolve => setTimeout(resolve, 200))
      );
      return `progress=${cancelled}`;
    },
    'window.webview': () => {
      const panel = vscode.window.createWebviewPanel('fixture.webview', 'A Webview', vscode.ViewColumn.One, {});
      return new Promise(resolve => {
        panel.webview.html = '<html><body>Hello</body></html>';
        panel.onDidDispose(() => resolve('disposed'));
        setTimeout(() => resolve('still open'), 2000);
      });
    },
    'window.clipboard': async () => {
      await vscode.env.clipboard.writeText('from the fixture');
      const text = await vscode.env.clipboard.readText();
      return `clipboard=${text}`;
    },
    'window.uri': () => {
      const handler = vscode.window.registerUriHandler({
        handleUri: uri => { lastUri = uri.toString(); }
      });
      const appUri = vscode.Uri.from({ scheme: 'baocode', authority: 'baocode-test.window-fixture', path: '/callback', query: 'code=42' });
      vscode.env.openExternal(appUri).then(ok => { lastUri = `opened=${ok}`; });
      setTimeout(() => handler.dispose(), 3000);
      return 'registered';
    },
    'window.uriHandled': () => `uri=${lastUri}`,
    'window.state.window': () => JSON.stringify(vscode.window.state)
  };
  for (const [id, run] of Object.entries(commands)) {
    extensionContext.subscriptions.push(vscode.commands.registerCommand(id, run));
  }
  return { commands: Object.keys(commands) };
}

function deactivate() {}

module.exports = { activate, deactivate };
