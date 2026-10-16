import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {existsSync, readFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {openCompilerService} from '../../src/snail-lofi/compiler-service.mjs';

const directory = process.argv[2];
const api = scope => scope.providers.get('lofi.compiler').exports;
function text(functions, value) {
  let token = functions['text-empty']();
  for (const character of value) token = functions['text-character'](token, character.codePointAt(0));
  return token;
}
function key(functions, names) {
  return names.reduceRight((tail, name) => functions['list-text'](text(functions, name), tail), functions['list-empty']());
}
function failure(functions, result) {
  assert.equal(functions['result-ok'](result), 0);
  let message = '';
  for (let i = 0n; i < functions['error-length'](result); ++i)
    message += String.fromCodePoint(functions['error-character'](result, i));
  return message;
}
function success(functions, result) {
  assert.equal(functions['result-ok'](result), 1);
  return functions['result-value'](result);
}

// ---- Compiler ownership checks are independent of scalar bit representations ----

const first = openCompilerService(), second = openCompilerService();
try {
  const left = api(first), right = api(second), foreign = success(right, right['map-empty']());
  assert.match(failure(left, left['map-primitives'](foreign)), /foreign compiler session/);
  assert.match(failure(left, left['map-primitives'](text(left, 'wrong kind'))), /expected compiler map/);
  assert.throws(() => left['scalar-Bool'](2), /canonical/);
  assert.throws(() => left['scalar-Char'](0xd800), /Unicode scalar/);
  const map = success(left, left['map-empty']());
  const ownedBuilder = second.providers.get('lofi.builder').exports;
  assert.match(failure(left, left['map-built'](map, key(left, ['wrong']), ownedBuilder['root-scope']())), /foreign library builder/);
} finally { first.close(); second.close(); }

// ---- Host loss invalidates compiler maps, while copied artifacts remain usable ----

process.env.LOFI_SERVICE_TEST_HOST = join(directory, 'host.json');
let runtimeToken, callbacks = 0;
const hook = new WebAssembly.Instance(new WebAssembly.Module(readFileSync(join(directory, 'reentry.wasm'))), {host: {
  callback() {
    callbacks++;
    assert.throws(() => scope.close(), /already executing/);
    if (runtimeToken !== undefined)
      assert.match(failure(api(scope), api(scope)['close-instance'](runtimeToken)), /already executing/);
  },
}});
const scope = openCompilerService({timeout: 3000,
  chibi: fileURLToPath(new URL('../target/debug/chibi-probe', import.meta.url)),
  providerSets: new Map([['hooks', new Map([['reentry', hook]])]])});
const host = JSON.parse(readFileSync(process.env.LOFI_SERVICE_TEST_HOST, 'utf8'));
delete process.env.LOFI_SERVICE_TEST_HOST;
try {
  const functions = api(scope), map = success(functions, functions['map-empty']()), name = key(functions, ['survivor']);
  const libraries = success(functions, functions['map-source'](map, name, text(functions, 'owned.lofi'),
    text(functions, '(define-library (survivor) (export main) (begin '
      + '(define-extern callback "reentry" "callback" (-> Unit)) (callback) '
      + '(def main (-> I32) (lambda () (begin (callback) 42)))))')));
  const artifact = success(functions, functions.compile(libraries, name, text(functions, 'main')));
  process.kill(host.pid, 'SIGKILL');
  const dead = failure(functions, functions['map-empty']());
  assert.match(dead, /timed out/);
  assert.equal(failure(functions, functions['map-primitives'](libraries)), dead);
  const code = success(functions, functions.load(artifact));
  runtimeToken = success(functions, functions.instantiate(code, text(functions, 'hooks')));
  const value = success(functions, functions.invoke(runtimeToken, functions['list-empty']()));
  assert.equal(functions['value-I32'](value), 42);
  assert.equal(callbacks, 2, 'scope closure is rejected before release during both initialization and invocation');
  assert.equal(existsSync(host.directory), false, 'failed host process and FIFO directory are released');
} finally { scope.close(); }
assert.equal(existsSync(host.directory), false);
console.log('PASS foreign/wrong-kind handles, compiler process loss, artifact ownership and deterministic scope cleanup');

// ---- Startup and progress deadlines stop even a TERM-ignoring process group ----

function running(pid) {
  try {
    return !/^[ZX]/.test(execFileSync('ps', ['-o', 'stat=', '-p', String(pid)], {encoding: 'utf8'}).trim());
  } catch (failure) { if (failure.status === 1) return false; throw failure; }
}

for (const mode of ['stall-start', 'noisy-start', 'stall-request', 'noisy-request', 'ignore-close']) {
  process.env.LOFI_SERVICE_TEST_HOST = join(directory, `${mode}.json`);
  process.env.LOFI_SERVICE_TEST_MODE = mode;
  const options = {chibi: fileURLToPath(new URL('../target/debug/chibi-adversary', import.meta.url)), timeout: 300};
  const start = Date.now();
  if (mode.endsWith('start')) {
    assert.throws(() => openCompilerService(options), /timed out\nowned host diagnostic sentinel/);
  } else {
    const owned = openCompilerService(options);
    try {
      if (mode === 'ignore-close') {
        const processes = JSON.parse(readFileSync(process.env.LOFI_SERVICE_TEST_HOST, 'utf8'));
        process.kill(-processes.pid, 'SIGTERM');
        assert(running(processes.pid) && running(processes.descendant));
      } else assert.match(failure(api(owned), api(owned)['map-empty']()), /timed out/);
    } finally { owned.close(); }
  }
  assert(Date.now() - start < 4000, `${mode} exceeded its timeout and cleanup budget`);
  const processes = JSON.parse(readFileSync(process.env.LOFI_SERVICE_TEST_HOST, 'utf8'));
  assert(!running(processes.pid) && !running(processes.descendant), `${mode} left an owned process running`);
  assert(!existsSync(processes.directory), `${mode} left its transport directory`);
  await new Promise(resolve => setTimeout(resolve, 20));
  assert.throws(() => process.kill(processes.pid, 0), {code: 'ESRCH'}, 'Node reaps its direct child');
}
delete process.env.LOFI_SERVICE_TEST_HOST;
delete process.env.LOFI_SERVICE_TEST_MODE;
assert.throws(() => openCompilerService({chibi: '/absent/lofi-compiler'}), /could not start Chibi compiler/);
console.log('PASS startup/streaming deadlines, TERM-ignoring leader and descendant cleanup, and child reaping');
