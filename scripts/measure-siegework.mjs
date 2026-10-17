// Measure the shipped build unchanged, or decorate a private loader view.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {closeSync, mkdirSync, openSync, readFileSync, writeFileSync} from 'node:fs';
import {cpus, loadavg, release, totalmem} from 'node:os';
import {dirname, join, resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const repository = dirname(dirname(fileURLToPath(import.meta.url)));
const json = (path, value) => writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

// ---- Private instrumentation ----

function replaceOnce(source, before, after) {
  assert.equal(source.split(before).length, 2, `instrumentation site changed: ${before}`);
  return source.replace(before, after);
}

function decorate(source, expression, name) {
  const opening = expression.indexOf(' ');
  const call = `((chromium-trace "${name}" ${expression.slice(1, opening)})`;
  return replaceOnce(source, expression, call + expression.slice(opening));
}

function compilerOverlay(source) {
  source = replaceOnce(source, '   (lofi artifact)',
    '   (lofi artifact)\n   (wasm-native chromium-trace)');
  for (const [call, name] of [
    ['(resolve-library-map libraries)', 'lofi.resolve'],
    ['(infer-program (append items trailing-items)', 'lofi.check'],
    ['(prepare-entry-generation core checked)', 'lofi.specialize'],
    ['(emit-artifact (strict-core->wasm program)', 'lofi.artifact'],
    ['(strict-core->wasm program)', 'lofi.emit'],
  ]) source = decorate(source, call, name);
  return source;
}

function artifactOverlay(source) {
  source = replaceOnce(source, '   (scheme file)',
    '   (scheme file)\n   (scheme process-context)');
  source = replaceOnce(source, '(string-append directory "/compile.trace.json")',
    '(string-append (get-environment-variable "SNAIL_PROFILE_DIRECTORY")\n' +
    '                         "/artifact-" (symbol->string (entry-export entry)) ".trace.json")');
  source = decorate(source, '(write-wasm module port)', 'lofi.write-wasm');
  return decorate(source, '(file-bytes output)', 'lofi.read-artifact');
}

function prepareOverlay(directory) {
  const overlay = join(directory, 'overlay');
  const sources = {};
  for (const [file, instrument] of [
    ['lofi/compiler/bootstrap.sld', compilerOverlay],
    ['lofi/artifact.sld', artifactOverlay],
  ]) {
    const original = readFileSync(join(repository, 'src', file), 'utf8');
    const modified = instrument(original);
    mkdirSync(dirname(join(overlay, file)), {recursive: true});
    writeFileSync(join(overlay, file), modified);
    sources[file] = {original: hash(original), instrumented: hash(modified)};
  }
  json(join(directory, 'instrumentation.json'), sources);
  return overlay;
}

// ---- Retained execution evidence ----

function capture(command, args) {
  const result = spawnSync(command, args, {cwd: repository, encoding: 'utf8'});
  assert.ifError(result.error);
  assert.equal(result.status, 0, `${command}: ${result.stderr}`);
  return result.stdout.trim();
}

function sourceIdentity() {
  return {
    commit: capture('git', ['rev-parse', 'HEAD']),
    status: capture('git', ['status', '--porcelain=v1', '--untracked-files=all']),
    trackedDiffSha256: hash(capture('git', ['diff', 'HEAD', '--binary'])),
    runnerSha256: hash(readFileSync(fileURLToPath(import.meta.url))),
  };
}

function runMetadata(mode, command, environment, source) {
  return {mode, source, command, tools: tools(environment),
    environment: Object.fromEntries(['BINARYEN_CORES', 'CHIBI', 'WASM_AS', 'WASM_OPT',
      'WASM_DIS', 'WASM_MERGE', 'SNAIL_PROFILE_DIRECTORY'].map(key => [key, environment[key] ?? null])),
    host: {platform: process.platform, release: release(), architecture: process.arch,
      cpu: cpus()[0]?.model, logicalCPUs: cpus().length, memoryBytes: totalmem()}};
}

function tools(environment) {
  return Object.fromEntries([
    ['chibi', environment.CHIBI ?? 'chibi-scheme', '-V'],
    ['wasmAs', environment.WASM_AS ?? 'wasm-as', '--version'],
    ['wasmOpt', environment.WASM_OPT ?? 'wasm-opt', '--version'],
    ['node', process.execPath, '--version'],
  ].map(([name, command, flag]) => [name, {command, version: capture(command, [flag])}]));
}

function buildCommand(overlay, directory, environment) {
  return [environment.CHIBI ?? 'chibi-scheme',
    '-I', join(repository, 'bootstrap'), '-I', join(repository, 'wasm-native/scheme'),
    // Chibi searches the last -I directory first.
    ...(overlay ? ['-I', overlay] : []),
    join(repository, 'apps/siegework/build.scm'), repository, join(directory, 'app')];
}

function execute(command, directory, environment) {
  const log = openSync(join(directory, 'build.log'), 'wx');
  const before = {time: new Date().toISOString(), load: loadavg()};
  const start = performance.now();
  try {
    const result = spawnSync(command[0], command.slice(1), {
      cwd: repository, env: environment, stdio: ['ignore', log, log],
    });
    return {before, seconds: (performance.now() - start) / 1000,
      status: result.status, signal: result.signal, error: result.error?.message,
      after: {time: new Date().toISOString(), load: loadavg()}};
  } finally {
    closeSync(log);
  }
}

function traceDurations(path) {
  const durations = {};
  for (const event of JSON.parse(readFileSync(path, 'utf8'))) {
    if (event.ph === 'X') durations[event.name] = (durations[event.name] ?? 0) + event.dur / 1e6;
  }
  return durations;
}

function artifactEvidence(directory) {
  return Object.fromEntries(['shader.wasm', 'simulation.wasm'].map(name => {
    const bytes = readFileSync(join(directory, 'app', name));
    return [name, {bytes: bytes.length, sha256: hash(bytes)}];
  }));
}

function profileEvidence(directory) {
  const phases = traceDurations(join(directory, 'app/build.trace.json'));
  for (const name of ['lofi.resolve', 'lofi.check', 'lofi.specialize', 'lofi.emit', 'lofi.artifact']) {
    assert(name in phases, `missing phase ${name}; private loader instrumentation was not used`);
  }
  return {compiler: phases, artifacts: Object.fromEntries(
    ['shader-entry', 'application-entry'].map(entry =>
      [entry, traceDurations(join(directory, `artifact-${entry}.trace.json`))]))};
}

// ---- One sample per invocation; repeat samples sequentially ----

function main(args) {
  assert(args.length === 2 && ['baseline', 'profile'].includes(args[0]),
    'usage: node scripts/measure-siegework.mjs baseline|profile NEW-OUTPUT-DIRECTORY');
  const [mode, output] = args;
  const directory = resolve(output);
  mkdirSync(directory); // Refuse to overwrite an existing run or create missing parents.
  const environment = {...process.env, BINARYEN_CORES: process.env.BINARYEN_CORES ?? '1'};
  if (mode === 'profile') environment.SNAIL_PROFILE_DIRECTORY = directory;
  const overlay = mode === 'profile' ? prepareOverlay(directory) : undefined;
  const command = buildCommand(overlay, directory, environment);
  const before = sourceIdentity();
  writeFileSync(join(directory, 'source.diff'), capture('git', ['diff', 'HEAD', '--binary']));
  json(join(directory, 'input.json'), runMetadata(mode, command, environment, before));
  const result = execute(command, directory, environment);
  json(join(directory, 'execution.json'), result);
  assert.equal(result.status, 0, `build failed; consult ${join(directory, 'build.log')}`);
  assert.deepEqual(sourceIdentity(), before, 'sources changed during the build');
  const evidence = {kind: mode === 'baseline' ? 'wall-time sample' : 'instrumented diagnostic',
    artifacts: artifactEvidence(directory), ...(overlay ? {traces: profileEvidence(directory)} : {})};
  json(join(directory, 'result.json'), evidence);
  console.log(`${mode}: ${result.seconds.toFixed(3)} seconds; evidence: ${directory}`);
}

main(process.argv.slice(2));
