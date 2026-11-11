// File selection belongs to the active pane; tabs share drafts across panes.
import assert from 'node:assert/strict';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {startDevelopment} from '../development-service.mjs';
import {openBrowser, until} from './chromium.mjs';
import {command} from './ide-commands.mjs';

const [root, screenshot] = process.argv.slice(2), project = await mkdtemp(join(tmpdir(), 'snail-tabs-'));
await writeFile(join(project, 'project.datum'), '()');
for (const [path, text] of [['main.sld', '; main\n'], ['one.txt', 'one'], ['two.txt', 'two']])
  await writeFile(join(project, path), text);
const service = await startDevelopment(root, project), browser = await openBrowser();
const tabs = () => browser.evaluate('[...document.querySelectorAll(".pane.active .pane-tab")].map(tab => tab.dataset.path)');
const active = () => browser.evaluate('document.querySelector(".pane.active textarea")?.snailPath');
const key = init => browser.evaluate(`document.activeElement.dispatchEvent(new KeyboardEvent('keydown', ${JSON.stringify({bubbles: true, cancelable: true, ...init})}))`);
async function open(path) {
  await key({key: 'p', metaKey: true});
  await until(() => browser.evaluate('document.activeElement?.id === "command-query"'), 'Cmd+P');
  await browser.evaluate(`(() => { const query = document.getElementById('command-query'); query.value = ${JSON.stringify(path)}; query.dispatchEvent(new Event('input')); })()`);
  await until(() => browser.evaluate(`document.querySelector('.choice-label')?.textContent === ${JSON.stringify(path)}`), 'filtered file');
  await key({key: 'Enter'});
  await until(async () => await active() === path && await browser.evaluate('document.activeElement?.tagName === "TEXTAREA"'), 'file in active pane');
}
async function focusPane(id) {
  const point = await browser.evaluate(`(() => { const rect = document.getElementById(${JSON.stringify(id)}).getBoundingClientRect(); return {x: rect.left + 20, y: rect.top + 12}; })()`);
  await browser.send('Input.dispatchMouseEvent', {type: 'mousePressed', ...point, button: 'left', buttons: 1, clickCount: 1});
  await browser.send('Input.dispatchMouseEvent', {type: 'mouseReleased', ...point, button: 'left', buttons: 0, clickCount: 1});
  await until(() => browser.evaluate(`document.querySelector('.pane.active textarea').id === ${JSON.stringify(id)}`), 'clicked pane active');
}
try {
  await browser.navigate(service.url + '/');
  await until(async () => await active() === 'main.sld', 'initial file');
  await open('one.txt'); await open('two.txt');
  assert.deepEqual(await tabs(), ['main.sld', 'one.txt', 'two.txt']);
  assert.equal(await browser.evaluate('document.querySelectorAll(".pane").length'), 1);
  await open('one.txt');
  assert.deepEqual(await tabs(), ['main.sld', 'one.txt', 'two.txt'], 'existing tab reused');
  await browser.evaluate(`const field = document.querySelector('.pane.active textarea'); field.value = 'unsaved one'; field.dispatchEvent(new Event('input'));`);
  await open('two.txt');
  await browser.evaluate(`document.querySelector('.pane.active .pane-tab[data-path="one.txt"]').click()`);
  await until(() => browser.evaluate('document.querySelector(".pane.active textarea").value === "unsaved one"'), 'tab retains draft');
  await command(browser, 'split-right');
  const second = await browser.evaluate('document.querySelector(".pane.active textarea").id');
  assert.deepEqual(await tabs(), ['one.txt'], 'split starts with the selected file');
  await open('two.txt'); await open('main.sld');
  assert.equal(await browser.evaluate('document.querySelector(".pane.active textarea").id'), second, 'file visible elsewhere opens here');
  assert.deepEqual(await tabs(), ['one.txt', 'two.txt', 'main.sld']);
  await browser.send('Emulation.setDeviceMetricsOverride', {width: 600, height: 700, deviceScaleFactor: 1, mobile: false});
  await open('main.sld');
  assert.ok(await browser.evaluate(`(() => { const strip = document.querySelector('.pane.active .pane-tabs'), tab = strip.querySelector('.active');
    const box = strip.getBoundingClientRect(), selected = tab.getBoundingClientRect();
    return strip.scrollWidth > strip.clientWidth && selected.left >= box.left - 1 && selected.right <= box.right + 1; })()`), 'selected tab stays visible in an overflowing strip');
  await browser.send('Emulation.clearDeviceMetricsOverride');
  await open('one.txt');
  assert.equal(await browser.evaluate('document.querySelector(".pane.active textarea").value'), 'unsaved one', 'shared draft');
  await open('two.txt');
  // Closing the other pane's visible copy must see this inactive dirty tab.
  await browser.evaluate('window.confirmations = 0; window.confirm = () => { window.confirmations++; return false; }');
  await focusPane('text-0');
  await command(browser, 'close-editor');
  assert.equal(await browser.evaluate('window.confirmations'), 0, 'inactive tab in other pane retains draft');
  assert.deepEqual(await tabs(), ['main.sld', 'two.txt']);
  assert.equal(await active(), 'two.txt', 'closing selects the adjacent tab');
  assert.equal(await browser.evaluate('document.querySelectorAll(".pane").length'), 2, 'closing a tab keeps its pane');
  await focusPane(second);
  await open('one.txt');
  await command(browser, 'close-editor');
  assert.equal(await browser.evaluate('window.confirmations'), 1, 'last dirty tab asks');
  assert.equal(await active(), 'one.txt', 'cancel preserves selected tab');
  assert.equal(await browser.evaluate('document.querySelector(".pane.active textarea").value'), 'unsaved one');
  if (screenshot) await browser.screenshot(screenshot);
  await browser.evaluate('window.beforeRefresh = true');
  await command(browser, 'refresh-ide');
  await until(() => browser.evaluate('!window.beforeRefresh && document.querySelector(".pane.active textarea")?.value === "unsaved one"'), 'draft restored after refresh');
  assert.deepEqual(await tabs(), ['one.txt', 'two.txt', 'main.sld'], 'tab order restored');
  assert.equal(await browser.evaluate('document.querySelectorAll(".pane").length'), 2, 'layout restored');
  await browser.evaluate('window.confirm = () => true');
  await command(browser, 'close-editor');
  assert.deepEqual(await tabs(), ['two.txt', 'main.sld']);
  await command(browser, 'close-editor');
  await command(browser, 'close-editor');
  await until(() => browser.evaluate('document.querySelectorAll(".pane").length === 1'), 'last tab removes split');
  console.log('ide-tabs: active-pane opening, deduplication, shared drafts, safe closing and recovery');
} catch (error) {
  console.error(await browser.evaluate(`({active: document.querySelector('.pane.active textarea')?.snailPath,
    focus: document.activeElement?.outerHTML, tabs: [...document.querySelectorAll('.pane-tab')].map(t => t.outerHTML),
    query: document.getElementById('command-query')?.value, error: document.body.dataset.error})`));
  throw error;
} finally { browser.close(); await service.stop(); await rm(project, {recursive: true, force: true}); }
