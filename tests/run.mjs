// The test suite, after the compiler's unit tests (tests/unit.scm, on
// Chez): every program is built by ./snail-scheme, as a user's is, and run
// on its host.
//
//   node tests/run.mjs ROOT [NAME ...]
//
// - A program NAME.sld of a suite must print NAME.out exactly, its standard
//   output and then its standard error, or fail to build with each line of
//   NAME.err in its diagnostics, in order.
// - Checks: a fixture built and handed to its check script, the command
//   line's own contracts, and the suites that are scripts already.
//
// With names, only the programs so named run. SNAIL_ENGINE=wasmtime builds
// each program for wasmtime and runs it on build/snail, but for those that
// need Node's sockets, processes or signals. Programs build and run eight
// at a time. Every build's output is removed first, so nothing here grows.
import {execFile} from 'node:child_process';
import {existsSync} from 'node:fs';
import {mkdir, readFile, readdir, rm, writeFile} from 'node:fs/promises';
import {join} from 'node:path';

const [root, ...selected] = process.argv.slice(2);
const wasmtime = process.env.SNAIL_ENGINE === 'wasmtime';
if (![undefined, '', 'node', 'wasmtime'].includes(process.env.SNAIL_ENGINE)) throw new Error('SNAIL_ENGINE must be node or wasmtime');
const snail = join(root, 'snail-scheme'), runner = join(root, 'host/native/run-snail.mjs'), native = join(root, 'build/snail');
const JOBS = 8;

// ---- Commands ----

// What a command printed and how it ended: {stdout, stderr, status}, with
// status null when a signal ended it.
function command(program, args, options = {}) {
  return new Promise(resolve => {
    const child = execFile(program, args, {cwd: root, maxBuffer: 64 * 1024 * 1024, ...options},
      (error, stdout, stderr) => resolve({stdout, stderr, status: error ? (typeof error.code === 'number' ? error.code : null) : 0}));
    child.stdin.end();
  });
}

const node = (...args) => command(process.execPath, ['--no-warnings', ...args]);

// The programs that stay on Node under wasmtime, by their sources.
const nodePrograms = new Set(['http-exchange', 'http-sockets', 'process-exec', 'process-run', 'process', 'tcp', 'udp']
  .map(name => `tests/programs/${name}.sld`).concat('tests/socket-boundary/main.sld', 'tests/termination/main.sld'));
const targetOf = source => wasmtime && !nodePrograms.has(source) ? 'wasmtime' : 'node';

// Builds `source`, a path from the root, for `target`: its module's path,
// or the failure's text.
async function build(source, target = targetOf(source)) {
  const built = await command(snail, ['build', '--target', target, source]);
  if (built.status !== 0) return {failure: built.stderr};
  const name = source.split('/').at(-1).replace(/\.[^.]*$/, '');
  return {module: join(built.stdout.trim(), `${name}.wasm`), target};
}

// Runs a built module on its host, as `snail-scheme run` would.
const run = ({module, target}, ...args) =>
  target === 'wasmtime' ? command(native, ['run-wasm', module, ...args]) : node(runner, module, ...args);

// Wasmtime tells a trap with the Wasm frames after its message, which name
// the functions the compiler chose; a case's expected output ends with the
// message.
const printed = ran => ran.stdout + ran.stderr.split('error while executing at wasm backtrace:\n')[0];

// ---- Reporting ----

const failures = [];
function fail(name, problem, detail = '') {
  failures.push(name);
  process.stderr.write(`FAIL ${name}: ${problem}\n${detail}\n`);
  return false;
}

// ---- Programs ----

function containsInOrder(text, parts) {
  let from = 0;
  for (const part of parts) {
    const at = text.indexOf(part, from);
    if (at < 0) return false;
    from = at + part.length;
  }
  return true;
}

async function program(suite, name) {
  const source = `${suite}/${name}.sld`, expected = join(root, suite, `${name}.out`), diagnostic = join(root, suite, `${name}.err`);
  const built = await build(source);
  if (existsSync(diagnostic)) {
    if (!built.failure) return fail(name, 'compiled, but a diagnostic was expected');
    const wanted = (await readFile(diagnostic, 'utf8')).replace(/\n$/, '');
    return containsInOrder(built.failure, wanted.split('\n')) || fail(name, 'wrong diagnostic', `${built.failure}\nexpected: ${wanted}`);
  }
  if (built.failure) return fail(name, 'compile failed', built.failure);
  if (!existsSync(expected)) return fail(name, 'no expected output');
  const output = printed(await run(built)), wanted = await readFile(expected, 'utf8');
  return output === wanted || fail(name, 'wrong output', `${output}\nexpected:\n${wanted}`);
}

