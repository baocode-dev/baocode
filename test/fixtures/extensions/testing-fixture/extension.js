// A test controller: a file with a suite of two tests found through the
// resolve handler, Run and Debug profiles; a run passes `adds`, fails
// `subtracts` with a message at its line, and writes output. The log says
// which tests each profile ran.
const vscode = require('vscode');

exports.activate = (context) => {
  const root = vscode.workspace.workspaceFolders[0].uri;
  const file = vscode.Uri.joinPath(root, 'math.test.js');
  const controller = vscode.tests.createTestController('fixtureTests', 'Fixture Tests');
  const log = [];
  context.subscriptions.push(controller);

  controller.resolveHandler = async (item) => {
    if (item) return;
    const suite = controller.createTestItem('suite', 'math', file);
    suite.range = new vscode.Range(0, 0, 9, 0);
    const adds = controller.createTestItem('adds', 'adds', file);
    adds.range = new vscode.Range(1, 2, 3, 4);
    const subtracts = controller.createTestItem('subtracts', 'subtracts', file);
    subtracts.range = new vscode.Range(5, 2, 7, 4);
    suite.children.replace([adds, subtracts]);
    controller.items.replace([suite]);
    log.push('resolved');
  };

  const leaves = (request) => {
    const out = [];
    const visit = (item) => {
      if (request.exclude && request.exclude.includes(item)) return;
      if (item.children.size === 0) out.push(item);
      item.children.forEach(visit);
    };
    if (request.include) request.include.forEach(visit);
    else controller.items.forEach(visit);
    return out;
  };

  const run = (kind) => async (request, token) => {
    const testRun = controller.createTestRun(request);
    for (const test of leaves(request)) {
      log.push(`${kind}:${test.id}`);
      testRun.started(test);
      testRun.appendOutput(`running ${test.id}\r\n`, undefined, test);
      if (test.id === 'subtracts') {
        const message = vscode.TestMessage.diff('2 - 1 should be 1', '1', '3');
        message.location = new vscode.Location(file, new vscode.Position(6, 4));
        testRun.failed(test, message, 12);
      } else {
        testRun.passed(test, 3);
      }
    }
    testRun.end();
  };

  controller.createRunProfile('Run', vscode.TestRunProfileKind.Run, run('run'), true);
  controller.createRunProfile('Debug', vscode.TestRunProfileKind.Debug, run('debug'), true);

  context.subscriptions.push(
    vscode.commands.registerCommand('testingFixture.log', () => log),
    vscode.commands.registerCommand('testingFixture.selfRun', () => {
      // A run the extension starts on its own (a watch mode does).
      const suite = controller.items.get('suite');
      const testRun = controller.createTestRun(
        new vscode.TestRunRequest([suite]),
        'self',
        false,
      );
      testRun.skipped(suite.children.get('adds'));
      testRun.end();
      return true;
    }),
  );
};
