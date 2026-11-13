// `snail dev` in a real browser, observed from outside the service
// (tests/development-service.mjs). Disk edits, compiler updates and file
// saves are independent; delayed HTTP replies must not erase typing.
// CHROMIUM=... node tests/browser/ide.mjs ROOT [SCREENSHOT]
import assert from 'node:assert/strict';
import {mkdtemp, readFile, rm, unlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {startDevelopment} from '../development-service.mjs';
import {openBrowser, sleep, until} from './chromium.mjs';
import {command} from './ide-commands.mjs';

const [root, screenshot] = process.argv.slice(2), project = await mkdtemp(join(tmpdir(), 'snail-ide-'));
const source = join(project, 'main.sld'), description = join(project, 'project.datum');
const config = '((build-target main (program (entry "main.sld"))))';
const program = text => `(import (snail core base) (snail core io))\n(define (greeting) (→ String) "${text}")\n(define (main) (→ Unit) (! output-port) (write-line (greeting)))\n`;
await writeFile(description, config); await writeFile(source, program('hello'));
await writeFile(join(project, 'notes.txt'), 'plain text\r\n');
const service = await startDevelopment(root, project), browser = await openBrowser();
const text = () => browser.evaluate('document.querySelector(".pane.active textarea").value');
const title = () => browser.evaluate('document.querySelector(".pane.active .pane-title").textContent');
const problem = () => browser.evaluate('document.querySelector(".pane.active .pane-problem").textContent');
const click = id => command(browser, ({save: 'save-buffer', reload: 'reload-buffer', build: 'build-project'})[id] ?? id);
const press = init => browser.evaluate(`document.querySelector('.pane.active textarea').dispatchEvent(new KeyboardEvent('keydown', ${JSON.stringify({bubbles: true, cancelable: true, ...init})}))`);
const type = (from, to) => browser.evaluate(`(() => { const t = document.querySelector('.pane.active textarea'), at = t.value.indexOf(${JSON.stringify(from)});
  if (at < 0 || t.disabled) return false; t.focus(); t.setSelectionRange(at, at + ${from.length}); return document.execCommand('insertText', false, ${JSON.stringify(to)}); })()`);
const select = path => browser.evaluate(`document.querySelector('.file[data-path=${JSON.stringify(path)}]').click()`);
const built = () => browser.evaluate('document.getElementById("status").dataset.state === "built"');
const saved = () => until(async () => !(await title()).includes('●') && !(await problem()), 'saved baseline');
const attemptShown = async () => Number(await browser.evaluate('document.getElementById("status").dataset.attempt'));
try {
  await browser.navigate(service.url + '/');
  await until(async () => (await text())?.includes('"hello"') && await built(), 'initial native project');
  assert.equal(await title(), 'main.sld');
  const attempt = (await service.status()).id;
  // A failed save remains visible after its successful follow-up read.
  assert.ok(await type('"hello"', '"hello draft"'));
  await browser.evaluate(`window.actualFetch = window.fetch;
    window.fetch = (...args) => args[1]?.method === 'PUT'
      ? Promise.resolve(new Response(JSON.stringify({message: 'save rejected for test'}), {status: 500}))
      : window.actualFetch(...args);`);
  await click('save');
  await until(async () => (await problem()).includes('save rejected for test'), 'save failure');
  await sleep(150);
  assert.match(await problem(), /save rejected for test/);
  assert.match(await text(), /"hello draft"/);
  await browser.evaluate('window.fetch = window.actualFetch; window.confirm = () => true');
  await click('reload');
  await until(async () => (await text()).includes('"hello"') && !(await problem()), 'failed-save recovery');
  assert.ok(await type('"hello"', '5'));
  await sleep(500);
  assert.equal((await service.status()).id, attempt, 'typing does not compile unsaved text');
  assert.match(await readFile(source, 'utf8'), /"hello"/);
  await click('save');
  await until(() => browser.evaluate('document.getElementById("diagnostics").textContent.includes("does not fit String")'), 'fresh compiler diagnostic');
  await until(() => browser.evaluate('document.querySelector(".pane.active .error-highlight")?.textContent === "5"'), 'fresh source observation');
  assert.equal(await browser.evaluate('document.querySelector(".pane.active .error-highlight")?.textContent'), '5', 'compiler-provided point');
  assert.ok(await type('(define (greeting) (→ String) 5)', '(define (greeting) (→ String)\n"fixed")'));
  await browser.evaluate(`(() => { const t = document.querySelector('.pane.active textarea'); const at = t.value.indexOf('"fixed"'); t.setSelectionRange(at, at); })()`);
  await press({key: 'Tab'});
  await until(async () => /\(define \(greeting\) \(→ String\)\n  "fixed"\)/.test(await text()), 'the indented line');
  // Enter trims the old line's trailing spaces and indents what follows;
  // the page undoes the complete change as typing.
  await browser.evaluate(`(() => { const t = document.querySelector('.pane.active textarea'); const at = t.value.indexOf('"fixed"');
    t.focus(); t.setSelectionRange(at, at); })()`);
  await press({key: 'Enter'});
  await until(async () => /\(define \(greeting\) \(→ String\)\n\n  "fixed"\)/.test(await text()), 'the indented new line');
  await browser.evaluate(`document.execCommand('undo')`);
  await until(async () => /\(define \(greeting\) \(→ String\)\n  "fixed"\)/.test(await text()), 'the undone new line');
  await press({code: 'KeyS', key: 's', ctrlKey: true});
  await saved(); await until(built, 'fixed build');
  assert.equal(await browser.evaluate('document.getElementById("diagnostics").textContent'), '');

  // Even a formatter/editor replacement failure must not prevent persistence.
  assert.ok(await type('  "fixed"', '          "unformatted"'));
  await browser.evaluate("window.insertCommand = document.execCommand; document.execCommand = () => { throw new Error('format replacement failed'); };");
  await click('save'); await saved();
  await browser.evaluate('document.execCommand = window.insertCommand');
  assert.match(await readFile(source, 'utf8'), /          "unformatted"/);

  const unicode = '(import (snail core base))\r\n(define (greeting) (→ String) (if #t "😀" 5))\r\n';
  // A diagnostic can arrive before its source GETs. Keep the old editor text
  // visible, but do not apply the new point to that older baseline.
  await browser.evaluate(`window.actualFetch = window.fetch; window.sourceReads = []; window.holdSource = true;
    window.fetch = async (...args) => { const response = await window.actualFetch(...args);
      if (window.holdSource && String(args[0]).startsWith('/api/file?path=main.sld') && !args[1]?.method)
        await new Promise(resolve => window.sourceReads.push(resolve));
      return response; };`);
  const beforeUnicode = (await service.status()).id;
  await writeFile(source, unicode);
  await until(async () => {
    const current = await service.status();
    return current.id > beforeUnicode && current.phase === 'failed' && await attemptShown() === current.id &&
      await browser.evaluate('window.sourceReads.length > 0');
  }, 'failure before its source reads');
  assert.match(await text(), /unformatted/);
  assert.equal(await browser.evaluate('document.querySelector(".pane.active .error-highlight")'), null);
  await browser.evaluate('window.holdSource = false; for (const release of window.sourceReads) release(); window.fetch = window.actualFetch');
  await until(() => browser.evaluate('document.querySelector(".pane.active .error-highlight")?.textContent === "5"'), 'Unicode compiler point');
  await browser.evaluate('document.querySelector("#diagnostics button").click()');
  await until(async () => await browser.evaluate('document.querySelector(".pane.active textarea").selectionStart') === unicode.replace(/\r\n/g, '\n').indexOf('5'), 'source navigation');
  assert.equal(await browser.evaluate('document.querySelector(".pane.active textarea").selectionStart'), unicode.replace(/\r\n/g, '\n').indexOf('5'));
  // A newer read must withdraw the previous point even before the next build
  // event arrives. Supply that HTTP observation independently of the watcher.
  await browser.evaluate(`window.newerReads = 0;
    window.fetch = (...args) => {
      if (String(args[0]).startsWith('/api/file?path=main.sld') && !args[1]?.method) {
        window.newerReads++; return Promise.resolve(new Response(JSON.stringify({text: ${JSON.stringify(program('newer observation'))}, revision: 'newer'})));
      } return window.actualFetch(...args); };`);
  await click('reload');
  await until(async () => (await text()).includes('newer observation'), 'newer baseline before build');
  assert.equal(await browser.evaluate('document.querySelector(".pane.active .error-highlight")'), null);
  assert.match(await browser.evaluate('document.getElementById("diagnostics").textContent'), /does not fit String/);
  await browser.evaluate('window.beforeReconnectReads = window.newerReads; document.getElementById("status").textContent = "Connection lost"; window.dispatchEvent(new Event("online"))');
  await until(() => browser.evaluate('window.newerReads > window.beforeReconnectReads && document.getElementById("status").textContent === "Build failed"'), 'replayed failure and fresh files');
  assert.equal(await browser.evaluate('document.querySelector(".pane.active .error-highlight")'), null, 'reconnect cannot rebind an old point to a newer read');
  await browser.evaluate('window.fetch = window.actualFetch');
  await click('reload');
  await until(() => browser.evaluate('document.querySelector(".pane.active .error-highlight")?.textContent === "5"'), 'matching observation restored');

  // Save invalidates the old failure even if its successor build has not yet
  // arrived. Keep the server status fixed while acknowledging the submitted text.
  await browser.evaluate(`window.savedObservation = null; window.savedReads = 0;
    window.fetch = (...args) => {
      if (String(args[0]).startsWith('/api/file?path=main.sld')) {
        if (args[1]?.method === 'PUT') window.savedObservation = {text: args[1].body, revision: 'saved'};
        if (window.savedObservation) {
          if (!args[1]?.method) window.savedReads++;
          return Promise.resolve(new Response(JSON.stringify(window.savedObservation)));
        }
      } return window.actualFetch(...args); };`);
  await click('save'); await saved();
  assert.equal(await browser.evaluate('document.querySelector(".pane.active .error-highlight")'), null);
  await browser.evaluate('window.dispatchEvent(new Event("online"))');
  await until(() => browser.evaluate('window.savedReads > 0'), 'replay after acknowledged save');
  assert.equal(await browser.evaluate('document.querySelector(".pane.active .error-highlight")'), null, 'reconnect preserves Save invalidation');
  await browser.evaluate('window.fetch = window.actualFetch');
  await click('reload');
  await until(async () => (await text()) === unicode.replace(/\r\n/g, '\n'), 'actual saved source');
  await click('build');
  await until(() => browser.evaluate('document.querySelector(".pane.active .error-highlight")?.textContent === "5"'), 'new failure replaces invalidation');
  assert.ok(await type('5', '"draft"'));
  assert.equal(await browser.evaluate('document.querySelector(".pane.active .error-highlight")'), null, 'unsaved text has no compiled point');
  await browser.evaluate('window.confirm = () => true');
  await click('reload');

  await writeFile(source, program('external'));
  await until(async () => (await text()).includes('"external"'), 'clean external edit');
  assert.ok(await type('"external"', '"draft"'));
  await writeFile(source, program('another writer'));
  await until(async () => (await problem()).includes('Changed on disk'), 'dirty external conflict');
  assert.match(await text(), /"draft"/);
  await click('save');
  await until(() => browser.evaluate('document.querySelector(".pane.active textarea").getAttribute("aria-busy") === "false"'), 'conflicting save completion');
  assert.match(await readFile(source, 'utf8'), /"another writer"/);
  await browser.evaluate('window.confirm = () => true');
  await click('reload');
  await until(async () => (await text()).includes('"another writer"') && !(await problem()), 'explicit reload');

  // Save/read ordering is exercised by tests/programs/ide-application.sld
  // against the same update loop, with deterministically delayed fetch replies.
  assert.ok(await type('"another writer"', '"new revision"'));
  await click('save'); await saved();

  // A split adds a pane beside the first, whose field stays, with its caret.
  await browser.evaluate(`(() => { window.firstField = document.querySelector('.pane.active textarea'); window.firstField.setSelectionRange(3, 3); })()`);
  await click('split-right');
  assert.equal(await browser.evaluate('document.querySelectorAll(".pane").length'), 2);
  assert.equal(await browser.evaluate('document.querySelector(".pane textarea") === window.firstField && window.firstField.isConnected'), true);
  assert.equal(await browser.evaluate('window.firstField.selectionStart'), 3);
  assert.ok(await type('"new revision"', '"two panes"'));
  assert.match(await browser.evaluate('document.querySelector(".pane textarea").value'), /"two panes"/);
  await click('save'); await saved();
  if (screenshot) await browser.screenshot(screenshot);

  // Reconnecting the event stream refreshes disk state without replay history.
  await browser.send('Network.enable');
  await browser.send('Network.emulateNetworkConditions', {offline: true, latency: 0, downloadThroughput: -1, uploadThroughput: -1});
  await writeFile(source, program('while disconnected'));
  await sleep(300);
  await browser.send('Network.emulateNetworkConditions', {offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1});
  await until(async () => (await text()).includes('"while disconnected"'), 'event reconnection');
  await until(async () => await attemptShown() === (await service.status()).id && await built(), 'current attempt after reconnect');

  await select('notes.txt');
  await until(async () => (await text()) === 'plain text\n', 'plain text file');
  assert.equal(await title(), 'notes.txt', 'CRLF read does not mark an untouched file dirty');
  await unlink(join(project, 'notes.txt'));
  await until(async () => (await title()) === 'main.sld', 'clean deletion returns to retained tab');
  await select('main.sld');
  assert.ok(await type('"while disconnected"', '"deleted draft"'));
  await unlink(source);
  await until(async () => (await problem()).includes('Deleted on disk'), 'dirty deletion');
  assert.match(await text(), /"deleted draft"/);
  await click('save');
  await until(() => browser.evaluate('document.querySelector(".pane.active textarea").getAttribute("aria-busy") === "false"'), 'deleted save rejection');
  await assert.rejects(readFile(source), {code: 'ENOENT'});
  // Discard removes the deleted file's buffer without reopening another file.
  await click('reload');
  await until(() => browser.evaluate(`![...document.querySelectorAll('.pane-title')].some(title => title.textContent.startsWith('main.sld'))
    && !document.querySelector('.file[data-path="main.sld"]')`), 'discard deleted draft');
  await unlink(description);
  await until(() => browser.evaluate('document.querySelectorAll(".file").length === 0'), 'empty project');
  // Explicit refresh checkpoints the current recovery state before navigation;
  // raw navigation may restore the previous five-second background checkpoint.
  await browser.evaluate('window.beforeRecoveryRefresh = true');
  await click('refresh-ide');
  await until(() => browser.evaluate('window.beforeRecoveryRefresh === undefined && document.querySelector(".pane textarea")?.disabled'), 'empty editor after reload');

  await writeFile(description, config); await writeFile(source, program('restored'));
  // Recovery preserves the user's empty pane; reopening is an explicit intent.
  await until(() => browser.evaluate(`Boolean(document.querySelector('.file[data-path="main.sld"]'))`), 'restored file listing');
  await browser.evaluate(`document.querySelector('.file[data-path="main.sld"]').click()`);
  await until(async () => (await text())?.includes('"restored"') && await built(), 'project restored from disk');
  const previous = (await service.status()).id;
  await click('build');
  await until(async () => {
    const current = await service.status();
    return current.id > previous && current.phase === 'succeeded';
  }, 'manual Build');

  // The command releases the service on an ordinary signal.
  const {code, signal, stderr} = await service.stop();
  assert.deepEqual({code, signal}, {code: 0, signal: null}, stderr);
  console.log('ide: native save/build, external edits, conflicts, delayed replies, deletion, reconnect and dev shutdown');
} catch (error) {
  console.error('IDE failure:', {text: await text(), problem: await problem(), status: await service.status()});
  throw error;
} finally {
  browser.close();
  await service.stop();
  await rm(project, {recursive: true, force: true});
}
