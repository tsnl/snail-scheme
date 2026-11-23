// Spans for Chrome's trace format, which Perfetto (ui.perfetto.dev) and
// chrome://tracing open: how a program's time is measured. A span is a
// name on a track, from a start to an end in `performance.now()`'s
// milliseconds. The host's spans stay in the checked-in code, where a
// trace of any run can show them: the scheduler's turns (tasks.mjs), and
// the GPU's submits, reads and passes (gpu.mjs). Benchmark from a trace,
// not from a timer added for the occasion, so that a later change is
// measured the same way (doc/book/snail-scheme/toolchain.md, "Traces").
//
// Tracing is off unless a run asks for it, and a span costs one test of
// `tracing` then. A page asks with `trace` in its URL's query
// (`page.html?trace`); its spans become `performance.measure`s, which
// Chromium's own trace records beside the page's tasks and the GPU
// process's work (tests/browser/chromium.mjs's `startTrace`). Node traces
// no measures, so a program on Node asks with SNAIL_TRACE=FILE
// (native/run-snail.mjs), and the host writes the file itself.

// The tracks a span is drawn on. `main` is the thread the program runs
// on, whose spans nest; `gpu` is the device's queue, whose passes run one
// after another; a `wait` is a host operation a task waits on, and waits
// overlap.
const TRACKS = {main: 1, gpu: 2, wait: 3};

export let tracing = typeof location === 'object' && new URLSearchParams(location.search).has('trace');
let events = null;

// One span. On a page the measure is cleared once made, so a long run's
// timeline does not grow; the trace has it already.
export function span(track, name, start, end = performance.now()) {
  if (!tracing) return;
  if (!events) {
    performance.measure(`${track}: ${name}`, {start, end});
    performance.clearMeasures(`${track}: ${name}`);
  } else {
    events.push(...traceEvents(track, name, start, end));
  }
}

// `f`'s call as a span on `main`, and its answer.
export function traced(name, f) {
  if (!tracing) return f();
  const start = performance.now();
  try { return f(); } finally { span('main', name, start); }
}

// ---- Trace files ----

// From here on, spans are kept for `traceFile`. Each track is a thread of
// the process, named for it.
export function startTrace() {
  tracing = true;
  events = Object.entries(TRACKS).map(([name, tid]) =>
    ({ph: 'M', name: 'thread_name', pid: 1, tid, args: {name}}));
}

// Work whose spans are yet to come, as the device's times are read after
// its passes: `traceFile` waits for it. A failure only loses its spans.
const later = new Set();
export function spansLater(promise) {
  const done = () => later.delete(promise);
  later.add(promise);
  promise.then(done, done);
}

// The trace file's text, once every span has come: Chrome's JSON trace
// format, times in microseconds.
export async function traceFile() {
  await Promise.allSettled([...later]);
  return JSON.stringify({traceEvents: events, displayTimeUnit: 'ms'});
}

// A span on `main` or `gpu` is a complete event, `X`, which nests. Waits
// overlap, so each is an async pair, `b` and `e`, whose id keeps it apart.
let waits = 0;
function traceEvents(track, name, start, end) {
  const ts = (performance.timeOrigin + start) * 1000, event = {name, cat: track, pid: 1, tid: TRACKS[track], ts};
  if (track !== 'wait') return [{...event, ph: 'X', dur: (end - start) * 1000}];
  const id = ++waits;
  return [{...event, ph: 'b', id}, {...event, ph: 'e', id, ts: (performance.timeOrigin + end) * 1000}];
}
