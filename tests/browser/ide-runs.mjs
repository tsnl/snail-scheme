// Current SSE observations own run state; HTTP replies only acknowledge intent.
// The page edits a spawned `snail dev`, which this test also drives as another
// client and observes from outside (tests/development-service.mjs).
// CHROMIUM=... node tests/browser/ide-runs.mjs ROOT [SCREENSHOT]
import assert from 'node:assert/strict';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {dead, startDevelopment} from '../development-service.mjs';
import {openBrowser, sleep, until} from './chromium.mjs';

const [root, screenshot] = process.argv.slice(2), project = await mkdtemp(join(tmpdir(), 'snail-ide-runs-'));
const config = includeApp => `(
  (build-target editor (program (entry "main.sld")))
  (build-target worker (program (entry "worker.sld")))
  (build-target failure (program (entry "failure.sld")))
  ${includeApp ? '(run-target app (run worker))' : ''}
  (run-target crash (run failure)))`;
const program = value => `(import (snail core base) (snail core io))\n(: greeting String)\n(define greeting ${value})\n(write-line greeting)\n`;
await writeFile(join(project, 'project.datum'), config(true));
await writeFile(join(project, 'main.sld'), program('"hello"'));
await writeFile(join(project, 'worker.sld'), '(import (snail core base) (snail core io) (snail shell task)) (dispatch-local (once (lambda () (let loop () (write-line "<b>literal output</b>") (sleep 80) (loop)))))');
await writeFile(join(project, 'failure.sld'), '(import (snail core base)) (panic "stderr literal")');
const service = await startDevelopment(root, project), browser = await openBrowser();
const click = id => browser.evaluate(`document.getElementById(${JSON.stringify(id)}).click()`);
const text = id => browser.evaluate(`document.getElementById(${JSON.stringify(id)}).textContent`);
const disabled = id => browser.evaluate(`document.getElementById(${JSON.stringify(id)}).disabled`);
const select = target => browser.evaluate(`(() => { const s = document.getElementById('run-target'); s.value = ${JSON.stringify(target)}; s.dispatchEvent(new Event('change')); })()`);
const run = async target => (await service.status()).runs.find(run => run.target === target);
const live = async () => (await run('app'))?.attempt?.stdout.includes('literal output');
const stopApp = async () => assert.equal((await service.command('/api/run/stop?target=app')).status, 204);
// The first status of an attempt after `after` that succeeded, if `also` holds of it.
const accepted = async (after, also) => {
  const current = await service.status();
  return current.id > after && current.phase === 'succeeded' && await also(current);
};
let finalPid = null;

