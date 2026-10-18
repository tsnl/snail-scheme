// Declarative browser controls. Pointer units and continuous payloads are
// declared by the app; reducers own camera movement and every other decision.

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
function mappedInputs(value = [], mappings) {
  if (!Array.isArray(value) || value.some(key => !mappings.has(key)))
    throw new Error('input lists must name mapped keys or button indices');
  return new Set(value);
}
function continuousCommand(value) {
  if (value.length !== 3) throw new Error('continuous input requires two I32 coefficients');
}
function controllerAxis(value) {
  const {axis, negative, positive, deadzone = 0.35, continuous = false} = value ?? {};
  if (!Number.isSafeInteger(axis) || axis < 0 || !Number.isFinite(deadzone) || deadzone <= 0 || deadzone >= 1 ||
      typeof continuous !== 'boolean')
    throw new Error('controller axis requires an index, a deadzone between zero and one, and an optional continuous flag');
  const result = {axis, negative: command(negative), positive: command(positive), deadzone, continuous};
  if (continuous) { continuousCommand(result.negative); continuousCommand(result.positive); }
  return result;
}
export function parseInputSettings(settings) {
  const {width, height, cellSize, pointer, inputRepeatMilliseconds: interval = 160} = settings;
  if ([width, height, cellSize, interval].some(x => !Number.isSafeInteger(x) || x <= 0) ||
      !pointer || [pointer.move, pointer.confirm].some(x => typeof x !== 'string' || !x))
    throw new Error('input requires positive dimensions, repeat interval, and pointer handlers');
  const coordinates = pointer.coordinates ?? 'cells';
  if (coordinates !== 'cells' && coordinates !== 'pixels') throw new Error('pointer coordinates must be cells or pixels');
  const zoomHandler = settings.zoomHandler;
  if (zoomHandler !== undefined && (typeof zoomHandler !== 'string' || !zoomHandler))
    throw new Error('zoom handler must name a client endpoint');
  const keys = commands(settings.keys), buttons = commands(settings.controller, true);
  const repeatKeys = mappedInputs(settings.repeatKeys, keys), continuousKeys = mappedInputs(settings.continuousKeys, keys);
  for (const key of continuousKeys) {
    continuousCommand(keys.get(key));
    if (repeatKeys.has(key)) throw new Error('continuous keys cannot also repeat discrete commands');
  }
  if (settings.controllerAxes !== undefined && !Array.isArray(settings.controllerAxes)) throw new Error('controller axes require an array');
  const axes = (settings.controllerAxes ?? []).map(controllerAxis);
  if (new Set(axes.map(value => value.axis)).size !== axes.length) throw new Error('controller axes must be unique');
  return {width, height, cellSize, pointer: {...pointer, coordinates}, zoomHandler, interval, keys, buttons, axes,
    repeatKeys, continuousKeys, repeatButtons: mappedInputs(settings.repeatButtons, buttons)};
}

// ---- Input lifetime ----

export class BrowserInput {
  // The caller retains one parsed settings object until a generation changes.
  // Replacing that object only resets physical input latches, never app state.
  constructor(canvas, readSettings, dispatch) {
    this.canvas = canvas; this.readSettings = readSettings; this.dispatch = dispatch;
    this.keys = new Map(); this.controls = new Map(); this.touches = new Map();
    this.touchAction = canvas.style.touchAction;
    this.syncSettings(); this.install();
  }
  syncSettings() {
    const settings = this.readSettings();
    if (settings !== this.settings) {
      this.settings = settings; this.reset();
      this.canvas.style.touchAction = settings.zoomHandler ? 'none' : this.touchAction;
    }
  }
  reset() {
    this.keys.clear(); this.controls.clear(); this.point = undefined;
    this.pad = undefined; this.baseline = true; this.time = undefined;
    const captured = [...this.touches.keys()];
    this.touches.clear(); this.tap = this.pinch = undefined; this.zoom = 0;
    for (const id of captured) if (this.canvas.hasPointerCapture(id)) this.canvas.releasePointerCapture(id);
  }
  send(value) {
    this.point = undefined;
    this.dispatch(value[0], value.slice(1));
  }
  install() {
    this.canvas.addEventListener('pointermove', event => event.pointerType === 'touch' ? this.moveTouch(event) : this.movePointer(event));
    this.canvas.addEventListener('pointerdown', event => this.pressPointer(event));
    this.canvas.addEventListener('pointerup', event => this.releaseTouch(event));
    this.canvas.addEventListener('pointercancel', event => this.releaseTouch(event, true));
    this.canvas.addEventListener('lostpointercapture', event => this.releaseTouch(event, true));
    this.canvas.addEventListener('wheel', event => this.wheel(event), {passive: false});
    document.addEventListener('pointerdown', event => {
      if (event.pointerType === 'touch' && this.tap && this.tap.id !== event.pointerId) this.tap = undefined;
    });
    document.addEventListener('keydown', event => this.pressKey(event));
    document.addEventListener('keyup', event => this.keys.delete(event.code || event.key));
    document.addEventListener('compositionstart', () => this.keys.clear());
    // Editing can begin and end between frames; discard held input immediately.
    document.addEventListener('focusin', event => editable(event.target) ? this.reset() : this.keys.clear());
    document.addEventListener('visibilitychange', () => this.reset());
    window.addEventListener('blur', () => this.reset());
    this.installControls();
  }
  installControls() {
    for (const element of document.querySelectorAll('[data-handler]')) {
      if (element instanceof HTMLFormElement) this.installForm(element);
      else element.addEventListener('click', () => this.send(command([element.dataset.handler, ...JSON.parse(element.dataset.args ?? '[]')])));
    }
  }
  frame(time) {
    this.syncSettings();
    if (document.hidden || !document.hasFocus() || editable(document.activeElement)) { this.reset(); return; }
    // A focus/settings reset starts a new clock. A delayed frame contributes
    // at most 50ms once; subsequent frames never repay the missing time.
    const elapsed = this.time === undefined ? 0 : Math.max(0, Math.min(50, time - this.time));
    this.time = time;
    this.flushZoom();
    this.pollKeys(time, elapsed); this.pollController(time, elapsed);
  }
  pollKeys(time, elapsed) {
    for (const held of this.keys.values()) {
      if (this.settings.continuousKeys.has(held.key)) {
        this.sendContinuous(this.settings.keys.get(held.key), elapsed); continue;
      }
      if (time < held.next) continue;
      this.send(this.settings.keys.get(held.key)); held.next = time + this.settings.interval;
    }
  }
  sendContinuous(command, elapsed) {
    if (elapsed <= 0) return;
    const values = command.slice(1).map(value => scaledI32(value, elapsed));
    this.send([command[0], ...values]);
  }

