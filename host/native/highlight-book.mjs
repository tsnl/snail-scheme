#!/usr/bin/env node
// The book's code highlighter, the mdbook preprocessor book.toml names.
// mdbook asks `highlight-book.mjs supports RENDERER` first, then writes
// [context, book] as JSON to standard input and reads the book back from
// standard output. Each fenced block whose language is `scheme` becomes the
// HTML that host/native/highlight.sld, (snail-core highlight) compiled to
// Wasm, makes of it by the compiler's own lexical rules; other blocks are
// left to highlight.js. The program is the one argument, or else
// `scripts/snail-tool book-tools` builds it when its sources are newer.
import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createWasi, instantiate} from '../browser/load.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '../..');

// ---- Protocol ----

async function main([command, renderer]) {
  if (command === 'supports') process.exit(renderer === 'html' ? 0 : 1);
  const highlight = await createHighlighter(readFileSync(command ?? bookTools().highlighter));
  const [, book] = JSON.parse(readFileSync(0, 'utf8'));
  for (const item of book.items ?? book.sections) visit(item, highlight);
  process.stdout.write(JSON.stringify(book));
}

// Separators and part titles have no content; a chapter's sub-items are
// chapters too.
function visit(item, highlight) {
  if (!item.Chapter) return;
  item.Chapter.content = highlightBlocks(item.Chapter.content, highlight);
  for (const sub of item.Chapter.sub_items) visit(sub, highlight);
}

// The tools the build driver keeps current, by name.
function bookTools() {
  const result = spawnSync(join(root, 'scripts/snail-tool'), ['book-tools'], {encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit']});
  if (result.status !== 0) throw new Error(`scripts/snail-tool book-tools exited with ${result.signal ?? result.status}`);
  return JSON.parse(result.stdout);
}

// ---- Fenced blocks ----

// As CommonMark has it: a fence is three or more backticks or tildes, and
// the first word of its info string names the language; a fence of the
// same character, at least as long and with nothing after it, closes the
// block, or else the chapter's end does; and as many spaces as the opening
// fence's indentation are removed from each line. Containers are not
// parsed, so a fence may be indented by any amount, as it is in a list
// item. A `scheme` block becomes one line of HTML, its newlines written
// `&#10;`, so it keeps its place in a list item. Its class, `nohighlight`,
// is the one highlight.js leaves alone.
function highlightBlocks(markdown, highlight) {
  const lines = markdown.split('\n'), out = [];
  for (let index = 0; index < lines.length; index++) {
    const fence = /^( *)(`{3,}|~{3,})(.*)$/.exec(lines[index]);
    if (!fence || (fence[2][0] === '`' && fence[3].includes('`'))) { out.push(lines[index]); continue; }
    const [, indent, marker, info] = fence, closing = new RegExp(`^ *${marker[0]}{${marker.length},}[ \\t]*$`);
    let end = index + 1;
    while (end < lines.length && !closing.test(lines[end])) end++;
    if (info.trim().split(/[\s,]/)[0] === 'scheme') {
      const code = lines.slice(index + 1, end).map(line => `${line.replace(new RegExp(`^ {0,${indent.length}}`), '')}\n`).join('');
      out.push(`${indent}<pre><code class="nohighlight">${highlight(code).replaceAll('\n', '&#10;')}</code></pre>`);
    } else {
      out.push(...lines.slice(index, end + 1));
    }
    index = end;
  }
  return out.join('\n');
}

// ---- The highlighter ----

// One instance of the program, called for each block. Text crosses a
// character at a time each way, as it does for the IDE's formatter in
// host/ide/formatter.mjs. A panic's message is what the program wrote to
// standard error.
async function createHighlighter(bytes) {
  const errors = [], wasi = createWasi({print: (fd, line) => errors.push(line)});
  const instance = await instantiate(await WebAssembly.compile(bytes), wasi.getImportObject());
  wasi.initialize(instance);
  instance.exports.main();
  const {highlight_character, highlight_html, highlight_result} = instance.exports;
  return text => {
    try {
      for (const character of text) highlight_character(character.codePointAt(0));
      let html = '';
      for (let index = 0, length = highlight_html(); index < length; index++) html += String.fromCodePoint(highlight_result(index));
      return html;
    } catch (error) {
      throw new Error(errors.join('\n') || error.message);
    }
  };
}

await main(process.argv.slice(2));
