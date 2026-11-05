// Check the actual browser's manifest and installability decisions, on the IDE
// origin. No service worker or offline cache is required by current Chromium.
import assert from 'node:assert/strict';
import {mkdtemp, mkdir, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {startDevelopment} from '../development-service.mjs';
import {openBrowser, until} from './chromium.mjs';

const root = process.argv[2], project = await mkdtemp(join(tmpdir(), 'snail-installable-'));
await writeFile(join(project, 'project.datum'),
  '((build-target one (browser (entry "main.sld") (public "public"))) (build-target two (browser (entry "main.sld") (public "public"))))');
await mkdir(join(project, 'public'));
await writeFile(join(project, 'main.sld'), '(import (snail core base))');
await writeFile(join(project, 'public/index.html'), '\ufeff\n<!-- preamble -->\n<!DOCTYPE html><title>Nested app</title>');
const service = await startDevelopment(root, project), browser = await openBrowser();
try {
  await browser.send('Page.addScriptToEvaluateOnNewDocument', {source:
    `window.installOffers = 0; addEventListener('beforeinstallprompt', event => { event.preventDefault(); window.installOffers++; });`});
  await browser.navigate(service.url + '/');
  await until(() => browser.evaluate('Boolean(document.getElementById("commands"))'), 'IDE boot');
  await browser.send('Input.dispatchMouseEvent', {type:'mousePressed',x:10,y:10,button:'left',clickCount:1});
  await browser.send('Input.dispatchMouseEvent', {type:'mouseReleased',x:10,y:10,button:'left',clickCount:1});
  const {result} = await browser.send('Page.getAppManifest');
  assert.deepEqual(result.errors, []);
  assert.equal(result.url, service.url + '/manifest.webmanifest');
  assert.equal(result.manifest.id, service.url + '/');
  assert.equal(result.manifest.startUrl, service.url + '/');
  assert.equal(result.manifest.scope, service.url + '/');
  assert.equal(result.manifest.display, 'kStandalone');
  assert.deepEqual(result.manifest.icons.map(icon => icon.sizes), ['192x192','512x512']);
  await until(() => browser.evaluate('window.installOffers > 0'), 'Chrome installation offer');
  assert.deepEqual((await browser.send('Page.getInstallabilityErrors')).result.installabilityErrors, []);
  assert.equal(await browser.evaluate('navigator.serviceWorker.controller'), null);
  const first = await service.settled(0);
  const urls = first.published.targets.map(target => target.url);
  const identities = [];
  for (const url of urls) {
    await browser.navigate(url);
    await until(() => browser.evaluate(`location.href === ${JSON.stringify(url)} && document.readyState === 'complete'`), 'application page loaded');
    const parsed = (await browser.send('Page.getAppManifest')).result;
    assert.equal(await browser.evaluate('document.compatMode'), 'CSS1Compat', 'preamble preserves standards mode');
    assert.equal(parsed.url, url + 'manifest.webmanifest');
    assert.equal(parsed.manifest.id, url, 'each mounted application has its own identity');
    assert.equal(parsed.manifest.startUrl, url);
    identities.push(parsed.manifest.id);
  }
  assert.notEqual(identities[0], identities[1]);
  await writeFile(join(project, 'main.sld'), '(import (snail core base)) ; changed');
  await service.settled(first.id);
  await browser.navigate(urls[0]);
  await until(() => browser.evaluate(`location.href === ${JSON.stringify(urls[0])} && document.readyState === 'complete'`), 'rebuilt application page');
  assert.equal((await browser.send('Page.getAppManifest')).result.manifest.id, identities[0]);
  console.log('ide-installable: stable manifest, standalone display, icons, and a real Chrome installation offer');
} finally { browser.close(); await service.stop(); await rm(project, {recursive:true,force:true}); }
