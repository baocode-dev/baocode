"use strict";
const vscode = require("vscode");
const { LanguageClient } = require("vscode-languageclient/node");
exports.activate = (context) => {
  context.subscriptions.push(vscode.languages.registerHoverProvider("lang", { provideHover() {} }));
  context.subscriptions.push(vscode.languages.registerDocumentFormattingEditProvider("lang", { provideDocumentFormattingEdits() { return []; } }));
};
