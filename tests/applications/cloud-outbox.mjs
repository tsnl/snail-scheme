// No browser or game compilation is needed for the durable queue boundary.
import assert from 'node:assert/strict';
import {CloudOutbox} from '../../src/browser/cloud-outbox.mjs';

const manifest = {effects: {}, settings: {id: 'outbox-test', runMarker: 1, remoteHandlers: ['buy']},
  applications: [{owner: 'match', state: 'World', schema: 1,
    handlers: [{id: 'buy-id', binding: 'buy', payload: ['I32'], result: {}}]}]};
const client = 'old-client', epoch = 'colony-one', command = {handler: 'buy-id', args: [25]};
function storage() {
  const values = new Map();
  return {getItem: key => values.get(key) ?? null, setItem: (key, value) => values.set(key, value),
    removeItem: key => values.delete(key), values};
}
function fixture() { const saved = storage(); return {saved, outbox: new CloudOutbox(manifest, client, saved)}; }
const session = (next, extra = {}) => ({client, epoch, next, ...extra});

{
  const {saved, outbox} = fixture(); outbox.append(1, epoch, command);
  const restored = new CloudOutbox(manifest, client, saved);
  assert.deepEqual(restored.reconcile(session(1)).pending, outbox.pending);
  assert.deepEqual(restored.reconcile(session(2)).pending, []); // Response lost after commit.
  restored.acknowledge(restored.pending[0]); assert.equal(saved.getItem(restored.key), null);
  console.log('ok - unsent order survives reload; accepted sequence is not replayed; acknowledgement removes storage');
}
{
  const {saved, outbox} = fixture(); outbox.append(1, epoch, command); outbox.append(2, epoch, command);
  assert.deepEqual(outbox.reconcile(session(2)).pending.map(x => x.sequence), [2]);
  assert.equal(outbox.reconcile(session(1, {client: 'new-client'})).pending[0].client, 'new-client');
  assert.deepEqual(outbox.reconcile(session(2, {epoch: 'colony-two'})), {pending: [], discarded: 1});
  outbox.acknowledge(outbox.pending[0]);
  assert.throws(() => outbox.reconcile(session(1, {client: 'new-client'})), /lost this player history/);
  assert.ok(saved.getItem(outbox.key));
  console.log('ok - consumed prefix, first-session restart and stale-colony orders reconcile without renumbering history');
}
{
  const {saved, outbox} = fixture(); outbox.append(1, epoch, command);
  const original = saved.getItem(outbox.key);
  const incompatible = structuredClone(manifest); incompatible.applications[0].schema = 2;
  assert.throws(() => new CloudOutbox(incompatible, client, saved), /previous compatible package/);
  assert.equal(saved.getItem(outbox.key), original);
  const record = JSON.parse(original); record.pending.push({...record.pending[0], sequence: 3});
  saved.setItem(outbox.key, JSON.stringify(record));
  assert.throws(() => new CloudOutbox(manifest, client, saved), /gap/);
  assert.throws(() => outbox.reconcile(session(0)), /sequences disagree/);
  assert.throws(() => outbox.append(2, epoch, {handler: 'buy-id', args: ['25']}), /invalid typed payload/);
  assert.throws(() => outbox.append(3, epoch, command), /contiguous/);
  assert.throws(() => outbox.acknowledge({...outbox.pending[0]}), /does not match/);
  console.log('ok - incompatible protocol, sequence gaps, invalid payload and foreign acknowledgement retain the original queue');
}
{
  const {saved, outbox} = fixture();
  saved.setItem = () => { throw new Error('storage full'); };
  assert.throws(() => outbox.append(1, epoch, command), /storage full/);
  assert.equal(outbox.pending.length, 0); assert.equal(saved.getItem(outbox.key), null);
  console.log('ok - failed storage write admits no optimistic or network order');
}
{
  const {saved, outbox} = fixture(); outbox.append(1, epoch, command);
  saved.removeItem = () => { throw new Error('storage unavailable'); };
  assert.throws(() => outbox.acknowledge(outbox.pending[0]), /storage unavailable/);
  assert.equal(outbox.pending.length, 1); assert.ok(saved.getItem(outbox.key));
  assert.deepEqual(new CloudOutbox(manifest, client, saved).reconcile(session(2)).pending, []);
  console.log('ok - failed acknowledgement cleanup keeps the exact order recoverable without replay after reload');
}
