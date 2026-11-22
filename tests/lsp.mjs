// `snail-scheme lsp` speaks the Language Server Protocol over its standard input
// and output, for a workspace of its own made here:
//
//   node tests/lsp.mjs ROOT
//
// It answers initialize with what it does; checks each open script and
// library when it is opened and saved, reports their failures at their
// places, once each, and clears a file once it is fixed; formats the open
// text; colours it with semantic
// tokens, a line at a time; gives a name's type where it is
// used, and where it is defined, in another file or in the same one, but
// not once the open text no longer spells it there; counts
// positions in UTF-16 code units; and exits when told to.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

const root = process.argv[2];
const project = mkdtempSync(join(tmpdir(), 'snail-lsp-'));
const put = (name, text) => {
  mkdirSync(join(project, name, '..'), {recursive: true});
  writeFileSync(join(project, name), text);
};
const uri = name => `file://${join(project, name)}`;

const library = `(define-library (demo twice)
  (export
   twice)
  (import
   (snail core base))
  (begin
    (define (twice (f (Fn I64 → I64)) (x I64)) (→ I64)
      (f (f x)))))
`;
// A name after a character outside the Basic Multilingual Plane, which
// takes two code units.
const program = `(import
 (snail core base)
 (snail core io)
 (demo twice))

(define (main (out OutputPort)) (→ Unit)
  (let ((n (twice (lambda (x) (+ x 1)) 40)))
    (write-line out "🐌") (write-line out (show n))))
`;

// ---- The server ----

const server = spawn(join(root, 'snail-scheme'), ['lsp'], {cwd: project, stdio: ['pipe', 'pipe', 'pipe']});
let stderr = '';
server.stderr.on('data', chunk => { stderr += chunk; });
let pending = Buffer.alloc(0);
const received = [];
const waiting = [];
server.stdout.on('data', chunk => {
  pending = Buffer.concat([pending, chunk]);
  for (;;) {
    const end = pending.indexOf('\r\n\r\n');
    if (end < 0) return;
    const length = Number(/^Content-Length: (\d+)$/im.exec(pending.subarray(0, end).toString())[1]);
    if (pending.length < end + 4 + length) return;
    received.push(JSON.parse(pending.subarray(end + 4, end + 4 + length).toString('utf8')));
    pending = pending.subarray(end + 4 + length);
    for (const wake of waiting.splice(0)) wake();
  }
});
const exited = new Promise(resolve => server.on('exit', code => resolve(code)));

const send = message => {
  const text = JSON.stringify({jsonrpc: '2.0', ...message});
  server.stdin.write(`Content-Length: ${Buffer.byteLength(text)}\r\n\r\n${text}`);
};

// The first message received that `test` accepts, within 120 s.
const next = (test, what) => new Promise((resolve, reject) => {
  const timer = setTimeout(() => reject(new Error(`no ${what}; stderr:\n${stderr}`)), 120000);
  const look = () => {
    const index = received.findIndex(test);
    if (index < 0) return waiting.push(look);
    clearTimeout(timer);
    resolve(received.splice(index, 1)[0]);
  };
  look();
});

let id = 0;
const ask = async (method, params) => {
  id += 1;
  const asked = id;
  send({id: asked, method, params});
  const reply = await next(message => message.id === asked, `reply to ${method}`);
  assert.equal(reply.error, undefined, `${method}: ${JSON.stringify(reply.error)}`);
  return reply.result;
};
const diagnostics = name => next(message => message.method === 'textDocument/publishDiagnostics'
                                 && message.params.uri === uri(name), `diagnostics of ${name}`)
  .then(message => message.params.diagnostics);
const at = (name, line, character) => ({textDocument: {uri: uri(name)}, position: {line, character}});
const range = (startLine, startCharacter, endLine, endCharacter) => ({
  start: {line: startLine, character: startCharacter},
  end: {line: endLine, character: endCharacter},
});
// An edit to the open main.scm, which the editor then saves: the server
// checks what was saved, and places what it reports in the open text.
let version = 1;
const changed = text => {
  version += 1;
  send({method: 'textDocument/didChange',
        params: {textDocument: {uri: uri('main.scm'), version}, contentChanges: [{text}]}});
};
const saved = name => send({method: 'textDocument/didSave', params: {textDocument: {uri: uri(name)}}});
const edited = text => {
  changed(text);
  put('main.scm', text);
  saved('main.scm');
};

