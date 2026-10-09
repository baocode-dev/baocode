// Drives vscode.window's terminals for the exthost-tagged terminal test:
// a shell terminal with shell integration, a Pseudoterminal, the
// terminals' events and an environment variable collection.
const vscode = require('vscode');

exports.activate = (context) => {
  const events = [];
  context.subscriptions.push(
    vscode.window.onDidOpenTerminal((t) => events.push(`open:${t.name}`)),
    vscode.window.onDidCloseTerminal((t) =>
      events.push(`close:${t.name}:${t.exitStatus && t.exitStatus.code}:${t.exitStatus && t.exitStatus.reason}`)),
    vscode.window.onDidChangeActiveTerminal((t) => events.push(`active:${t && t.name}`)),
  );
  context.environmentVariableCollection.replace('BAOCODE_FIXTURE_ENV', 'from-extension');

  const command = (id, run) =>
    context.subscriptions.push(vscode.commands.registerCommand(id, run));

  command('terminalFixture.events', () => events.slice());
  command('terminalFixture.shell', () => vscode.env.shell);

  // A shell terminal: a command run through its shell integration, its
  // output read, its exit code.
  command('terminalFixture.run', async (cwd, home) => {
    const terminal = vscode.window.createTerminal({
      name: 'Fixture Shell',
      shellPath: '/bin/zsh',
      cwd,
      env: { FIXTURE_VAR: 'set', HOME: home },
    });
    terminal.show(true);
    const integration = terminal.shellIntegration || await new Promise((resolve) => {
      const timer = setTimeout(() => resolve(undefined), 30000);
      const listener = vscode.window.onDidChangeTerminalShellIntegration((e) => {
        if (e.terminal === terminal) {
          clearTimeout(timer);
          listener.dispose();
          resolve(e.shellIntegration);
        }
      });
    });
    if (!integration) return { error: 'no shell integration' };
    const ended = new Promise((resolve) => {
      const listener = vscode.window.onDidEndTerminalShellExecution((e) => {
        if (e.terminal === terminal) {
          listener.dispose();
          resolve(e);
        }
      });
    });
    const execution = integration.executeCommand(
      'echo "var=$FIXTURE_VAR env=$BAOCODE_FIXTURE_ENV"; pwd; false',
    );
    let output = '';
    for await (const data of execution.read()) output += data;
    const end = await ended;
    const pid = await terminal.processId;
    return {
      output,
      exitCode: end.exitCode,
      commandLine: execution.commandLine.value,
      cwd: integration.cwd && integration.cwd.fsPath,
      pid,
      dimensions: terminal.dimensions,
    };
  });

  command('terminalFixture.sendText', (text) => {
    const terminal = vscode.window.terminals.find((t) => t.name === 'Fixture Shell');
    terminal.sendText(text);
    return true;
  });

  // A Pseudoterminal: what it writes, what is typed back, its exit.
  command('terminalFixture.pty', async () => {
    const write = new vscode.EventEmitter();
    const close = new vscode.EventEmitter();
    let typed = '';
    let opened;
    const open = new Promise((resolve) => (opened = resolve));
    const pty = {
      onDidWrite: write.event,
      onDidClose: close.event,
      open: (dimensions) => {
        write.fire('pty ready\r\n');
        opened(dimensions);
      },
      close: () => {},
      handleInput: (data) => {
        if (data === '\r') {
          write.fire(`got ${typed}\r\n`);
          setTimeout(() => close.fire(7), 50);
        } else {
          typed += data;
        }
      },
    };
    const terminal = vscode.window.createTerminal({ name: 'Fixture Pty', pty });
    terminal.show();
    return await open;
  });
};
