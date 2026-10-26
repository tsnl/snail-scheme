// The native project service in a real browser. Disk edits, compiler updates
// and file saves are independent; delayed HTTP replies must not erase typing.
// CHROMIUM=... node tests/browser/ide.mjs ROOT [SCREENSHOT]
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp, readFile, rm, unlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {serveProject} from '../../scripts/project-http.mjs';
import {editorTools} from '../../scripts/project.mjs';
import {openBrowser, sleep, until} from './chromium.mjs';

const [root, screenshot] = process.argv.slice(2), project = await mkdtemp(join(tmpdir(), 'lofi-ide-'));
const source = join(project, 'main.sld'), description = join(project, 'project.datum');
const config = '((build-target main (program (entry "main.sld"))))';
const program = text => `(import (lofi base) (lofi io))\n(: greeting String)\n(define greeting "${text}")\n(write-line greeting)\n`;
await writeFile(description, config); await writeFile(source, program('hello'));
await writeFile(join(project, 'notes.txt'), 'plain text\r\n');
const tools = editorTools(root), service = await serveProject({root, project, tools});
const browser = await openBrowser();
const text = () => browser.evaluate('document.querySelector(".pane.active textarea").value');
const title = () => browser.evaluate('document.querySelector(".pane.active .pane-title").textContent');
const problem = () => browser.evaluate('document.querySelector(".pane.active .pane-problem").textContent');
const click = id => browser.evaluate(`document.getElementById(${JSON.stringify(id)}).click()`);
const press = init => browser.evaluate(`document.querySelector('.pane.active textarea').dispatchEvent(new KeyboardEvent('keydown', ${JSON.stringify({bubbles: true, cancelable: true, ...init})}))`);
const type = (from, to) => browser.evaluate(`(() => { const t = document.querySelector('.pane.active textarea'), at = t.value.indexOf(${JSON.stringify(from)});
  if (at < 0 || t.disabled) return false; t.focus(); t.setSelectionRange(at, at + ${from.length}); return document.execCommand('insertText', false, ${JSON.stringify(to)}); })()`);
