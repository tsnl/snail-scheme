// One synchronous resident compiler. Caches remain opaque WasmGC references;
// native code receives parsed records and files, never language syntax to parse.
import {closeSync, fstatSync, ftruncateSync, openSync, readFileSync, readSync} from 'node:fs';
import {WASI} from 'node:wasi';

// A compile that stops, at a source error or for an input it was not
// supplied, returns with that record; the compiler's own exit 1, from a panic
// or a checked IO path, releases resources first and is recoverable too. An
// arbitrary trap is not.
export class CompilerFailure extends Error {
  constructor(message, request, diagnostic) {
    super(message); this.request = request; this.diagnostic = diagnostic;
  }
}
export class CompilerCrashed extends Error {}

// ---- Parsed records ----

// String host arguments borrow UTF-32 staging memory. Copy synchronously and
// acquire the view after staging may have grown memory. UTF-16 decoding avoids
// a JavaScript call or argument conversion for every emitted WAT character.
function stagedText(memory, pointer, length) {
  length >>>= 0;
  const scalars = new DataView(memory.buffer, pointer >>> 0, length * 4), units = Buffer.allocUnsafe(length * 4);
  let end = 0;
  for (let index = 0; index < length; index++) {
    let code = scalars.getUint32(index * 4, true);
    if (code > 0xffff) {
      if (code > 0x10ffff) throw new RangeError('invalid compiler character');
      code -= 0x10000;
      units.writeUInt16LE(0xd800 + (code >> 10), end); end += 2;
      code = 0xdc00 + (code & 1023);
    }
    units.writeUInt16LE(code, end); end += 2;
  }
  return units.toString('utf16le', 0, end);
}

function recordImports(receive, memory) {
  let fields = [];
  const take = () => { const taken = fields; fields = []; return taken; };
  return {
    text(pointer, length) { fields.push(stagedText(memory(), pointer, length)); },
    program() {
      const [name, entry, location, ...libraries] = take();
      receive({kind: 'program', name, entry, location, libraries});
    },
    browser() {
      const [name, entry, location, publicPath, ...libraries] = take();
      receive({kind: 'browser', name, entry, location, libraries, public: publicPath || null});
    },
    run() {
      const [name, build, location, ...args] = take();
      receive({kind: 'run', name, build, location, args});
    },
    module(compiled) { const [name, text, ...links] = take(); receive({name, text, compiled: !!compiled, links: linkPairs(links)}); },
    link() { receive({kind: 'link', ...linkPairs(take())[0]}); },
    generate() { const [key] = take(); receive({kind: 'generate', key}); },
    diagnostic(line, column) {
      const [message, file] = take();
      line = Number(line); column = Number(column);
      if (!Number.isSafeInteger(line) || !Number.isSafeInteger(column)) throw new Error('invalid compiler source point');
      // Internal no-loc sentinels are not source locations. Positive columns
      // count Unicode scalar values, starting at one, just like the reader.
      // A location in line 0 is a file as a whole, which the message names.
      const source = file && line > 0 && column > 0 ? {file, line, column} : null;
      receive({severity: 'error', message: file && line === 0 ? `${file}: ${message}` : message, source});
    },
    artifact(line, column) {
      const [name, file] = take();
      receive({kind: 'artifact', name, file, line: Number(line), column: Number(column)});
    },
    produce(index, count) {
      const [key, source, ...rest] = take();
      receive({kind: 'produce', index: Number(index), key, source, ...phaseInputs(rest, count)});
    },
    build(index, count) {
      const [name, entry, ...rest] = take();
      receive({kind: 'build', index: Number(index), name, entry, ...phaseInputs(rest, count)});
    },
    waiting() { receive({kind: 'waiting'}); },
  };
}

// Each file a library links: the name it ships under, and where it is.
function linkPairs(fields) {
  const links = [];
  for (let index = 0; index < fields.length; index += 2) links.push({name: fields[index], file: fields[index + 1]});
  return links;
}

// A phase's library directories, counted, then the targets it embeds.
function phaseInputs(fields, count) {
  count = Number(count);
  return {directories: fields.slice(0, count), embeds: fields.slice(count)};
}

// A wave: the plan that handed it out, its phases in the order they run,
// and whether the plan waits for their producers' outputs to go on.
function wave({value, records}) {
  return {plan: value, phases: records.filter(record => record.kind !== 'waiting'), waiting: records.some(record => record.kind === 'waiting')};
}

