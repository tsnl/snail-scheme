// Browser input contracts without a running Scheme authority or GPU adapter.
// Start Chromium with a DevTools port, then pass its URL as the first argument.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync, mkdtempSync, rmSync} from 'node:fs';
import {createServer} from 'node:http';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {parseInputSettings} from '../../src/browser/input.mjs';
import {packageApplication} from '../../src/browser/build.mjs';

const root = new URL('../../', import.meta.url), devtools = process.argv[2] ?? 'http://127.0.0.1:9336';
// Keep the old discrete contract explicit even when Siegework opts into
// continuous controls. Neither fixture needs a running Scheme application.
const settings = {
  width: 960, height: 640, cellSize: 40, inputRepeatMilliseconds: 140,
  pointer: {move: 'move', confirm: 'confirm'},
  keys: {'3': ['choose', 3], Enter: ['confirm'], ' ': ['confirm'], u: ['improve'], r: ['mend'],
    w: ['pan', 0, -1], a: ['pan', -1, 0], s: ['pan', 0, 1], d: ['pan', 1, 0], ArrowDown: ['nudge', 0, 1]},
  repeatKeys: ['w', 'a', 's', 'd', 'ArrowDown'],
  controller: {0: ['confirm'], 12: ['nudge', 0, -1], 15: ['nudge', 1, 0]}, repeatButtons: [12, 15],
  controllerAxes: [
    {axis: 0, negative: ['pan', -1, 0], positive: ['pan', 1, 0], deadzone: 0.35},
    {axis: 1, negative: ['pan', 0, -1], positive: ['pan', 0, 1], deadzone: 0.35}
  ]
};
const continuous = {...settings, pointer: {...settings.pointer, coordinates: 'pixels'},
  keys: {...settings.keys, w: ['drift', 0, -1], a: ['drift', -1, 0], s: ['drift', 0, 1], d: ['drift', 1, 0]},
  repeatKeys: ['ArrowDown'], continuousKeys: ['w', 'a', 's', 'd'],
  controllerAxes: settings.controllerAxes.map(axis => ({...axis, continuous: true,
    negative: ['drift', ...axis.negative.slice(1)], positive: ['drift', ...axis.positive.slice(1)]}))};