async function programs(suite) {
  const names = (await readdir(join(root, suite))).filter(file => file.endsWith('.sld')).map(file => file.slice(0, -4)).sort();
  return names.filter(name => !selected.length || selected.includes(name)).map(name => () => program(suite, name));
}

// ---- Checks ----

// A fixture built for `target` and handed to a script, which fails by its
// status.
function fixture(name, source, script, target) {
  return async () => {
    const built = await build(source, target);
    if (built.failure) return fail(name, 'compile failed', built.failure);
    const checked = await node(join(root, script), built.module);
    return checked.status === 0 || fail(name, 'failed', checked.stdout + checked.stderr);
  };
}

// A suite that is a script already, given the root.
function script(name, ...flags) {
  return async () => {
    const ran = await node(...flags, join(root, `tests/${name}.mjs`), root);
    return ran.status === 0 || fail(name, 'failed', ran.stdout + ran.stderr);
  };
}

// The command line's own contracts: `wat` prints a program's text, and a
// run's status is its program's on either engine: a panic exits with 1,
// and a trap is 2.
async function commandLine() {
  const target = wasmtime ? 'wasmtime' : 'node', ran = file => command(snail, ['run', '--target', target, file]);
  const wat = await command(snail, ['wat', '--target', target, 'examples/fibonacci.sld']);
  if (wat.status !== 0 || !wat.stdout.includes('(func $main')) return fail('command line', 'wat printed no module text', wat.stderr);
  const fibonacci = await ran('examples/fibonacci.sld');
  if (fibonacci.stdout !== '832040\n') return fail('command line', 'run printed', fibonacci.stdout + fibonacci.stderr);
  const failed = await ran('tests/tasks/failure.sld');
  if (failed.status === 0 || failed.stdout !== '') return fail('command line', 'a fatal child panic must fail the run before starting queued siblings', failed.stdout + failed.stderr);
  const panicked = await ran('tests/programs/panic.sld');
  if (panicked.status !== 1) return fail('command line', 'a panic must exit with status 1', panicked.stderr);
  const trapped = await ran('tests/programs/traps.sld');
  return trapped.status === 2 || fail('command line', 'a trap must be status 2', trapped.stderr);
}

// An Any's TypeId describes its type's structure: reordering an enum's
// cases keeps the enum's representation and gives it a new identity.
async function typeIds() {
  const id = async (name, cases) => {
    const source = `build/tests/type-ids/${name}.sld`;
    await mkdir(join(root, 'build/tests/type-ids'), {recursive: true});
    await writeFile(join(root, source), `(import (snail core base))\n(enum Phase ${cases})\n(define (main) (→ Unit) (match (Any (Day)) (_ (unit))))\n`);
    const wat = await command(snail, ['wat', '--target', 'node', source]);
    return /\(struct\.new \$any \(i32\.const ([^)]*)\)/.exec(wat.stdout)?.[1] ?? fail('type ids', 'no TypeId in the text', wat.stderr);
  };
  const dayNight = await id('day-night', '(Day) (Night)'), nightDay = await id('night-day', '(Night) (Day)');
  return dayNight !== false && nightDay !== false && (dayNight !== nightDay || fail('type ids', "unchanged by reordering an enum's cases", dayNight));
}

// The native async file provider, where io_uring is available.
async function asyncFiles() {
  const built = await build('tests/async-files/main.sld');
  if (built.failure) return fail('async files', 'compile failed', built.failure);
  const output = printed(await run(built, join(root, 'build/tests/async-data')));
  if (output === 'SKIP: native async file provider unavailable\n') {
    console.log('async files: io_uring unavailable; native integration skipped');
    return true;
  }
  return output === await readFile(join(root, 'tests/async-files/main.out'), 'utf8') || fail('async files', 'wrong output', output);
}