const select = path => browser.evaluate(`document.querySelector('.file[data-path=${JSON.stringify(path)}]').click()`);
const built = () => browser.evaluate('document.getElementById("status").dataset.state === "built"');
const saved = () => until(async () => !(await title()).includes('●') && !(await problem()), 'saved baseline');
let cli = null;
try {
  await browser.navigate(service.url + '/');
  await until(async () => (await text())?.includes('"hello"') && await built(), 'initial native project');
  assert.equal(await title(), 'main.sld');
  const attempt = service.development.status.id;
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
  assert.equal(service.development.status.id, attempt, 'typing does not compile unsaved text');
  assert.match(await readFile(source, 'utf8'), /"hello"/);
  await click('save');
  await until(() => browser.evaluate('document.getElementById("diagnostics").textContent.includes("does not fit String")'), 'fresh compiler diagnostic');
  await until(() => browser.evaluate('document.querySelector(".pane.active .squiggle")?.textContent === "5"'), 'fresh source observation');
  assert.equal(await browser.evaluate('document.querySelector(".pane.active .squiggle")?.textContent'), '5', 'compiler-provided point');
  assert.ok(await type('(define greeting 5)', '(define greeting\n"fixed")'));
  await browser.evaluate(`(() => { const t = document.querySelector('.pane.active textarea'); const at = t.value.indexOf('"fixed"'); t.setSelectionRange(at, at); })()`);
  await press({key: 'Tab'});
  assert.match(await text(), /\(define greeting\n  "fixed"\)/);
  await press({code: 'KeyS', key: 's', ctrlKey: true});
  await saved(); await until(built, 'fixed build');
  assert.equal(await browser.evaluate('document.getElementById("diagnostics").textContent'), '');

  // Even a formatter/editor replacement failure must not prevent persistence.
  assert.ok(await type('  "fixed"', '          "unformatted"'));
  await browser.evaluate("window.insertCommand = document.execCommand; document.execCommand = () => { throw new Error('format replacement failed'); };");
  await click('save'); await saved();
  await browser.evaluate('document.execCommand = window.insertCommand');
  assert.match(await readFile(source, 'utf8'), /          "unformatted"/);

  const unicode = '(import (lofi base))\r\n(: greeting String)\r\n(define greeting (if #t "😀" 5))\r\n';
  // A diagnostic can arrive before its source GETs. Keep the old editor text
  // visible, but do not apply the new point to that older baseline.
  await browser.evaluate(`window.actualFetch = window.fetch; window.sourceReads = []; window.holdSource = true;
    window.fetch = async (...args) => { const response = await window.actualFetch(...args);
      if (window.holdSource && String(args[0]).startsWith('/api/file?path=main.sld') && !args[1]?.method)
        await new Promise(resolve => window.sourceReads.push(resolve));
      return response; };`);
  const beforeUnicode = service.development.status.id;
  await writeFile(source, unicode);
  await until(async () => service.development.status.id > beforeUnicode && service.development.status.phase === 'failed' &&
    Number(await browser.evaluate('document.getElementById("status").dataset.attempt')) === service.development.status.id &&
    await browser.evaluate('window.sourceReads.length > 0'), 'failure before its source reads');
  assert.match(await text(), /unformatted/);
  assert.equal(await browser.evaluate('document.querySelector(".pane.active .squiggle")'), null);
  await browser.evaluate('window.holdSource = false; for (const release of window.sourceReads) release(); window.fetch = window.actualFetch');
  await until(() => browser.evaluate('document.querySelector(".pane.active .squiggle")?.textContent === "5"'), 'Unicode compiler point');
  await browser.evaluate('document.querySelector("#diagnostics button").click()');
  await until(async () => await browser.evaluate('document.querySelector(".pane.active textarea").selectionStart') === unicode.replace(/\r\n/g, '\n').indexOf('5'), 'source navigation');
  assert.equal(await browser.evaluate('document.querySelector(".pane.active textarea").selectionStart'), unicode.replace(/\r\n/g, '\n').indexOf('5'));
  // A newer read must withdraw the previous point even before the next build
  // event arrives. Supply that HTTP observation independently of the watcher.
  await browser.evaluate(`window.fetch = (...args) => String(args[0]).startsWith('/api/file?path=main.sld') && !args[1]?.method
    ? Promise.resolve(new Response(JSON.stringify({text: ${JSON.stringify(program('newer observation'))}, revision: 'newer'})))
    : window.actualFetch(...args);`);
  await click('reload');
  await until(async () => (await text()).includes('newer observation'), 'newer baseline before build');
  assert.equal(await browser.evaluate('document.querySelector(".pane.active .squiggle")'), null);
  assert.match(await browser.evaluate('document.getElementById("diagnostics").textContent'), /does not fit String/);
  await browser.evaluate('window.fetch = window.actualFetch');
  await click('reload');
  await until(() => browser.evaluate('document.querySelector(".pane.active .squiggle")?.textContent === "5"'), 'matching observation restored');
  assert.ok(await type('5', '"draft"'));
  assert.equal(await browser.evaluate('document.querySelector(".pane.active .squiggle")'), null, 'unsaved text has no compiled point');
  await browser.evaluate('window.confirm = () => true');
  await click('reload');

  await writeFile(source, program('external'));
  await until(async () => (await text()).includes('"external"'), 'clean external edit');
  assert.ok(await type('"external"', '"draft"'));
  await writeFile(source, program('another writer'));
  await until(async () => (await problem()).includes('Changed on disk'), 'dirty external conflict');
  assert.match(await text(), /"draft"/);
  await click('save');
  await until(() => browser.evaluate('!document.getElementById("save").disabled'), 'conflicting save completion');
  assert.match(await readFile(source, 'utf8'), /"another writer"/);
  await browser.evaluate('window.confirm = () => true');
  await click('reload');
  await until(async () => (await text()).includes('"another writer"') && !(await problem()), 'explicit reload');

  // Discard is immediate, so a newer watcher read can finish Reload;
  // subsequent typing survives the older discard request's delayed response.
  assert.ok(await type('"another writer"', '"discard me"'));
  await browser.evaluate(`window.actualFetch = window.fetch;
    window.fetch = async (...args) => { const response = await window.actualFetch(...args);
      if (String(args[0]).startsWith('/api/file?path=main.sld') && !window.heldReload) {
        window.heldReload = true; await new Promise(resolve => window.releaseReload = resolve);
      } return response; };`);
  await click('reload');
  await until(() => browser.evaluate('window.heldReload'), 'held reload');
  await writeFile(source, program('watcher during reload'));
  await until(async () => (await text()).includes('"watcher during reload"'), 'watcher completes discard');
  assert.ok(await type('"watcher during reload"', '"typing after reload"'));
  await browser.evaluate('window.releaseReload(); window.fetch = window.actualFetch');
  await sleep(100);
  assert.match(await text(), /"typing after reload"/);
  await click('reload');
  await until(async () => (await text()).includes('"watcher during reload"'), 'discard later typing');

  // Hold the successful save response after its real disk write. Later typing
  // remains a draft against the submitted bytes, even with watcher updates.
  await browser.evaluate(`window.actualFetch = window.fetch;
    window.fetch = async (...args) => { const response = await window.actualFetch(...args);
      if (args[1]?.method === 'PUT' && !window.heldSave) { window.heldSave = true; await new Promise(resolve => window.releaseSave = resolve); }
      return response; };`);
  assert.ok(await type('"watcher during reload"', '"submitted"'));
  await click('save');
  await until(() => browser.evaluate('window.heldSave'), 'held save response');
  assert.ok(await type('"submitted"', '"typed later"'));
  await browser.evaluate('window.releaseSave()');
  await until(() => browser.evaluate('!document.getElementById("save").disabled'), 'save release');
  assert.match(await readFile(source, 'utf8'), /"submitted"/);
  assert.match(await text(), /"typed later"/); assert.match(await title(), /●/);
  await browser.evaluate('window.fetch = window.actualFetch');
  await click('save'); await saved();

  // A read begun before Save cannot restore its older revision afterward.
  await browser.evaluate(`window.fetch = async (...args) => { const response = await window.actualFetch(...args);
    if (String(args[0]).startsWith('/api/file?path=main.sld') && !args[1]?.method && !window.heldRead) {
      window.heldRead = true; await new Promise(resolve => window.releaseRead = resolve);
    } return response; };`);
  await writeFile(source, await readFile(source));
  await until(() => browser.evaluate('window.heldRead'), 'held old file read');
  assert.ok(await type('"typed later"', '"new revision"'));
  await click('save'); await saved();
  await browser.evaluate('window.releaseRead(); window.fetch = window.actualFetch');
  await sleep(100);
  assert.ok(await type('"new revision"', '"after stale read"'));
  await click('save'); await saved();
  assert.match(await readFile(source, 'utf8'), /"after stale read"/);

  await click('split-right');
  assert.equal(await browser.evaluate('document.querySelectorAll(".pane").length'), 2);
  assert.ok(await type('"after stale read"', '"two panes"'));
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
  await until(async () => Number(await browser.evaluate('document.getElementById("status").dataset.attempt')) === service.development.status.id && await built(), 'current attempt after reconnect');

  await select('notes.txt');
  await until(async () => (await text()) === 'plain text\n', 'plain text file');
  assert.equal(await title(), 'notes.txt', 'CRLF read does not mark an untouched file dirty');
  await unlink(join(project, 'notes.txt'));
  await until(async () => (await title()) === 'Choose a file', 'clean deletion');
  await select('main.sld');
  assert.ok(await type('"while disconnected"', '"deleted draft"'));
  await unlink(source);
  await until(async () => (await problem()).includes('Deleted on disk'), 'dirty deletion');
  assert.match(await text(), /"deleted draft"/);
  await click('save');
  await until(() => browser.evaluate('!document.getElementById("save").disabled'), 'deleted save rejection');
  await assert.rejects(readFile(source), {code: 'ENOENT'});
  await click('reload');
  await until(async () => (await title()) === 'Choose a file', 'discard deleted draft');
  await unlink(description);
  await until(() => browser.evaluate('document.querySelectorAll(".file").length === 0'), 'empty project');
  await browser.navigate(service.url + '/');
  await until(() => browser.evaluate('document.querySelector(".pane textarea")?.disabled'), 'empty editor after reload');

  await writeFile(description, config); await writeFile(source, program('restored'));
  await until(async () => (await text())?.includes('"restored"') && await built(), 'project restored from disk');
  const previous = service.development.status.id;
  await click('build');
  await until(() => service.development.status.id > previous && service.development.status.phase === 'succeeded', 'manual Build');
  await service.close();

  // The command owns the same service and releases it on an ordinary signal.
  cli = spawn(join(root, 'lofi'), ['dev', '--port', '0', project], {stdio: ['ignore', 'pipe', 'pipe']});
  let output = '', errors = '';
  cli.stdout.on('data', bytes => output += bytes); cli.stderr.on('data', bytes => errors += bytes);
  const exited = new Promise(resolve => cli.once('exit', (code, signal) => resolve({code, signal})));
  const address = await until(() => /at (http:\/\/127\.0\.0\.1:\d+)\//.exec(output)?.[1], 'dev command address');
  assert.equal((await fetch(address + '/api/project')).status, 200);
  cli.kill('SIGTERM');
  assert.deepEqual(await exited, {code: 0, signal: null}, errors);
  console.log('ide: native save/build, external edits, conflicts, delayed replies, deletion, reconnect and dev shutdown');
} finally {
  cli?.kill('SIGTERM'); browser.close();
  await service.close();
  await rm(project, {recursive: true, force: true});
}
