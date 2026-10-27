// The resident compiler boundary, exercised against real linked Wasm and
// emitted programs. Graph traversal and retry policy belong to the builder.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import {existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync} from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createAssembler} from '../host/native/assemble.mjs';
import {CompilerCrashed, CompilerFailure, createCompiler} from '../host/native/compiler.mjs';

const [program, assembler, runtime] = process.argv.slice(2);
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const directory = mkdtempSync(join(tmpdir(), 'snail-compiler-'));
const assemble = await createAssembler(readFileSync(assembler));
const compiler = await createCompiler(program, join(directory, 'errors'));
const empty = compiler.inputs();
const libraries = [directory, join(root, 'src')];
let sequence = 0;
const fresh = () => { const path = join(directory, String(sequence++)); mkdirSync(path); return path; };
const write = (path, text) => { mkdirSync(dirname(path), {recursive: true}); writeFileSync(path, text); };

function execute(modules, expected, args = []) {
  const output = fresh(), manifest = join(output, 'modules.json');
  const files = modules.map(({name, text}) => {
    const wasm = join(output, `${name}.wasm`);
    writeFileSync(wasm, assemble(text));
    return {name, file: wasm};
  });
  writeFileSync(manifest, JSON.stringify({runtime, modules: files}));
  const result = spawnSync(process.execPath, ['--no-warnings', join(root, 'host/native/run-snail.mjs'), manifest, ...args], {encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout + result.stderr, expected);
}

function failure(call, pattern) {
  let caught;
  assert.throws(call, error => { caught = error; return error instanceof CompilerFailure && pattern.test(error.message); });
  return caught;
}

try {
  // Snail-Core parses forward run references, path fields and escaped strings.
  const project = join(directory, 'project λ😀.datum');
  write(project, String.raw`((run-target dev (run server (args ("" "λ😀" "quote\"\\\n"))))
    (build-target client (browser (entry "client λ.sld") (library-roots ("." "src")) (public "public")))
    (build-target server (program (entry "main.sld"))))`);
  const parsed = compiler.project(project);
  assert.deepEqual(parsed.builds.map(({location, ...target}) => target), [
    {kind: 'browser', name: 'client', entry: 'client λ.sld', libraries: ['.', 'src'], public: 'public'},
    {kind: 'program', name: 'server', entry: 'main.sld', libraries: []},
  ]);
  assert.equal(parsed.builds[0].location, `${project}:2:5`);
  assert.deepEqual(parsed.runs[0], {kind: 'run', name: 'dev', build: 'server', location: `${project}:1:2`, args: ['', 'λ😀', 'quote"\\\n']});
  write(project, '((unknown x))');
  const malformedProject = failure(() => compiler.project(project), /expected a build-target/);
  assert.deepEqual(malformedProject.diagnostic, {severity: 'error', message: 'expected a build-target or run-target declaration', source: {file: project, line: 1, column: 2}});
  write(project, '()');
  assert.deepEqual(compiler.project(project), {builds: [], runs: []});

  // A genuine Session survives success, cache reuse, a failed edit and repair.
  const source = join(directory, 'main.sld'), helper = join(directory, 'sample/value.sld');
  const value = number => `(define-library (sample value) (export value) (import (snail-core base))
    (begin (: value (-> I64)) (define (value) ${number})))`;
  write(helper, value(42));
  write(source, '(import (snail-core base) (snail-core io) (sample value)) (write-line (i64->string (value)))');
  const first = compiler.modules(compiler.session(libraries), empty, source, fresh());
  execute(first.modules, '42\n');
  const second = compiler.modules(first.session, empty, source, fresh());
  assert.deepEqual(second.modules.filter(module => module.compiled), []);
  write(helper, value('missing-name'));
  const badHelper = failure(() => compiler.modules(second.session, empty, source, fresh()), /missing-name/);
  assert.equal(badHelper.diagnostic.source.file, helper);
  assert.equal(badHelper.diagnostic.source.line, 2);
  assert.match(badHelper.diagnostic.message, /missing-name/);
  write(helper, value(43));
  const repaired = compiler.modules(second.session, empty, source, fresh());
  assert.deepEqual(repaired.modules.filter(module => module.compiled).map(module => module.name), ['sample.value']);
  execute(repaired.modules, '43\n');
  const wat = join(fresh(), 'program.wat');
  compiler.static(empty, source, wat, fresh(), libraries);
  execute([{name: 'program', text: readFileSync(wat, 'utf8')}], '43\n');
  assert.equal(failure(() => compiler.static(empty, join(directory, 'absent.sld'), wat, fresh(), libraries), /absent.sld/).diagnostic, null, 'IO failures cannot inherit a preceding source point');
  assert.deepEqual(compiler.modules(repaired.session, empty, source, fresh()).modules.filter(module => module.compiled), []);

  // Missing inputs unwind before native work. A new logical compilation
  // requests generated syntax again, even with its last successful Session.
  const generated = join(directory, 'generated.sld'), scratch = fresh();
  write(generated, '(import (snail-core base) (snail-core io) (sample table)) (write-line (i64->string (length squares)))');
  const generatedLibraries = [join(root, 'tests/programs/lib'), join(root, 'src')];
  const previous = compiler.session(generatedLibraries);
  const missing = failure(() => compiler.modules(previous, empty, generated, scratch), /compiler requires an input/);
  assert.equal(missing.diagnostic, null, 'input requests have no source-failure record');
  const request = missing.request;
  assert.equal(existsSync(join(scratch, 'request.datum')), false);
  assert.equal(failure(() => compiler.static(empty, join(directory, 'absent.sld'), wat, fresh(), libraries), /absent.sld/).request, null);
  const malformed = join(directory, 'malformed.sld');
  write(malformed, '(import (snail-core base)) (');
  const syntaxFailure = failure(() => compiler.static(empty, malformed, wat, fresh(), libraries), /unclosed list/);
  assert.equal(syntaxFailure.request, null);
  assert.equal(syntaxFailure.diagnostic.source.file, malformed);
  const retried = failure(() => compiler.modules(previous, empty, generated, scratch), /compiler requires an input/);
  assert.deepEqual(retried.request, request);
  assert.equal(retried.diagnostic, null);
  assert.equal(request.kind, 'generate');
  assert.match(request.key, /^\d+$/);
  const producer = join(fresh(), 'producer.wat');
  compiler.static(empty, join(scratch, `${request.key}.sld`), producer, fresh(), generatedLibraries);
  execute([{name: 'program', text: readFileSync(producer, 'utf8')}], '', [join(scratch, `${request.key}.syntax`)]);
  const built = compiler.modules(previous, empty, generated, scratch);
  execute(built.modules, '6\n');
  failure(() => compiler.modules(built.session, empty, generated, fresh()), /compiler requires an input/);

  // Snapshot creation owns the bytes before compilation starts. Independent
  // values and failed additions cannot mutate a caller's previous inputs.
  const artifactSource = join(root, 'tests/artifacts/native.sld'), artifactScratch = fresh();
  const artifact = failure(() => compiler.static(empty, artifactSource, wat, artifactScratch, libraries), /compiler requires an input/).request;
  assert.deepEqual(artifact, {kind: 'artifact', name: 'client', file: artifactSource, line: 6, column: 16});
  const relative = 'data"\\😀\n\t\x01.bin', backing = join(directory, 'backing"\\😀.bin');
  write(backing, Buffer.from([0, 128, 255]));
  const inputs = compiler.addArtifact(empty, 'client', [[relative, backing]]);
  failure(() => compiler.addArtifact(inputs, 'client', []), /already provided/);
  failure(() => compiler.addArtifact(inputs, 'other', [['incomplete']]), /backing path pairs/);
  failure(() => compiler.addArtifact(inputs, 'other', [['first', backing], ['second', join(directory, 'absent-artifact')]]), /absent-artifact/);
  const repairedInputs = compiler.addArtifact(inputs, 'other', []);
  write(backing, Buffer.from([42]));
  const independent = compiler.addArtifact(empty, 'client', [[relative, backing]]);
  rmSync(backing);
  compiler.static(repairedInputs, artifactSource, wat, fresh(), libraries);
  execute([{name: 'program', text: readFileSync(wat, 'utf8')}], `${relative}:0,128,255,\n`);
  compiler.static(independent, artifactSource, wat, fresh(), libraries);
  execute([{name: 'program', text: readFileSync(wat, 'utf8')}], `${relative}:42,\n`);
  compiler.static(inputs, artifactSource, wat, fresh(), libraries);
  execute([{name: 'program', text: readFileSync(wat, 'utf8')}], `${relative}:0,128,255,\n`);
  assert.deepEqual(compiler.project(project), {builds: [], runs: []});
  assert.equal(readFileSync(join(directory, 'errors'), 'utf8'), '', 'successful calls start with fresh diagnostics');

  const unicode = '(import (snail-core base))\n(: greeting String)\n(define greeting (if #t "😀" 5))';
  write(source, unicode);
  const point = failure(() => compiler.static(empty, source, wat, fresh(), libraries), /does not fit String/).diagnostic;
  assert.deepEqual(point.source, {file: source, line: 3, column: Array.from(unicode.split('\n')[2].split('5')[0]).length + 1});
  write(source, '(import (snail-core base))\n(');
  assert.deepEqual(failure(() => compiler.static(empty, source, wat, fresh(), libraries), /unclosed list/).diagnostic.source, {file: source, line: 2, column: 1});

  // Session and artifact references keep distinct Wasm types. Passing one
  // where the other belongs is a host trap, so the instance cannot be reused.
  const wrongHandle = await createCompiler(program, join(directory, 'wrong-handle-errors'));
  try {
    const session = wrongHandle.session(libraries);
    assert.throws(() => wrongHandle.static(session, source, wat, fresh(), libraries),
      error => error instanceof CompilerCrashed && error.cause instanceof TypeError);
    assert.throws(() => wrongHandle.inputs(), /compiler is closed/);
  } finally { wrongHandle.close(); }

  // An arbitrary imported-function trap is terminal; it cannot be confused
  // with the trusted compiler's resource-cleaning diagnostic exit.
  const trapping = join(directory, 'trapping.wasm');
  write(trapping, assemble(`(module
    (import "snail-core.compiler" "text" (func $text (param i32 i32)))
    (memory (export "memory") 1)
    (func (export "_initialize")) (func (export "main")) (func (export "reset"))
    (func (export "input_character") (param i32) (i32.store (i32.const 0) (i32.const 1114112)) (call $text (i32.const 0) (i32.const 1)))
    (func (export "input_end")) (func (export "project"))
    (func (export "request")) (func (export "diagnostic"))
    (func (export "close-resources") (result i32) (i32.const 0)))`));
  const broken = await createCompiler(trapping, join(directory, 'trapping-errors'));
  assert.throws(() => broken.project(project), error => error instanceof CompilerCrashed && error.cause instanceof RangeError);
  assert.throws(() => broken.project(project), /compiler is closed/);
  broken.close();

  // Diagnostic reset/projection are part of the trusted boundary too. A trap
  // there retires the instance; emitting a record never makes a trap recoverable.
  for (const stage of ['reset', 'argument-exit', 'request', 'diagnostic', 'after-record']) {
    const fixture = join(directory, `${stage}.wasm`);
    write(fixture, assemble(`(module
      (import "wasi_snapshot_preview1" "proc_exit" (func $exit (param i32)))
      (import "snail-core.compiler" "text" (func $text (param i32 i32)))
      (import "snail-core.compiler" "diagnostic" (func $diagnostic (param i64 i64)))
      (memory (export "memory") 1)
      (func (export "_initialize")) (func (export "main"))
      (func (export "input_character") (param i32) ${stage === 'argument-exit' ? '(call $exit (i32.const 1))' : ''})
      (func (export "input_end"))
      (func (export "reset") ${stage === 'reset' ? 'unreachable' : ''})
      (func (export "request") ${stage === 'request' ? 'unreachable' : ''})
      (func (export "diagnostic") ${stage === 'diagnostic' ? 'unreachable' : ''})
      (func (export "project") ${stage === 'after-record'
        ? '(call $text (i32.const 0) (i32.const 0)) (call $text (i32.const 0) (i32.const 0)) (call $diagnostic (i64.const 1) (i64.const 1)) unreachable'
        : '(call $exit (i32.const 1))'})
      (func (export "close-resources") (result i32) (i32.const 0)))`));
    const trapped = await createCompiler(fixture, join(directory, `${stage}-errors`));
    assert.throws(() => trapped.project(project), CompilerCrashed, stage);
    assert.throws(() => trapped.project(project), /compiler is closed/, stage);
    trapped.close();
  }

  // A diagnostic stream failure retires the instance and must tell the
  // project worker to stop, rather than accepting another recoverable build.
  const readSync = fs.readSync, unavailable = new Error('diagnostic read failed');
  fs.readSync = () => { throw unavailable; };
  syncBuiltinESMExports();
  try {
    assert.throws(() => compiler.static(empty, source, wat, fresh(), libraries),
      error => error instanceof CompilerCrashed && error.cause === unavailable);
  } finally { fs.readSync = readSync; syncBuiltinESMExports(); }
  assert.throws(() => compiler.project(project), /compiler is closed/);

  // Initialization owns its descriptor even before WASI exists. On Linux,
  // an unlinked current directory makes environment preparation fail.
  if (process.platform === 'linux') {
    const original = process.cwd(), removed = fresh();
    const descriptors = readdirSync('/proc/self/fd').length;
    process.chdir(removed);
    rmSync(removed, {recursive: true});
    try { await assert.rejects(createCompiler(program, join(directory, 'initialization-errors')), {code: 'ENOENT'}); }
    finally { process.chdir(original); }
    assert.equal(readdirSync('/proc/self/fd').length, descriptors, 'failed construction closes its diagnostics descriptor');
  }
} finally {
  compiler.close();
  rmSync(directory, {recursive: true, force: true});
}
console.log('resident compiler: parsed records, reusable sessions, typed inputs and terminal traps');
