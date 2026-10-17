// Declarative browser controls. Coordinates are viewport cells; reducers own
// camera offsets, movement, purchases, and every other application decision.

// ---- Input settings ----

function command(value) {
  if (!Array.isArray(value) || typeof value[0] !== 'string' || !value[0] || value.length > 3 ||
      value.slice(1).some(x => !Number.isInteger(x) || x < -2147483648 || x > 2147483647))
    throw new Error('input command requires a binding and up to two I32 values');
  return [...value];
}
function commands(value = {}, indexed = false) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('input mappings require an object');
  return new Map(Object.entries(value).map(([key, value]) => {
    if (!key || (indexed && (!/^(0|[1-9]\d*)$/.test(key) || !Number.isSafeInteger(Number(key)))))
      throw new Error('controller mappings require nonnegative button indices');
    return [indexed ? Number(key) : key, command(value)];
  }));
}
function repeats(value = [], mappings) {
  if (!Array.isArray(value) || value.some(key => !mappings.has(key)))
    throw new Error('repeated inputs must name mapped keys or button indices');
  return new Set(value);
}
function controllerAxis(value) {
  const {axis, negative, positive, deadzone = 0.35} = value ?? {};
  if (!Number.isSafeInteger(axis) || axis < 0 || !Number.isFinite(deadzone) || deadzone <= 0 || deadzone >= 1)
    throw new Error('controller axis requires a nonnegative index and a deadzone between zero and one');
  return {axis, negative: command(negative), positive: command(positive), deadzone};
}
export function parseInputSettings(settings) {
  const {width, height, cellSize, pointer, inputRepeatMilliseconds: interval = 160} = settings;
  if ([width, height, cellSize, interval].some(x => !Number.isSafeInteger(x) || x <= 0) ||
      !pointer || [pointer.move, pointer.confirm].some(x => typeof x !== 'string' || !x))
    throw new Error('input requires positive dimensions, repeat interval, and pointer handlers');
  const keys = commands(settings.keys), buttons = commands(settings.controller, true);
  if (settings.controllerAxes !== undefined && !Array.isArray(settings.controllerAxes)) throw new Error('controller axes require an array');
  const axes = (settings.controllerAxes ?? []).map(controllerAxis);
  if (new Set(axes.map(value => value.axis)).size !== axes.length) throw new Error('controller axes must be unique');
  return {width, height, cellSize, pointer: {...pointer}, interval, keys, buttons, axes,
    repeatKeys: repeats(settings.repeatKeys, keys), repeatButtons: repeats(settings.repeatButtons, buttons)};
}

// ---- Input lifetime ----

export class BrowserInput {
  // The caller retains one parsed settings object until a generation changes.
  // Replacing that object only resets physical input latches, never app state.
  constructor(canvas, readSettings, dispatch) {
    this.canvas = canvas; this.readSettings = readSettings; this.dispatch = dispatch;
    this.keys = new Map(); this.controls = new Map();
    this.syncSettings(); this.install();
  }
  syncSettings() {
    const settings = this.readSettings();
    if (settings !== this.settings) { this.settings = settings; this.reset(); }
  }
  reset() {
    this.keys.clear(); this.controls.clear(); this.point = undefined;
    this.pad = undefined; this.baseline = true;
  }
  send(value) {
    this.point = undefined;
    this.dispatch(value[0], value.slice(1));
  }
  install() {
    this.canvas.addEventListener('pointermove', event => this.movePointer(event));
    this.canvas.addEventListener('pointerdown', event => this.pressPointer(event));
    document.addEventListener('keydown', event => this.pressKey(event));
    document.addEventListener('keyup', event => this.keys.delete(event.code || event.key));
    document.addEventListener('compositionstart', () => this.keys.clear());
    document.addEventListener('focusin', () => this.keys.clear());
    document.addEventListener('visibilitychange', () => this.reset());
    window.addEventListener('blur', () => this.reset());
    for (const button of document.querySelectorAll('[data-handler]'))
      button.addEventListener('click', () => this.send(command([button.dataset.handler, ...JSON.parse(button.dataset.args ?? '[]')])));
  }
  frame(time) {
    this.syncSettings();
    if (document.hidden || !document.hasFocus() || editable(document.activeElement)) { this.reset(); return; }
    for (const held of this.keys.values()) {
      if (time < held.next) continue;
      this.send(this.settings.keys.get(held.key)); held.next = time + this.settings.interval;
    }
    this.pollController(time);
  }

