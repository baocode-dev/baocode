// Asks for what BaoCode degrades: a Webview panel, a Webview view, a custom
// editor, a notebook serializer and controller, and a language model tool;
// reports what the extension sees of each.
const vscode = require('vscode');

const state = { panel: 'none', notebookError: null, tools: null };

function activate(context) {
  context.subscriptions.push(
    vscode.window.registerWebviewViewProvider('degradation.webviewView', {
      resolveWebviewView(view) {
        view.webview.html = '<p>never shown</p>';
      }
    }),
    vscode.window.registerCustomEditorProvider('degradation.preview', {
      resolveCustomTextEditor() {}
    }),
    vscode.workspace.registerNotebookSerializer('degradation-notebook', {
      deserializeNotebook() {
        return new vscode.NotebookData([]);
      },
      serializeNotebook() {
        return new Uint8Array();
      }
    }),
    vscode.notebooks.createNotebookController('degradation.kernel', 'degradation-notebook', 'Fixture Kernel', () => {}),
    vscode.lm.registerTool('degradation_tool', {
      invoke() {
        return new vscode.LanguageModelToolResult([new vscode.LanguageModelTextPart('never')]);
      }
    }),
    vscode.commands.registerCommand('degradation.panel', () => {
      const panel = vscode.window.createWebviewPanel('degradation.panel', 'Fixture Panel', vscode.ViewColumn.One, {});
      panel.webview.html = '<p>never shown</p>';
      return new Promise(resolve => {
        panel.onDidDispose(() => {
          state.panel = 'disposed';
          resolve('disposed');
        });
        setTimeout(() => resolve('still open'), 3000);
      });
    }),
    vscode.commands.registerCommand('degradation.openNotebook', async (path) => {
      try {
        await vscode.workspace.openNotebookDocument(vscode.Uri.file(path));
        state.notebookError = 'opened';
      } catch (e) {
        state.notebookError = String(e && e.message || e);
      }
      return state.notebookError;
    }),
    vscode.commands.registerCommand('degradation.state', () => {
      state.tools = vscode.lm.tools.map(t => t.name);
      return JSON.stringify(state);
    })
  );
}

module.exports = { activate };
