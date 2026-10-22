// The formatter, src/ide/format.sld, on the page's own thread, so Tab and
// Enter indent at once and highlighting follows each keystroke. Text
// crosses a character at a time each way. A formatter that panics may hold
// half its input, so the next call gets a fresh instance.

export async function createFormatter(bytes) {
  const module = await WebAssembly.compile(bytes);
  const instance = {module, exports: await instantiate(module)};
  return {
    // The whole text, formatted as `make check` expects.
    format: text => call(instance, text, exports => exports.format_source()),
    // The text with lines `first` to `last`, counting from 0, reindented.
    indent: (text, first, last) => call(instance, text, exports => exports.format_indent(first, last)),
    // One letter per character, naming its class for coloring.
    highlight: text => call(instance, text, exports => exports.format_highlight()),
  };
}

// Sends the text, runs one entry point, and reads back its result.
function call(instance, text, entry) {
  const {exports} = instance;
  try {
    for (const character of text) exports.format_character(character.codePointAt(0));
    let result = '';
    for (let index = 0, length = entry(exports); index < length; index++) result += String.fromCodePoint(exports.format_result(index));
    return result;
  } catch (error) {
    instantiate(instance.module).then(fresh => { instance.exports = fresh; });
    throw error;
  }
}

// The formatter needs no arguments; standard error holds a panic's message.
async function instantiate(module) {
  let exports = null, errors = '';
  const memory = () => new DataView(exports.memory.buffer);
  const wasi = {
    args_sizes_get(count, size) { memory().setUint32(count, 0, true); memory().setUint32(size, 0, true); return 0; },
    args_get() { return 0; },
    fd_write(fd, iovs, count, written) {
      let total = 0;
      for (let i = 0; i < count; i++) {
        const length = memory().getUint32(iovs + 8 * i + 4, true);
        errors += new TextDecoder().decode(new Uint8Array(exports.memory.buffer, memory().getUint32(iovs + 8 * i, true), length));
        total += length;
      }
      memory().setUint32(written, total, true);
      return 0;
    },
    proc_exit() { throw new Error(errors.trim() || 'the formatter failed'); },
  };
  for (const {module: from, name} of WebAssembly.Module.imports(module)) if (from === 'wasi_snapshot_preview1' && !wasi[name]) wasi[name] = () => 52;
  ({exports} = await WebAssembly.instantiate(module, {wasi_snapshot_preview1: wasi}));
  exports._initialize();
  exports.main();
  return exports;
}