  // ---- Keyboard and pointer ----

  pressKey(event) {
    this.syncSettings();
    if (event.ctrlKey || event.metaKey || event.altKey || event.isComposing || editable(event.target)) { this.keys.clear(); return; }
    if (event.defaultPrevented || nativeActivation(event)) return;
    const {keys, repeatKeys, interval} = this.settings;
    const key = keys.has(event.key) ? event.key : event.key.length === 1 ? event.key.toLowerCase() : event.key;
    if (!keys.has(key)) return;
    event.preventDefault();
    const code = event.code || event.key;
    if (event.repeat || this.keys.has(code)) return;
    this.keys.set(code, {key, next: repeatKeys.has(key) ? performance.now() + interval : Infinity});
    this.send(keys.get(key));
  }
  movePointer(event, force = false) {
    this.syncSettings();
    const rect = this.canvas.getBoundingClientRect(), {width, height, cellSize, pointer} = this.settings;
    if (!rect.width || !rect.height) return;
    const x = cellAt(event.clientX - rect.left, rect.width, width / cellSize);
    const y = cellAt(event.clientY - rect.top, rect.height, height / cellSize);
    if (!force && this.point?.[0] === x && this.point?.[1] === y) return;
    this.send([pointer.move, x, y]); this.point = [x, y];
  }
  pressPointer(event) {
    if (event.button !== 0) return;
    event.preventDefault(); this.canvas.focus({preventScroll: true});
    this.movePointer(event, true); this.send([this.settings.pointer.confirm]);
  }

  // ---- Controller polling ----

  pollController(time) {
    const pad = Array.from(navigator.getGamepads?.() ?? []).find(pad => pad?.connected);
    const identity = pad && `${pad.index}:${pad.id}`;
    if (identity !== this.pad) { this.controls.clear(); this.pad = identity; this.baseline = true; }
    if (!pad) return;
    for (const [index, command] of this.settings.buttons)
      this.pollControl(`button:${index}`, command, pad.buttons[index]?.pressed, this.settings.repeatButtons.has(index), time);
    for (const {axis, negative, positive, deadzone} of this.settings.axes) {
      this.pollControl(`axis:${axis}:-`, negative, pad.axes[axis] < -deadzone, true, time);
      this.pollControl(`axis:${axis}:+`, positive, pad.axes[axis] > deadzone, true, time);
    }
    this.baseline = false;
  }
  pollControl(key, command, active, repeating, time) {
    if (!active) { this.controls.delete(key); return; }
    const next = this.controls.get(key);
    // Infinity means an ordinary held press, or a control held across a focus,
    // device, or settings change. It must release before becoming active again.
    if (next === undefined && this.baseline) this.controls.set(key, Infinity);
    else if (next === undefined || time >= next) {
      this.send(command); this.controls.set(key, repeating ? time + this.settings.interval : Infinity);
    }
  }
}
function editable(element) {
  return element?.isContentEditable || Boolean(element?.closest('input, textarea, select, [role="textbox"]'));
}
function nativeActivation(event) {
  return (event.key === 'Enter' || event.key === ' ') && Boolean(event.target?.closest('button, a[href], summary, [role="button"]'));
}
function cellAt(position, length, cells) {
  return Math.max(0, Math.min(Math.ceil(cells) - 1, Math.floor(position / length * cells)));
}
