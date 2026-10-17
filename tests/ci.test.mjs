import assert from 'node:assert/strict';
import {mkdtempSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {makePlan, verifyPlan, verifyIntegration} from './ci.mjs';

const suites = ['one', 'lofi-integration', 'two', 'three'];
const cases = ['a', 'b', 'c', 'd', 'e'];

test('uneven partitions preserve every suite and case exactly once', () => {
  const plan = makePlan(suites, cases, 2, 3);
  assert.deepEqual(plan.map(job => job.items), [['one', 'three'], ['two'],
    ['a', 'd'], ['b', 'e'], ['c']]);
  assert.equal(makePlan(['one', 'lofi-integration'], ['a']).length, 2);
});

test('malformed or ambiguous work cannot produce a matrix', () => {
  assert.throws(() => makePlan([], cases), /nonempty/);
  assert.throws(() => makePlan(suites, []), /nonempty/);
  assert.throws(() => makePlan(['one'], cases), /missing integration/);
  assert.throws(() => makePlan(suites, ['a', 'a']), /duplicate/);
  assert.throws(() => makePlan([...suites, 'one'], cases), /duplicate/);
  assert.throws(() => makePlan(suites, ['--output']), /not options/);
  assert.throws(() => makePlan(suites, cases, 0), /positive/);
  assert.throws(() => makePlan(suites, cases, 1, 1.5), /positive/);
});

test('coverage verification detects omissions, extra work, duplicates and empty jobs', () => {
  for (const damage of [
    plan => plan.pop(),
    plan => plan[0].items.push('unexpected'),
    plan => plan[1].items.push('one'),
    plan => { plan[0].items = []; },
    plan => { plan[1].name = plan[0].name; },
  ]) {
    const plan = makePlan(suites, cases, 2, 3);
    damage(plan);
    assert.throws(() => verifyPlan(plan, ['one', 'two', 'three'], cases));
  }
});

test('a selected case is insufficient without matching successful completion', () => {
  const directory = mkdtempSync(join(tmpdir(), 'lofi-ci-records-'));
  const write = (name, value) => writeFileSync(join(directory, `${name}.json`), JSON.stringify(value));
  try {
    write('selection', {cases: ['a', 'b']});
    write('completion', {completed: 2, failed: []});
    write('results', [{name: 'a', passed: true}, {name: 'b', passed: true}]);
    verifyIntegration(directory, ['a', 'b']);
    for (const broken of [[{name: 'a', passed: true}],
      [{name: 'a', passed: true}, {name: 'a', passed: true}],
      [{name: 'a', passed: true}, {name: 'b', passed: false}]]) {
      write('results', broken);
      assert.throws(() => verifyIntegration(directory, ['a', 'b']));
    }
  } finally {
    rmSync(directory, {recursive: true});
  }
});
