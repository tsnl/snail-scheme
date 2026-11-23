// Build a real importing project outside the checkout. Only the producer
// can see the Ink inputs and reference compiler. The published program
// must keep running if a subsequent generation fails.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {copyFile, cp, mkdtemp, readFile, readdir, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {promisify} from 'node:util';

const exec = promisify(execFile);
const root = resolve(process.argv[2]);
const workspace = await mkdtemp(join(tmpdir(), 'snail Ink '));
const lib = join(workspace, 'src', 'radio');
const recipe = join(lib, 'lines.sld');
const source = join(lib, 'pickup.ink');
const section = join(lib, 'parts', 'till.ink');
const script = join(workspace, 'read.scm');

async function build() {
  const {stdout} = await exec(join(root, 'snail-scheme'), ['build', '--target', 'node', script], {cwd: workspace});
  return stdout.trim();
}

async function run(directory) {
  const {stdout} = await exec(process.execPath, [join(directory, 'main.mjs')],
    {cwd: tmpdir(), env: {...process.env, PATH: ''}});
  return stdout;
}

async function rejects(text, pattern) {
  await writeFile(source, text);
  await assert.rejects(build, error => {
    assert.match(error.stderr, pattern);
    return true;
  });
}

try {
  await Promise.all([
    cp(join(root, 'tests/ink/src'), join(workspace, 'src'), {recursive: true}),
    copyFile(join(root, 'tests/ink/read.scm'), script),
  ]);
  const [story, till, definition] = await Promise.all([source, section, recipe].map(path => readFile(path, 'utf8')));
  const original = await build();
  assert.equal(await run(original), 'pickup Meter?\nTip start.1 Total 1.\nSkip start.2 Total 0.\n');

  // An edit to either linked file is picked up by an ordinary build.
  await writeFile(source, story.replace('Meter?', 'Receipt?'));
  assert.equal(await run(await build()), 'pickup Receipt?\nTip start.1 Total 1.\nSkip start.2 Total 0.\n');
  await writeFile(section, till.replace('Total', 'Fare'));
  const latest = await build();
  const expected = 'pickup Receipt?\nTip start.1 Fare 1.\nSkip start.2 Fare 0.\n';
  assert.equal(await run(latest), expected);
  assert.equal(await readFile(recipe, 'utf8'), definition);
  assert.deepEqual((await readdir(lib)).sort(), ['lines.sld', 'parts', 'pickup.ink']);

  await rejects('-> again\n=== again ===\nWait? # id:again\n+ [Repeat] -> again\n', /cyclic passage/);
  await rejects('Roll {RANDOM(1, 20)}\n-> END\n', /random output/);
  await rejects('EXTERNAL cue()\n{cue()}\n-> END\n', /EXTERNAL cue/);
  await rejects('Wait?\n+ [A] -> END\n+ [B] -> END\n+ [C] -> END\n', /exceeds 3 turns/);
  await rejects('-> missing_knot\n', /missing_knot/);
  await rejects('INCLUDE parts/missing.ink\n-> END\n', /parts\/missing\.ink/);
  await writeFile(section, till.replace('{fare}.', '{fare}. # id:till'));
  await rejects(story, /save id names different dialogue states/);
  await rm(section);
  await assert.rejects(build, error => {
    assert.match(error.stderr, /till\.ink/);
    return true;
  });
  assert.equal(await run(latest), expected);
  console.log('Ink recipes rebuilt linked stories and includes, preserved choice histories, and kept the last good build.');
} finally {
  await rm(workspace, {recursive: true, force: true});
}
