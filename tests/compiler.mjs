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
import {createAssembler} from '../scripts/assemble.mjs';
import {CompilerCrashed, CompilerFailure, createCompiler} from '../scripts/compiler.mjs';

const [program, assembler, runtime] = process.argv.slice(2);
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const directory = mkdtempSync(join(tmpdir(), 'lofi-compiler-'));
const assemble = await createAssembler(readFileSync(assembler));
const compiler = await createCompiler(program, join(directory, 'errors'));
const libraries = [directory, join(root, 'lib')];
let sequence = 0;
const fresh = () => { const path = join(directory, String(sequence++)); mkdirSync(path); return path; };
const write = (path, text) => { mkdirSync(dirname(path), {recursive: true}); writeFileSync(path, text); };

function execute(modules, expected, args = []) {
  const output = fresh(), manifest = join(output, 'modules.json');
  const files = modules.map(({name, file}) => {
    const wasm = join(output, `${name}.wasm`);
    writeFileSync(wasm, assemble(readFileSync(file, 'utf8')));
    return {name, file: wasm};
  });
  writeFileSync(manifest, JSON.stringify({runtime, modules: files}));
  const result = spawnSync(process.execPath, ['--no-warnings', join(root, 'scripts/run-lofi.mjs'), manifest, ...args], {encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout + result.stderr, expected);
}

function failure(call, pattern) {
  let caught;
  assert.throws(call, error => { caught = error; return error instanceof CompilerFailure && pattern.test(error.message); });
  return caught;
}

try {
  // Lofi parses forward run references, path fields and escaped strings.
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
  const value = number => `(define-library (sample value) (export value) (import (lofi base))
    (begin (: value (-> I64)) (define (value) ${number})))`;
  write(helper, value(42));
  write(source, '(import (lofi base) (lofi io) (sample value)) (write-line (i64->string (value)))');
  const first = compiler.modules(compiler.session(libraries), source, fresh(), fresh());
  execute(first.modules, '42\n');
  const second = compiler.modules(first.session, source, fresh(), fresh());
  assert.deepEqual(second.modules.filter(module => module.compiled), []);
  write(helper, value('missing-name'));
  const badHelper = failure(() => compiler.modules(second.session, source, fresh(), fresh()), /missing-name/);
  assert.equal(badHelper.diagnostic.source.file, helper);
  assert.equal(badHelper.diagnostic.source.line, 2);
  assert.match(badHelper.diagnostic.message, /missing-name/);
  write(helper, value(43));
  const repaired = compiler.modules(second.session, source, fresh(), fresh());
  assert.deepEqual(repaired.modules.filter(module => module.compiled).map(module => module.name), ['sample.value']);
  execute(repaired.modules, '43\n');
  const wat = join(fresh(), 'program.wat');
  compiler.static(source, wat, fresh(), libraries);
  execute([{name: 'program', file: wat}], '43\n');
  assert.equal(failure(() => compiler.static(join(directory, 'absent.sld'), wat, fresh(), libraries), /absent.sld/).diagnostic, null, 'IO failures cannot inherit a preceding source point');
  assert.deepEqual(compiler.modules(repaired.session, source, fresh(), fresh()).modules.filter(module => module.compiled), []);

  // Missing inputs unwind before native work. A new logical compilation
  // requests generated syntax again, even with its last successful Session.
  const generated = join(directory, 'generated.sld'), scratch = fresh();
  write(generated, '(import (lofi base) (lofi io) (sample table)) (write-line (i64->string (length squares)))');
  const generatedLibraries = [join(root, 'tests/programs/lib'), join(root, 'lib')];
  const previous = compiler.session(generatedLibraries);
  const missing = failure(() => compiler.modules(previous, generated, fresh(), scratch), /compiler requires an input/);
  assert.equal(missing.diagnostic, null, 'input requests have no source-failure record');
  const request = missing.request;
  assert.equal(existsSync(join(scratch, 'request.datum')), false);
  assert.equal(failure(() => compiler.static(join(directory, 'absent.sld'), wat, fresh(), libraries), /absent.sld/).request, null);
  const malformed = join(directory, 'malformed.sld');
  write(malformed, '(import (lofi base)) (');
  const syntaxFailure = failure(() => compiler.static(malformed, wat, fresh(), libraries), /unclosed list/);
  assert.equal(syntaxFailure.request, null);
  assert.equal(syntaxFailure.diagnostic.source.file, malformed);
  const retried = failure(() => compiler.modules(previous, generated, fresh(), scratch), /compiler requires an input/);
  assert.deepEqual(retried.request, request);
  assert.equal(retried.diagnostic, null);
  assert.equal(request.kind, 'generate');
  assert.match(request.key, /^\d+$/);
  const producer = join(fresh(), 'producer.wat');
  compiler.static(join(scratch, `${request.key}.sld`), producer, fresh(), generatedLibraries);
  execute([{name: 'program', file: producer}], '', [join(scratch, `${request.key}.syntax`)]);
  const built = compiler.modules(previous, generated, fresh(), scratch);
  execute(built.modules, '6\n');
  failure(() => compiler.modules(built.session, generated, fresh(), fresh()), /compiler requires an input/);

  // One Lofi reader/printer handles artifact fields, including control
  // characters and supplementary Unicode. A rejected update keeps the file.
  const artifactSource = join(root, 'tests/artifacts/native.sld'), artifactScratch = fresh();
  const artifact = failure(() => compiler.static(artifactSource, wat, artifactScratch, libraries), /compiler requires an input/).request;
  assert.deepEqual(artifact, {kind: 'artifact', name: 'client', file: artifactSource, line: 6, column: 16});
  const relative = 'data"\\😀\n\t\x01.bin', backing = join(directory, 'backing"\\😀.bin');
  write(backing, Buffer.from([0, 128, 255]));
  const replies = join(artifactScratch, 'artifacts.datum');
  compiler.addArtifact(replies, 'client', [[relative, backing]]);
  const before = readFileSync(replies, 'utf8');
  failure(() => compiler.addArtifact(replies, 'client', []), /already provided/);
  failure(() => compiler.addArtifact(replies, 'other', [['incomplete']]), /backing path pairs/);
  assert.equal(readFileSync(replies, 'utf8'), before);
  compiler.static(artifactSource, wat, artifactScratch, libraries);
  rmSync(backing);
  execute([{name: 'program', file: wat}], `${relative}:0,128,255,\n`);
  assert.deepEqual(compiler.project(project), {builds: [], runs: []});
  assert.equal(readFileSync(join(directory, 'errors'), 'utf8'), '', 'successful calls start with fresh diagnostics');

  const unicode = '(import (lofi base))\n(: greeting String)\n(define greeting (if #t "😀" 5))';
  write(source, unicode);
  const point = failure(() => compiler.static(source, wat, fresh(), libraries), /does not fit String/).diagnostic;
  assert.deepEqual(point.source, {file: source, line: 3, column: Array.from(unicode.split('\n')[2].split('5')[0]).length + 1});
  write(source, '(import (lofi base))\n(');
  assert.deepEqual(failure(() => compiler.static(source, wat, fresh(), libraries), /unclosed list/).diagnostic.source, {file: source, line: 2, column: 1});

  // An arbitrary imported-function trap is terminal; it cannot be confused
  // with the trusted compiler's resource-cleaning diagnostic exit.
  const trapping = join(directory, 'trapping.wasm');
  write(trapping, assemble(`(module
    (import "lofi.compiler" "character" (func $character (param i32)))
    (memory (export "memory") 1)
    (func (export "_initialize")) (func (export "main")) (func (export "reset"))
    (func (export "input_character") (param i32) (call $character (i32.const 1114112)))
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
      (import "lofi.compiler" "end" (func $end))
      (import "lofi.compiler" "diagnostic" (func $diagnostic (param i64 i64)))
      (memory (export "memory") 1)
      (func (export "_initialize")) (func (export "main"))
      (func (export "input_character") (param i32) ${stage === 'argument-exit' ? '(call $exit (i32.const 1))' : ''})
      (func (export "input_end"))
      (func (export "reset") ${stage === 'reset' ? 'unreachable' : ''})
      (func (export "request") ${stage === 'request' ? 'unreachable' : ''})
      (func (export "diagnostic") ${stage === 'diagnostic' ? 'unreachable' : ''})
      (func (export "project") ${stage === 'after-record'
        ? '(call $end) (call $end) (call $diagnostic (i64.const 1) (i64.const 1)) unreachable'
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
    assert.throws(() => compiler.static(source, wat, fresh(), libraries),
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
