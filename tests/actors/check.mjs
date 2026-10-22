// Real Wasm: typed local/wire messages, independent actors and run-to-empty.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {fileURLToPath} from 'node:url';
import {createHost} from '../../src/app/actors.mjs';
import {createAssembler} from '../../scripts/assemble.mjs';

const file = resolve(process.argv[2]);
const source = file.endsWith('.json') ? {manifest: file, read: path => readFile(resolve(dirname(file), path))} :
  {module: await WebAssembly.compile(await readFile(file))};
const assemble = await createAssembler(await readFile(process.argv[3]));
const {instance: inspector} = await WebAssembly.instantiate(assemble(await readFile(new URL('./inspect.wat', import.meta.url), 'utf8')));

function fixture(roles, {transport = 'local', programs = {}, gate = Promise.resolve()} = {}) {
  const observed = [], traced = [], endpoint = {id: 0, arrivals: []};
  const host = createHost({programs: {...Object.fromEntries(Object.keys(roles).map(name => [name, () => ({...source, transport})])), ...programs},
    imports: name => ({'snail.test': {role: () => roles[name], target: () => { endpoint.arrivals.push(name); return endpoint.id; }, trace: value => traced.push(inspector.exports.payload(value)),
                                    observe: value => observed.push([name, value]),
                                    wait: new WebAssembly.Suspending(() => gate)}})});
  return {host, observed, traced, endpoint};
}

async function until(test) {
  for (let attempt = 0; attempt < 3000; attempt++) {
    if (test()) return;
    await delay(10);
  }
  assert.fail('the actor did not reach its expected suspension');
}

async function checkPing(transport) {
  const {host, observed, traced} = fixture({bootstrap: 0, server: 1}, {transport});
  assert.deepEqual(await host.run(['bootstrap']), []);
  assert.deepEqual(observed, [['bootstrap', 42n]]);
  assert.equal(host.size, 0);
  assert.equal(traced[0] === traced[1], transport === 'local', 'direct requests preserve GC identity; wire requests reconstruct');
  assert.equal(traced[2] === traced[3], transport === 'local', 'the same identity rule applies to replies');
}

async function checkQueued(role) {
  const gate = Promise.withResolvers();
  const {host, observed, endpoint} = fixture({server: role, a: 10, b: 10}, {gate: gate.promise});
  endpoint.id = await host.spawn('server');
  const done = host.run(['a', 'b']);
  await until(() => endpoint.arrivals.length === 2);
  assert.equal(host.size, 3);
  assert.deepEqual(observed, []);
  gate.resolve();
  const errors = await done;
  if (role === 8) {
    assert.deepEqual(errors, []);
    assert.deepEqual(observed, endpoint.arrivals.map(name => [name, 42n]), 'queued callers receive exactly their response in arrival order');
  } else {
    assert.deepEqual(errors.map(({name}) => name).sort(), ['a', 'b'], 'normal server exit rejects current and queued requests');
  }
}

async function checkConcurrency() {
  const gate = Promise.withResolvers();
  const {host, observed, traced} = fixture({bootstrap: 0, server: 2, other: 9}, {gate: gate.promise});
  let drained = false;
  const done = host.run(['bootstrap', 'other']).then(errors => { drained = true; return errors; });
  await until(() => observed.length === 1 && traced.length === 2);
  assert.deepEqual(observed, [['other', 9n]], 'a waiting actor does not block another entry');
  assert.equal(host.size, 2, 'both the requester and the waiting server remain alive');
  assert.equal(drained, false);
  gate.resolve();
  assert.deepEqual(await done, []);
  assert.deepEqual(observed.at(-1), ['bootstrap', 42n]);
}

async function checkChild() {
  const gate = Promise.withResolvers();
  const {host, observed} = fixture({parent: 4, child: 5}, {gate: gate.promise});
  let drained = false;
  const done = host.run(['parent']).then(errors => { drained = true; return errors; });
  await until(() => observed.length === 1);
  assert.deepEqual(observed, [['parent', 4n]]);
  assert.equal(host.size, 1, 'the child outlives its parent');
  assert.equal(drained, false);
  gate.resolve();
  assert.deepEqual(await done, []);
  assert.deepEqual(observed.at(-1), ['child', 5n]);
}

async function checkStarting() {
  const loaded = Promise.withResolvers();
  const {host, observed} = fixture({slow: 9, other: 9}, {programs: {slow: () => loaded.promise}});
  let drained = false;
  const done = host.run(['slow', 'other']).then(errors => { drained = true; return errors; });
  await until(() => observed.length === 1);
  assert.deepEqual(observed, [['other', 9n]]);
  assert.equal(host.size, 1, 'a loading actor reserves its lifetime immediately');
  assert.equal(drained, false);
  loaded.resolve(source);
  assert.deepEqual(await done, []);
  assert.deepEqual(observed.at(-1), ['slow', 9n]);
}

async function checkFailures() {
  const failed = fixture({bootstrap: 0, server: 3});
  const errors = await failed.host.run(['bootstrap']);
  assert.deepEqual(errors.map(error => error.name).sort(), ['bootstrap', 'server'], 'server failure settles its waiting requester');
  assert.equal(failed.host.size, 0);
  const mismatch = fixture({bootstrap: 6, server: 1});
  const mismatched = await mismatch.host.run(['bootstrap']);
  assert.equal(mismatched.length, 2);
  assert.ok(mismatched.every(({error}) => /different protocol/.test(error.message)));
  const unsupported = createHost({programs: {server: () => source}});
  await assert.rejects(unsupported.spawn('server'), /this host does not provide snail.test/);
  assert.equal((await unsupported.drain()).length, 1);
  assert.equal(unsupported.size, 0);
}

async function checkNodeProcess(mode) {
  const child = spawn(process.execPath, [fileURLToPath(new URL('./node.mjs', import.meta.url)), file, mode]);
  const exited = once(child, 'exit');
  const stopped = () => child.exitCode !== null || child.signalCode !== null;
  let output = '';
  child.stdout.on('data', bytes => { output += bytes; });
  child.stderr.on('data', bytes => { output += bytes; });
  try {
    await until(() => output.includes('waiting') || stopped());
    if (mode === 'idle') { await delay(100); assert.equal(stopped(), false, output); }
    else { await until(stopped); assert.equal(child.exitCode, 0, output); assert.match(output, /reply:42/); }
  } finally { child.kill(); await exited; }
}

await checkPing('local');
await checkPing('wire');
await checkConcurrency();
await checkChild();
await checkStarting();
await checkQueued(8);
await checkQueued(11);
await checkFailures();
await checkNodeProcess('idle');
await checkNodeProcess('done');
console.log('actors: local/wire requests, concurrency, spawning, drain and failures passed');
