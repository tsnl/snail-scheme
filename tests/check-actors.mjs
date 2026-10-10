import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { readdir } from 'node:fs/promises';
import { spawn } from '../runtime/actors.mjs';
import { invoke, loadInstance } from '../runtime/actor-instance.mjs';

const artifact = process.argv[2];

// ---- Embedding ownership and the actual compiled codec ----

async function checkRoots() {
  const instance = await loadInstance(artifact);
  assert.equal(invoke(instance, '(value)'), '0'); // Initialize lazy runtime services.
  const baseline = instance.exports.awi_live_roots.value;
  assert.equal(instance.exports['scheme:method:macro'], undefined);
  for (let index = 0; index < 100; index++) {
    assert.equal(invoke(instance, '(echo #(1 "λ🐌\n" |a b|))'), '#(1 "λ🐌\\n" |a b|)');
    assert.equal(instance.exports.awi_live_roots.value, baseline);
  }
  assert.equal(invoke(instance, '(echo -9223372036854775808)'), '-9223372036854775808');
  assert.equal(invoke(instance, '(echo 9223372036854775807)'), '9223372036854775807');
  assert.equal(invoke(instance, '(shared)'), '#((1 2) (1 2))');
  assert.throws(() => instance.exports.actor_initialize(), WebAssembly.RuntimeError);
}

// ---- Independent actors and connection ownership ----

async function checkConnections() {
  const first = await spawn(artifact), second = await spawn(artifact);
  try {
    const left = first.connect(), right = first.connect(), other = second.connect();
    assert.deepEqual(await Promise.all([left.call('(add 3)'), other.call('(value)')]), ['3', '0']);
    assert.equal(await right.call('(value)'), '3');
    assert.equal(await right.call('(echo (set! count 99))'), '(|set!| |count| 99)');
    assert.equal(await right.call('(value)'), '3');
    const abandoned = assert.rejects(left.call('(add 5)'), /connection is closed/);
    left.close();
    await abandoned;
    assert.equal(await right.call('(value)'), '8'); // Closing did not cancel the queued call.
    assert.equal(await other.call('(echo #t); trailing comment'), '#t');
    await assert.rejects(left.call('(value)'), /connection is closed/);
    await assert.rejects(right.call({ value: 1 }), /S-expression text/);
    await assert.rejects(right.call(' '.repeat(65537)), /65536/);
    assert.equal(await right.call('(value)'), '8');
  } finally { await first.stop(); await second.stop(); }
}

async function checkFailure(call) {
  const actor = await spawn(artifact);
  try {
    const first = actor.connect(), second = actor.connect();
    const outcomes = await Promise.allSettled([first.call(call), second.call('(value)')]);
    assert.deepEqual(outcomes.map(outcome => outcome.status), ['rejected', 'rejected']);
    assert.throws(() => actor.connect());
    await assert.rejects(first.call('(value)'), /connection is closed/);
  } finally { await actor.stop(); }
}

// A Scheme infinite loop monopolizes its worker, but cannot block its supervisor
// or another worker. Termination must settle its connections without a response.
async function checkStop() {
  const actor = await spawn(artifact), survivor = await spawn(artifact);
  const result = assert.rejects(actor.connect().call('(spin)'), /actor stopped/);
  try {
    await delay(20);
    assert.equal(await survivor.connect().call('(add 7)'), '7');
    const stopped = actor.stop();
    assert.equal(actor.stop(), stopped);
    await stopped;
    await result;
    assert.throws(() => actor.connect(), /actor stopped/);
  } finally { await actor.stop(); await survivor.stop(); }
}

// Repeated retirement must not retain the subprocess's WASI trace descriptors.
async function checkRetirement() {
  const retire = async () => {
    const actor = await spawn(artifact);
    try { await actor.connect().call('(value)'); }
    finally { await actor.stop(); }
  };
  await retire(); // Warm up Node's parent-side process machinery.
  const before = process.platform === 'linux' ? (await readdir('/proc/self/fd')).length : null;
  for (let index = 0; index < 10; index++) await retire();
  if (before !== null) assert.equal((await readdir('/proc/self/fd')).length, before);
}

await checkRoots();
await checkConnections();
for (const call of ['(fail)', '(unknown)', '(add)', '(nonprocedure)', '(cycle)',
  '(procedure)', '(empty)', '(many)', '(echo 1.5)', '(echo)', '(echo 1) (echo 2)', '(']) {
  await checkFailure(call);
}
await checkStop();
await checkRetirement();
await assert.rejects(spawn(`${artifact}.missing`), /actor exited/);
console.log('actor isolation, S-expression calls, root ownership, and cleanup passed');