const zoom = {...continuous, zoomHandler: 'zoom'};
const drag = {...zoom, dragHandler: 'drag'};
const shell = readFileSync(new URL('apps/siegework/index.html', root), 'utf8').replace('<script type="module" data-application-entry></script>', '');
const page = `<!doctype html><html><body style="margin:0;min-height:3000px">
<canvas width="960" height="640" tabindex="0" style="display:block;width:480px;height:320px"></canvas>
<button data-handler="choose" data-args="[3]"><span>Observation tower</span></button>
<input id="text"><textarea></textarea><select><option>One</option><option>Two</option></select>
<div contenteditable="true" id="editor"></div><details><summary>Help</summary>Field guide</details>
<form id="integer-form" data-handler="restart-seed" novalidate>
  <label for="integer">Next run seed</label><input id="integer" type="text" inputmode="numeric" data-i32 aria-describedby="integer-error">
  <button id="integer-submit" type="submit">Start this seed</button><p id="integer-error" data-input-error role="alert"></p>
</form>
<form id="pair-form" data-handler="position" novalidate>
  <label for="left">Left</label><input id="left" data-i32 aria-describedby="pair-error">
  <label for="top">Top</label><input id="top" data-i32 aria-describedby="pair-error">
  <button type="submit">Set position</button><p id="pair-error" data-input-error role="alert"></p>
</form>
<script type="module">
import {BrowserInput,parseInputSettings} from '/input.mjs';
globalThis.settings=${JSON.stringify(settings)};
globalThis.continuous=${JSON.stringify(continuous)};
globalThis.zoomSettings=${JSON.stringify(zoom)};
globalThis.dragSettings=${JSON.stringify(drag)};
globalThis.configuration=parseInputSettings(settings);
globalThis.dispatches=[];globalThis.keys=[];globalThis.pads=[];
Object.defineProperty(navigator,'getGamepads',{value:()=>pads});
globalThis.input=new BrowserInput(document.querySelector('canvas'),()=>configuration,(binding,args)=>dispatches.push([binding,...args]));
document.querySelector('canvas').addEventListener('pointerdown',event=>{globalThis.lastPointer=event.pointerId;if(event.pointerType==='touch')globalThis.lastTouch=event.pointerId});
document.addEventListener('keydown',event=>keys.push({key:event.key,prevented:event.defaultPrevented}));
globalThis.replaceSettings=value=>configuration=parseInputSettings(value);
document.querySelector('canvas').focus();globalThis.ready=true;
</script></body></html>`;
const server = createServer((request, response) => {
  const paths = {'/input.mjs': ['src/browser/input.mjs', 'text/javascript'], '/style.css': ['apps/siegework/style.css', 'text/css'],
    '/lib/ui/style.css': ['src/ui/style.css','text/css']};
  const asset = paths[request.url];
  response.setHeader('content-type', asset?.[1] ?? 'text/html');
  response.end(asset ? readFileSync(new URL(asset[0], root)) : request.url === '/shell' ? shell : page);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
let ws, target, id = 0;
const pending = new Map(), extraTargets = [];
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(check, message) {
  const deadline = Date.now() + 10000;
  while (Date.now() < deadline) { if (await check()) return; await pause(25); }
  throw new Error(message);
}
function call(method, params = {}) {
  return new Promise((resolve, reject) => {
    const key = ++id, timeout = setTimeout(() => { pending.delete(key); reject(new Error(`DevTools timed out: ${method}`)); }, 10000);
    pending.set(key, value => { clearTimeout(timeout); value.error ? reject(new Error(value.error.message)) : resolve(value.result); });
    ws.send(JSON.stringify({id: key, method, params}));
  });
}
async function read(expression) {
  const result = await call('Runtime.evaluate', {expression, awaitPromise: true, returnByValue: true});
  if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description ?? result.exceptionDetails.text);
  return result.result.value;
}
async function down(key, code, windowsVirtualKeyCode, extra = {}) {
  await call('Input.dispatchKeyEvent', {type: 'keyDown', key, code, windowsVirtualKeyCode, ...extra});
}
async function up(key, code, windowsVirtualKeyCode) {
  await call('Input.dispatchKeyEvent', {type: 'keyUp', key, code, windowsVirtualKeyCode});
}
async function press(key, code, number, extra) {
  await down(key, code, number, extra); await up(key, code, number);
}
async function take() { return read('dispatches.splice(0)'); }
async function touch(type, points = []) {
  await call('Input.dispatchTouchEvent', {type, touchPoints: points.map(([id, x, y]) => ({id, x, y}))});
  await read('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve(true))))');
}
async function checkGestureEndpoints() {
  const directory = mkdtempSync(join(tmpdir(), 'snail-gesture-input-'));
  const handlers = [{binding:'tick',payload:[]},{binding:'move',payload:['I32','I32']},{binding:'confirm',payload:[]},{binding:'zoom',payload:['I32']}];
  const source = {library:['test'],applications:[{binding:'world',state:'World',schema:1,handlers},
    {binding:'client',state:'Client',schema:1,handlers}]};
  writeFileSync(join(directory,'application.syntax.json'),JSON.stringify(source));
  try { for (const [name, bindings] of [['zoomHandler',['confirm','move','missing']],['dragHandler',['confirm','zoom','missing']]]) {
    for (const binding of bindings) {
      const input = {...settings,id:'gesture-test',owners:{world:'match',client:'client'},tick:'tick',reset:'tick',[name]:binding};
      writeFileSync(join(directory,'settings.json'),JSON.stringify(input));
      await assert.rejects(packageApplication(root.pathname,directory,directory),/zoom handler requires one I32|drag handler requires two I32|unknown client handler/);
    }
  }} finally { rmSync(directory,{recursive:true,force:true}); }
}

try {
  assert.equal(parseInputSettings(settings).axes.length, 2);
  assert.equal(parseInputSettings(settings).continuousKeys.size, 0);
  assert.equal(parseInputSettings(settings).pointer.coordinates, 'cells');
  assert.equal(parseInputSettings(continuous).continuousKeys.size, 4);
  assert.equal(parseInputSettings(continuous).axes.every(axis => axis.continuous), true);
  assert.equal(parseInputSettings(zoom).zoomHandler, 'zoom');
  assert.equal(parseInputSettings(drag).dragHandler, 'drag');
  const legacy = {...settings, controllerAxes: undefined, repeatKeys: undefined, repeatButtons: undefined};
  assert.equal(parseInputSettings(legacy).buttons.get(0)[0], 'confirm');
  for (const broken of [
    {...settings, repeatKeys: ['missing']}, {...settings, repeatButtons: [99]},
    {...settings, inputRepeatMilliseconds: 0}, {...settings, keys: {x: ['pan', 2147483648]}},
    {...settings, controllerAxes: {}},
    {...settings, controllerAxes: [{axis: 0, negative: ['pan', -1, 0], positive: ['pan', 1, 0], deadzone: 1}]},
    {...settings, controllerAxes: [settings.controllerAxes[0], settings.controllerAxes[0]]},
    {...continuous, continuousKeys: 'd'}, {...continuous, continuousKeys: ['missing']},
    {...continuous, continuousKeys: ['Enter']}, {...continuous, continuousKeys: ['3']},
    {...continuous, repeatKeys: ['d']},
    {...continuous, controllerAxes: [{...continuous.controllerAxes[0], continuous: 'yes'}]},
    {...continuous, controllerAxes: [{...continuous.controllerAxes[0], negative: ['confirm']}]},
    {...continuous, pointer: {...continuous.pointer, coordinates: 'tiles'}},
    {...settings, zoomHandler: ''}, {...settings, zoomHandler: 1}, {...settings, zoomHandler: null},
    {...settings, dragHandler: ''}, {...settings, dragHandler: 1}, {...settings, dragHandler: null}
  ]) assert.throws(() => parseInputSettings(broken));
  await checkGestureEndpoints();
  console.log('ok - settings retain legacy maps and reject malformed repeat/continuous/axis/I32/pointer declarations');

  target = await (await fetch(`${devtools}/json/new?${encodeURIComponent(origin)}`, {method: 'PUT'})).json();
  ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise(resolve => ws.addEventListener('open', resolve, {once: true}));
  ws.onmessage = event => { const value = JSON.parse(event.data); if (value.id) { pending.get(value.id)?.(value); pending.delete(value.id); } };
  await call('Page.enable'); await call('Page.bringToFront');
  await until(() => read('globalThis.ready && document.hasFocus()'), 'input fixture did not receive focus');
  await press('3', 'Digit3', 51);
  assert.deepEqual(await take(), [['choose', 3]]);
  await down('Enter', 'Enter', 13); await down('Enter', 'Enter', 13, {autoRepeat: true}); await up('Enter', 'Enter', 13);
  assert.deepEqual(await take(), [['confirm']]);
  await down('d', 'KeyD', 68);
  assert.deepEqual(await take(), [['pan', 1, 0]]);
  await read('globalThis.time=performance.now()+1000;input.frame(time);input.frame(time);input.frame(time+10000)');
  assert.deepEqual(await take(), [['pan', 1, 0], ['pan', 1, 0]]);
  await up('d', 'KeyD', 68); await read('input.frame(time+20000)');
  assert.deepEqual(await take(), []);
  await down('W', 'KeyW', 87, {modifiers: 8}); await up('w', 'KeyW', 87); await read('input.frame(time+30000)');
  assert.deepEqual(await take(), [['pan', 0, -1]]);
  await press('ArrowDown', 'ArrowDown', 40); await press(' ', 'Space', 32);
  assert.deepEqual(await take(), [['nudge', 0, 1], ['confirm']]);
  assert.equal(await read('keys.slice(-2).every(event=>event.prevented) && scrollY===0'), true);
  console.log('ok - real keys select tools, distinguish camera/cursor, prevent scrolling, and bound held repeats without catchup');

  await read("document.querySelector('button').focus()");
  await press('Enter', 'Enter', 13, {text: '\r'}); await press(' ', 'Space', 32, {text: ' '});
  assert.deepEqual(await take(), [['choose', 3], ['choose', 3]]);
  await read("document.querySelector('summary').focus()"); await press('Enter', 'Enter', 13, {text: '\r'});
  assert.equal(await read("document.querySelector('details').open"), true); assert.deepEqual(await take(), []);
  for (const selector of ['input', 'textarea', '[contenteditable]']) {
    await read(`document.querySelector(${JSON.stringify(selector)}).focus()`);
    await press('w', 'KeyW', 87, {text: 'w'});
    assert.equal(await read(`(()=>{const e=document.querySelector(${JSON.stringify(selector)});return (e.value??e.textContent)==='w'})()`), true);
  }
  await read("document.querySelector('select').focus()"); await press('ArrowDown', 'ArrowDown', 40);
  assert.deepEqual(await take(), []);
  assert.equal(await read('keys.slice(-1)[0].prevented'), false);
  await read("document.querySelector('canvas').focus(); for(const modifiers of [{ctrlKey:true},{metaKey:true},{altKey:true},{isComposing:true}]) document.activeElement.dispatchEvent(new KeyboardEvent('keydown',{key:'r',code:'KeyR',bubbles:true,cancelable:true,...modifiers}))");
  assert.equal(await read('keys.slice(-4).every(event=>!event.prevented)'), true); assert.deepEqual(await take(), []);
  console.log('ok - native Enter/Space activates only the focused button; editing, composition, and shortcut defaults remain available');

  await down('d', 'KeyD', 68); await take();
  const blur = await (await fetch(`${devtools}/json/new?about:blank`, {method: 'PUT'})).json(); extraTargets.push(blur.id);
  await until(() => read('!document.hasFocus()'), 'second page did not blur input fixture');
  await read('input.frame(time+40000)'); assert.deepEqual(await take(), []);
  await call('Page.bringToFront'); await until(() => read('document.hasFocus()'), 'input fixture did not regain focus');
  await down('d', 'KeyD', 68, {autoRepeat: true}); await read('input.frame(time+50000)');
  assert.deepEqual(await take(), []);
  await up('d', 'KeyD', 68); await press('d', 'KeyD', 68); assert.deepEqual(await take(), [['pan', 1, 0]]);
  await down('d', 'KeyD', 68); await take();
  await read("replaceSettings({...settings,keys:{...settings.keys,d:['pan',-7,0]}});input.frame(time+60000)");
  await down('d', 'KeyD', 68, {autoRepeat: true}); assert.deepEqual(await take(), []);
  await up('d', 'KeyD', 68); await press('d', 'KeyD', 68); assert.deepEqual(await take(), [['pan', -7, 0]]);
  await read('replaceSettings(settings);input.frame(performance.now())');
  console.log('ok - actual window blur and settings replacement cancel held keys until a fresh press');

  await read("globalThis.pad={index:1,id:'test-controller',connected:true,buttons:Array.from({length:16},()=>({pressed:false})),axes:[0,0]};pads=[null,pad];time=0;input.frame(time)");
  await read('pad.axes=[0.3,-0.34];input.frame(++time)'); assert.deepEqual(await take(), []);
  await read('pad.axes=[0.8,-0.8];input.frame(++time)'); assert.deepEqual(await take(), [['pan', 1, 0], ['pan', 0, -1]]);
  await read('input.frame(time+139)'); assert.deepEqual(await take(), []);
  await read('input.frame(time+140);input.frame(time+140);input.frame(time+10000)');
  assert.deepEqual(await take(), [['pan', 1, 0], ['pan', 0, -1], ['pan', 1, 0], ['pan', 0, -1]]);
  await read('pad.axes=[-0.8,0];input.frame(time+10001)'); assert.deepEqual(await take(), [['pan', -1, 0]]);
  await read('pad.axes=[0,0];pad.buttons[0].pressed=true;time+=20000;input.frame(time);input.frame(time+10000)');
  assert.deepEqual(await take(), [['confirm']]);
  await read('pad.buttons[0].pressed=false;pad.buttons[12].pressed=true;pad.buttons[15].pressed=true;input.frame(time+10001);input.frame(time+10141)');
  assert.deepEqual(await take(), [['nudge', 0, -1], ['nudge', 1, 0], ['nudge', 0, -1], ['nudge', 1, 0]]);
  await read('pads=[];input.frame(time+20000);pads=[pad];input.frame(time+30000);input.frame(time+40000)');
  assert.deepEqual(await take(), []);
  await read('pad.buttons.forEach(button=>button.pressed=false);input.frame(time+40001);pad.buttons[0].pressed=true;input.frame(time+40002)');
  assert.deepEqual(await take(), [['confirm']]);
  await read('replaceSettings({...settings});input.frame(time+50000);input.frame(time+60000)');
  assert.deepEqual(await take(), []);
  await read('pad.buttons[0].pressed=false;input.frame(time+60001);pad.buttons[0].pressed=true;input.frame(time+60002)');
  assert.deepEqual(await take(), [['confirm']]);
  await read("document.querySelector('input').focus();input.frame(time+70000);document.querySelector('canvas').focus();input.frame(time+80000)");
  assert.deepEqual(await take(), []);
  await read('pads=[];input.frame(time+80001)');
  console.log('ok - injected Gamepad axes have a deadzone and fair bounded repeats; buttons are edges; reconnect/reload/editing require release');

  await call('Input.dispatchMouseEvent', {type: 'mouseMoved', x: 170, y: 70}); await take();
  await call('Input.dispatchMouseEvent', {type: 'mousePressed', x: 170, y: 70, button: 'left', buttons: 1, clickCount: 1});
  await call('Input.dispatchMouseEvent', {type: 'mouseReleased', x: 170, y: 70, button: 'left', buttons: 0, clickCount: 1});
  assert.deepEqual(await take(), [['move', 8, 3], ['confirm']]);
  await press('u', 'KeyU', 85); assert.deepEqual(await take(), [['improve']]);
  await call('Input.dispatchMouseEvent', {type: 'mouseMoved', x: 479, y: 319});
  await call('Input.dispatchMouseEvent', {type: 'mouseMoved', x: 478, y: 318});
  assert.deepEqual(await take(), [['move', 23, 15]]);
  console.log('ok - scaled pointer input sends screen cells before confirmation, coalesces same-cell moves, and leaves keyboard controls active');

  await read('replaceSettings(continuous);input.frame(time=0)');
  await down('d', 'KeyD', 68); await down('d', 'KeyD', 68, {autoRepeat: true});
  assert.deepEqual(await take(), []);
  await read('for(const next of [8,24,57,57,10057,10073])input.frame(time=next)');
  assert.deepEqual(await take(), [['drift', 8, 0], ['drift', 16, 0], ['drift', 33, 0], ['drift', 50, 0], ['drift', 16, 0]]);
  await up('d', 'KeyD', 68); await read('input.frame(time+=16)'); assert.deepEqual(await take(), []);
  await down('W', 'KeyW', 87, {modifiers: 8}); await down('a', 'KeyA', 65);
  await read('input.frame(time+=20)');
  assert.deepEqual(await take(), [['drift', 0, -20], ['drift', -20, 0]]);
  await up('w', 'KeyW', 87); await up('a', 'KeyA', 65);
  await press('ArrowDown', 'ArrowDown', 40); await press('u', 'KeyU', 85);
  assert.deepEqual(await take(), [['nudge', 0, 1], ['improve']]);
  console.log('ok - continuous keys follow variable frame durations, cap stalls, allow Shift/diagonals, and stop immediately on release');

  await down('d', 'KeyD', 68);
  await read("document.activeElement.dispatchEvent(new KeyboardEvent('keydown',{key:'r',code:'KeyR',ctrlKey:true,bubbles:true,cancelable:true}));input.frame(time+=16)");
  assert.deepEqual(await take(), []); assert.equal(await read('keys.slice(-1)[0].prevented'), false);
  await down('d', 'KeyD', 68, {autoRepeat: true}); await read('input.frame(time+=16)'); assert.deepEqual(await take(), []);
  await up('d', 'KeyD', 68); await down('d', 'KeyD', 68);
  await read("document.querySelector('input').focus();input.frame(time+=10000);document.querySelector('canvas').focus();input.frame(time+=10000)");
  assert.deepEqual(await take(), []);
  await up('d', 'KeyD', 68); await down('d', 'KeyD', 68);
  await read('replaceSettings({...continuous});input.frame(time+=10000)');
  await down('d', 'KeyD', 68, {autoRepeat: true}); await read('input.frame(time+=16)'); assert.deepEqual(await take(), []);
  await up('d', 'KeyD', 68); await down('d', 'KeyD', 68);
  const continuousBlur = await (await fetch(`${devtools}/json/new?about:blank`, {method: 'PUT'})).json(); extraTargets.push(continuousBlur.id);
  await until(() => read('document.hidden && !document.hasFocus()'), 'second page did not hide and blur continuous input fixture');
  await read('input.frame(time+=10000)'); assert.deepEqual(await take(), []);
  await call('Page.bringToFront'); await until(() => read('document.hasFocus()'), 'continuous input fixture did not regain focus');
  await down('d', 'KeyD', 68, {autoRepeat: true}); await read('input.frame(time+=10000)'); assert.deepEqual(await take(), []);
  await up('d', 'KeyD', 68); await down('d', 'KeyD', 68); await read('input.frame(time+=16)');
  assert.deepEqual(await take(), [['drift', 16, 0]]); await up('d', 'KeyD', 68);
  console.log('ok - shortcuts, editing, reload, and actual window blur/hidden discard continuous keys without stale repeats or catchup');

  await read('replaceSettings(continuous);pad.axes=[0,0];pad.buttons.forEach(button=>button.pressed=false);pads=[pad];input.frame(time=0)');
  await read('pad.axes=[0.3,-0.34];input.frame(time=8)'); assert.deepEqual(await take(), []);
  await read('pad.axes=[0.5,-0.75];input.frame(time=24)');
  assert.deepEqual(await take(), [['drift', 8, 0], ['drift', 0, -12]]);
  await read('pad.axes=[-1,1];input.frame(time=40);input.frame(time);input.frame(time=10040)');
  assert.deepEqual(await take(), [['drift', -16, 0], ['drift', 0, 16], ['drift', -50, 0], ['drift', 0, 50]]);
  await read('pad.axes=[0,0];pad.buttons[0].pressed=true;input.frame(time+=16);input.frame(time+=16)');
  assert.deepEqual(await take(), [['confirm']]);
  await read('pads=[];input.frame(time=20000);pad.axes=[1,-1];pads=[pad];input.frame(time=30000);input.frame(time+=16)');
  assert.deepEqual(await take(), []);
  await read('pad.axes=[-1,1];input.frame(time+=16)');
  assert.deepEqual(await take(), [['drift', -16, 0], ['drift', 0, 16]]);
  await read('pad.axes=[0,0];pad.buttons[0].pressed=false;input.frame(time+=16);pad.axes=[1,-1];pad.buttons[0].pressed=true;input.frame(time+=16)');
  assert.deepEqual(await take(), [['confirm'], ['drift', 16, 0], ['drift', 0, -16]]);
  await read('replaceSettings({...continuous});input.frame(time+=10000);input.frame(time+=16)'); assert.deepEqual(await take(), []);
  await read('pad.axes=[0,0];pad.buttons[0].pressed=false;input.frame(time+=16);pad.axes=[-0.5,0.5];input.frame(time+=20)');
  assert.deepEqual(await take(), [['drift', -10, 0], ['drift', 0, 10]]);
  await read("document.querySelector('input').focus();input.frame(time+=10000);document.querySelector('canvas').focus();input.frame(time+=10000);input.frame(time+=16)");
  assert.deepEqual(await take(), []);
  await read('pad.axes=[0,0];input.frame(time+=16);pad.axes=[1,0];input.frame(time+=16)');
  assert.deepEqual(await take(), [['drift', 16, 0]]);
  await read('pad.axes=[0.5,-0.5];input.frame(time+=3)');
  assert.deepEqual(await take(), [['drift', 2, 0], ['drift', 0, -2]]);
  await read('pad.axes=[0.4,-0.4];input.frame(time+=1);input.frame(time)');
  assert.deepEqual(await take(), [['drift', 0, 0], ['drift', 0, 0]]);
  await read('pads=[];input.frame(time+=16)');
  console.log('ok - continuous joystick axes preserve magnitude and negative/diagonal directions; release/reconnect/reload/focus gate motion');

  await read("replaceSettings({...continuous,keys:{z:['drift',2147483647,-2147483648]},repeatKeys:[],continuousKeys:['z']});input.frame(time=0)");
  await down('z', 'KeyZ', 90); await read('input.frame(time=10000)'); await up('z', 'KeyZ', 90);
  assert.deepEqual(await take(), [['drift', 2147483647, -2147483648]]);
  await read('replaceSettings(continuous);input.frame(time=0)');
  await call('Input.dispatchMouseEvent', {type: 'mouseMoved', x: 170.25, y: 70.25});
  await call('Input.dispatchMouseEvent', {type: 'mouseMoved', x: 170.49, y: 70.49});
  await call('Input.dispatchMouseEvent', {type: 'mouseMoved', x: 170.75, y: 70.75});
  assert.deepEqual(await take(), [['move', 340, 140], ['move', 341, 141]]);
  await call('Input.dispatchMouseEvent', {type: 'mousePressed', x: 170.75, y: 70.75, button: 'left', buttons: 1, clickCount: 1});
  await call('Input.dispatchMouseEvent', {type: 'mouseReleased', x: 170.75, y: 70.75, button: 'left', buttons: 0, clickCount: 1});
  assert.deepEqual(await take(), [['move', 341, 141], ['confirm']]);
  await read('input.movePointer({clientX:-1,clientY:-1});input.movePointer({clientX:10000,clientY:10000})');
  assert.deepEqual(await take(), [['move', 0, 0], ['move', 959, 639]]);
  console.log('ok - continuous payloads stay I32; opt-in pointer pixels scale, floor, coalesce, clamp, and precede confirmation');

  await read(`replaceSettings(zoomSettings);input.frame(time=0);
    globalThis.wheel=(deltaY,deltaMode=0,extra={})=>{const event=new WheelEvent('wheel',{deltaY,deltaMode,bubbles:true,cancelable:true,...extra});
      document.querySelector('canvas').dispatchEvent(event);return event.defaultPrevented;}`);
  await call('Input.dispatchMouseEvent', {type:'mouseWheel',x:170,y:70,deltaX:0,deltaY:100});
  await until(() => read('input.zoom!==0'), 'real wheel event did not reach the zoom handler');
  assert.deepEqual(await take(), []);
  await read('input.frame(time+=16);input.frame(time+=16)'); assert.deepEqual(await take(), [['zoom',100]]);
  assert.equal(await read('wheel(3,1)'),true);
  await read('input.frame(time+=16)'); assert.deepEqual(await take(), [['zoom',48]]);
  await read('wheel(1,2);input.frame(time+=16)'); assert.deepEqual(await take(), [['zoom',320]]);
  assert.equal(await read('wheel(-75,0,{ctrlKey:true})'),true);
  await read('input.frame(time+=16)'); assert.deepEqual(await take(), [['zoom',-75]]);
  await read('wheel(-.6);input.frame(time+=16)'); assert.deepEqual(await take(), []);
  await read('wheel(-.6);input.frame(time+=16)'); assert.deepEqual(await take(), [['zoom',-1]]);
  await read('wheel(.2);wheel(2500);wheel(-1500);input.frame(time+=16);input.frame(time+=16)');
  assert.deepEqual(await take(), [['zoom',1000]]);
  await read('wheel(5000);input.frame(time+=16);input.frame(time+=16)'); assert.deepEqual(await take(), [['zoom',1000]]);
  await read('wheel(-5000);input.frame(time+=16);input.frame(time+=16)'); assert.deepEqual(await take(), [['zoom',-1000]]);
  await read('wheel(30);replaceSettings({...zoomSettings});input.frame(time+=16)'); assert.deepEqual(await take(), []);
  await read("document.querySelector('#integer').focus()"); assert.equal(await read('wheel(100)'),false);
  await read("document.querySelector('canvas').focus();replaceSettings(continuous);input.frame(time+=16)");
  assert.equal(await read('wheel(100)'),false); assert.deepEqual(await take(), []);
  console.log('ok - wheel zoom is opt-in, typed, normalized across units, coalesced, fractional and bounded without catch-up');

  await read('replaceSettings(zoomSettings);input.frame(time=0)');
  await touch('touchStart',[[1,120,100]]); assert.deepEqual(await take(), []);
  await touch('touchEnd'); assert.deepEqual(await take(), [['move',240,200],['confirm']]);
  await touch('touchStart',[[1,120,100]]);
  await touch('touchMove',[[1,140,100]]); await touch('touchMove',[[1,120,100]]);
  await touch('touchEnd'); assert.deepEqual(await take(), []);
  await touch('touchStart',[[1,120,100]]); await touch('touchCancel'); assert.deepEqual(await take(), []);
  await touch('touchStart',[[1,120,100]]);
  await read('replaceSettings({...zoomSettings});input.frame(time+=16)');
  await touch('touchEnd'); assert.deepEqual(await take(), []);
  await touch('touchStart',[[1,120,100]]); await touch('touchStart',[[1,120,100],[2,600,100]]);
  await touch('touchEnd'); assert.deepEqual(await take(), []);
  await touch('touchStart',[[1,600,100]]); await touch('touchStart',[[1,600,100],[2,120,100]]);
  await touch('touchEnd'); assert.deepEqual(await take(), []);
  console.log('ok - real single-finger taps confirm on release; drag, cancellation and settings replacement cannot build');

  await touch('touchStart',[[1,140,100]]); await touch('touchStart',[[1,140,100],[2,240,100]]);
  await touch('touchMove',[[1,90,100],[2,290,100]]); await read('input.frame(time+=16)');
  assert.deepEqual(await take(), [['zoom',-693]]);
  // CDP touchEnd releases every contact. Inject one observed pointer's release
  // to check the surviving finger before completing the native touch sequence.
  await read("document.querySelector('canvas').dispatchEvent(new PointerEvent('pointerup',{pointerType:'touch',pointerId:lastTouch,clientX:290,clientY:100}))");
  await touch('touchMove',[[1,90,100],[2,290,100]]); await touch('touchMove',[[1,110,100],[2,290,100]]);
  await touch('touchEnd'); assert.deepEqual(await take(), []);
  await read('replaceSettings({...zoomSettings});input.frame(time+=16)');
  await touch('touchStart',[[1,100,100],[2,300,100]]);
  await touch('touchStart',[[1,100,100],[2,300,100],[3,200,200]]);
  await touch('touchMove',[[1,110,100],[2,290,100],[3,200,210]]); await read('input.frame(time+=16)');
  assert.deepEqual(await take(), []);
  await read("document.querySelector('canvas').dispatchEvent(new PointerEvent('pointercancel',{pointerType:'touch',pointerId:lastTouch}))");
  await touch('touchMove',[[1,110,100],[2,290,100],[3,200,210]]); await read('input.frame(time+=16)');
  assert.deepEqual(await take(), []);
  await touch('touchMove',[[1,155,100],[2,245,100],[3,200,210]]); await read('input.frame(time+=16)');
  assert.deepEqual(await take(), [['zoom',693]]);
  await touch('touchEnd'); assert.deepEqual(await take(), []);
  await touch('touchStart',[[1,120,100]]); await touch('touchEnd');
  assert.deepEqual(await take(), [['move',240,200],['confirm']]);
  console.log('ok - real pinches preserve scale ratios and suppress builds; individual release/cancel signals rebase surviving contacts');

  await read('replaceSettings(dragSettings);input.frame(time=0)');
  await call('Input.dispatchMouseEvent',{type:'mouseMoved',x:120,y:100});await take();
  await call('Input.dispatchMouseEvent',{type:'mousePressed',x:120,y:100,button:'left',buttons:1});assert.deepEqual(await take(),[]);
  await call('Input.dispatchMouseEvent',{type:'mouseReleased',x:120,y:100,button:'left',buttons:0});
  assert.deepEqual(await take(),[['move',240,200],['confirm']]);
  await call('Input.dispatchMouseEvent',{type:'mousePressed',x:120,y:100,button:'left',buttons:1});
  await call('Input.dispatchMouseEvent',{type:'mouseMoved',x:124,y:104,button:'left',buttons:1});await read('input.frame(time+=16)');
  assert.deepEqual(await take(),[]);
  await call('Input.dispatchMouseEvent',{type:'mouseMoved',x:130,y:100,button:'left',buttons:1});
  await call('Input.dispatchMouseEvent',{type:'mouseMoved',x:145,y:110,button:'left',buttons:1});assert.deepEqual(await take(),[]);
  await read('input.frame(time+=16);input.frame(time+=16)');assert.deepEqual(await take(),[['drag',25,10]]);
  await read('input.moveContact({pointerId:lastPointer,clientX:145.6,clientY:110.6});input.frame(time+=16)');assert.deepEqual(await take(),[]);
  await read('input.moveContact({pointerId:lastPointer,clientX:146.2,clientY:111.2});input.frame(time+=16)');assert.deepEqual(await take(),[['drag',1,1]]);
  await call('Input.dispatchMouseEvent',{type:'mouseReleased',x:146,y:111,button:'left',buttons:0});await read('input.frame(time+=16)');
  assert.deepEqual(await take(),[]);assert.equal(await read('input.dragX===0&&input.dragY===0'),true);
  await call('Input.dispatchMouseEvent',{type:'mousePressed',x:120,y:100,button:'left',buttons:1,pointerType:'pen'});
  await call('Input.dispatchMouseEvent',{type:'mouseMoved',x:140,y:110,button:'left',buttons:1,pointerType:'pen'});
  await call('Input.dispatchMouseEvent',{type:'mouseReleased',x:140,y:110,button:'left',buttons:0,pointerType:'pen'});
  await read('input.frame(time+=16)');assert.deepEqual(await take(),[['drag',20,10]]);
  console.log('ok - opt-in mouse/pen confirm on release; drags cross eight CSS pixels and coalesce unscaled deltas with fractional precision');

  await touch('touchStart',[[1,120,100]]);await touch('touchMove',[[1,140,110]]);await touch('touchEnd');
  assert.deepEqual(await take(),[]);await read('input.frame(time+=16)');assert.deepEqual(await take(),[['drag',20,10]]);
  await touch('touchStart',[[1,120,100]]);await touch('touchMove',[[1,140,100]]);await touch('touchMove',[[1,120,100]]);await touch('touchEnd');
  await read('input.frame(time+=16)');assert.deepEqual(await take(),[]);
  await touch('touchStart',[[1,120,100]]);await touch('touchMove',[[1,140,100]]);await touch('touchCancel');
  await read('input.frame(time+=16)');assert.deepEqual(await take(),[]);
  assert.equal(await read("input.contacts.size===0&&!document.querySelector('canvas').hasPointerCapture(lastTouch)"),true);
  await touch('touchStart',[[1,120,100]]);await touch('touchMove',[[1,140,100]]);
  await call('Target.activateTarget',{targetId:blur.id});await until(()=>read('!document.hasFocus()'),'drag fixture did not blur');
  assert.equal(await read('input.contacts.size===0'),true);
  await call('Page.bringToFront');await until(()=>read('document.hasFocus()'),'drag fixture did not refocus');await touch('touchEnd');
  await read('input.frame(time+=16)');assert.deepEqual(await take(),[]);
  await touch('touchStart',[[1,120,100]]);await touch('touchMove',[[1,140,100]]);
  await read('replaceSettings({...dragSettings});input.frame(time+=16)');await touch('touchEnd');assert.deepEqual(await take(),[]);
  console.log('ok - touch drag releases preserve final movement; return-to-start, cancel, blur and settings reset never select or replay movement');

  await touch('touchStart',[[1,120,100]]);await touch('touchMove',[[1,140,100]]);
  await touch('touchStart',[[1,140,100],[2,240,100]]);await touch('touchMove',[[1,90,100],[2,290,100]]);
  await read('input.frame(time+=16)');assert.deepEqual(await take(),[['zoom',-693]]);
  await read("document.querySelector('canvas').dispatchEvent(new PointerEvent('pointerup',{pointerType:'touch',pointerId:lastTouch,clientX:290,clientY:100}))");
  await touch('touchMove',[[1,110,100],[2,290,100]]);await touch('touchEnd');await read('input.frame(time+=16)');assert.deepEqual(await take(),[]);
  await touch('touchStart',[[1,120,100]]);await touch('touchMove',[[1,140,100]]);await touch('touchStart',[[1,140,100],[2,600,100]]);
  await touch('touchEnd');await read('input.frame(time+=16)');assert.deepEqual(await take(),[]);
  await touch('touchStart',[[1,600,100]]);await touch('touchStart',[[1,600,100],[2,120,100]]);await touch('touchMove',[[1,600,100],[2,140,100]]);
  await touch('touchEnd');await read('input.frame(time+=16)');assert.deepEqual(await take(),[]);
  await touch('touchStart',[[1,120,100]]);await touch('touchEnd');assert.deepEqual(await take(),[['move',240,200],['confirm']]);
  console.log('ok - pinch and outside contacts discard queued drag and never hand a surviving finger back to pan or tap');

  await read("document.querySelector('#integer').focus()");
  for (const value of ['', ' ', '1.5', '1e2', '0x2a', '1_000', 'NaN', 'Infinity', '2147483648', '-2147483649']) {
    await read(`document.querySelector('#integer').value=${JSON.stringify(value)}`);
    await press('Enter', 'Enter', 13, {text: '\r'});
    assert.deepEqual(await take(), [], `invalid integer dispatched: ${value}`);
    assert.equal(await read("document.querySelector('#integer').getAttribute('aria-invalid')==='true' && document.activeElement.id==='integer' && document.querySelector('#integer-error').textContent.length>0"), true);
  }
  const accessibility = await call('Accessibility.getFullAXTree');
  const integerField = accessibility.nodes.find(node => node.role?.value === 'textbox' && node.name?.value === 'Next run seed');
  assert.equal(integerField?.properties.some(property => property.name === 'invalid' && property.value.value === 'true'), true);
  assert.match(integerField?.description?.value ?? '', /whole number/);
  await read("document.querySelector('#integer').value='';document.querySelector('#integer').dispatchEvent(new Event('input',{bubbles:true}))");
  await call('Input.insertText', {text: '12345'});
  assert.deepEqual(await take(), []);
  assert.equal(await read("document.querySelector('#integer-error').textContent==='' && !document.querySelector('#integer').hasAttribute('aria-invalid')"), true);
  await press('Enter', 'Enter', 13, {text: '\r'}); assert.deepEqual(await take(), [['restart-seed', 12345]]);
  for (const [text, value] of [['-2147483648', -2147483648], ['2147483647', 2147483647], ['0', 0], ['65536', 65536], ['+00042', 42], ['  42  ', 42]]) {
    await read(`document.querySelector('#integer').value=${JSON.stringify(text)}`);
    await press('Enter', 'Enter', 13, {text: '\r'}); assert.deepEqual(await take(), [['restart-seed', value]]);
  }
  await read("document.querySelector('#integer-submit').focus()");
  await press('Enter', 'Enter', 13, {text: '\r'}); await press(' ', 'Space', 32, {text: ' '});
  assert.deepEqual(await take(), [['restart-seed', 42], ['restart-seed', 42]]);
  await read("document.querySelector('#integer-submit').click()"); assert.deepEqual(await take(), [['restart-seed', 42]]);
  await read("document.querySelector('#left').value='7';document.querySelector('#top').value='1.5';document.querySelector('#pair-form').requestSubmit()");
  assert.deepEqual(await take(), []); assert.equal(await read('document.activeElement.id'), 'top');
  await read("document.querySelector('#left').value='-2147483648';document.querySelector('#top').value='2147483647';document.querySelector('#pair-form').requestSubmit()");
  assert.deepEqual(await take(), [['position', -2147483648, 2147483647]]);
  console.log('ok - integer forms reject malformed/I32-overflow text accessibly; editing is local; Enter, Space, click and ordered fields dispatch once');

  await read("document.querySelector('canvas').focus();replaceSettings({...continuous});pad.axes=[0,0];pad.buttons.forEach(button=>button.pressed=false);pads=[pad];input.frame(time=0)");
  await down('d', 'KeyD', 68); await read('pad.axes=[1,0];input.frame(time=16)');
  assert.deepEqual(await take(), [['drift', 16, 0], ['drift', 16, 0]]);
  await read("document.querySelector('#integer').focus();pad.buttons[0].pressed=true;input.frame(time=32)");
  await press('w', 'KeyW', 87, {text: 'w'}); await read('input.frame(time=48)'); assert.deepEqual(await take(), []);
  await read("document.querySelector('#integer').value='37';document.querySelector('#integer-submit').focus();input.frame(time=64)");
  await press('w', 'KeyW', 87); assert.deepEqual(await take(), []);
  await press('Enter', 'Enter', 13, {text: '\r'}); assert.deepEqual(await take(), [['restart-seed', 37]]);
  await read("document.querySelector('canvas').focus();input.frame(time=80)");
  await down('d', 'KeyD', 68, {autoRepeat: true}); await read('input.frame(time=96)'); assert.deepEqual(await take(), []);
  await up('d', 'KeyD', 68); await down('d', 'KeyD', 68); await read('input.frame(time=112)');
  assert.deepEqual(await take(), [['drift', 16, 0]]); await up('d', 'KeyD', 68);
  await read('pad.axes=[0,0];pad.buttons[0].pressed=false;input.frame(time=128);pad.axes=[1,0];input.frame(time=144)');
  assert.deepEqual(await take(), [['drift', 16, 0]]);
  await read("document.querySelector('#integer').focus();document.querySelector('canvas').focus();input.frame(time=160);input.frame(time=176)");
  assert.deepEqual(await take(), []);
  await read('pad.axes=[0,0];input.frame(time=192);pad.axes=[1,0];input.frame(time=208)');
  assert.deepEqual(await take(), [['drift', 16, 0]]);
  await read("document.querySelector('#integer').focus();pad.axes=[0,0];input.frame(time=224);pad.axes=[1,0];input.frame(time=240);document.querySelector('canvas').focus();input.frame(time=256);input.frame(time=272)");
  assert.deepEqual(await take(), []);
  await read('pad.axes=[0,0];input.frame(time=288);pad.axes=[1,0];input.frame(time=304)');
  assert.deepEqual(await take(), [['drift', 16, 0]]);
  console.log('ok - form fields and submit-button focus suspend gameplay, including edits between frames, and require fresh input afterward');

  await call('Page.navigate', {url: `${origin}/shell`});
  await until(() => read("document.readyState==='complete' && document.querySelector('[data-ui]') !== null"), 'Siegework shell did not load');
  for (const width of [360, 680, 900, 1280]) {
    await call('Emulation.setDeviceMetricsOverride', {width, height: 1000, deviceScaleFactor: 1, mobile: false});
    // Chromium exposes fractional CSS boxes but rounds innerWidth/innerHeight.
    const layout = await read("(()=>{const c=document.querySelector('canvas').getBoundingClientRect(),ui=document.querySelector('[data-ui]'),r=ui.getBoundingClientRect();return {overflow:document.documentElement.scrollWidth>innerWidth,full:Math.abs(c.width-innerWidth)<1&&Math.abs(c.height-innerHeight)<1,dimensions:[c.width,c.height,innerWidth,innerHeight],overlay:r.left>=0&&r.top>=0&&r.right<=innerWidth&&r.bottom<=innerHeight&&getComputedStyle(ui).pointerEvents==='none'}})()");
    assert.equal(layout.overflow, false, `horizontal overflow at ${width}px`);
    assert.equal(layout.full,true, `world canvas does not fill the viewport at ${width}px: ${layout.dimensions}`);
    assert.equal(layout.overlay,true, `HUD overlay intercepts the world or leaves the viewport at ${width}px`);
  }
  assert.equal(await read("document.querySelector('canvas').tabIndex===0 && !!document.querySelector('canvas').getAttribute('aria-label') && !!document.querySelector('[data-ui]').getAttribute('aria-label')"),true);
  const browser = await (await fetch(`${devtools}/json/version`)).json();
  console.log(`ok - Siegework shell fits 360/680/900/1280px with a full world canvas and accessible Scheme HUD region (${browser.Browser}); no physical controller tested`);
} finally {
  ws?.close();
  for (const targetId of [...extraTargets, target?.id].filter(Boolean)) await fetch(`${devtools}/json/close/${targetId}`);
  server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
}
