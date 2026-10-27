// The formatter, host/ide/format.sld, on the page's own thread, so Tab and
// Enter indent at once and highlighting follows each keystroke. Text
// crosses a character at a time each way. A formatter that panics may hold
// half its input, so the next call gets a fresh instance.
import {createWasi, instantiate} from './load.mjs';

export async function createFormatter(bytes) {
  const module = await WebAssembly.compile(bytes);
  const formatter = {module, ...(await start(module))};
  return {
    // The whole text, formatted as `make check` expects.
    format: text => call(formatter, text, exports => exports.format_whole()),
    // The text with lines `first` to `last`, counting from 0, reindented.
    indent: (text, first, last) => call(formatter, text, exports => exports.format_indent(first, last)),
    // One letter per character, naming its class for coloring.
    highlight: text => call(formatter, text, exports => exports.format_highlight()),
  };
}

// Sends the text, runs one entry point, and reads back its result. A
// panic's message is what the formatter wrote to standard error.
function call(formatter, text, entry) {
  const {exports} = formatter;
  try {
    for (const character of text) exports.format_character(character.codePointAt(0));
    let result = '';
    for (let index = 0, length = entry(exports); index < length; index++) result += String.fromCodePoint(exports.format_result(index));
    return result;
  } catch (error) {
    const message = formatter.errors.join('\n').replace(/^snail: /, '') || error.message;
    start(formatter.module).then(fresh => Object.assign(formatter, fresh));
    throw new Error(message);
  }
}

async function start(module) {
  const errors = [], wasi = createWasi({print: (fd, line) => errors.push(line)});
  const instance = await instantiate(module, wasi.getImportObject());
  wasi.initialize(instance);
  instance.exports.main();
  return {exports: instance.exports, errors};
}
