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
  const windowsVirtualKeyCode = key === 'Enter' ? 13 : key === 'Tab' ? 9 : key.toUpperCase().charCodeAt(0);
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
async function hoverControls() {
  await call('Input.dispatchMouseEvent', {type: 'mouseMoved', x: 240, y: 240});
  await evaluate(`globalThis.hoverActions = []; globalThis.hoverRoot = document.createElement('div');
    Object.assign(hoverRoot.style, {position:'fixed', left:'0', top:'0', width:'160px', height:'70px', zIndex:'10000'});
    document.body.append(hoverRoot); globalThis.hoverUi = new snailApp.ui.constructor(hoverRoot, action => hoverActions.push(action));
    globalThis.hoverModel = structuredClone(snailApp.ui.nodes.get('more').model);
    hoverModel.key = 'hover-choice'; hoverModel.rect = [0,0,160,70];
    const preview = snailApp.ui.nodes.get('amount').model.action;
    hoverModel.hover = {enter: {...preview, command: {...preview.command,args:[3]}},
      leave: {...preview,command:{...preview.command,args:[0]}}};
    hoverUi.render(hoverModel); globalThis.hoverButton = hoverRoot.firstChild;`);
  await call('Input.dispatchMouseEvent', {type: 'mouseMoved', x: 80, y: 35});
  assert.deepEqual(await evaluate('hoverActions.map(action => action.command.args)'), [[3]]);
  await evaluate('const retained = structuredClone(hoverModel); retained.hover.leave.command.args = [99]; hoverUi.render(retained)');
  assert.equal(await evaluate('hoverRoot.firstChild === hoverButton && hoverActions.length === 1'), true);
  await click('[data-ui-key="hover-choice"]');
  assert.deepEqual(await evaluate('hoverActions.map(action => action.command.args)'), [[3], []]);
  await call('Input.dispatchMouseEvent', {type: 'mouseMoved', x: 240, y: 240});
  assert.deepEqual(await evaluate('hoverActions.map(action => action.command.args)'), [[3], [], [0]]);
  await call('Input.dispatchMouseEvent', {type: 'mouseMoved', x: 80, y: 35});
  await evaluate('hoverUi.render(undefined)');
  assert.deepEqual(await evaluate('hoverActions.slice(-2).map(action => action.command.args)'), [[3], [99]]);
  await call('Input.dispatchMouseEvent', {type: 'mouseMoved', x: 240, y: 240});
  await evaluate(`hoverActions.length = 0; hoverUi.render(hoverModel); hoverButton = hoverRoot.firstChild;
    hoverButton.dispatchEvent(new PointerEvent('pointerenter', {pointerId:7,pointerType:'pen'}));
    hoverButton.dispatchEvent(new PointerEvent('pointercancel', {pointerId:7,pointerType:'pen'}));`);
  assert.deepEqual(await evaluate('hoverActions.map(action => action.command.args)'), [[3], [0]]);
  await evaluate(`hoverActions.length = 0; hoverButton.dispatchEvent(new PointerEvent('pointerenter', {pointerId:7,pointerType:'pen'}));
    window.dispatchEvent(new Event('blur'));`);
  assert.deepEqual(await evaluate('hoverActions.map(action => action.command.args)'), [[3], [0]]);
  await evaluate(`hoverActions.length = 0; hoverButton.dispatchEvent(new PointerEvent('pointerenter', {pointerId:7,pointerType:'pen'}));
    hoverUi.render({...hoverModel,hover:undefined});`);
  assert.deepEqual(await evaluate('hoverActions.map(action => action.command.args)'), [[3], [0]]);
  await evaluate(`hoverActions.length = 0; hoverUi.render(hoverModel);
    hoverButton.dispatchEvent(new PointerEvent('pointerenter', {pointerId:7,pointerType:'pen'}));
    hoverUi.render({...hoverModel,kind:1,hover:undefined});`);
  assert.equal(await evaluate('hoverRoot.firstChild !== hoverButton'), true);
  assert.deepEqual(await evaluate('hoverActions.map(action => action.command.args)'), [[3], [0]]);
  await evaluate('hoverUi.render(hoverModel); hoverActions.length = 0');
  await call('Emulation.setTouchEmulationEnabled', {enabled: true});
  await call('Input.dispatchTouchEvent', {type:'touchStart',touchPoints:[{x:80,y:35,id:1}]});
  await call('Input.dispatchTouchEvent', {type:'touchEnd',touchPoints:[]});
  assert.deepEqual(await evaluate('hoverActions.map(action => action.command.args)'), [[]]);
  await call('Emulation.setTouchEmulationEnabled', {enabled: false});
  await evaluate('hoverUi.render(undefined); hoverRoot.remove()');
  console.log('ok - hover previews retain keyed nodes, pair cleanup on removal/blur/cancel, and keep mouse/touch clicks separate');
}
async function dialControls() {
  await evaluate(`globalThis.dialRoot = document.createElement('div'); document.body.append(dialRoot);
    globalThis.dialUi = new snailApp.ui.constructor(dialRoot, () => { throw new Error('A readout cannot activate'); });
    globalThis.dialModel = {key:'dial',kind:6,rect:[0,0,72,72],text:'42',help:'Ore 42; hub health',
      properties:[2,,,75,,100],children:[]};
    dialUi.render(dialModel); globalThis.dialNode = dialRoot.firstChild;`);
  assert.equal(await evaluate('dialNode.textContent'), '42');
  assert.equal(await evaluate('dialNode.style.getPropertyValue("--ui-dial-fill")'), '0.75turn');
  assert.match(await evaluate('getComputedStyle(dialNode).backgroundImage'), /conic-gradient/);
  assert.equal(await evaluate('dialNode.getAttribute("aria-valuenow")'), '75');
  const accessibility = await call('Accessibility.getFullAXTree');
  const meter = accessibility.nodes.find(node => node.role?.value === 'meter' && node.name?.value === 'Ore 42; hub health');
  assert.equal(meter?.value?.value, 75); assert.equal(meter?.description?.value, '42');
  await evaluate('dialUi.render({...dialModel,text:"99",properties:[3,,,150,,100]}); dialNode.click()');
  assert.equal(await evaluate('dialRoot.firstChild === dialNode && dialNode.textContent === "99"'), true);
  assert.equal(await evaluate('dialNode.style.getPropertyValue("--ui-dial-fill")'), '1turn');
  assert.equal(await evaluate('dialNode.getAttribute("aria-valuenow")'), '100');
  await evaluate('dialUi.render({...dialModel,properties:[4,,,-1,,100]})');
  assert.equal(await evaluate('dialNode.style.getPropertyValue("--ui-dial-fill")'), '0turn');
  await evaluate('dialUi.render(undefined); dialRoot.remove()');
  console.log('ok - circular readouts expose accessible meter values, center text and clamped rings on retained DOM nodes');
}
try {
  await call('Page.bringToFront'); await until('!!globalThis.snailApp && !!document.querySelector("[data-ui-key=more]")');
  await evaluate('snailApp.local("set-value", [10])'); await until('!snailApp.localWork && !snailApp.dirty');
  await evaluate('globalThis.originalInput = document.querySelector("[data-ui-key=amount] input")');
  const initialAccessibility = await call('Accessibility.getFullAXTree');
  assert.match(initialAccessibility.nodes.find(node => node.role?.value === 'textbox' && node.name?.value === 'Value')?.description?.value ?? '', /unfinished edit/);
  await click('[data-ui-key="more"]');
  assert.match(await evaluate('document.querySelector("[data-status]").textContent'), /11/);
  await key('Tab', 'Tab'); assert.equal(await evaluate('document.activeElement === originalInput'), true);
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
  const accessibility = await call('Accessibility.getFullAXTree');
  const field = accessibility.nodes.find(node => node.role?.value === 'textbox' && node.name?.value === 'Value');
  assert.match(field?.description?.value ?? '', /whole number/);
  assert.match(await evaluate('document.querySelector("[data-status]").textContent'), /12/);
  await enter('37'); await key('Enter', 'Enter'); await until('!snailApp.localWork && !snailApp.dirty');
  await until('document.querySelector("[data-status]").textContent === "Value 37"');
  await click('[data-ui-key="more"]'); await key('Enter', 'Enter'); await until('!snailApp.localWork && !snailApp.dirty');
  await until('document.querySelector("[data-status]").textContent === "Value 39"');
  console.log('ok - integer errors, native form Enter, and focused button activation');
  await evaluate(`globalThis.normalDispatch = snailApp.ui.dispatch; globalThis.queued = [];
    snailApp.ui.dispatch = action => new Promise(resolve => queued.push(async () => resolve(await normalDispatch(action))));`);
  await enter('41'); await key('Enter', 'Enter'); await enter('42');
  await evaluate('queued.shift()()'); await until('!snailApp.localWork && !snailApp.dirty');
  assert.equal(await evaluate('originalInput.value'), '42');
  await enter('45'); await key('Enter', 'Enter'); await key('Enter', 'Enter');
  await evaluate('queued.shift()()'); await evaluate('snailApp.local("increment")'); await until('!snailApp.localWork && !snailApp.dirty');
  assert.equal(await evaluate('originalInput.value'), '45');
  await evaluate('queued.shift()()'); await until('!snailApp.localWork && !snailApp.dirty');
  await evaluate('snailApp.ui.dispatch = () => Promise.resolve(false)');
  await enter('47'); await key('Enter', 'Enter'); await evaluate('snailApp.dirty = true'); await until('!snailApp.dirty');
  assert.equal(await evaluate('originalInput.value'), '47');
  await evaluate(`originalInput.setSelectionRange(0, 1); const tree = structuredClone(snailApp.runtime.view().ui);
    tree.children.reverse(); snailApp.ui.render(tree);`);
  assert.equal(await evaluate('document.activeElement === originalInput && originalInput.selectionStart === 0 && originalInput.selectionEnd === 1'), true);
  await evaluate('snailApp.ui.dispatch = normalDispatch; snailApp.dirty = true'); await until('!snailApp.dirty');
  await enter('39'); await key('Enter', 'Enter'); await until('!snailApp.localWork && !snailApp.dirty');
  console.log('ok - later typing and submissions survive older completion; failed submits and keyed movement retain draft/focus');
  await hoverControls();
  await dialControls();
  if (process.argv[4]) {
    const screenshot = await call('Page.captureScreenshot', {format: 'png', captureBeyondViewport: true});
    writeFileSync(process.argv[4], Buffer.from(screenshot.data, 'base64'));
  }
  await call('Emulation.setDeviceMetricsOverride', {width: 390, height: 844, deviceScaleFactor: 1, mobile: true});
  await until('document.querySelector("[data-ui]").getBoundingClientRect().width < 400');
  await until('Math.abs(document.querySelector("[data-ui-key=controls]").getBoundingClientRect().width - document.querySelector("[data-ui]").getBoundingClientRect().width) < 1');
  assert.ok(await evaluate('Array.from(document.querySelectorAll("[data-ui-key]")).every(node => { const r = node.getBoundingClientRect(); return r.width >= 0 && r.height >= 0; })'));
  assert.ok(await evaluate('Array.from(document.querySelectorAll("[data-ui-key]")).filter(node => node.style.overflowY === "auto").every(node => node.scrollWidth <= node.clientWidth)'));
  await call('Emulation.setTouchEmulationEnabled', {enabled: true});
  const touch = await evaluate(`(() => { const node = document.querySelector('[data-ui-key="more"]'); node.scrollIntoView({block:'center'});
    const r = node.getBoundingClientRect(); return {x:r.x+r.width/2,y:r.y+r.height/2}; })()`);
  await call('Input.dispatchTouchEvent', {type: 'touchStart', touchPoints: [{...touch, id: 1}]});
  await call('Input.dispatchTouchEvent', {type: 'touchEnd', touchPoints: []});
  await until('document.querySelector("[data-status]").textContent === "Value 40"');
  console.log('ok - narrow viewport retains nonnegative rectangles and touch activates a control');
} finally { socket.close(); await fetch(`${devtools}/json/close/${target.id}`); }
