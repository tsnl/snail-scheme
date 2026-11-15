// VS Code's extension for snail-scheme. The language is data: package.json
// names its files and language-configuration.json its comments and
// brackets. This code only starts the language server, `snail-scheme lsp`
// (src/snail/shell/lsp.sld), which answers everything else: colours as
// semantic tokens, diagnostics on save, formatting, hover and definitions.
// VS Code runs extensions in Node and has no client of its own for the
// protocol, so Microsoft's vscode-languageclient speaks it.
const {statSync} = require('node:fs');
const {join} = require('node:path');
const vscode = require('vscode');
const {LanguageClient} = require('vscode-languageclient/node');

let client = null;

// ---- Finding the launcher ----

// The command the `snail-scheme.path` setting names, then the launcher at
// a workspace folder's root, then `snail-scheme` on the PATH.
function command() {
  const configured = vscode.workspace.getConfiguration('snail-scheme').get('path');
  if (configured) return configured;
  for (const folder of vscode.workspace.workspaceFolders ?? []) {
    const launcher = join(folder.uri.fsPath, 'snail-scheme');
    if (statSync(launcher, {throwIfNoEntry: false})?.isFile()) return launcher;
  }
  return 'snail-scheme';
}

// ---- The extension ----

function activate() {
  const server = {command: command(), args: ['lsp']};
  client = new LanguageClient('snail-scheme', 'snail-scheme', {run: server, debug: server},
                              {documentSelector: [{language: 'snail-scheme'}]});
  return client.start();
}

function deactivate() {
  return client?.stop();
}

module.exports = {activate, deactivate};
