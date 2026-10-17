// Browser input contracts without a running Scheme authority or GPU adapter.
// Start Chromium with a DevTools port, then pass its URL as the first argument.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createServer} from 'node:http';
import {parseInputSettings} from '../../src/browser/input.mjs';

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
const shell = readFileSync(new URL('apps/siegework/index.html', root), 'utf8').replace(/<script[^>]*src="\/lib\/browser\/client.mjs"[^>]*><\/script>/, '');
const page = `<!doctype html><html><body style="margin:0;min-height:3000px">
<canvas width="960" height="640" tabindex="0" style="display:block;width:480px;height:320px"></canvas>
<button data-handler="choose" data-args="[3]"><span>Observation tower</span></button>
<input id="text"><textarea></textarea><select><option>One</option><option>Two</option></select>
<div contenteditable="true" id="editor"></div><details><summary>Help</summary>Field guide</details>
<script type="module">
import {BrowserInput,parseInputSettings} from '/input.mjs';
globalThis.settings=${JSON.stringify(settings)};
globalThis.continuous=${JSON.stringify(continuous)};
globalThis.configuration=parseInputSettings(settings);
globalThis.dispatches=[];globalThis.keys=[];globalThis.pads=[];
Object.defineProperty(navigator,'getGamepads',{value:()=>pads});
globalThis.input=new BrowserInput(document.querySelector('canvas'),()=>configuration,(binding,args)=>dispatches.push([binding,...args]));
document.addEventListener('keydown',event=>keys.push({key:event.key,prevented:event.defaultPrevented}));
globalThis.replaceSettings=value=>configuration=parseInputSettings(value);
document.querySelector('canvas').focus();globalThis.ready=true;
</script></body></html>`;
const server = createServer((request, response) => {
  const paths = {'/input.mjs': ['src/browser/input.mjs', 'text/javascript'], '/style.css': ['apps/siegework/style.css', 'text/css']};
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

try {
  assert.equal(parseInputSettings(settings).axes.length, 2);
  assert.equal(parseInputSettings(settings).continuousKeys.size, 0);
  assert.equal(parseInputSettings(settings).pointer.coordinates, 'cells');
  assert.equal(parseInputSettings(continuous).continuousKeys.size, 4);
  assert.equal(parseInputSettings(continuous).axes.every(axis => axis.continuous), true);
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
    {...continuous, pointer: {...continuous.pointer, coordinates: 'tiles'}}
  ]) assert.throws(() => parseInputSettings(broken));
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

  await call('Page.navigate', {url: `${origin}/shell`});
  await until(() => read("document.querySelector('.commands') !== null"), 'Siegework shell did not load');
  for (const width of [360, 680, 900, 1280]) {
    await call('Emulation.setDeviceMetricsOverride', {width, height: 1000, deviceScaleFactor: 1, mobile: false});
    const layout = await read("(()=>{const c=document.querySelector('canvas').getBoundingClientRect();return {overflow:document.documentElement.scrollWidth>innerWidth,ratio:c.width/c.height,targets:[...document.querySelectorAll('button')].every(b=>{const r=b.getBoundingClientRect();return r.width>=40&&r.height>=44})}})()");
    assert.equal(layout.overflow, false, `horizontal overflow at ${width}px`);
    assert.ok(Math.abs(layout.ratio - 1.5) < 0.01, `distorted map at ${width}px`);
    assert.equal(layout.targets, true, `small control target at ${width}px`);
  }
  const browser = await (await fetch(`${devtools}/json/version`)).json();
  console.log(`ok - Siegework shell fits 360/680/900/1280px with readable control targets (${browser.Browser}); no physical controller tested`);
} finally {
  ws?.close();
  for (const targetId of [...extraTargets, target?.id].filter(Boolean)) await fetch(`${devtools}/json/close/${targetId}`);
  server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
}