  // ---- Keyboard and pointer ----

  pressKey(event) {
    this.syncSettings();
    if (event.ctrlKey || event.metaKey || event.altKey || event.isComposing || editable(event.target)) { this.keys.clear(); return; }
    if (event.defaultPrevented || nativeActivation(event)) return;
    const {keys, repeatKeys, continuousKeys, interval} = this.settings;
    const key = keys.has(event.key) ? event.key : event.key.length === 1 ? event.key.toLowerCase() : event.key;
    if (!keys.has(key)) return;
    event.preventDefault();
    const code = event.code || event.key;
    if (event.repeat || this.keys.has(code)) return;
    this.keys.set(code, {key, next: repeatKeys.has(key) ? performance.now() + interval : Infinity});
    if (!continuousKeys.has(key)) this.send(keys.get(key));
  }
  movePointer(event, force = false) {
    this.syncSettings();
    const rect = this.canvas.getBoundingClientRect(), {width, height, cellSize, pointer} = this.settings;
    if (!rect.width || !rect.height) return;
    const unit = pointer.coordinates === 'pixels' ? 1 : cellSize;
    const x = coordinateAt(event.clientX - rect.left, rect.width, width / unit);
    const y = coordinateAt(event.clientY - rect.top, rect.height, height / unit);
    if (!force && this.point?.[0] === x && this.point?.[1] === y) return;
    this.send([pointer.move, x, y]); this.point = [x, y];
  }
  pressPointer(event) {
    this.syncSettings();
    if (event.button !== 0) return;
    event.preventDefault(); this.canvas.focus({preventScroll: true});
    if (event.pointerType === 'touch') { this.pressTouch(event); return; }
    this.movePointer(event, true); this.send([this.settings.pointer.confirm]);
  }

  // ---- A touch gesture can confirm only until its first drag or second finger ----

  pressTouch(event) {
    this.tap = event.isPrimary && !this.touches.size ? {id: event.pointerId, x: event.clientX, y: event.clientY} : undefined;
    this.touches.set(event.pointerId, {x: event.clientX, y: event.clientY});
    this.canvas.setPointerCapture(event.pointerId); this.pinch = touchDistance(this.touches);
  }
  moveTouch(event) {
    this.syncSettings();
    if (!this.touches.has(event.pointerId)) return;
    this.touches.set(event.pointerId, {x: event.clientX, y: event.clientY});
    if (this.tap && Math.hypot(event.clientX - this.tap.x, event.clientY - this.tap.y) > 8) this.tap = undefined;
    const distance = touchDistance(this.touches);
    if (this.pinch && distance) this.queueZoom(1000 * Math.log(this.pinch / distance));
    this.pinch = distance;
  }
  releaseTouch(event, cancelled = false) {
    this.syncSettings();
    if (!this.touches.has(event.pointerId)) return;
    const confirm = !cancelled && this.tap?.id === event.pointerId &&
      Math.hypot(event.clientX - this.tap.x, event.clientY - this.tap.y) <= 8;
    this.touches.delete(event.pointerId); this.tap = undefined; this.pinch = touchDistance(this.touches);
    if (this.canvas.hasPointerCapture(event.pointerId)) this.canvas.releasePointerCapture(event.pointerId);
    if (confirm) { this.movePointer(event, true); this.send([this.settings.pointer.confirm]); }
  }

  // ---- Zoom describes a scale change; the Scheme client owns camera policy ----

