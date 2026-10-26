// Drives the in-process assembler (crates/assembler) built for wasm32-wasip1:
// WebAssembly text in, a binary module out, without Binaryen. It uses only
// the WebAssembly API, so the development loop's hosts, in Node and in the
// IDE's worker, import it alike. It keeps its own few WASI functions: the
// IDE's site copies it beside host/browser/load.mjs, but here it lives in
// scripts/, and no one relative import finds load.mjs from both places.

// ---- Platform ----

// The assembler needs no files. Rust's standard library asks for randomness
// to seed hash maps and the environment at startup, and writes to standard
// error only when it panics.
function platformImports(memory) {
  const view = () => new DataView(memory().buffer);
  return {
    random_get(pointer, length) {
      crypto.getRandomValues(new Uint8Array(memory().buffer, pointer, length));
      return 0;
    },
    environ_get() { return 0; },
    environ_sizes_get(count, size) {
      view().setUint32(count, 0, true);
      view().setUint32(size, 0, true);
      return 0;
    },
    fd_write(fd, iovs, count, written) {
      let total = 0;
      for (let i = 0; i < count; i++) {
        const pointer = view().getUint32(iovs + 8 * i, true), length = view().getUint32(iovs + 8 * i + 4, true);
        console.error(new TextDecoder().decode(new Uint8Array(memory().buffer, pointer, length)));
        total += length;
      }
      view().setUint32(written, total, true);
      return 0;
    },
    proc_exit(code) { throw new Error(`the assembler exited with status ${code}`); },
  };
}

// ---- Assembling ----

// Returns `assemble(text)`, which returns the module's bytes or throws the
// parser's message, naming the line and column.
export async function createAssembler(bytes) {
  let exports;
  const {instance} = await WebAssembly.instantiate(bytes, {wasi_snapshot_preview1: platformImports(() => exports.memory)});
  exports = instance.exports;
  exports._initialize();
  return text => {
    // Making room may grow the memory, which replaces its buffer, so the
    // buffer is read only after.
    const encoded = new TextEncoder().encode(text);
    const pointer = exports['snail:assembler/input'](encoded.length);
    new Uint8Array(exports.memory.buffer, pointer, encoded.length).set(encoded);
    const status = exports['snail:assembler/assemble']();
    const output = new Uint8Array(exports.memory.buffer, exports['snail:assembler/output'](), exports['snail:assembler/output-length']());
    if (status !== 0) throw new Error(new TextDecoder().decode(output));
    return output.slice();
  };
}
