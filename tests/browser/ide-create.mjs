// Create from the palette; empty directories survive reconnect, and old replies
// never replace the user's later selection.
import assert from 'node:assert/strict';
import {mkdtemp, writeFile, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {startDevelopment} from '../development-service.mjs';
import {openBrowser, until, sleep} from './chromium.mjs';
import {command} from './ide-commands.mjs';

const root = process.argv[2], project = await mkdtemp(join(tmpdir(), 'snail-ide-create-'));
await writeFile(join(project, 'project.datum'), '()');
await writeFile(join(project, 'main.sld'), '(import (snail core base))\n');
const service = await startDevelopment(root, project), browser = await openBrowser();
const key = key => browser.evaluate(`document.activeElement.dispatchEvent(new KeyboardEvent('keydown', {key:${JSON.stringify(key)}, bubbles:true, cancelable:true}))`);
const query = value => browser.evaluate(`(() => { const q = document.getElementById('command-query'); q.value = ${JSON.stringify(value)}; q.dispatchEvent(new Event('input')); })()`);
const title = () => browser.evaluate('document.querySelector(".pane.active .pane-title").textContent');
const create = async (name, path) => { await command(browser, name); await query(path); await key('Enter'); };
try {
  await browser.navigate(service.url + '/');
  await until(async () => (await title()) === 'main.sld', 'initial editor');
  await create('new-directory', 'agent-core');
  await until(() => browser.evaluate('[...document.querySelectorAll("#files summary")].some(node => node.textContent === "agent-core")'), 'empty directory');
  await create('new-file', 'agent-core/main.sld');
  await until(async () => (await title()) === 'agent-core/main.sld', 'new file editor');
  await until(() => browser.evaluate('!document.querySelector("textarea").disabled'), 'new file read');
  await browser.evaluate(`const field = document.querySelector('textarea'); field.value = '(import (snail core base))\\n; written by hand\\n'; field.dispatchEvent(new Event('input'));`);
  await until(async () => (await title()).includes('●'), 'new file draft');
  await command(browser, 'save-buffer');
  await until(async () => (await readFile(join(project, 'agent-core/main.sld'), 'utf8')).includes('written by hand'), 'new file save');
  await create('new-directory', 'empty');
  await until(() => browser.evaluate('!document.getElementById("command-query")'), 'directory command completed');
  await browser.navigate(service.url + '/');
  await until(() => browser.evaluate('[...document.querySelectorAll("#files summary")].some(node => node.textContent === "empty")'), 'empty directory after reload');
  await create('new-file', 'main.sld');
  await until(() => browser.evaluate('document.getElementById("palette-help").textContent.includes("already exists")'), 'creation refusal');
  await key('Escape');
  await browser.evaluate(`window.actualFetch = window.fetch; window.releaseCreation = null;
    window.fetch = async (...args) => { const response = await window.actualFetch(...args);
      if (args[1]?.method === 'POST' && String(args[0]).includes('late.sld'))
        return new Promise(resolve => { window.releaseCreation = () => resolve(response); });
      return response;
    };`);
  await create('new-file', 'late.sld');
  await until(() => browser.evaluate('Boolean(window.releaseCreation)'), 'creation reply held');
  await key('Escape');
  await browser.evaluate(`document.querySelector('.file[data-path="main.sld"]').click()`);
  await until(async () => (await title()) === 'main.sld', 'later file selection');
  await browser.evaluate('window.fetch = window.actualFetch; window.releaseCreation()');
  await sleep(250);
  assert.equal(await title(), 'main.sld');
  assert.equal(await readFile(join(project, 'late.sld'), 'utf8'), '');
  await until(() => browser.evaluate(`Boolean(document.querySelector('.file[data-path="late.sld"]'))`), 'watcher lists the late creation');
  await browser.evaluate(`window.actualFetch = window.fetch; window.creations = [];
    window.fetch = async (...args) => { const response = await window.actualFetch(...args);
      if (args[1]?.method === 'POST' && String(args[0]).includes('pending-'))
        return new Promise(resolve => window.creations.push({resolve, response}));
      return response;
    };`);
  await create('new-file', 'pending-a.sld');
  await until(() => browser.evaluate('window.creations.length === 1'), 'first creation held');
  await key('Escape'); await create('new-file', 'pending-b.sld');
  await until(() => browser.evaluate('window.creations.length === 2'), 'second creation held');
  await browser.evaluate('window.creations[0].resolve(window.creations[0].response)');
  await sleep(250);
  assert.equal(await browser.evaluate('document.getElementById("command-query").value'), 'pending-b.sld');
  assert.equal(await browser.evaluate('document.getElementById("command-query").readOnly'), true);
  await key('Escape'); await create('new-file', 'pending-c.sld');
  await until(() => browser.evaluate('window.creations.length === 3'), 'third creation held');
  await browser.evaluate(`window.creations[1].resolve(new Response(JSON.stringify({message:'old failure'}), {status:500}))`);
  await sleep(250);
  assert.equal(await browser.evaluate('document.getElementById("command-query").value'), 'pending-c.sld');
  assert.equal(await browser.evaluate('document.getElementById("command-query").readOnly'), true);
  await browser.evaluate('window.fetch = window.actualFetch; window.creations[2].resolve(window.creations[2].response)');
  await until(async () => (await title()) === 'pending-c.sld', 'current creation opens');
  console.log('ide-create: file/directory commands, saving, reconnect, refusals, and obsolete completion');
} finally { browser.close(); await service.stop(); await rm(project, {recursive: true, force: true}); }
