// Run against an isolated 3D test package/save: this pauses its test match.
// Actual held browser inputs must move projected landmarks along screen axes.
import assert from 'node:assert/strict';
import {colony, client} from '../applications/colony-state.mjs';
const [origin, devtools = 'http://127.0.0.1:9452'] = process.argv.slice(2);
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const target = await (await fetch(`${devtools}/json/new?about:blank`, {method:'PUT'})).json();
const ws = new WebSocket(target.webSocketDebuggerUrl), pending = new Map(); let sequence = 0;
await new Promise(resolve => ws.addEventListener('open', resolve, {once:true}));
ws.onmessage = event => { const data = JSON.parse(event.data); if (data.id) { pending.get(data.id)?.(data); pending.delete(data.id); } };
function call(method, params = {}) {
  return new Promise((resolve, reject) => { const id = ++sequence;
    const timer = setTimeout(() => reject(new Error(`CDP timeout: ${method}`)), 30000);
    pending.set(id, data => { clearTimeout(timer); data.error ? reject(new Error(data.error.message)) : resolve(data.result); });
    ws.send(JSON.stringify({id, method, params})); });
}
async function evaluate(expression) {
  const result = await call('Runtime.evaluate', {expression, awaitPromise:true, returnByValue:true});
  if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description ?? result.exceptionDetails.text);
  return result.result.value;
}
async function until(expression) {
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline) { if (await evaluate(expression)) return; await pause(50); }
  throw new Error(`Did not settle: ${expression}`);
}
const settled = () => until('!snailApp.localWork && !snailApp.dirty');
const command = async (binding, args = []) => { await evaluate(`snailApp.local(${JSON.stringify(binding)},${JSON.stringify(args)})`); await settled(); };
const landmark = async () => {
  const hub=colony(await evaluate('snailApp.runtime.snapshot(1)')).surveys.find(s=>s.radius===9);
  return evaluate(`(async()=>{await snailApp.updates;const m=snailApp.runtime.view().scene.uniforms,[w,h]=snailApp.viewport;
  return[(m[0]*${hub.x}-m[4]*${hub.y}+m[8]+m[12]+1)*w/2,(1-(m[1]*${hub.x}-m[5]*${hub.y}+m[9]+m[13]))*h/2]})()`); };
const difference = (before, after) => after.map((value, axis) => value - before[axis]);
function aligned(motion, screen, label) {
  const length = Math.hypot(...screen), along = -(motion[0] * screen[0] + motion[1] * screen[1]) / length;
  const across = Math.abs(motion[0] * screen[1] - motion[1] * screen[0]) / length;
  assert.ok(along > 10, `${label}: no sustained motion ${motion}`);
  assert.ok(across < 1.5, `${label}: off-axis motion ${motion}`);
}
async function key(type, value) {
  await call('Input.dispatchKeyEvent', {type, key:value, code:`Key${value.toUpperCase()}`,
    windowsVirtualKeyCode:value.toUpperCase().charCodeAt(0), ...(type === 'keyDown' ? {text:value} : {})});
}
async function holdKeys(keys, ms = 600) {
  const initial = await landmark();
  for (const value of keys) await key('keyDown', value);
  const before = await landmark();
  await pause(ms / 2); const middle = await landmark();
  await pause(ms / 2); const after = await landmark();
  for (const value of keys) await key('keyUp', value);
  await settled(); return {initial, before, middle, after, stopped:await landmark()};
}
async function center() {
  await command('home');
  for(let i=0;i<100&&client(await evaluate('snailApp.runtime.snapshot(2)')).homing;i++)await pause(50);
  assert.equal(client(await evaluate('snailApp.runtime.snapshot(2)')).homing,false);
  await command('dismiss');await evaluate('snailApp.canvas.focus();snailApp.input.reset()');
}
async function nearBound(screen) {
  await center(); await command('pan', screen.map(value => value * 10000));
  await command('pan', screen.map(value => -value));
}
try {
  await call('Network.enable'); await call('Network.setCacheDisabled', {cacheDisabled:true});
  await call('Page.navigate', {url:origin}); await call('Page.bringToFront'); await until('!!globalThis.snailApp');
  await command('suspend', [1]); const committed = await evaluate('snailApp.runtime.snapshot(1)');
  const directions = [['w',[0,-1]],['s',[0,1]],['a',[-1,0]],['d',[1,0]]];
  const evidence = [];
  for (const [value, screen] of directions) {
    await center(); const motion = await holdKeys([value]);
    aligned(difference(motion.before, motion.middle), screen, `${value} first half`);
    aligned(difference(motion.middle, motion.after), screen, `${value} second half`);
    evidence.push({key:value, pixels:difference(motion.before,motion.after)});
  }
  for (const [keys, screen] of [[['w','d'],[1,-1]],[['s','a'],[-1,1]]]) {
    await center(); const motion = await holdKeys(keys); aligned(difference(motion.before,motion.after),screen,keys.join('+'));
  }
  for (const [value, screen] of directions) {
    await nearBound(screen); const motion = await holdKeys([value]);
    aligned(difference(motion.before,motion.after), screen, `${value} at bound`);
    assert.ok(Math.hypot(...difference(motion.middle,motion.after)) < .1, `${value} slid along the bound`);
  }
  console.log('ok - held WASD stays screen-aligned, open diagonals combine, and cardinal travel stops at the first bound', evidence);
  await center(); await evaluate(`(()=>{globalThis.panField=document.createElement('input');panField.setAttribute('aria-label','Pan focus fixture');
    document.body.append(panField);panField.focus()})()`);
  const focused = await holdKeys(['w']); assert.ok(Math.hypot(...difference(focused.initial,focused.stopped)) < .1);
  assert.equal(await evaluate('panField.value'), 'w'); await evaluate('panField.remove()');
  assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'), committed);
  await center(); console.log('ok - native edit focus and match ownership are preserved');
} finally {
  await evaluate("dispatchEvent(new PageTransitionEvent('pagehide'))").catch(()=>{});
  ws.close(); await fetch(`${devtools}/json/close/${target.id}`);
}
