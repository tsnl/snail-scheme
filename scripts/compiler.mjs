// One synchronous resident compiler. Caches remain opaque WasmGC references;
// native code receives parsed records and files, never language syntax to parse.
import {closeSync, fstatSync, ftruncateSync, openSync, readFileSync, readSync} from 'node:fs';
import {WASI} from 'node:wasi';

// Only the trusted compiler's diagnostic exit is recoverable. Its panic and
// checked IO paths release resources before exiting; an arbitrary trap does not.
export class CompilerFailure extends Error {
  constructor(message, request, diagnostic) {
    super(message); this.request = request; this.diagnostic = diagnostic;
  }
}
export class CompilerCrashed extends Error {}

// ---- Parsed records ----

function recordImports(receive) {
  let fields = [], text = '';
  const take = () => { const taken = fields; fields = []; return taken; };
  return {
    character(code) { text += String.fromCodePoint(code); },
    end() { fields.push(text); text = ''; },
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
    module(compiled) { const [name, file] = take(); receive({name, file, compiled: !!compiled}); },
    generate() { const [key] = take(); receive({kind: 'generate', key}); },
    diagnostic(line, column) {
      const [message, file] = take();
      line = Number(line); column = Number(column);
      if (!Number.isSafeInteger(line) || !Number.isSafeInteger(column)) throw new Error('invalid compiler source point');
      // Internal no-loc sentinels are not source locations. Positive columns
      // count Unicode scalar values, starting at one, just like the reader.
      const source = file && line > 0 && column > 0 ? {file, line, column} : null;
      receive({severity: 'error', message, source});
    },
    artifact(line, column) {
      const [name, file] = take();
      receive({kind: 'artifact', name, file, line: Number(line), column: Number(column)});
    },
  };
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
    return bytes.toString().trim().replace(/^lofi: /, '');
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
      // main initializes the request and diagnostic cells before reset can run.
      if (name !== 'main') api.reset();
      for (const text of strings) {
        for (const character of text) api.input_character(character.codePointAt(0));
        api.input_end();
      }
      entered = true;
      const value = api[name](...values);
      return {value, records};
    } catch (error) {
      let diagnostic;
      try { diagnostic = readErrors(); }
      catch (failure) { retire(new CompilerCrashed('cannot read compiler diagnostics', {cause: failure})); }
      const message = diagnostic || error?.message || `compiler exited with status ${exitCode}`;
      if (entered && name !== 'main' && error === exited && exitCode === 1) {
        records = [];
        try { api.request(); }
        catch (failure) { retire(new CompilerCrashed('cannot read compiler request', {cause: failure})); }
        const request = records[0] ?? null;
        records = [];
        try { api.diagnostic(); }
        catch (failure) { retire(new CompilerCrashed('cannot read compiler diagnostic', {cause: failure})); }
        throw new CompilerFailure(message, request, records[0] ?? null);
      }
      retire(new CompilerCrashed(message, {cause: error}));
    }
  }

  try {
    const wasi = new WASI({version: 'preview1', args: [program],
      env: {...process.env, SNAIL_CWD: process.cwd()}, preopens: {'/': '/'}, stderr: errors});
    const imports = {...wasi.getImportObject(), 'lofi.compiler': recordImports(record => records.push(record))};
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
    static(inputs, source, output, scratch, directories) { invoke('static', [source, output, scratch, ...directories], inputs); },
    check(inputs, source, scratch, directories) { invoke('check', [source, scratch, ...directories], inputs); },
    modules(previous, inputs, source, output, scratch) {
      const {value: session, records: modules} = invoke('modules', [source, output, scratch], previous, inputs);
      return {session, modules};
    },
    inputs() { return invoke('inputs', []).value; },
    addArtifact(inputs, name, files) { return invoke('add_artifact', [name, ...files.flat()], inputs).value; },
    close,
  };
}
