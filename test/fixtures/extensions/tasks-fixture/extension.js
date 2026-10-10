// Tasks of an extension: a task provider of `baotask` tasks (a shell one
// and a custom execution in a Pseudoterminal), the task events, and
// `fetchTasks`/`executeTask` for the test to drive.
const vscode = require('vscode');

const events = [];

function shellTask(kind, command) {
  return new vscode.Task(
    { type: 'baotask', kind },
    vscode.TaskScope.Workspace,
    kind,
    'baotask',
    new vscode.ShellExecution(command),
  );
}

function customTask() {
  return new vscode.Task(
    { type: 'baotask', kind: 'custom' },
    vscode.TaskScope.Workspace,
    'custom',
    'baotask',
    new vscode.CustomExecution(async (definition) => {
      const write = new vscode.EventEmitter();
      const close = new vscode.EventEmitter();
      return {
        onDidWrite: write.event,
        onDidClose: close.event,
        open() {
          write.fire(`custom output ${definition.kind}\r\n`);
          setTimeout(() => close.fire(3), 200);
        },
        close() {},
      };
    }),
  );
}

function activate(context) {
  const record = (name) => (e) => {
    const task = e.execution.task;
    events.push(
      e.exitCode !== undefined || name === 'endProcess'
        ? `${name}:${task.name}:${e.exitCode}`
        : `${name}:${task.name}`,
    );
  };
  context.subscriptions.push(
    vscode.tasks.onDidStartTask(record('start')),
    vscode.tasks.onDidEndTask(record('end')),
    vscode.tasks.onDidStartTaskProcess(record('startProcess')),
    vscode.tasks.onDidEndTaskProcess(record('endProcess')),
    vscode.tasks.registerTaskProvider('baotask', {
      provideTasks() {
        return [
          shellTask('echo', "printf 'p.c:2:1: error: from provider\\n'"),
          customTask(),
        ];
      },
      resolveTask() {
        return undefined;
      },
    }),
    vscode.commands.registerCommand('tasksFixture.events', () => events),
    vscode.commands.registerCommand('tasksFixture.fetch', async () => {
      const tasks = await vscode.tasks.fetchTasks();
      return tasks.map((t) => ({
        name: t.name,
        source: t.source,
        definition: t.definition,
      }));
    }),
    vscode.commands.registerCommand('tasksFixture.execute', async (name) => {
      const tasks = await vscode.tasks.fetchTasks({ type: 'baotask' });
      const task = tasks.find((t) => t.name === name);
      if (!task) return null;
      const execution = await vscode.tasks.executeTask(task);
      return execution.task.name;
    }),
    vscode.commands.registerCommand('tasksFixture.executeAdhoc', async () => {
      const execution = await vscode.tasks.executeTask(
        shellTask('adhoc', 'exit 4'),
      );
      return execution.task.name;
    }),
  );
}

module.exports = { activate };
