// CI partitions the existing correctness runners; each job owns its checkout.
import assert from 'node:assert/strict';
import {mkdirSync, mkdtempSync, readFileSync, writeFileSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const repository = dirname(dirname(fileURLToPath(import.meta.url)));
const readJSON = path => JSON.parse(readFileSync(path, 'utf8'));
const writeJSON = (path, value) => writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);

// ---- Complete deterministic partitions ----

function names(values, description) {
  assert(Array.isArray(values) && values.length > 0, `${description} must be nonempty`);
  assert(values.every(value => typeof value === 'string' && value.length && !value.startsWith('-')),
    `${description} must contain names, not options`);
  assert.equal(new Set(values).size, values.length, `duplicate ${description}`);
  return values;
}

function partition(kind, items, count) {
  assert(Number.isSafeInteger(count) && count > 0, 'partition count must be positive');
  // Manifest order groups cheap rejections together. Deal cases across jobs.
  return Array.from({length: Math.min(count, items.length)}, (_, index) => ({
    name: `${kind}-${index + 1}`, kind,
    items: items.filter((_, position) => position % Math.min(count, items.length) === index),
  }));
}

export function verifyPlan(plan, suites, cases) {
  names(plan.map(job => job.name), 'job names');
  for (const job of plan) {
    assert(['backend', 'integration'].includes(job.kind), `unknown job kind: ${job.kind}`);
    names(job.items, `${job.name} assignments`);
  }
  for (const [kind, expected] of [['backend', suites], ['integration', cases]]) {
    const assigned = plan.filter(job => job.kind === kind).flatMap(job => job.items);
    assert.deepEqual(assigned.toSorted(), expected.toSorted(), `${kind} coverage differs`);
  }
}

// Nine backend + eight integration + three host/public jobs fit 20 runners.
export function makePlan(suites, cases, backendCount = 9, integrationCount = 8) {
  names(suites, 'backend suites');
  names(cases, 'integration cases');
  assert(suites.includes('lofi-integration'), 'missing integration suite');
  const ordinary = suites.filter(suite => suite !== 'lofi-integration');
  names(ordinary, 'ordinary backend suites');
  const plan = [...partition('backend', ordinary, backendCount),
    ...partition('integration', cases, integrationCount)];
  verifyPlan(plan, ordinary, cases);
  return plan;
}

function currentPlan() {
  const suites = readJSON(join(repository, 'tests/backend-suites.json'));
  const cases = readJSON(join(repository, 'tests/lofi-integration/cases.json'));
  return makePlan(suites.map(suite => suite.name), cases.map(test => test.name));
}

// ---- Successful execution must cover the assigned work ----

export function verifyIntegration(directory, expected) {
  assert.deepEqual(readJSON(join(directory, 'selection.json')).cases, expected);
  const results = readJSON(join(directory, 'results.json'));
  assert.deepEqual(results.map(result => result.name), expected, 'completed cases differ');
  assert(results.every(result => result.passed === true), 'integration cases failed');
  assert.deepEqual(readJSON(join(directory, 'completion.json')),
    {completed: expected.length, failed: []});
}

function verifyBackend(directory, expected) {
  assert.deepEqual(readJSON(join(directory, 'selection.json')).suites, expected);
  assert.deepEqual(readJSON(join(directory, 'validation.json')).suites, expected);
}

function runJob(name) {
  const job = currentPlan().find(candidate => candidate.name === name);
  assert(job, `unknown CI job: ${name}`);
  const parent = join(repository, 'build/ci');
  mkdirSync(parent, {recursive: true});
  const directory = mkdtempSync(join(parent, `${name}-`));
  writeJSON(join(directory, 'job.json'), job);
  const script = job.kind === 'backend' ? 'test-backend' : 'test-lofi-integration';
  const start = performance.now();
  const result = spawnSync(join(repository, 'scripts', script),
    ['--output', directory, ...job.items], {cwd: repository, stdio: 'inherit'});
  writeJSON(join(directory, 'execution.json'), {status: result.status,
    signal: result.signal, error: result.error?.message, seconds: (performance.now() - start) / 1000});
  assert.equal(result.status, 0, `job failed; evidence: ${directory}`);
  if (job.kind === 'backend') verifyBackend(directory, job.items);
  else verifyIntegration(directory, job.items);
  console.log(`PASS ${name}: ${directory}`);
}

function main(arguments_) {
  if (arguments_.length === 1 && arguments_[0] === 'matrix') {
    const jobs = ['host', 'native', 'applications', ...currentPlan().map(job => job.name)];
    console.log(JSON.stringify({include: jobs.map(suite => ({suite}))}));
  } else if (arguments_.length === 2 && arguments_[0] === 'run') {
    runJob(arguments_[1]);
  } else {
    throw new Error('usage: node tests/ci.mjs matrix | run JOB');
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  main(process.argv.slice(2));
}
