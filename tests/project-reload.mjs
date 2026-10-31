// Run a browser target from snail dev in Node through the browser host's
// loader and application runtime. The normal suite executes live relinking
// and state handover even when Chromium is unavailable.
import assert from 'node:assert/strict';
import {cp, mkdtemp, readFile, realpath, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {screenImports} from '../host/browser/host.mjs';
import {createRuntime, applicationEntry} from '../host/browser/runtime.mjs';
import {createWasi, linkProgram, relinkProgram, runProgram} from '../host/browser/load.mjs';
import {startDevelopment} from './development-service.mjs';

const root = process.argv[2];
const directory = await realpath(await mkdtemp(join(tmpdir(), 'snail-project-reload-')));
const app = join(directory, 'counter'), source = join(app, 'main.sld');
await cp(join(root, 'tests/apps/counter'), app, {recursive: true});

// Every read stays in the accepted generation, including reads made after
// another build publishes. This is the base the service gives its pages.
async function published(status) {
  const target = status.published.targets.find(target => target.name === 'site');
  const manifest = new URL(`.snail/builds/${status.id}/modules.json`, target.url).href;
  const read = async file => {
    const response = await fetch(new URL(file, manifest));
    assert.equal(response.status, 200, file);
    return new Uint8Array(await response.arrayBuffer());
  };
  return {id: status.id, target, manifest, read, modules: JSON.parse(new TextDecoder().decode(await read(manifest))).modules};
}

async function linkPage(build) {
  const page = {build, widgets: [], runtime: createRuntime()};
  const screen = screenImports({hasBatch: () => false, draw() {}}, {has: () => true},
    {update: panels => { page.widgets = panels.flatMap(panel => panel.widgets); }});
  const wasi = createWasi({print: (fd, line) => console.log(line)});
  page.program = await linkProgram(build.read, build.manifest, wasi,
    {...page.runtime.imports, 'snail.runtime.browser.screen': screen});
  runProgram(page.program);
  await page.runtime.start(applicationEntry(page.program)).ready.promise;
  return page;
}

async function relink(page, build) {
  const changed = build.modules.find((entry, index) => {
    const old = page.build.modules[index];
    return entry.name !== old?.name || entry.file !== old?.file;
  });
  assert.equal(changed.name, 'main', 'only the program changes');
  const {state, saved} = await page.runtime.stop();
  const program = await relinkProgram(page.program, changed.name, build.manifest, build.read);
  for (const {name} of build.modules.slice(0, -1)) {
    assert.equal(program.linked.get(name), page.program.linked.get(name), name);
  }
  const boot = await page.runtime.start(applicationEntry(program), state, {restore: saved}).ready.promise;
  assert.equal(boot, 0, 'the unchanged state type is adopted directly');
  Object.assign(page, {program, build});
}

const text = (page, key) => page.widgets.find(entry => entry.key === key)?.text;
const edit = async (before, after) => writeFile(source, (await readFile(source, 'utf8')).replace(before, after));
const service = await startDevelopment(root, app);
let page;
try {
  page = await linkPage(await published(await service.settled(0)));
  page.runtime.send(9, 1);
  page.runtime.send(9, 1);
  await service.until(() => text(page, 'count') === '2', 'two presses');
  assert.equal(text(page, 'greeting'), 'hello');

  await edit('"hello"', '"hello again"');
  const next = await published(await service.settled(page.build.id));
  assert.equal(next.target.compiled, 1, 'a function body edit reuses the libraries');
  await relink(page, next);
  assert.deepEqual([text(page, 'greeting'), text(page, 'count')], ['hello again', '2']);

  await edit('"hello again"', '5');
  const failed = await service.settled(next.id, 'failed');
  assert.equal(failed.published.targets.find(target => target.name === 'site').directory, next.target.directory);
  page.runtime.send(9, 1);
  await service.until(() => text(page, 'count') === '3', 'the old program to keep running after a failed build');

  await edit('(define greeting 5)', '(define greeting "repaired")');
  await relink(page, await published(await service.settled(failed.id)));
  assert.deepEqual([text(page, 'greeting'), text(page, 'count')], ['repaired', '3']);
  console.log('project reload: incremental modules, state handover and failure recovery passed');
} finally {
  try { if (page) await page.runtime.stop(); }
  finally { await service.stop(); await rm(directory, {recursive: true, force: true}); }
}
