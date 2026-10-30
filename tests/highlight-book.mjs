// The book's preprocessor, bootstrap/highlight-book.sld, run as mdbook runs
// it: it supports only the HTML renderer, and given [context, book] on
// standard input it prints the book with each `scheme` block as the
// highlighter's spans, leaving every other block and line as it was.
//
//   node tests/highlight-book.mjs ROOT HIGHLIGHTER.wasm
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {join} from 'node:path';

const [root, program] = process.argv.slice(2);
const runner = join(root, 'host/native/run-snail.mjs');
const run = (args, input = '') => spawnSync(process.execPath, ['--no-warnings', runner, program, ...args], {input, encoding: 'utf8'});

assert.equal(run(['supports', 'html']).status, 0);
assert.equal(run(['supports', 'markdown']).status, 1);

const text = '```text\n```scheme\n(define x 1)\n```\n';
const listed = '- An item:\n\n  ```scheme\n  #t\n  ```\n';
const chapter = (content, sub_items = []) =>
  ({Chapter: {name: 'Sample', content, number: [1], sub_items, path: 'sample.md', source_path: 'sample.md', parent_names: []}});
const book = {items: [chapter(`# Sample\n\n\`\`\`scheme\n(define (f x) "a<b") ; c\n\`\`\`\n\n${text}`, [chapter(listed)]), 'Separator']};
const result = run([], JSON.stringify([{root, config: {}, renderer: 'html', mdbook_version: '0.5.4'}, book]));
assert.equal(result.status, 0, result.stderr);

const span = (name, text) => `<span class="tok-${name}">${text}</span>`;
const [item, separator] = JSON.parse(result.stdout).items;
const code = [span('punctuation', '('), span('keyword', 'define'), ' ', span('punctuation', '('), span('definition', 'f'), ' ',
              span('identifier', 'x'), span('punctuation', ')'), ' ', span('string', '"a&lt;b"'), span('punctuation', ')'), ' ',
              span('comment', '; c'), '&#10;'].join('');
assert.equal(item.Chapter.content, `# Sample\n\n<pre><code class="nohighlight">${code}</code></pre>\n\n${text}`);
assert.equal(item.Chapter.sub_items[0].Chapter.content,
             `- An item:\n\n  <pre><code class="nohighlight">${span('boolean', '#t')}&#10;</code></pre>\n`);
assert.equal(separator, 'Separator');
