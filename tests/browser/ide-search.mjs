// One palette for files and saved-text matches; old replies never change a new query.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtemp, mkdir, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {startDevelopment} from '../development-service.mjs';
import {openBrowser, until, sleep} from './chromium.mjs';
import {command} from './ide-commands.mjs';

const [root, screenshot] = process.argv.slice(2), project = await mkdtemp(join(tmpdir(), 'snail-ide-search-'));
await mkdir(join(project, 'lib'));
await writeFile(join(project, 'project.datum'), '()');
await writeFile(join(project, 'main.sld'), '(import (snail core base))\n; alpha\n');
const notes = '😀 prefix\r\nfind NEEDLE here\r\n';
await writeFile(join(project, 'lib/notes.txt'), notes);
execFileSync('git', ['init', '-q'], {cwd: project});
execFileSync('git', ['config', 'core.excludesFile', '/dev/null'], {cwd: project});
await writeFile(join(project, '.gitignore'), 'ignored.txt\n');
await writeFile(join(project, 'ignored.txt'), 'needle');
const service = await startDevelopment(root, project), browser = await openBrowser();
const key = init => browser.evaluate(`document.activeElement.dispatchEvent(new KeyboardEvent('keydown', ${JSON.stringify({bubbles: true, cancelable: true, ...init})}))`);
const query = value => browser.evaluate(`(() => { const q = document.getElementById('command-query'); q.value = ${JSON.stringify(value)}; q.dispatchEvent(new Event('input')); })()`);
const title = () => browser.evaluate('document.querySelector(".pane.active .pane-title").textContent');
const labels = () => browser.evaluate('[...document.querySelectorAll(".choice-label")].map(node => node.textContent)');
try {
  await browser.navigate(service.url + '/');
  await until(async () => (await title()) === 'main.sld', 'initial editor');
  assert.equal(await browser.evaluate('Boolean(document.querySelector(".file[data-path=\\"ignored.txt\\"]"))'), false);
  await key({key: 'p', metaKey: true});
  await until(() => browser.evaluate('document.activeElement?.id === "command-query"'), 'go to file');
  assert.ok(!(await labels()).includes('ignored.txt'), 'ignored file absent from file picker');
  await query('lnote');
  await until(async () => (await labels()).join() === 'lib/notes.txt', 'fuzzy path');
  await key({key: 'Enter'});
  await until(async () => (await title()) === 'lib/notes.txt', 'file opened');
  await key({key: 'F', ctrlKey: true, shiftKey: true});
  await until(() => browser.evaluate('document.activeElement?.id === "command-query"'), 'text search shortcut');
  await query('needle');
  await until(async () => (await labels()).join() === 'lib/notes.txt:2:6', 'saved match');
  if (screenshot) await browser.screenshot(screenshot);
  await key({key: 'Enter'});
  await until(() => browser.evaluate('document.querySelector("textarea").selectionStart === 15'), 'Unicode and CRLF match navigation');
  await browser.evaluate(`const field = document.querySelector('textarea'); field.value = 'draft only'; field.dispatchEvent(new Event('input'));`);
  await until(async () => (await title()).includes('●'), 'draft');
  await command(browser, 'search-project'); await query('needle');
  await until(async () => (await labels()).length === 1, 'saved match with a draft');
  await key({key: 'Enter'});
  await until(() => browser.evaluate('!document.getElementById("command-query")'), 'picked draft');
  assert.equal(await browser.evaluate('document.querySelector("textarea").value'), 'draft only');

  // An ignore change refreshes the sidebar while an open draft survives.
  await writeFile(join(project, '.gitignore'), 'ignored.txt\nlib/notes.txt\n');
  await until(() => browser.evaluate('!document.querySelector("#files > ul .file[data-path=\\"lib/notes.txt\\"]")'), 'ignore change updates sidebar');
  assert.equal(await browser.evaluate('document.querySelector("textarea").value'), 'draft only');
  await writeFile(join(project, '.gitignore'), 'ignored.txt\n');
  await until(() => browser.evaluate('Boolean(document.querySelector("#files > ul .file[data-path=\\"lib/notes.txt\\"]"))'), 'rule removal restores sidebar');

  // Current-file search includes unsaved text and uses browser scalar offsets.
  await browser.evaluate(`(() => { const field = document.querySelector('textarea'); field.value = '😀 draft ONLY'; field.dispatchEvent(new Event('input')); })()`);
  await key({key: 'f', ctrlKey: true});
  await until(() => browser.evaluate('document.activeElement?.id === "command-query"'), 'current-file shortcut');
  await query('only');
  await until(async () => (await labels()).join() === 'lib/notes.txt:1:9', 'unsaved current-file result');
  // A replacement through the editor, rather than the query, refreshes results.
  await browser.evaluate(`(() => { const field = document.querySelector('textarea'); field.value = '😀 changed draft ONLY'; field.dispatchEvent(new Event('input')); })()`);
  await until(async () => (await labels()).join() === 'lib/notes.txt:1:17', 'draft replacement refreshes search');
  await key({key: 'Enter'});
  await until(() => browser.evaluate('document.activeElement?.tagName === "TEXTAREA" && document.activeElement.selectionStart === 17'), 'draft match navigation');
  assert.equal(await browser.evaluate('document.querySelector("textarea").value'), '😀 changed draft ONLY');

  // Keep actual responses, then deliver A1 after B and A2. Matching query
  // text alone cannot distinguish this old success or old failure.
  await browser.evaluate(`window.actualFetch = window.fetch; window.heldSearches = [];
    window.fetch = async (...args) => {
      const response = await window.actualFetch(...args);
      if (String(args[0]).startsWith('/api/search?'))
        return new Promise(resolve => window.heldSearches.push({url: args[0], response, resolve}));
      return response;
    };`);
  await command(browser, 'search-project'); await query('needle');
  await until(() => browser.evaluate('window.heldSearches.length === 1'), 'A1 pending');
  await query('alpha');
  await until(() => browser.evaluate('window.heldSearches.length === 2'), 'B pending');
  await query('needle');
  await until(() => browser.evaluate('window.heldSearches.length === 3'), 'A2 pending');
  await browser.evaluate('window.heldSearches[2].resolve(window.heldSearches[2].response)');
  await until(async () => (await labels()).join() === 'lib/notes.txt:2:6', 'A2 accepted');
  await browser.evaluate(`window.heldSearches[0].resolve(new Response(JSON.stringify({message:'stale failure'}), {status:500}));
    window.heldSearches[1].resolve(window.heldSearches[1].response);`);
  await sleep(250); assert.deepEqual(await labels(), ['lib/notes.txt:2:6']);
  await query('alpha');
  await until(() => browser.evaluate('window.heldSearches.length === 4'), 'pending before close');
  await key({key: 'Escape'}); await command(browser, 'go-to-file');
  await browser.evaluate('window.heldSearches[3].resolve(window.heldSearches[3].response); window.fetch = window.actualFetch');
  await sleep(250); assert.ok((await labels()).includes('main.sld'), 'late text reply cannot replace the file picker');
  await key({key: 'ArrowDown'});
  assert.equal(await browser.evaluate('document.querySelector("#command-query").getAttribute("aria-activedescendant")'), 'command-result-1');
  await key({key: 'Escape'});
  // Reconnection starts a new search intention even when the query is unchanged.
  await browser.evaluate(`window.heldReconnect = [];
    window.fetch = async (...args) => { const response = await window.actualFetch(...args);
      if (String(args[0]).startsWith('/api/search?'))
        return new Promise(resolve => window.heldReconnect.push({response, resolve}));
      return response; };`);
  await command(browser, 'search-project'); await query('needle');
  await until(() => browser.evaluate('window.heldReconnect.length === 1'), 'search before reconnect');
  await browser.evaluate('window.dispatchEvent(new Event("online"))');
  await until(() => browser.evaluate('window.heldReconnect.length === 2'), 'search refreshed on reconnect');
  await browser.evaluate('window.heldReconnect[1].resolve(window.heldReconnect[1].response)');
  await until(async () => (await labels()).join() === 'lib/notes.txt:2:6', 'reconnected search');
  await browser.evaluate(`window.heldReconnect[0].resolve(new Response('{"message":"old server"}', {status:500}));
    window.fetch = window.actualFetch;`);
  await sleep(200); assert.deepEqual(await labels(), ['lib/notes.txt:2:6']);
  await key({key: 'Escape'});
  // A search read must not move the cursor after explicit A→B→A navigation.
  await browser.evaluate(`window.actualFetch = window.fetch; window.heldFile = null;
    window.fetch = async (...args) => {
      const response = await window.actualFetch(...args);
      if (String(args[0]) === '/api/file?path=main.sld')
        return new Promise(resolve => { window.heldFile = () => resolve(response); });
      return response;
    };`);
  await command(browser, 'search-project'); await query('alpha');
  await until(async () => (await labels()).join() === 'main.sld:2:3', 'navigation result');
  await key({key: 'Enter'});
  await until(() => browser.evaluate('Boolean(window.heldFile)'), 'search read held');
  await browser.evaluate(`document.querySelector('.file[data-path="lib/notes.txt"]').click()`);
  await until(async () => (await title()).startsWith('lib/notes.txt'), 'navigate away');
  await browser.evaluate(`document.querySelector('.file[data-path="main.sld"]').click()`);
  await until(async () => (await title()) === 'main.sld', 'navigate back');
  await browser.evaluate('document.querySelector("textarea").setSelectionRange(0,0); window.fetch = window.actualFetch; window.heldFile()');
  await sleep(250);
  assert.equal(await browser.evaluate('document.querySelector("textarea").selectionStart'), 0, 'old search cannot move the cursor');
  await command(browser, 'search-project'); await query('alpha');
  await until(async () => (await labels()).join() === 'main.sld:2:3', 'result before a disk change');
  await writeFile(join(project, 'main.sld'), '(import (snail core base))\n; inserted\n; alpha\n');
  await until(() => browser.evaluate('document.querySelector("textarea").value.includes("inserted")'), 'new disk revision');
  await browser.evaluate('document.querySelector("textarea").setSelectionRange(0,0)');
  await key({key: 'Enter'});
  await until(() => browser.evaluate('!document.getElementById("command-query")'), 'stale revision opened');
  await sleep(250);
  assert.equal(await browser.evaluate('document.querySelector("textarea").selectionStart'), 0, 'old coordinates are rejected');

  // Search can jump beyond the first screen. Use actual pointer input here:
  // setting selectionStart would also succeed on an offscreen textarea.
  const longLines = Array.from({length: 240}, (_, i) => `; line ${i + 1}: ${i === 89 ? 'cursor-target' : 'ordinary text'}`);
  const longText = longLines.join('\n') + '\n';
  const offset = line => longLines.slice(0, line).reduce((count, text) => count + text.length + 1, 0);
  await writeFile(join(project, 'long.sld'), longText);
  await command(browser, 'search-project'); await query('cursor-target');
  await until(async () => (await labels()).join() === 'long.sld:90:12', 'result beyond first screen');
  await key({key: 'Enter'});
  await until(() => browser.evaluate('document.querySelector(".pane.active textarea").snailPath === "long.sld" && document.querySelector(".pane.active .editor").scrollTop > 1000'), 'deep result revealed');
  const point = line => browser.evaluate(`(() => {
    const field = document.querySelector('.pane.active textarea'), box = field.getBoundingClientRect(), style = getComputedStyle(field);
    return {x: box.left + parseFloat(style.paddingLeft) + 1,
      y: box.top + parseFloat(style.paddingTop) + (${line} + .5) * parseFloat(style.lineHeight)};
  })()`);
  const mouse = (type, where, buttons) => browser.send('Input.dispatchMouseEvent', {type, ...where, button: 'left', buttons, clickCount: 1});
  const click = async where => { await mouse('mousePressed', where, 1); await mouse('mouseReleased', where, 0); };
  await click(await point(100));
  assert.equal(await browser.evaluate('document.querySelector(".pane.active textarea").selectionStart'), offset(100), 'click reaches the text field below the first screen');

  const beforeScroll = await browser.evaluate('document.querySelector(".pane.active .editor").scrollTop');
  await browser.send('Input.dispatchMouseEvent', {type: 'mouseWheel', ...await point(100), deltaX: 0, deltaY: 1200});
  await until(() => browser.evaluate(`document.querySelector('.pane.active .editor').scrollTop > ${beforeScroll + 1000}`), 'wheel scroll after search');
  const line = await browser.evaluate(`Math.floor(document.querySelector('.pane.active .editor').scrollTop / 20) + 5`);
  await mouse('mousePressed', await point(line), 1);
  await mouse('mouseMoved', await point(line + 2), 1);
  await mouse('mouseReleased', await point(line + 2), 0);
  assert.deepEqual(await browser.evaluate(`(() => { const field = document.querySelector('.pane.active textarea'); return [field.selectionStart, field.selectionEnd]; })()`), [offset(line), offset(line + 2)], 'drag selects visible text after scrolling');
  await click(await point(line + 1));
  await browser.send('Input.insertText', {text: 'typed '});
  const edited = longText.slice(0, offset(line + 1)) + 'typed ' + longText.slice(offset(line + 1));
  await until(() => browser.evaluate(`document.querySelector('.pane.active textarea').value === ${JSON.stringify(edited)}`), 'typing at the clicked line');
  await until(async () => (await title()).includes('●'), 'deep edit retained as a draft');
  if (screenshot) await browser.screenshot(screenshot);

  // A short file still fills its pane, including the space after its text.
  await browser.evaluate(`document.querySelector('.file[data-path="main.sld"]').click()`);
  await until(() => browser.evaluate('document.querySelector(".pane.active textarea").snailPath === "main.sld"'), 'short file restored');
  const blank = await browser.evaluate(`(() => { const field = document.querySelector('.pane.active textarea'), box = field.closest('.editor').getBoundingClientRect();
    return {x: field.getBoundingClientRect().left + 20, y: box.bottom - 25}; })()`);
  await click(blank);
  assert.equal(await browser.evaluate('document.querySelector(".pane.active textarea").selectionStart === document.querySelector(".pane.active textarea").value.length'), true, 'blank space in a short file remains editable');
  console.log('ide-search: files, saved and draft matches, pointer editing after scrolling, cursor safety, and stale replies');
} catch (error) {
  console.error(await browser.evaluate(`({query:document.getElementById('command-query')?.value,
    mode:document.getElementById('command-query')?.placeholder,
    labels:[...document.querySelectorAll('.choice-label')].map(node=>node.textContent),
    help:document.querySelector('.palette-help')?.textContent,
    empty:document.querySelector('.palette-empty')?.textContent})`));
  throw error;
} finally { browser.close(); await service.stop(); await rm(project, {recursive: true, force: true}); }
