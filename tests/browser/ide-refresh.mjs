// An isolated copy of the IDE sources: edits rebuild complete browser bundles,
// while drafts and their old disk baselines survive navigation. No test edits
// the checkout or any IDE a person has running from it.
import assert from 'node:assert/strict';
import {cp, mkdir, mkdtemp, readFile, realpath, rm, symlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {basename, join} from 'node:path';
import {startDevelopment} from '../development-service.mjs';
import {openBrowser, until, sleep} from './chromium.mjs';
import {command} from './ide-commands.mjs';

const root = process.argv[2], fixture = await mkdtemp(join(tmpdir(), 'snail-ide-refresh-'));
let service, browser, stream;
try {
  for (const name of ['src', 'host', 'scripts', 'bootstrap', 'snail', 'rust-toolchain.toml'])
    await cp(join(root, name), join(fixture, name), {recursive: true, preserveTimestamps: true,
      filter: path => !path.startsWith(join(root, 'host/ide/build'))});
  await mkdir(join(fixture, 'crates'));
  await symlink(join(root, 'crates/snail-core-support'), join(fixture, 'crates/snail-core-support'));
  const built = await realpath(join(root, 'host/ide/build/ide'));
  await mkdir(join(fixture, 'host/ide/build'), {recursive: true});
  await cp(built, join(fixture, 'host/ide/build', basename(built)), {recursive: true, preserveTimestamps: true});
  await symlink(basename(built), join(fixture, 'host/ide/build/ide'));
  await mkdir(join(fixture, 'build/engine'), {recursive: true});
  await symlink(join(root, 'build/engine/engine.wasm'), join(fixture, 'build/engine/engine.wasm'));
  await writeFile(join(fixture, 'build/tools-dev-tools.txt'), [join(fixture, 'host/ide/build/ide'),
    join(root, 'build/ide-tools/reload.wasm'), join(root, 'build/project/cli.wasm'),
    join(root, 'build/wasm-snail-core-support/wasm32-wasip1/release/snail_core_support.wasm'),
    join(root, 'build/engine/engine.wasm')].join('\n') + '\n');
  const project = join(fixture, 'project');
  await mkdir(project);
  await writeFile(join(project, 'project.datum'), '()');
  await writeFile(join(project, 'main.sld'), '(import (snail core base))\n; original\n');
  service = await startDevelopment(fixture, project);
  stream = await service.events();
  const latest = () => stream.seen.filter(event => event.kind === 'snapshot').at(-1)?.data;
  browser = await openBrowser();
  await browser.navigate(service.url + '/');
  const ready = () => browser.evaluate('Boolean(document.querySelector(".pane.active textarea"))');
  await until(ready, 'initial editor');
  await until(() => browser.evaluate('document.querySelector("textarea").value.includes("original")'), 'initial read');
  const draft = '(import (snail core base))\n; unsaved λ draft\n';
  const type = text => browser.evaluate(`(() => { const field = document.querySelector('.pane.active textarea');
    field.value = ${JSON.stringify(text)}; field.dispatchEvent(new Event('input')); })()`);
  const contents = () => browser.evaluate('document.querySelector(".pane.active textarea")?.value');
  const mark = () => browser.evaluate('window.beforeRefresh = true');
  const navigated = () => browser.evaluate('!window.beforeRefresh && Boolean(document.querySelector(".pane.active textarea"))');
  await type(draft);
  await command(browser, 'split-right');
  await mark();
  const first = latest().editor;
  const css = join(fixture, 'host/ide/public/ide.css'), originalCss = await readFile(css, 'utf8');
  await writeFile(css, originalCss + '\nbody { --refresh-probe: updated; }\n');
  await until(navigated, 'automatic IDE navigation after CSS build', 60);
  assert.equal(await contents(), draft);
  assert.equal(await browser.evaluate('document.querySelectorAll(".pane").length'), 2);
  assert.equal(await browser.evaluate('getComputedStyle(document.body).getPropertyValue("--refresh-probe").trim()'), 'updated');
  assert.notEqual(latest().editor, first);
  assert.equal(await (await service.get(first + 'ide.css')).text(), originalCss, 'old generation remains immutable');
  assert.ok((await readFile(join(project, 'main.sld'), 'utf8')).includes('original'), 'refresh never saves a draft to disk');

  // Bad Scheme retains the last working generation and the current page.
  const source = join(fixture, 'src/snail/shell/ide/application.sld'), originalSource = await readFile(source, 'utf8');
  const accepted = latest().editor;
  await mark();
  await writeFile(source, originalSource.replace('\">_\"', '(unknown-ide-refresh-name)'));
  await until(() => Boolean(latest()?.['editor-problem']), 'failed IDE build', 60);
  assert.equal(latest().editor, accepted);
  assert.equal(await browser.evaluate('window.beforeRefresh'), true);
  assert.equal(await contents(), draft);
  await writeFile(source, originalSource.replace('">_"', '">+"'));
  await until(navigated, 'successful Scheme edit after failed IDE build', 60);
  assert.equal(await browser.evaluate('document.getElementById("commands").textContent'), '>+');
  assert.equal(await contents(), draft);

  // Persisting is the navigation barrier. A failure leaves editing usable,
  // with the recovery record intact; retry adopts the latest edited text.
  await browser.evaluate(`window.actualStore = Storage.prototype.setItem;
    Storage.prototype.setItem = function(key, value) {
      if (key.startsWith('snail-save:')) throw new Error('test storage refusal');
      return window.actualStore.call(this, key, value);
    };`);
  await browser.evaluate(`window.actualFetch = window.fetch; window.createdRequests = 0;
    window.fetch = async (...args) => { const response = await window.actualFetch(...args);
      if (String(args[0]).includes('pending.sld') && args[1]?.method === 'POST') {
        window.createdRequests++; await new Promise(resolve => window.releaseCreated = resolve);
      } return response; };`);
  await command(browser, 'new-file');
  await browser.evaluate(`const query = document.getElementById('command-query'); query.value = 'pending.sld';
    query.dispatchEvent(new Event('input')); query.dispatchEvent(new KeyboardEvent('keydown', {key:'Enter', bubbles:true}));`);
  await until(() => browser.evaluate('Boolean(window.releaseCreated)'), 'create acknowledgement pending at refresh');
  await mark();
  await writeFile(css, originalCss + '\nbody { --refresh-probe: refused; }\n');
  await until(() => browser.evaluate('document.querySelector("[role=alert]")?.textContent.includes("Refresh deferred")'), 'storage refusal', 60);
  assert.equal(await browser.evaluate('window.beforeRefresh'), true);
  assert.equal(await contents(), draft);
  assert.equal(await browser.evaluate('document.getElementById("command-query")'), null, 'canceled create does not leave a pending palette');
  assert.equal(await browser.evaluate('window.createdRequests'), 1, 'resume never repeats a mutation');
  await browser.evaluate('window.fetch = window.actualFetch; window.releaseCreated()');
  await type(draft + '; typed after refused refresh\n');
  await browser.evaluate('Storage.prototype.setItem = window.actualStore; document.querySelector("[role=alert] button").click()');
  await until(navigated, 'retry after storage refusal', 60);
  assert.equal(await contents(), draft + '; typed after refused refresh\n');

  // A composition in progress holds navigation until its final input arrives.
  await mark();
  await browser.evaluate('document.querySelector(".pane.active textarea").dispatchEvent(new CompositionEvent("compositionstart", {bubbles:true}))');
  const beforeComposition = latest().editor;
  await writeFile(css, originalCss + '\nbody { --refresh-probe: composed; }\n');
  await until(() => latest()?.editor !== beforeComposition, 'build during composition', 60);
  await sleep(200);
  assert.equal(await browser.evaluate('window.beforeRefresh'), true);
  assert.equal(await browser.evaluate('window.dispatchEvent(new Event("beforeunload", {cancelable:true}))'), false,
    'draft warning remains until the final checkpoint has been stored');
  await browser.evaluate(`const field = document.querySelector('.pane.active textarea');
    field.dispatchEvent(new CompositionEvent('compositionend', {bubbles:true}));
    field.dispatchEvent(new CompositionEvent('compositionstart', {bubbles:true}));`);
  await sleep(100);
  assert.equal(await browser.evaluate('window.beforeRefresh'), true, 'a new composition during handover also holds navigation');
  await type(draft + '; composed 日本語\n');
  await browser.evaluate('document.querySelector(".pane.active textarea").dispatchEvent(new CompositionEvent("compositionend", {bubbles:true}))');
  await until(navigated, 'navigation after composition ends', 60);
  assert.equal(await contents(), draft + '; composed 日本語\n');

  // Preserve the old base, not just text: an external write still conflicts.
  await writeFile(join(project, 'main.sld'), '(import (snail core base))\n; external\n');
  await until(() => browser.evaluate('document.querySelector(".pane.active")?.textContent.includes("Changed on disk")'), 'external conflict');
  await mark();
  await command(browser, 'refresh-ide');
  await until(navigated, 'explicit safe refresh');
  assert.equal(await contents(), draft + '; composed 日本語\n');
  await command(browser, 'save-buffer');
  await sleep(150);
  assert.ok((await readFile(join(project, 'main.sld'), 'utf8')).includes('external'));
  // An incompatible save is an explicit recovery failure, never a cold-start
  // fallback that could overwrite the only remaining copy of the drafts.
  const recovery = await browser.evaluate(`(() => {
    const key = Object.keys(sessionStorage).find(key => key.startsWith('snail-save:'));
    return {key, value:sessionStorage.getItem(key)};
  })()`);
  const poison = await browser.send('Page.addScriptToEvaluateOnNewDocument', {
    source: `sessionStorage.setItem(${JSON.stringify(recovery.key)}, 'AA==')`
  });
  await browser.navigate(service.url + '/');
  await until(() => browser.evaluate('Boolean(document.body.dataset.error)'), 'incompatible recovery refused');
  assert.equal(await browser.evaluate(`sessionStorage.getItem(${JSON.stringify(recovery.key)})`), 'AA==');
  await browser.send('Page.removeScriptToEvaluateOnNewDocument', {identifier:poison.result.identifier});
  await browser.evaluate(`sessionStorage.setItem(${JSON.stringify(recovery.key)}, ${JSON.stringify(recovery.value)})`);
  await browser.navigate(service.url + '/');
  await until(async () => (await contents()) === draft + '; composed 日本語\n', 'original recovery still readable');
  console.log('IDE refresh: immutable builds, failed compilation, Scheme edits, drafts/layout, storage refusal, composition, conflicts and incompatible recovery');
} finally {
  browser?.close();
  await stream?.close();
  if (service) await service.stop();
  await rm(fixture, {recursive: true, force: true});
}
