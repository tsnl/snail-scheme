// The resident compiler boundary, exercised against real linked Wasm and
// emitted programs. Graph traversal and retry policy belong to the builder.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createAssembler} from '../scripts/assemble.mjs';
import {CompilerFailure, createCompiler} from '../scripts/compiler.mjs';

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
  failure(() => compiler.project(project), /expected a build-target/);
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
  failure(() => compiler.modules(second.session, source, fresh(), fresh()), /missing-name/);
  write(helper, value(43));
  const repaired = compiler.modules(second.session, source, fresh(), fresh());
  assert.deepEqual(repaired.modules.filter(module => module.compiled).map(module => module.name), ['sample.value']);
  execute(repaired.modules, '43\n');
  const wat = join(fresh(), 'program.wat');
  compiler.static(source, wat, fresh(), libraries);
  execute([{name: 'program', file: wat}], '43\n');
  failure(() => compiler.static(join(directory, 'absent.sld'), wat, fresh(), libraries), /absent.sld/);
  assert.deepEqual(compiler.modules(repaired.session, source, fresh(), fresh()).modules.filter(module => module.compiled), []);

  // Missing inputs unwind before native work. A new logical compilation
  // requests generated syntax again, even with its last successful Session.
  const generated = join(directory, 'generated.sld'), scratch = fresh();
  write(generated, '(import (lofi base) (lofi io) (sample table)) (write-line (i64->string (length squares)))');
  const generatedLibraries = [join(root, 'tests/programs/lib'), join(root, 'lib')];
  const previous = compiler.session(generatedLibraries);
  const request = failure(() => compiler.modules(previous, generated, fresh(), scratch), /compiler requires an input/).request;
  assert.equal(existsSync(join(scratch, 'request.datum')), false);
  assert.equal(failure(() => compiler.static(join(directory, 'absent.sld'), wat, fresh(), libraries), /absent.sld/).request, null);
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

  // An arbitrary imported-function trap is terminal; it cannot be confused
  // with the trusted compiler's resource-cleaning diagnostic exit.
  const trapping = join(directory, 'trapping.wasm');
  write(trapping, assemble(`(module
    (import "lofi.compiler" "character" (func $character (param i32)))
    (memory (export "memory") 1)
    (func (export "_initialize")) (func (export "main")) (func (export "reset"))
    (func (export "input_character") (param i32) (call $character (i32.const 1114112)))
    (func (export "input_end")) (func (export "project"))
    (func (export "close-resources") (result i32) (i32.const 0)))`));
  const broken = await createCompiler(trapping, join(directory, 'trapping-errors'));
  assert.throws(() => broken.project(project), error => !(error instanceof CompilerFailure) && error.cause instanceof RangeError);
  assert.throws(() => broken.project(project), /compiler is closed/);
  broken.close();

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