  wheel(event) {
    this.syncSettings();
    if (!this.settings.zoomHandler || event.defaultPrevented || document.hidden || !document.hasFocus() ||
        editable(document.activeElement) || !Number.isFinite(event.deltaY) || !event.deltaY) return;
    event.preventDefault();
    const unit = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? this.canvas.getBoundingClientRect().height : 1;
    this.queueZoom(event.deltaY * unit);
  }
  queueZoom(delta) {
    if (!this.settings.zoomHandler || !Number.isFinite(delta)) return;
    this.zoom = Math.max(-2147483647, Math.min(2147483647, this.zoom + delta));
  }
  flushZoom() {
    const whole = Math.trunc(this.zoom); this.zoom -= whole;
    const delta = Math.max(-1000, Math.min(1000, whole));
    // Keep fractional input; discard excess whole units instead of replaying a
    // stalled frame's wheel burst across later frames.
    if (delta) this.send([this.settings.zoomHandler, delta]);
  }

  // ---- Integer forms ----

  installForm(form) {
    const fields = [...form.querySelectorAll('input[data-i32]')], feedback = form.querySelector('[data-input-error]');
    if (fields.length < 1 || fields.length > 2 || !feedback)
      throw new Error('input form requires one or two I32 fields and a data-input-error element');
    const [binding] = command([form.dataset.handler]);
    form.addEventListener('submit', event => { event.preventDefault(); this.submitForm(binding, fields, feedback); });
    form.addEventListener('input', () => clearFormError(fields, feedback));
  }
  submitForm(binding, fields, feedback) {
    this.syncSettings(); this.reset(); clearFormError(fields, feedback);
    const result = integerFields(fields);
    if (result.error) {
      feedback.textContent = result.error; result.field.setAttribute('aria-invalid', 'true');
      result.field.focus(); return;
    }
    this.send([binding, ...result.values]);
  }

  // ---- Controller polling ----

  pollController(time, elapsed) {
    const pad = Array.from(navigator.getGamepads?.() ?? []).find(pad => pad?.connected);
    const identity = pad && `${pad.index}:${pad.id}`;
    if (identity !== this.pad) { this.controls.clear(); this.pad = identity; this.baseline = true; }
    if (!pad) return;
    for (const [index, command] of this.settings.buttons)
      this.pollControl(`button:${index}`, command, pad.buttons[index]?.pressed, this.settings.repeatButtons.has(index), time);
    for (const axis of this.settings.axes) this.pollAxis(axis, pad.axes[axis.axis], time, elapsed);
    this.baseline = false;
  }
  pollAxis({axis, negative, positive, deadzone, continuous}, value, time, elapsed) {
    if (continuous) {
      const magnitude = Math.min(1, Math.abs(value));
      this.pollContinuous(`axis:${axis}:-`, negative, value < -deadzone ? magnitude : 0, elapsed);
      this.pollContinuous(`axis:${axis}:+`, positive, value > deadzone ? magnitude : 0, elapsed);
    } else {
      this.pollControl(`axis:${axis}:-`, negative, value < -deadzone, true, time);
      this.pollControl(`axis:${axis}:+`, positive, value > deadzone, true, time);
    }
  }
  pollContinuous(key, command, magnitude, elapsed) {
    if (!magnitude) { this.controls.delete(key); return; }
    // A stick held across a device/focus/settings change must release before
    // moving again, just like a held button. Only blocked directions need state.
    if (this.baseline) this.controls.set(key, Infinity);
    else if (this.controls.get(key) !== Infinity) this.sendContinuous(command, elapsed * magnitude);
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
  return element?.isContentEditable || Boolean(element?.closest('input, textarea, select, [role="textbox"], form[data-handler], form[data-ui-form]'));
}
function nativeActivation(event) {
  return (event.key === 'Enter' || event.key === ' ') && Boolean(event.target?.closest('button, a[href], summary, [role="button"]'));
}
function coordinateAt(position, length, units) {
  return Math.max(0, Math.min(Math.ceil(units) - 1, Math.floor(position / length * units)));
}
function touchDistance(touches) {
  if (touches.size !== 2) return undefined;
  const [left, right] = touches.values(), distance = Math.hypot(left.x - right.x, left.y - right.y);
  return Number.isFinite(distance) && distance > 0 ? distance : undefined;
}
function scaledI32(value, scale) {
  // Equal magnitudes round symmetrically; saturation preserves the I32 ABI.
  const rounded = Math.sign(value) * Math.round(Math.abs(value) * scale);
  return Math.max(-2147483648, Math.min(2147483647, rounded)) || 0;
}
function integerFields(fields) {
  const values = [];
  for (const field of fields) {
    const text = field.value.trim(), value = Number(text);
    if (!/^[+-]?\d+$/.test(text)) return {field, error: 'Enter a whole number.'};
    if (!Number.isInteger(value) || value < -2147483648 || value > 2147483647)
      return {field, error: 'Enter a whole number from -2147483648 to 2147483647.'};
    values.push(value);
  }
  return {values};
}
function clearFormError(fields, feedback) {
  feedback.textContent = '';
  for (const field of fields) field.removeAttribute('aria-invalid');
}