try {
  put('src/demo/twice.sld', library);
  put('main.scm', program);

  // ---- Starting ----

  const initialized = await ask('initialize', {processId: null, rootUri: `file://${project}`, capabilities: {}});
  assert.deepEqual(initialized.capabilities, {
    textDocumentSync: {openClose: true, change: 1, save: true},
    documentFormattingProvider: true,
    hoverProvider: true,
    definitionProvider: true,
    semanticTokensProvider: {
      legend: {tokenTypes: ['comment', 'string', 'number', 'keyword', 'type', 'function'],
                tokenModifiers: ['declaration']},
      full: true,
    },
  });
  send({method: 'textDocument/didOpen',
        params: {textDocument: {uri: uri('main.scm'), languageId: 'snail-scheme', version: 1, text: program}}});
  send({method: 'initialized', params: {}});

  // ---- Names ----

  const twice = await ask('textDocument/hover', at('main.scm', 6, 13));
  assert.deepEqual(twice.contents, {
    kind: 'markdown',
    value: '```snail\ntwice : (Fn (Fn I64 → I64) I64 → I64)\n```\n\nfrom `demo.twice`',
  });
  assert.deepEqual(await ask('textDocument/definition', at('main.scm', 6, 15)),
                   {uri: uri('src/demo/twice.sld'), range: range(6, 13, 6, 18)});
  // After the snail, `n` is at code unit 48 of its line, its 47th character.
  assert.equal((await ask('textDocument/hover', at('main.scm', 7, 48))).contents.value,
               '```snail\nn : I64\n```');
  assert.deepEqual(await ask('textDocument/definition', at('main.scm', 7, 48)),
                   {uri: uri('main.scm'), range: range(6, 9, 6, 10)});
  assert.equal(await ask('textDocument/hover', at('main.scm', 5, 0)), null);
  // An edit not yet saved, nor built, moves what the build saw: the name now
  // at a use's point is not the use's, so it has no answer.
  changed(program.replace('(twice (lambda', '(thrice (lambda'));
  assert.equal(await ask('textDocument/hover', at('main.scm', 6, 13)), null);
  changed(program);

  // ---- Formatting ----

  assert.deepEqual(await ask('textDocument/formatting', {textDocument: {uri: uri('main.scm')}, options: {}}), []);
  const messy = program.replace(' (write-line out (show n))', '\n(write-line out (show n))');
  changed(messy);
  assert.deepEqual(await ask('textDocument/formatting', {textDocument: {uri: uri('main.scm')}, options: {}}), [{
    range: range(0, 0, 9, 0),
    newText: messy.replace('\n(write-line out (show n))', '\n    (write-line out (show n))'),
  }]);
  changed(program);

  // ---- Colours ----

  // A block comment over two lines is a token on each; after the snail,
  // columns count it as two units. Names used are not coloured.
  const coloured = '#| one\ntwo |#\n(define (f) (→ String) "🐌" 7)\n';
  changed(coloured);
  const {data} = await ask('textDocument/semanticTokens/full', {textDocument: {uri: uri('main.scm')}});
  const tokens = [];
  for (let index = 0, line = 0, column = 0; index < data.length; index += 5) {
    const [dLine, dColumn, length, type, modifiers] = data.slice(index, index + 5);
    line += dLine;
    column = dLine === 0 ? column + dColumn : dColumn;
    tokens.push([line, column, length, ['comment', 'string', 'number', 'keyword', 'type', 'function'][type], modifiers]);
  }
  assert.deepEqual(tokens, [
    [0, 0, 6, 'comment', 0],
    [1, 0, 6, 'comment', 0],
    [2, 1, 6, 'keyword', 0],
    [2, 9, 1, 'function', 1],
    [2, 13, 1, 'keyword', 0],
    [2, 15, 6, 'type', 0],
    [2, 23, 4, 'string', 0],
    [2, 28, 1, 'number', 0],
  ]);
  changed(program);

  // ---- Diagnostics ----

  edited(program.replace('(show n)', '(show "n" n)'));
  assert.deepEqual(await diagnostics('main.scm'), [{
    range: range(7, 42, 7, 54),
    severity: 1,
    source: 'snail-scheme',
    message: 'expected 1 arguments, found 2',
  }]);
  edited(program);
  assert.deepEqual(await diagnostics('main.scm'), []);

  // A path is a use of the name it starts with: `out::write-string` at
  // code unit 27 answers for `out`, and leads to where `out` is bound.
  edited(program.replace('(write-line out (show n))', '(out::write-string (show n))'));
  assert.equal((await ask('textDocument/hover', at('main.scm', 7, 32))).contents.value,
               '```snail\nout : OutputPort\n```');
  assert.deepEqual(await ask('textDocument/definition', at('main.scm', 7, 27)),
                   {uri: uri('main.scm'), range: range(5, 15, 5, 18)});
  edited(program);

  // An open library is checked as the program that imports it; its
  // failure, which the script's check meets too, is reported once.
  send({method: 'textDocument/didOpen',
        params: {textDocument: {uri: uri('src/demo/twice.sld'), languageId: 'snail-scheme', version: 1, text: library}}});
  // The server takes messages in order, so a reply comes after the check.
  await ask('textDocument/hover', at('main.scm', 5, 0));
  put('src/demo/twice.sld', library.replace('(f (f x))', '(f (f "x"))'));
  saved('src/demo/twice.sld');
  const failure = await diagnostics('src/demo/twice.sld');
  assert.equal(failure.length, 1, JSON.stringify(failure));
  assert.equal(failure[0].range.start.line, 7);
  put('src/demo/twice.sld', library);
  saved('src/demo/twice.sld');
  assert.deepEqual(await diagnostics('src/demo/twice.sld'), []);

  // ---- Ending ----

  assert.equal(await ask('shutdown', null), null);
  send({method: 'exit'});
  assert.equal(await exited, 0);
} finally {
  server.kill();
  rmSync(project, {recursive: true, force: true});
}
