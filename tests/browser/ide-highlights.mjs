// Lexical error ranges over real compiler failures, across syntax runs,
// lines and the editor's virtualized coloring window.
// CHROMIUM=... node tests/browser/ide-highlights.mjs ROOT [SCREENSHOT]
import assert from 'node:assert/strict';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {startDevelopment} from '../development-service.mjs';
import {openBrowser, until} from './chromium.mjs';

const [root, screenshot] = process.argv.slice(2), project = await mkdtemp(join(tmpdir(), 'snail-ide-highlights-'));
const source = join(project, 'main.sld');
const prefix = '(import (snail core base))\n(: take-one (-> String String))\n(define (take-one x) x)\n';
await writeFile(join(project, 'project.datum'), '((build-target main (program (entry "main.sld"))))');
await writeFile(source, prefix);
const service = await startDevelopment(root, project), browser = await openBrowser();
const marker = () => browser.evaluate('document.querySelector(".pane.active .error-highlight")?.textContent');

async function failed(text, marked) {
  const before = (await service.status()).id;
  await writeFile(source, text);
  await service.settled(before, 'failed');
  await until(() => browser.evaluate(`document.querySelector('.pane.active textarea')?.value === ${JSON.stringify(text.replace(/\r\n/g, '\n'))}`), 'failed source in editor');
  await until(async () => await marker() === marked, 'complete error highlight');
}

// Compare the actual text's geometry in the syntax and mark layers. The
// syntax layer contains only a window of lines; the mark can start above it.
async function aligned(fragment) {
  const boxes = await browser.evaluate(`(() => {
    const syntax = document.querySelector('.pane.active .highlight');
    const mark = document.querySelector('.pane.active .error-highlight');
    const box = element => {
      let offset = element.textContent.indexOf(${JSON.stringify(fragment)});
      if (offset < 0) return null;
      const nodes = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
      for (let node; node = nodes.nextNode();) {
        if (offset < node.length) {
          const range = document.createRange();
          range.setStart(node, offset); range.setEnd(node, offset + 1);
          const rect = range.getBoundingClientRect();
          return [rect.x, rect.y, rect.width, rect.height];
        }
        offset -= node.length;
      }
    };
    return [box(syntax), box(mark)];
  })()`);
  assert.ok(boxes[0], `syntax contains ${fragment}`);
  assert.ok(boxes[1], `mark contains ${fragment}`);
  for (let i = 0; i < 4; i++) assert.ok(Math.abs(boxes[0][i] - boxes[1][i]) < 1, `matching geometry: ${JSON.stringify(boxes)}`);
}

try {
  await browser.navigate(service.url + '/');
  await until(() => browser.evaluate('document.querySelector(".pane.active textarea")?.value.includes("take-one")'), 'editor');

  // CRLF and an astral character before the compiler point: highlight the
  // whole multi-character literal without shifting the navigation position.
  const number = prefix + '(define bad (if #t "😀" 12345))\n';
  await failed(number.replace(/\n/g, '\r\n'), '12345');
  await aligned('12345');
  await browser.evaluate('document.querySelector("#diagnostics button").click()');
  await until(() => browser.evaluate(`document.querySelector('.pane.active textarea').selectionStart === ${number.indexOf('12345')}`), 'exact compiler point');
  assert.equal(await browser.evaluate('getComputedStyle(document.querySelector(".error-highlight")).textDecorationLine'), 'none');
  assert.equal(await browser.evaluate('getComputedStyle(document.querySelector(".error-highlight")).backgroundColor'), 'rgba(224, 108, 117, 0.24)');

  // Wrong argument count locates the call's opening bracket. Its display
  // includes nested calls, comments, whitespace and different syntax colors.
  const form = '(take-one\n\t(string-append "😀 ]"\n\t               (if #t "(" ")"))\n  #| ) [ #| nested |# |#\n  #;(ignored [datum])\n  "extra")';
  await failed(prefix + `(define bad ${form})\n`, form);
  await aligned('(take-one\n');
  await aligned('string-append');
  await aligned('"extra"');
  const lines = await browser.evaluate('document.querySelector(".error-highlight").getClientRects().length');
  assert.ok(lines >= form.split('\n').length, 'background spans each source line');
  if (screenshot) await browser.screenshot(screenshot);

  const longForm = form.replace('  "extra"', Array.from({length: 200}, (_, i) => `  ; continuation ${i}`).join('\n') + '\n  "extra"');
  await failed(prefix + `(define bad ${longForm})\n`, longForm);
  await browser.evaluate(`const editor = document.querySelector('.pane.active .editor'); editor.scrollTop = editor.scrollHeight; editor.scrollLeft = 35; editor.dispatchEvent(new Event('scroll'));`);
  await until(() => browser.evaluate('parseFloat(document.querySelector(".pane.active .highlight").style.top) > 0'), 'virtualized syntax window');
  await aligned('"extra"');
  assert.equal(await marker(), longForm, 'scrolling retains the full range');

  // An unterminated block comment reports EOF. Preserve its visible cell,
  // anchored after the source instead of expanding the preceding token.
  const incomplete = prefix + '#| unfinished';
  await failed(incomplete, ' ');
  assert.equal(await browser.evaluate('document.querySelector(".pane.active .marks").textContent'), incomplete + ' ');
  assert.ok(await browser.evaluate('document.querySelector(".error-highlight").getBoundingClientRect().width > 0'));

  await browser.evaluate(`const textarea = document.querySelector('.pane.active textarea'); textarea.focus(); textarea.setSelectionRange(0, 0); document.execCommand('insertText', false, ${JSON.stringify('; draft\n')});`);
  await until(async () => await marker() == null, 'draft withdraws the range');
  console.log('IDE error highlights passed');
} finally {
  browser.close();
  await service.stop();
  await rm(project, {recursive: true, force: true});
}
