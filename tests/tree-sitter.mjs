// The editors' grammar, editors/tree-sitter-snail-scheme, agrees with the reader
// and with itself:
//
//   node tests/tree-sitter.mjs ROOT
//
// - the committed parser is the one grammar.js generates: generating again
//   gives the same grammar.json and node-types.json;
// - its corpus and highlight tests pass (`tree-sitter test`);
// - every tracked Scheme file parses without an error or a missing node;
// - the keywords Zed colors are (snail shell highlight)'s, which begin with
//   the compiler's core forms.
//
// It needs the tree-sitter CLI and a C compiler, which shell.nix provides.
import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

const root = process.argv[2];
const grammar = join(root, 'editors/tree-sitter-snail-scheme');
const scratch = mkdtempSync(join(tmpdir(), 'snail-tree-sitter-'));
const run = (args, cwd) => {
  const result = spawnSync('tree-sitter', args, {cwd, encoding: 'utf8'});
  assert.equal(result.status, 0, `tree-sitter ${args.join(' ')}\n${result.stdout}${result.stderr}`);
  return result.stdout;
};

// The strings in a file from `header` up to `end`: the keywords a
// definition lists, up to the next definition, or a query names, up to the
// blank line after it.
const listed = (file, header, end) => {
  const text = readFileSync(join(root, file), 'utf8');
  const start = text.indexOf(header);
  assert.ok(start >= 0, `${file} has ${header}`);
  const stop = text.indexOf(end, start + header.length);
  return [...text.slice(start, stop).matchAll(/"((?:[^"\\]|\\.)*)"/g)].map(match => match[1]);
};

try {
  const copy = join(scratch, 'grammar');
  cpSync(grammar, copy, {recursive: true});
  run(['generate'], copy);
  for (const file of ['src/grammar.json', 'src/node-types.json']) {
    assert.equal(readFileSync(join(copy, file), 'utf8'), readFileSync(join(grammar, file), 'utf8'),
                 `${file} is not what grammar.js generates; run tree-sitter generate in ${grammar}`);
  }

  run(['test'], grammar);

  const files = execFileSync('git', ['ls-files', '*.sld', '*.scm', '*.sls', '*.datum'],
                             {cwd: root, encoding: 'utf8'}).split('\n').filter(Boolean);
  const paths = join(scratch, 'paths.txt');
  writeFileSync(paths, files.map(file => join(root, file)).join('\n'));
  const parsed = spawnSync('tree-sitter', ['parse', '--grammar-path', grammar, '--quiet', '--paths', paths],
                           {encoding: 'utf8'});
  const failures = parsed.stdout.split('\n').filter(line => /ERROR|MISSING/.test(line));
  assert.deepEqual(failures, [], `files the grammar does not parse:\n${failures.join('\n')}`);
  assert.ok(files.length > 100, `parsed only ${files.length} files`);

  const colored = listed('editors/zed/languages/snail-scheme/highlights.scm', '((symbol) @keyword', '\n\n');
  const keywords = [...listed('src/snail/shell/compiler/core.sld', '(define (core-keywords)', '(define'),
                    ...listed('src/snail/shell/highlight.sld', '(define (keywords)', '(define')];
  assert.deepEqual([...colored].sort(), [...keywords].sort(),
                   'highlights.scm colors other keywords than (snail shell highlight)');
} finally {
  rmSync(scratch, {recursive: true, force: true});
}