// The toolchain's runtime assembles in-process: a tool linked with it turns
// a program's text into a module and links it, which must print what the
// program prints, and names the line and column of broken text.
async function toolchainAssembler() {
  const directory = join(root, 'build/tests/toolchain');
  await mkdir(directory, {recursive: true});
  const wat = await command(snail, ['wat', '--target', 'node', 'examples/fibonacci.sld']);
  if (wat.status !== 0) return fail('toolchain assembler', 'compile failed', wat.stderr);
  await writeFile(join(directory, 'fibonacci.wat'), wat.stdout);
  const tool = await build('tests/toolchain/assemble.sld', 'node');
  if (tool.failure) return fail('toolchain assembler', 'compile failed', tool.failure);
  const [, runtime] = (await command(join(root, 'scripts/bootstrap'), [])).stdout.split('\n');
  const assembled = printed(await run(tool, join(directory, 'fibonacci.wat'), join(directory, 'fibonacci.wasm'), runtime, join(directory, 'linked.wasm')));
  if (assembled !== 'assembled the program\nlinked the program after a failed link\nbroken text names its line and column\n') {
    return fail('toolchain assembler', 'assembling failed', assembled);
  }
  const ran = printed(await node(runner, join(directory, 'linked.wasm')));
  return ran === await readFile(join(root, 'examples/fibonacci.out'), 'utf8') || fail('toolchain assembler', 'the module printed', ran);
}

// The book's preprocessor, tools/highlight-book.scm, on a small book.
async function bookHighlighter() {
  const built = await build('tools/highlight-book.scm', 'node');
  if (built.failure) return fail('book highlighter', 'compile failed', built.failure);
  const checked = await node(join(root, 'tests/highlight-book.mjs'), root, built.module);
  return checked.status === 0 || fail('book highlighter', 'failed', checked.stdout + checked.stderr);
}

// The command line must emit the same text on V8 and on wasmtime, the
// engines it runs on. The integer and GC subset the backend uses is
// deterministic by the spec; only NaN payloads could differ. The
// application fixture exercises classes, effects, tasks and serialization.
async function engineAgreement() {
  const [cli, runtime, toolchain] = (await command(join(root, 'scripts/bootstrap'), [])).stdout.split('\n');
  const arguments_ = ['wat', '--target', 'browser', 'tests/app-runtime/main.sld'];
  const v8 = await command(snail, arguments_);
  const other = await command(native, ['run-wasm', cli, root, runtime, toolchain, ...arguments_],
                              {env: {...process.env, SNAIL_ROOT: root, SNAIL_RUNTIME: runtime}});
  if (v8.status !== 0 || other.status !== 0) return fail('engine agreement', 'compile failed', v8.stderr + other.stderr);
  return v8.stdout === other.stdout || fail('engine agreement', 'V8 and wasmtime emit different text for the application fixture');
}

const checks = () => [
  commandLine,
  typeIds,
  asyncFiles,
  toolchainAssembler,
  bookHighlighter,
  fixture('host values', 'tests/host-values/main.sld', 'tests/host-values/check.mjs', 'node'),
  fixture('host boundary', 'tests/host-boundary/main.sld', 'tests/host-boundary/check.mjs', 'portable'),
  fixture('socket boundary', 'tests/socket-boundary/main.sld', 'tests/socket-boundary/check.mjs', 'node'),
  fixture('termination', 'tests/termination/main.sld', 'tests/termination/check.mjs', 'node'),
  fixture('app runtime', 'tests/app-runtime/main.sld', 'tests/app-runtime/check.mjs', 'browser'),
  ...['scripts', 'script-builds', 'script-run', 'script-failures', 'script-resources', 'embedding', 'launcher', 'lsp',
      'tree-sitter', 'vscode', 'tcp', 'udp', 'format-scheme', 'siegework/headless'].map(name => script(name)),
  script('udp', '--test-udp-no-try-send'),
  ...(wasmtime ? [engineAgreement] : []),
];

// ---- The run ----

// Each check in turn, `JOBS` at a time; a check that throws has failed.
async function runAll(cases) {
  let next = 0, passed = 0;
  const worker = async () => {
    while (next < cases.length) {
      const check = cases[next++];
      try { if (await check()) passed++; }
      catch (error) { fail(check.name || 'check', 'raised', error.stack ?? String(error)); }
    }
  };
  await Promise.all(Array.from({length: JOBS}, worker));
  return passed;
}

// What the suite's builds publish, removed so that no run adds to the last.
for (const output of ['build/examples', 'build/tests', 'build/tools', 'tests/programs/build', 'tests/host-boundary/build']) {
  await rm(join(root, output), {recursive: true, force: true});
}
const suites = (await Promise.all(['examples', 'tests/programs', 'tests/siegework', 'tests/hearsay'].map(programs))).flat();
const cases = [...suites, ...(selected.length ? [] : checks())];
const passed = await runAll(cases);
console.log(`${passed}/${cases.length} passed`);
process.exit(passed === cases.length ? 0 : 1);