try {
  await browser.navigate(service.url + '/');
  await until(async () => {
    const current = await service.status();
    assert.notEqual(current.phase, 'failed', JSON.stringify(current.diagnostics));
    return browser.evaluate('document.querySelector(".pane.active textarea")?.value.includes("hello") && !document.getElementById("runs").hidden');
  }, 'editor and accepted run targets');
  assert.equal((await run('app')).attempt, null);
  assert.equal(await disabled('run-start'), false);
  await click('run-start'); await until(live, 'application output');
  await until(async () => (await text('run-stdout')).includes('<b>literal output</b>'), 'literal displayed output');
  assert.equal(await browser.evaluate('document.querySelector("#run-stdout b")'), null);
  assert.equal(await browser.evaluate('document.querySelectorAll("iframe").length'), 0);
  assert.equal(await disabled('run-start'), true);

  // Delay a real Restart acknowledgement, then observe a later Stop from
  // another client. Releasing the older reply cannot restore the old intent.
  const firstPid = (await run('app')).attempt.pid;
  await browser.evaluate(`window.actualFetch = window.fetch;
    window.fetch = async (...args) => { const response = await window.actualFetch(...args);
      if (String(args[0]).startsWith('/api/run/restart')) await new Promise(resolve => window.releaseRun = resolve);
      return response; };`);
  await click('run-restart');
  await until(async () => await browser.evaluate('Boolean(window.releaseRun)') && (await run('app')).attempt.pid !== firstPid && await live(), 'held restart acknowledgement');
  assert.equal(await disabled('run-stop'), true);
  await stopApp();
  await until(async () => (await run('app')).attempt.phase === 'exited' && (await text('run-status')).includes('Requested: stop'), 'newer Stop observation');
  await browser.evaluate('window.releaseRun(); window.fetch = window.actualFetch');
  await until(async () => !(await disabled('run-start')), 'acknowledgement release');
  assert.match(await text('run-status'), /Requested: stop/); dead(firstPid);

  // Lose the response after the command reached the service. It starts once;
  // output, selection and reconnect must not erase the unknown-outcome message.
  await browser.evaluate(`window.runRequests = 0; window.NativeEventSource = window.EventSource;
    window.EventSource = class extends window.NativeEventSource { constructor(...args) { super(...args); window.runEvents = this; } };
    window.dispatchEvent(new Event('online'));
    window.fetch = async (...args) => { const response = await window.actualFetch(...args);
      if (String(args[0]).startsWith('/api/run/')) { window.runRequests++; await new Promise(resolve => window.rejectRun = resolve); throw new TypeError('lost response'); }
      return response; };`);
  await click('run-start');
  await until(async () => await browser.evaluate('Boolean(window.rejectRun)') && (await run('app')).wanted && await live(), 'command reached service');
  // A restarted service may temporarily have no accepted targets. Feedback
  // must stay visible through that authoritative empty observation.
  await browser.evaluate(`window.runEvents.close(); window.runEvents.dispatchEvent(new MessageEvent('runs', {data:'[]'}));`);
  assert.equal(await browser.evaluate('document.getElementById("runs").hidden'), false);
  await browser.evaluate('window.rejectRun()');
  await until(async () => (await run('app')).wanted && await live() && (await text('run-problem')).includes('Outcome unknown'), 'lost command response');
  assert.equal(await browser.evaluate('document.getElementById("runs").hidden'), false);
  await browser.evaluate('window.fetch = window.actualFetch; window.EventSource = window.NativeEventSource; window.dispatchEvent(new Event("online"))');
  await until(() => browser.evaluate('document.getElementById("run-target").options.length === 2'), 'current run catalog');
  await browser.evaluate(`window.runEvents.dispatchEvent(new MessageEvent('runs', {data:'[]'}));`);
  assert.equal(await browser.evaluate('document.getElementById("run-target").options.length'), 2, 'a replaced source cannot overwrite the current observation');
  assert.equal(await browser.evaluate('window.runRequests'), 1);
  assert.match(await text('run-problem'), /start app: Outcome unknown/);
  await select('crash');
  assert.match(await text('run-problem'), /start app: Outcome unknown/);
  await click('run-start');
  await until(async () => (await text('run-stderr')).includes('stderr literal'), 'process error output');
  assert.equal(await text('run-problem'), '');
  assert.equal(await disabled('run-start'), true);
  assert.equal(await disabled('run-restart'), false);

  const removedPid = (await run('app')).attempt.pid;
  let before = (await service.status()).id;
  await writeFile(join(project, 'project.datum'), config(false));
  await until(() => accepted(before, current => !current.runs.find(run => run.target === 'app').available), 'accepted removal');
  await select('app');
  await until(async () => (await text('run-status')).includes('Removed') && (await run('app')).attempt.phase === 'exited', 'removed process stops');
  assert.equal(await disabled('run-start'), true); assert.equal(await disabled('run-restart'), true);
  assert.equal(await disabled('run-stop'), false); dead(removedPid);
  before = (await service.status()).id;
  await writeFile(join(project, 'project.datum'), config(true));
  await until(() => accepted(before, async () => !(await disabled('run-start'))), 'reintroduced stopped target');
  await click('run-start'); await until(async () => await live() && (await run('app')).attempt.pid !== removedPid, 'new application attempt');

  // Output is independent of compiler errors, editor evidence and drafts.
  const activePid = (await run('app')).attempt.pid;
  await writeFile(join(project, 'main.sld'), program('5'));
  await until(() => browser.evaluate('document.querySelector(".pane.active .squiggle")?.textContent === "5"'), 'compiler point while application runs');
  await sleep(200);
  await browser.evaluate(`window.fileReads = 0; window.marker = document.querySelector('.pane.active .squiggle');
    window.fetch = (...args) => { if (String(args[0]).startsWith('/api/file')) window.fileReads++; return window.actualFetch(...args); };
    document.querySelector('.pane.active textarea').focus();
    document.getElementById('run-stdout').scrollTop = 0;`);
  const outputSize = (await text('run-stdout')).length;
  await until(async () => (await text('run-stdout')).length > outputSize + 100, 'live output with stable editor');
  assert.equal(await browser.evaluate('window.fileReads'), 0);
  assert.equal(await browser.evaluate('window.marker === document.querySelector(".pane.active .squiggle")'), true);
  assert.equal(await browser.evaluate('document.activeElement === document.querySelector(".pane.active textarea")'), true);
  assert.equal(await browser.evaluate('document.getElementById("run-stdout").scrollTop'), 0);
  assert.equal((await run('app')).attempt.pid, activePid);
  if (screenshot) await browser.screenshot(screenshot);
  await browser.evaluate(`(() => { const t = document.querySelector('.pane.active textarea'), at = t.value.indexOf('5'); t.setSelectionRange(at, at + 1); document.execCommand('insertText', false, '6'); })()`);
  await sleep(200);
  assert.equal(await browser.evaluate('document.querySelector(".pane.active textarea").value.includes("greeting 6")'), true);
  assert.equal(await browser.evaluate('window.fileReads'), 0);
  await browser.evaluate('window.fetch = window.actualFetch');

  await browser.send('Network.enable');
  await browser.send('Network.emulateNetworkConditions', {offline: true, latency: 0, downloadThroughput: -1, uploadThroughput: -1});
  await stopApp();
  await until(async () => (await run('app')).attempt.phase === 'exited', 'stop while disconnected');
  await browser.send('Network.emulateNetworkConditions', {offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1});
  await browser.evaluate('window.dispatchEvent(new Event("online"))');
  await until(async () => (await text('run-status')).includes('Requested: stop') && !(await disabled('run-start')), 'current run snapshot on reconnect');
  assert.equal(await browser.evaluate('document.querySelector(".pane.active textarea").value.includes("greeting 6")'), true);
  await click('run-start'); await until(async () => await live() && (await run('app')).attempt.pid !== activePid, 'accepted launch during compile failure');
  finalPid = (await run('app')).attempt.pid;
  browser.close(); await sleep(100); process.kill(finalPid, 0);
  const {code, signal, stderr} = await service.stop();
  assert.deepEqual({code, signal}, {code: 0, signal: null}, stderr);
  dead(finalPid);
  console.log('IDE runs: controls, literal output, delayed/lost replies, compiler isolation, removal, reconnect and shutdown');
} finally {
  browser.close(); await service.stop();
  await rm(project, {recursive: true, force: true});
}
