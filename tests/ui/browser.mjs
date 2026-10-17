// Real DOM input and compatible Wasm replacement, without a GPU requirement.
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
const origin = process.argv[2] ?? 'http://127.0.0.1:4195';
const devtools = process.argv[3] ?? 'http://127.0.0.1:9451';
const target = await (await fetch(`${devtools}/json/new?${encodeURIComponent(origin)}`, {method: 'PUT'})).json();
const socket = new WebSocket(target.webSocketDebuggerUrl), waiting = new Map(); let sequence = 0;
await new Promise(resolve => socket.addEventListener('open', resolve, {once: true}));
socket.onmessage = event => { const value = JSON.parse(event.data); if (value.id) { waiting.get(value.id)?.(value); waiting.delete(value.id); } };
function call(method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = ++sequence, timer = setTimeout(() => reject(new Error(`CDP timeout: ${method}`)), 15000);
    waiting.set(id, result => { clearTimeout(timer); result.error ? reject(new Error(result.error.message)) : resolve(result.result); });
    socket.send(JSON.stringify({id, method, params}));
  });
}
async function evaluate(expression) {
  const result = await call('Runtime.evaluate', {expression, awaitPromise: true, returnByValue: true});
  if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description ?? result.exceptionDetails.text);
  return result.result.value;
}
async function until(expression) {
  const deadline = Date.now() + 15000;
  while (Date.now() < deadline) {
    if (await evaluate(expression)) return;
    await new Promise(resolve => setTimeout(resolve, 80));
  }
  throw new Error(`Condition did not settle: ${expression}`);
}
async function key(key, code, modifiers = 0) {
  const windowsVirtualKeyCode = key === 'Enter' ? 13 : key.toUpperCase().charCodeAt(0);
  await call('Input.dispatchKeyEvent', {type: 'keyDown', key, code, modifiers, windowsVirtualKeyCode,
    ...(key === 'Enter' ? {text: '\r'} : {})});
  await call('Input.dispatchKeyEvent', {type: 'keyUp', key, code, modifiers, windowsVirtualKeyCode});
}
async function click(selector) {
  const point = await evaluate(`(() => { const node = document.querySelector(${JSON.stringify(selector)}); node.scrollIntoView({block:'center'});
    const rect = node.getBoundingClientRect(); return {x: rect.x + rect.width/2, y: rect.y + rect.height/2}; })()`);
  await call('Input.dispatchMouseEvent', {type: 'mousePressed', ...point, button: 'left', clickCount: 1});
  await call('Input.dispatchMouseEvent', {type: 'mouseReleased', ...point, button: 'left', clickCount: 1});
  await until('!snailApp.localWork && !snailApp.dirty');
}
async function enter(text) {
  await click('[data-ui-key="amount"] input'); await key('a', 'KeyA', 2);
  await call('Input.insertText', {text});
}
try {
  await call('Page.bringToFront'); await until('!!globalThis.snailApp && !!document.querySelector("[data-ui-key=more]")');
  await evaluate('snailApp.local("set-value", [10])'); await until('!snailApp.localWork && !snailApp.dirty');
  await evaluate('globalThis.originalInput = document.querySelector("[data-ui-key=amount] input")');
  await click('[data-ui-key="more"]');
  assert.match(await evaluate('document.querySelector("[data-status]").textContent'), /11/);
  await enter('37'); await evaluate('snailApp.local("increment")'); await until('!snailApp.localWork && !snailApp.dirty');
  assert.equal(await evaluate('originalInput.value'), '37');
  assert.equal(await evaluate('document.activeElement === originalInput'), true);
  await evaluate(`(async () => { const app = snailApp, bytes = await (await fetch(app.manifest.module)).arrayBuffer();
    await app.runtime.replace(app.runtime.prepare(new Uint8Array(bytes), app.manifest)); app.dirty = true; })()`);
  await until('!snailApp.dirty');
  assert.equal(await evaluate('document.querySelector("[data-ui-key=amount] input") === originalInput && document.activeElement === originalInput && originalInput.value === "37"'), true);
  console.log('ok - pointer control, typed state transition, draft and focus survive redraw and compatible reload');
  await enter('12.5'); await click('[data-ui-key="amount"] button');
  assert.equal(await evaluate('originalInput.getAttribute("aria-invalid")'), 'true');
  assert.match(await evaluate('document.querySelector("[data-status]").textContent'), /12/);
  await enter('37'); await key('Enter', 'Enter'); await until('!snailApp.localWork && !snailApp.dirty');
  await until('document.querySelector("[data-status]").textContent === "Value 37"');
  await click('[data-ui-key="more"]'); await key('Enter', 'Enter'); await until('!snailApp.localWork && !snailApp.dirty');
  await until('document.querySelector("[data-status]").textContent === "Value 39"');
  console.log('ok - integer errors, native form Enter, and focused button activation');
  if (process.argv[4]) {
    const screenshot = await call('Page.captureScreenshot', {format: 'png', captureBeyondViewport: true});
    writeFileSync(process.argv[4], Buffer.from(screenshot.data, 'base64'));
  }
  await call('Emulation.setDeviceMetricsOverride', {width: 390, height: 844, deviceScaleFactor: 1, mobile: true});
  await until('document.querySelector("[data-ui]").getBoundingClientRect().width < 400');
  assert.ok(await evaluate('Array.from(document.querySelectorAll("[data-ui-key]")).every(node => { const r = node.getBoundingClientRect(); return r.width >= 0 && r.height >= 0; })'));
  console.log('ok - narrow viewport retains nonnegative assigned rectangles');
} finally { socket.close(); await fetch(`${devtools}/json/close/${target.id}`); }