// A compile that stopped returned its diagnostic's record or its request's,
// and nothing else: the entry sends a stop's record in place of its output.
function stopped(records) {
  const diagnostic = records.find(record => record.severity === 'error');
  if (diagnostic) {
    const {file, line, column} = diagnostic.source ?? {};
    throw new CompilerFailure(diagnostic.source ? `${file}:${line}:${column}: ${diagnostic.message}` : diagnostic.message, null, diagnostic);
  }
  const request = records.find(record => record.kind === 'generate' || record.kind === 'artifact');
  if (request) throw new CompilerFailure('compiler requires an input', request, null);
}

// ---- Instance ownership ----

// The caller owns the diagnostics file's directory; this object owns its fd.
// Calls are serial. A worker keeps this object private and never transfers a
// Session or artifact inputs to another instance, worker, or compiler version.
export async function createCompiler(program, diagnostics) {
  // Append semantics let each invocation truncate without leaving a stale
  // write position. Positional reads do not change WASI's descriptor state.
  const errors = openSync(diagnostics, 'a+'), exited = Symbol('compiler exit');
  let api = null, closed = false, exitCode = null, records = [];

  function readErrors() {
    const bytes = Buffer.alloc(fstatSync(errors).size);
    let read = 0;
    while (read < bytes.length) {
      const count = readSync(errors, bytes, read, bytes.length - read, read);
      if (!count) throw new Error('cannot read compiler diagnostics');
      read += count;
    }
    return bytes.toString().trim().replace(/^snail: /, '');
  }

  function close() {
    if (closed) return;
    closed = true;
    try { api?.['close-resources'](); }
    finally { api = null; closeSync(errors); }
  }

  function retire(error) {
    try { close(); } catch {} // Cleanup must preserve the original failure.
    throw error;
  }

  function invoke(name, strings, ...values) {
    if (closed) throw new Error('the compiler is closed');
    records = []; exitCode = null;
    let entered = false;
    try {
      ftruncateSync(errors, 0);
      for (const text of strings) {
        for (const character of text) api.input_character(character.codePointAt(0));
        api.input_end();
      }
      entered = true;
      const value = api[name](...values);
      stopped(records);
      return {value, records};
    } catch (error) {
      if (error instanceof CompilerFailure) throw error;
      let diagnostic;
      try { diagnostic = readErrors(); }
      catch (failure) { retire(new CompilerCrashed('cannot read compiler diagnostics', {cause: failure})); }
      const message = diagnostic || error?.message || `compiler exited with status ${exitCode}`;
      if (entered && name !== 'main' && error === exited && exitCode === 1)
        throw new CompilerFailure(message, null, null);
      retire(new CompilerCrashed(message, {cause: error}));
    }
  }

  try {
    const wasi = new WASI({version: 'preview1', args: [program],
      env: {...process.env, SNAIL_CWD: process.cwd()}, preopens: {'/': '/'}, stderr: errors});
    const imports = {...wasi.getImportObject(), 'snail.records': recordImports(record => records.push(record), () => api.memory)};
    imports.wasi_snapshot_preview1.proc_exit = code => { exitCode = code; throw exited; };
    const {instance} = await WebAssembly.instantiate(readFileSync(program), imports);
    api = instance.exports;
    wasi.initialize(instance);
    invoke('main', []);
  } catch (error) {
    retire(error);
  }

  return {
    project(path) {
      const {records} = invoke('project', [path]);
      return {builds: records.filter(record => record.kind !== 'run'), runs: records.filter(record => record.kind === 'run')};
    },
    session(directories) { return invoke('session', directories).value; },
    // The files the program links, which ship beside its module.
    static(inputs, source, output, scratch, directories) {
      const {records} = invoke('static', [source, output, scratch, ...directories], inputs);
      return records.filter(record => record.kind === 'link').map(({name, file}) => ({name, file}));
    },
    modules(previous, inputs, source, scratch) {
      const {value: session, records: modules} = invoke('modules', [source, scratch], previous, inputs);
      return {session, modules};
    },
    inputs() { return invoke('inputs', []).value; },
    addArtifact(inputs, name, files) { return invoke('add_artifact', [name, ...files.flat()], inputs).value; },
    addGenerated(inputs, key, source, output, directories) {
      return invoke('add_generated', [key, source, output, ...directories], inputs).value;
    },
    plan(inputs, project, standard, scratch, names) {
      return wave(invoke('plan', [project, standard, scratch, ...names], inputs));
    },
    refine(plan, inputs) { return wave(invoke('refine', [], plan, inputs)); },
    close,
  };
}
