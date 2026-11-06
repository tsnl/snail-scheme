// Browser-only focus, keyboard delivery and confirm-dialog behavior.
// Registry, fuzzy selection and request ordering run in Snail-Core fixtures.
import assert from 'node:assert/strict';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {startDevelopment} from '../development-service.mjs';
import {openBrowser, until} from './chromium.mjs';
import {command} from './ide-commands.mjs';

const [root, screenshot] = process.argv.slice(2), project = await mkdtemp(join(tmpdir(), 'snail-palette-'));
await writeFile(join(project, 'project.datum'), '()');
await writeFile(join(project, 'main.sld'), '(import (snail core base))\n');
const service = await startDevelopment(root, project), browser = await openBrowser();
const key = init => browser.evaluate(`(document.activeElement ?? window).dispatchEvent(new KeyboardEvent('keydown', ${JSON.stringify({bubbles: true, cancelable: true, ...init})}))`);
const query = value => browser.evaluate(`(() => { const input = document.getElementById('command-query'); input.value = ${JSON.stringify(value)}; input.dispatchEvent(new Event('input')); })()`);
const title = () => browser.evaluate('document.querySelector(".pane.active .pane-title").textContent');
try {
  await browser.navigate(service.url + '/');
  await until(async () => (await title()) === 'main.sld', 'first file');
  assert.equal(await browser.evaluate('document.querySelector(".toolbar")'), null);
  assert.equal(await browser.evaluate('document.querySelectorAll(".pane-header button").length'), 1);
  await key({key: 'P', metaKey: true, shiftKey: true});
  await until(() => browser.evaluate('document.activeElement?.id === "command-query"'), 'Command+Shift+P');
  await query('spri');
  await until(() => browser.evaluate('document.querySelectorAll(".palette-option").length === 1'), 'fuzzy command');
  assert.equal(await browser.evaluate('document.querySelector(".palette-option").dataset.command'), 'split-right');
  await key({key: 'Enter'});
  await until(() => browser.evaluate('document.querySelectorAll(".pane").length === 2'), 'palette split');
  await key({key: 'w', altKey: true});
  await until(() => browser.evaluate('document.querySelectorAll(".pane").length === 1'), 'shortcut close');
  await key({key: 'F1'});
  await until(() => browser.evaluate('document.activeElement?.id === "command-query"'), 'palette focus');
  await key({key: 'Escape'});
  await until(() => browser.evaluate('document.activeElement?.tagName === "TEXTAREA"'), 'focus returned');
  await browser.evaluate(`const field = document.querySelector('.pane.active textarea'); field.value += ${JSON.stringify('; draft\n')}; field.dispatchEvent(new Event('input')); window.confirm = () => false;`);
  await until(async () => (await title()).includes('●'), 'draft reaches buffer');
  await command(browser, 'close-editor');
  assert.match(await title(), /●/);
  await browser.evaluate('window.confirm = () => true');
  await command(browser, 'close-editor');
  await until(async () => (await title()) === 'Choose a file', 'last editor closes');
  await browser.evaluate(`window.originalFetch = window.fetch; window.fetch = async (...args) => {
    const response = await window.originalFetch(...args);
    if (String(args[0]) === '/api/project') { const project = await response.json(); project.name = 'refreshed'; return new Response(JSON.stringify(project)); }
    return response;
  }; window.dispatchEvent(new Event('online'));`);
  await until(() => browser.evaluate('document.querySelector("#files h2").textContent === "refreshed"'), 'new listing accepted');
  await browser.evaluate('window.fetch = window.originalFetch');
  assert.equal(await title(), 'Choose a file', 'a refresh cannot reopen an explicitly closed buffer');
  await key({key: 'F1'});
  await until(() => browser.evaluate('Boolean(document.getElementById("command-query"))'), 'palette in empty pane');
  if (screenshot) await browser.screenshot(screenshot);
  await key({key: 'Escape'});
  await until(() => browser.evaluate('document.activeElement?.id === "commands"'), 'empty editor focus fallback');
  await browser.evaluate(`document.querySelector('.file[data-path="main.sld"]').click()`);
  await until(async () => (await title()) === 'main.sld', 'reopen source');
  await command(browser, 'split-right');
  await browser.evaluate(`document.querySelector('.file[data-path="project.datum"]').click()`);
  await until(async () => (await title()) === 'project.datum', 'other pane');
  await browser.evaluate(`const fields = document.querySelectorAll('.pane textarea');
    fields[0].focus(); fields[0].value += ${JSON.stringify('; another draft\n')}; fields[0].dispatchEvent(new Event('input'));
    fields[1].focus(); window.confirm = () => false;`);
  await until(async () => (await title()) === 'project.datum', 'focus second pane');
  await browser.evaluate('document.querySelector(".pane .pane-button").click()');
  await until(() => browser.evaluate('document.activeElement === document.querySelector(".pane.active textarea")'), 'cancelled close restores focus');
  assert.match(await title(), /main.sld.*●/);
  console.log('ide-palette: registered commands, keys, focus, and safe editor closing');
} finally {
  browser.close(); await service.stop(); await rm(project, {recursive: true, force: true});
}
