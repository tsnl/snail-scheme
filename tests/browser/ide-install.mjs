// The real browser proves eligibility in ide-installable.mjs. Here controlled
// offers exercise the Scheme commands without installing anything on the host.
import assert from 'node:assert/strict';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {startDevelopment} from '../development-service.mjs';
import {openBrowser, until} from './chromium.mjs';
import {command} from './ide-commands.mjs';

const root = process.argv[2], project = await mkdtemp(join(tmpdir(), 'snail-install-'));
await writeFile(join(project, 'project.datum'), '()');
await writeFile(join(project, 'main.sld'), '(import (snail core base))');
const service = await startDevelopment(root, project), browser = await openBrowser();
const notice = text => until(() => browser.evaluate(`document.getElementById('status')?.textContent.includes(${JSON.stringify(text)})`), text);
const install = () => command(browser, 'install-app', {userGesture: true});
async function offer(outcome) {
  await browser.evaluate(`(() => {
    const event = new Event('beforeinstallprompt', {cancelable:true});
    event.prompt = () => {
      window.promptCalls++; window.activated = navigator.userActivation.isActive;
      if (${JSON.stringify(outcome)} === 'throw') throw new Error('refused');
      if (${JSON.stringify(outcome)} === 'reject') return Promise.reject(new Error('refused'));
      return Promise.resolve({outcome:${JSON.stringify(outcome)}});
    };
    dispatchEvent(event);
  })()`);
}
try {
  await browser.send('Page.addScriptToEvaluateOnNewDocument', {source:
    `window.promptCalls = 0; window.realOffers = 0;
     addEventListener('beforeinstallprompt', event => { if (event.isTrusted) window.realOffers++; });`});
  await browser.navigate(service.url + '/');
  await until(() => browser.evaluate('Boolean(document.getElementById("commands"))'), 'IDE boot');
  await browser.send('Input.dispatchMouseEvent', {type:'mousePressed',x:10,y:10,button:'left',clickCount:1});
  await browser.send('Input.dispatchMouseEvent', {type:'mouseReleased',x:10,y:10,button:'left',clickCount:1});
  await until(() => browser.evaluate('window.realOffers > 0'), 'real installation offer captured first');
  await offer('dismissed');
  const cancelled = await browser.send('Runtime.evaluate', {awaitPromise:true, returnByValue:true, userGesture:true, expression:
    `(async () => {
      const {webAppImports} = await import('/install.mjs');
      const controller = new AbortController(); controller.abort();
      let pending;
      const imports = webAppImports({execution:{tasks:{start(ticket, work) {
        pending = Promise.resolve(work(controller.signal));
      }}}});
      imports['start-install'](0n); await pending;
      imports['start-fullscreen'](1n, 1); await pending;
      return [window.promptCalls, Boolean(document.fullscreenElement)];
    })()`});
  assert.deepEqual(cancelled.result.result.value, [0, false], 'stopped tasks cannot consume offers or open fullscreen');
  await until(() => browser.evaluate('!navigator.userActivation.isActive'), 'initial activation expires');
  await command(browser, 'install-app');
  await notice('click install-app');
  assert.equal(await browser.evaluate('window.promptCalls'), 0, 'an expired gesture preserves the offer');
  await install();
  await notice('Installation dismissed');
  assert.equal(await browser.evaluate('window.promptCalls'), 1);
  assert.equal(await browser.evaluate('window.activated'), true, 'Scheme task retains transient activation');
  await install();
  await notice('browser’s Install App');
  assert.equal(await browser.evaluate('window.promptCalls'), 1, 'offers are single use');
  const stopped = await browser.send('Runtime.evaluate', {awaitPromise:true, returnByValue:true, userGesture:true, expression:
    `(async () => {
      const {webAppImports} = await import('/install.mjs');
      const event = new Event('beforeinstallprompt', {cancelable:true});
      let finish;
      event.prompt = () => new Promise(resolve => { finish = resolve; });
      dispatchEvent(event);
      const controller = new AbortController();
      let pending;
      const imports = webAppImports({execution:{tasks:{start(ticket, work) {
        pending = Promise.resolve(work(controller.signal));
      }}}});
      imports['start-install'](2n); controller.abort();
      await pending; // Must finish before the unresolved browser dialog does.
      finish({outcome:'dismissed'});
      return true;
    })()`});
  assert.equal(stopped.result.result.value, true, 'stopping a generation releases its prompt wait');
  for (const failure of ['throw', 'reject']) {
    await offer(failure);
    await install();
    await notice('could not open');
  }
  await offer('accepted');
  await install();
  await notice('Installation accepted');
  await install();
  await notice('browser’s Install App');
  await browser.evaluate('dispatchEvent(new Event("appinstalled"))');
  await install();
  await notice('already installed');
  await command(browser, 'toggle-fullscreen', {userGesture: true});
  await until(() => browser.evaluate('Boolean(document.fullscreenElement)'), 'entered fullscreen');
  await command(browser, 'toggle-fullscreen', {userGesture: true});
  await until(() => browser.evaluate('!document.fullscreenElement'), 'left fullscreen');
  console.log('ide-install: activation, single-use offers, outcomes, and fullscreen through Scheme commands');
} finally { browser.close(); await service.stop(); await rm(project, {recursive:true,force:true}); }
