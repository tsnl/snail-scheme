// The VS Code extension, editors/vscode, with VS Code and its protocol
// client replaced by stand-ins, since neither runs here:
//
//   node tests/vscode.mjs ROOT
//
// - it starts `snail-scheme lsp` for the language's documents, as the
//   `snail-scheme.path` setting names it, or else from the workspace
//   folder's launcher, or else from the PATH;
// - its files are the ones Zed's configuration names.
import assert from 'node:assert/strict';
import {mkdtempSync, readFileSync, rmSync} from 'node:fs';
import Module, {createRequire} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

const root = process.argv[2];
const extension = join(root, 'editors/vscode');

// ---- Stand-ins ----

const settings = {path: ''};
const workspace = {
  getConfiguration: section => ({get: name => (assert.equal(section, 'snail-scheme'), settings[name])}),
  workspaceFolders: [],
};
const started = [];
class LanguageClient {
  constructor(id, name, server, client) { Object.assign(this, {id, name, server, client}); }
  start() { started.push(this); return Promise.resolve(); }
  stop() { return Promise.resolve(); }
}
const require = createRequire(import.meta.url);
const load = Module._load;
Module._load = function (request, ...rest) {
  if (request === 'vscode') return {workspace};
  if (request === 'vscode-languageclient/node') return {LanguageClient};
  return load.call(this, request, ...rest);
};
const {activate, deactivate} = require(join(extension, 'extension.js'));

// ---- The server it starts ----

const folder = path => ({uri: {fsPath: path}});
const empty = mkdtempSync(join(tmpdir(), 'snail-vscode-'));
const launched = async () => {
  await activate();
  await deactivate();
  return started.at(-1);
};
try {
  workspace.workspaceFolders = [folder(empty)];
  const fromPath = await launched();
  assert.deepEqual(fromPath.server.run, {command: 'snail-scheme', args: ['lsp']});
  assert.deepEqual(fromPath.server.debug, fromPath.server.run);
  assert.deepEqual(fromPath.client.documentSelector, [{language: 'snail-scheme'}]);

  // The repository's root has the launcher, but a folder named like it
  // is not one.
  workspace.workspaceFolders = [folder(empty), folder(join(root, 'editors')), folder(root)];
  assert.equal((await launched()).server.run.command, join(root, 'snail-scheme'));

  settings.path = '/opt/snail/snail-scheme';
  assert.equal((await launched()).server.run.command, '/opt/snail/snail-scheme');
} finally {
  rmSync(empty, {recursive: true, force: true});
}

// ---- Files ----

const manifest = JSON.parse(readFileSync(join(extension, 'package.json'), 'utf8'));
const [language] = manifest.contributes.languages;
const zed = readFileSync(join(root, 'editors/zed/languages/snail-scheme/config.toml'), 'utf8');
const suffixes = JSON.parse(/^path_suffixes = (\[.*\])$/m.exec(zed)[1]);
assert.equal(language.id, 'snail-scheme');
assert.deepEqual(language.extensions, suffixes.map(suffix => `.${suffix}`));
JSON.parse(readFileSync(join(extension, language.configuration), 'utf8'));
console.log('vscode: the launcher it starts, from the setting, the workspace or the PATH, and its files');
