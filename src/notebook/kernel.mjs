// The driver of a Scheme kernel: a compiled program whose `define-kernel`
// (lib/lofi/kernel.sld) keeps an environment to evaluate text in. The REPL
// in scripts/repl.mjs and the notebook in this directory both use it, in
// Node and in the browser alike.

// ---- WASI ----

// The kernel's Rust runtime writes standard output and error through
// fd_write; the driver collects both for the evaluation in progress. A Lofi
// panic reports its message and then calls proc_exit, which throws here so
// the evaluation stops while the instance lives on. A kernel reads no files,
// clock or arguments, so any other WASI import it has fails with ENOSYS.
const ENOSYS = 52, EBADF = 8;

class KernelExit extends Error {
  constructor(code) {
    super(`the kernel exited with status ${code}`);
  }
}

function wasiImports(module, memory, streams) {
  const view = () => new DataView(memory().buffer);
  const decoders = {1: new TextDecoder(), 2: new TextDecoder()};
  const zeros = (a, b) => { view().setUint32(a, 0, true); view().setUint32(b, 0, true); return 0; };
  const implemented = {
    fd_write(fd, iovs, count, written) {
      let total = 0;
      for (let i = 0; i < count; i++) {
        const pointer = view().getUint32(iovs + 8 * i, true), length = view().getUint32(iovs + 8 * i + 4, true);
        const bytes = new Uint8Array(memory().buffer, pointer, length);
        if (fd in decoders) streams[fd] += decoders[fd].decode(bytes, {stream: true});
        total += length;
      }
      view().setUint32(written, total, true);
      return 0;
    },
    fd_read(fd, iovs, count, read) { view().setUint32(read, 0, true); return 0; },
    proc_exit(code) { throw new KernelExit(code); },
    environ_sizes_get: zeros,
    args_sizes_get: zeros,
    environ_get: () => 0,
    args_get: () => 0,
    fd_close: () => 0,
    fd_prestat_get: () => EBADF,
  };
  const imports = {};
  for (const {module: name, name: field} of WebAssembly.Module.imports(module)) {
    if (name === 'wasi_snapshot_preview1') imports[field] = implemented[field] ?? (() => ENOSYS);
  }
  return imports;
}

// ---- Text across the boundary ----

// Text crosses one Unicode scalar at a time, as the screen effect's does.
function send(exports, text) {
  const codes = Array.from(text, character => character.codePointAt(0));
  exports.kernel_input_begin(codes.length);
  codes.forEach((code, index) => exports.kernel_input_character(index, code));
}

function result(exports) {
  const length = exports.kernel_result_length();
  let text = '';
  for (let index = 0; index < length; index++) text += String.fromCodePoint(exports.kernel_result_character(index));
  return text;
}

// A panic's message as the runtime printed it, without its prefix; or else
// what the engine threw, such as a stack overflow.
function failure(stderr, error) {
  const message = stderr.trim().replace(/^lofi: /, '');
  return message || error.message;
}

// ---- Kernel ----

// Instantiates a kernel from its bytes or its compiled module. `evaluate`
// runs text in the kernel's environment and returns what it printed, the
// written value (null when unspecified), and the error that stopped it, if
// one did. Each evaluation ends by releasing the runtime's resources, which
// flushes standard output, so no file stays open from one to the next.
export async function createKernel(source) {
  const module = source instanceof WebAssembly.Module ? source : await WebAssembly.compile(source);
  const streams = {1: '', 2: ''};
  let exports;
  const instance = await WebAssembly.instantiate(module, {
    wasi_snapshot_preview1: wasiImports(module, () => exports.memory, streams),
  });
  exports = instance.exports;
  exports._initialize();
  exports.main();
  const take = fd => { const text = streams[fd]; streams[fd] = ''; return text; };
  return {
    module,
    evaluate(text) {
      take(1); take(2);
      send(exports, text);
      let shown = 0, error = null;
      try {
        shown = exports.kernel_evaluate();
      } catch (thrown) {
        error = thrown;
      }
      exports['close-resources']();
      const output = take(1), stderr = take(2);
      if (error) return {ok: false, output, value: null, error: failure(stderr, error)};
      return {ok: true, output, value: shown ? result(exports) : null, error: stderr ? stderr.trim() : null};
    },
    names() {
      return exports.kernel_names() > 0 ? result(exports).split('\n') : [];
    },
  };
}

// ---- Kernels in workers ----

// A kernel runs in a worker (src/notebook/worker.mjs), so a long evaluation
// blocks neither the page nor the terminal, and stopping one means
// terminating its worker. `worker` is a browser Worker or a Node one; each
// request is answered with the result of the same call on the kernel.
export function kernelClient(worker) {
  const pending = new Map();
  let next = 0;
  const receive = ({id, result, error}) => {
    const {resolve, reject} = pending.get(id);
    pending.delete(id);
    if (error) reject(new Error(error)); else resolve(result);
  };
  if (worker.on) worker.on('message', receive);
  else worker.addEventListener('message', event => receive(event.data));
  const request = (kind, argument) => new Promise((resolve, reject) => {
    pending.set(++next, {resolve, reject});
    worker.postMessage({id: next, kind, argument});
  });
  return {
    load: bytes => request('load', bytes),
    evaluate: text => request('evaluate', text),
    names: () => request('names'),
    terminate() {
      worker.terminate();
      for (const {reject} of pending.values()) reject(new Error('the kernel was stopped'));
      pending.clear();
    },
  };
}

// ---- Cells ----

// Whether text is ready to evaluate: every parenthesis opened outside a
// string, a character or a comment is closed. A REPL reads more lines until
// it is. Text that closes too many is ready, and fails to read.
export function balanced(text) {
  let depth = 0, i = 0;
  const skipLine = () => { while (i < text.length && text[i] !== '\n') i++; };
  const skipString = () => { for (i++; i < text.length && text[i] !== '"'; i++) if (text[i] === '\\') i++; };
  for (; i < text.length; i++) {
    switch (text[i]) {
      case ';': skipLine(); break;
      case '"': skipString(); if (i >= text.length) return false; break;
      case '#': if (text[i + 1] === '\\') i += 2; break;
      case '(': depth++; break;
      case ')': depth--; break;
    }
  }
  return depth <= 0;
}

// A notebook as plain Scheme, in Jupytext's percent format: each cell begins
// with a `;; %%` line. Text before the first marker is a cell too, unless it
// is blank.
export function parseCells(text) {
  const cells = [];
  let lines = [];
  for (const line of text.split('\n')) {
    if (/^;; %%/.test(line)) { cells.push(lines.join('\n')); lines = []; }
    else lines.push(line);
  }
  cells.push(lines.join('\n'));
  const trimmed = cells.map(cell => cell.replace(/^\n+|\s+$/g, ''));
  return trimmed[0] === '' ? trimmed.slice(1) : trimmed;
}

export function formatCells(cells) {
  return cells.map(cell => `;; %%\n${cell.replace(/\s+$/, '')}\n`).join('\n');
}
