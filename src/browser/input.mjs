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
  const {width, height, cellSize, pointer, renderScale = 1, inputRepeatMilliseconds: interval = 160} = settings;
  if ([width, height, cellSize, interval].some(x => !Number.isSafeInteger(x) || x <= 0) ||
      !pointer || [pointer.move, pointer.confirm].some(x => typeof x !== 'string' || !x))
    throw new Error('input requires positive dimensions, repeat interval, and pointer handlers');
  if (!Number.isFinite(renderScale) || renderScale <= 0 || renderScale > 1)
    throw new Error('render scale must be a finite number greater than zero and at most one');
  const coordinates = pointer.coordinates ?? 'cells';
  if (coordinates !== 'cells' && coordinates !== 'pixels') throw new Error('pointer coordinates must be cells or pixels');
  const {zoomHandler, dragHandler} = settings;
  if (zoomHandler !== undefined && (typeof zoomHandler !== 'string' || !zoomHandler))
    throw new Error('zoom handler must name a client endpoint');
  if (dragHandler !== undefined && (typeof dragHandler !== 'string' || !dragHandler))
    throw new Error('drag handler must name a client endpoint');
  const keys = commands(settings.keys), buttons = commands(settings.controller, true);
  const repeatKeys = mappedInputs(settings.repeatKeys, keys), continuousKeys = mappedInputs(settings.continuousKeys, keys);
  for (const key of continuousKeys) {
    continuousCommand(keys.get(key));
    if (repeatKeys.has(key)) throw new Error('continuous keys cannot also repeat discrete commands');
  }
  if (settings.controllerAxes !== undefined && !Array.isArray(settings.controllerAxes)) throw new Error('controller axes require an array');
  const axes = (settings.controllerAxes ?? []).map(controllerAxis);
  if (new Set(axes.map(value => value.axis)).size !== axes.length) throw new Error('controller axes must be unique');
  return {width, height, cellSize, renderScale, pointer: {...pointer, coordinates}, zoomHandler, dragHandler, interval, keys, buttons, axes,
    repeatKeys, continuousKeys, repeatButtons: mappedInputs(settings.repeatButtons, buttons)};
}

// ---- Input lifetime ----

export class BrowserInput {
  // The caller retains one parsed settings object until a generation changes.
  // Replacing that object only resets physical input latches, never app state.
  constructor(canvas, readSettings, dispatch) {
    this.canvas = canvas; this.readSettings = readSettings; this.dispatch = dispatch;
    this.keys = new Map(); this.controls = new Map(); this.contacts = new Map();
    this.touchAction = canvas.style.touchAction;
    this.syncSettings(); this.install();
  }
  syncSettings() {
    const settings = this.readSettings();
    if (settings !== this.settings) {
      this.settings = settings; this.reset();
      this.canvas.style.touchAction = settings.zoomHandler || settings.dragHandler ? 'none' : this.touchAction;
    }
  }
  reset() {
    this.keys.clear(); this.controls.clear(); this.point = undefined;
    this.pad = undefined; this.baseline = true; this.time = undefined;
    const captured = [...this.contacts.keys()];
    this.contacts.clear(); this.gesture = this.pinch = undefined; this.zoom = this.dragX = this.dragY = 0;
    for (const id of captured) if (this.canvas.hasPointerCapture(id)) this.canvas.releasePointerCapture(id);
  }
  send(value) {
    this.point = undefined;
    this.dispatch(value[0], value.slice(1));
  }
  install() {
    this.canvas.addEventListener('pointermove', event => {
      if (this.contacts.has(event.pointerId)) this.moveContact(event);
      else if (event.pointerType !== 'touch') this.movePointer(event);
    });
    this.canvas.addEventListener('pointerdown', event => this.pressPointer(event));
    this.canvas.addEventListener('pointerup', event => this.releaseContact(event));
    this.canvas.addEventListener('pointercancel', event => this.releaseContact(event, true));
    this.canvas.addEventListener('lostpointercapture', event => this.releaseContact(event, true));
    this.canvas.addEventListener('wheel', event => this.wheel(event), {passive: false});
    document.addEventListener('pointerdown', event => {
      if (event.pointerType === 'touch' && this.gesture && this.gesture.id !== event.pointerId) this.suppressDrag();
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
    this.flushDrag(); this.flushZoom();
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
    if (event.pointerType === 'touch' || this.settings.dragHandler) { this.pressContact(event); return; }
    this.movePointer(event, true); this.send([this.settings.pointer.confirm]);
  }

  // ---- One contact can tap or drag; multiple contacts can only pinch ----

  suppressDrag() {
    this.gesture = undefined; this.dragX = this.dragY = 0;
  }
  pressContact(event) {
    if (event.isPrimary && !this.contacts.size)
      this.gesture = {id: event.pointerId, x: event.clientX, y: event.clientY, dragging: false};
    else this.suppressDrag();
    this.contacts.set(event.pointerId, {x: event.clientX, y: event.clientY, type: event.pointerType});
    this.canvas.setPointerCapture(event.pointerId); this.pinch = touchDistance(this.contacts);
  }
  moveContact(event) {
    this.syncSettings();
    const previous = this.contacts.get(event.pointerId); if (!previous) return;
    this.contacts.set(event.pointerId, {...previous, x: event.clientX, y: event.clientY});
    if (this.gesture?.id === event.pointerId) this.moveGesture(event, previous);
    const distance = touchDistance(this.contacts);
    if (this.pinch && distance) this.queueZoom(1000 * Math.log(this.pinch / distance));
    this.pinch = distance;
  }
  moveGesture(event, previous) {
    const gesture = this.gesture;
    if (!gesture.dragging && Math.hypot(event.clientX - gesture.x, event.clientY - gesture.y) <= 8) return;
    // Crossing the threshold includes the press-to-current displacement once.
    const from = gesture.dragging ? previous : gesture;
    this.queueDrag(event.clientX - from.x, event.clientY - from.y); gesture.dragging = true;
  }
  releaseContact(event, cancelled = false) {
    this.syncSettings();
    if (!this.contacts.has(event.pointerId)) return;
    if (cancelled) { this.suppressDrag(); this.zoom = 0; } else this.moveContact(event);
    const confirm = !cancelled && this.gesture?.id === event.pointerId && !this.gesture.dragging;
    this.contacts.delete(event.pointerId); this.gesture = undefined; this.pinch = touchDistance(this.contacts);
    // Delete before releasing capture: its expected lost-capture event must
    // not discard a completed drag still waiting for the next display frame.
    if (this.canvas.hasPointerCapture(event.pointerId)) this.canvas.releasePointerCapture(event.pointerId);
    if (confirm) { this.movePointer(event, true); this.send([this.settings.pointer.confirm]); }
  }
  queueDrag(dx, dy) {
    if (!this.settings.dragHandler || !Number.isFinite(dx) || !Number.isFinite(dy)) return;
    this.dragX = Math.max(-2147483648, Math.min(2147483647, this.dragX + dx));
    this.dragY = Math.max(-2147483648, Math.min(2147483647, this.dragY + dy));
  }
  flushDrag() {
    const dx = Math.trunc(this.dragX), dy = Math.trunc(this.dragY);
    this.dragX -= dx; this.dragY -= dy;
    if (!this.gesture?.dragging) this.dragX = this.dragY = 0;
    if (dx || dy) this.send([this.settings.dragHandler, dx, dy]);
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
  const [left, right] = touches.values();
  if (left.type !== 'touch' || right.type !== 'touch') return undefined;
  const distance = Math.hypot(left.x - right.x, left.y - right.y);
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
