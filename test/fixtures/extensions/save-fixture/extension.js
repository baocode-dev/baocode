// A formatter, a source.fixAll code action and an onWillSaveTextDocument
// listener for `.fix` files, so a save shows each participant's part.
const vscode = require('vscode');

const reasons = [];

function replaceAll(document, from, to) {
  const edits = [];
  const text = document.getText();
  let index = text.indexOf(from);
  while (index >= 0) {
    edits.push(vscode.TextEdit.replace(
      new vscode.Range(document.positionAt(index), document.positionAt(index + from.length)),
      to
    ));
    index = text.indexOf(from, index + from.length);
  }
  return edits;
}

function activate(context) {
  context.subscriptions.push(
    vscode.languages.registerDocumentFormattingEditProvider('fixturelang', {
      provideDocumentFormattingEdits(document) {
        return replaceAll(document, 'format-me', 'formatted');
      }
    }),
    vscode.languages.registerCodeActionsProvider('fixturelang', {
      provideCodeActions(document, _range, context) {
        if (!context.only || !context.only.contains(vscode.CodeActionKind.SourceFixAll)) {
          return [];
        }
        const action = new vscode.CodeAction('Fix all', vscode.CodeActionKind.SourceFixAll.append('fixture'));
        const edit = new vscode.WorkspaceEdit();
        for (const e of replaceAll(document, 'fix-me', 'fixed')) {
          edit.replace(document.uri, e.range, e.newText);
        }
        action.edit = edit;
        return [action];
      }
    }, { providedCodeActionKinds: [vscode.CodeActionKind.SourceFixAll.append('fixture')] }),
    vscode.workspace.onWillSaveTextDocument(event => {
      if (event.document.languageId !== 'fixturelang') {
        return;
      }
      reasons.push(event.reason);
      event.waitUntil(Promise.resolve([
        vscode.TextEdit.insert(new vscode.Position(0, 0), '// will save\n')
      ]));
    }),
    vscode.commands.registerCommand('saveFixture.reasons', () => reasons)
  );
}

module.exports = { activate };
