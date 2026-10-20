// Package browser libraries and build a finite protocol manifest from literal
// application declarations retained by the compiler. It does not reparse a
// potentially edited file or expand arbitrary user macros independently.
import {readFileSync, writeFileSync, mkdirSync, copyFileSync, renameSync, existsSync} from 'node:fs';
import {join, dirname, resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {loadWasm, instantiate, invokeEntry, closeInstance} from '../lofi/compiler/execute.mjs';
import {ReducerRuntime} from '../application/runtime.mjs';
import {parseInputSettings} from './input.mjs';
import {saveName} from '../application/indexeddb.mjs';

const hash = value => createHash('sha256').update(value).digest('hex').slice(0, 24);
export function applicationManifest(source, settings) {
  const applications = source.applications.map(app => {
    const {binding, state, schema} = app, owner = settings.owners[binding];
    if (!owner || !Number.isInteger(schema)) throw new Error('application requires declared owner and literal schema version');
    return {binding, owner, state, schema, handlers: app.handlers.map(({binding, payload}, slot) => {
      if (payload.length > 2 || payload.some(type => type !== 'I32')) throw new Error('initial payload subset is zero to two I32 values');
      const identity = [source.library, app.binding, schema, binding, payload];
      return {binding, slot, payload, result: {state, effects: "application.Effect/v1"}, identity, id: hash(JSON.stringify(identity))};
    })};
  });
  return {version: 1, applications, effects: {identity: 'application.Effect/v1', variants: [
    {kind: 'send', destination: 'typed owner and endpoint identity', payload: 'endpoint payload schema'},
    {kind: 'notice', payload: ['String']}]}};
}
function checkSettings(settings, protocol) {
  saveName(settings.id);
  const input = parseInputSettings(settings);
  const select = (owner, binding) => {
    const handler = protocol.applications.find(app => app.owner === owner)?.handlers.find(h => h.binding === binding);
    if (!handler) throw new Error(`settings refer to unknown ${owner} handler: ${binding}`);
    return handler;
  };
  for (const binding of [settings.tick, settings.reset]) {
    if (select('match', binding).payload.length) throw new Error('clock and reset handlers require no payload');
  }
  if (settings.viewportHandler && select('client', settings.viewportHandler).payload.length !== 2)
    throw new Error('viewport handler requires width and height I32 arguments');
  if (settings.animationHandler && select('client', settings.animationHandler).payload.length !== 1)
    throw new Error('animation handler requires elapsed milliseconds');
  if (input.zoomHandler && select('client', input.zoomHandler).payload.length !== 1)
    throw new Error('zoom handler requires one I32 scale delta');
  if (input.dragHandler && select('client', input.dragHandler).payload.length !== 2)
    throw new Error('drag handler requires two I32 CSS-pixel deltas');
  if (settings.resetPresentation && select('client', settings.resetPresentation).payload.length)
    throw new Error('reset presentation handler requires no payload');
  if (settings.randomSeed && select('match', settings.randomSeed.handler).payload.length !== 1)
    throw new Error('random seed handler requires one I32 seed');
  if (settings.inspection) checkInspection(settings.inspection);
  for (const [binding, arity] of [[input.pointer.move, 2], [input.pointer.confirm, 0]]) {
    if (select('client', binding).payload.length !== arity) throw new Error('pointer handler payload does not match its input');
  }
  for (const command of [...input.keys.values(), ...input.buttons.values(), ...input.axes.flatMap(axis => [axis.negative, axis.positive])]) {
    if (select('client', command[0]).payload.length !== command.length - 1)
      throw new Error('input mapping does not match a typed client handler');
  }
}
// An inspection projection names the scalar fields of privileged operation 11.
function checkInspection(projection) {
  if (!Number.isInteger(projection.version) || projection.version < 1 || !Array.isArray(projection.fields)
      || !projection.fields.length || projection.fields.length > 64 || new Set(projection.fields).size !== projection.fields.length
      || projection.fields.some(field => typeof field !== 'string' || !/^[a-zA-Z][a-zA-Z0-9]{0,63}$/.test(field)))
    throw new Error('inspection requires a version and distinct field names');
}
function shaderSource(path) {
  const instance = instantiate(loadWasm(readFileSync(path)));
  try {
    const length = invokeEntry(instance, [-1]), scalars = [];
    for (let index = 0; index < Math.abs(length); index++) scalars.push(invokeEntry(instance, [index]));
    const source = String.fromCodePoint(...scalars);
    if (length < 0) throw new Error(source); return source;
  } finally { closeInstance(instance); }
}
async function checkInitialProgram(bytes, manifest) {
  const runtime = new ReducerRuntime();
  try {
    await runtime.replace(runtime.prepare(bytes, manifest));
    await runtime.initialize(1); await runtime.initialize(2); runtime.view();
    if (manifest.settings.inspection && runtime.inspect(-1) !== manifest.settings.inspection.version)
      throw new Error('inspection version does not match the module');
    const marker = manifest.settings.runMarker;
    if (marker !== undefined && (!Number.isInteger(marker) || marker < 1 || marker >= runtime.snapshot(1).length))
      throw new Error('invalid run marker snapshot offset');
  } catch (error) { throw new Error(`application startup check failed: ${error.message}`, {cause: error}); }
  finally { await runtime.close(); }
}
async function readApplication(app, artifacts) {
  const settings = JSON.parse(readFileSync(join(app, 'settings.json'), 'utf8'));
  const protocol = applicationManifest(JSON.parse(readFileSync(join(artifacts, 'application.syntax.json'), 'utf8')), settings);
  checkSettings(settings, protocol);
  const wasm = readFileSync(join(artifacts, 'simulation.wasm')), shader = shaderSource(join(artifacts, 'shader.wasm'));
  const generation = hash(Buffer.concat([wasm, Buffer.from(shader + JSON.stringify(protocol) + JSON.stringify(settings))]));
  const moduleName = `simulation.${generation}.wasm`, shaderName = `shader.${generation}.wgsl`;
  const manifest = {...protocol, generation, module: moduleName, shader: shaderName, settings};
  await checkInitialProgram(wasm, manifest);
  return {manifest, wasm, shader, html: readShell(app)};
}
function readShell(app) {
  const html = readFileSync(join(app, 'index.html'), 'utf8');
  if (html.split('<script type="module" data-application-entry></script>').length !== 2)
    throw new Error('index.html must contain one data-application-entry module script');
  return html;
}
function checkOutput(output) {
  const existing = join(output, 'manifest.json');
  if (existsSync(existing) && JSON.parse(readFileSync(existing)).target !== 'solo')
    throw new Error('Cannot change an installed package target. Choose a new output directory; existing files and saves were retained.');
}
function copyLibraries(root, output) {
  for (const path of ['lofi/compiler/execute.mjs', 'application/runtime.mjs', 'application/local.mjs',
    'webgpu/quads.mjs', 'webgpu/scene.mjs', 'draw3d/bridge.mjs', 'browser/application.mjs', 'browser/input.mjs',
    'ui/bridge.mjs', 'ui/dom.mjs', 'ui/style.css', 'application/indexeddb.mjs', 'browser/solo.mjs']) {
    const target = join(output, 'lib', path); mkdirSync(dirname(target), {recursive: true}); copyFileSync(join(root, 'src', path), target);
  }
}
function writePackage(root, app, output, {manifest: source, wasm, shader, html}) {
  checkOutput(output);
  const manifest = {...source, target: 'solo'}; mkdirSync(output, {recursive: true});
  writeFileSync(join(output, manifest.module), wasm); writeFileSync(join(output, manifest.shader), shader);
  copyLibraries(root, output);
  writeFileSync(join(output, 'index.html'), html.replace('<script type="module" data-application-entry></script>',
    '<script type="module" src="./lib/browser/solo.mjs"></script>'));
  copyFileSync(join(app, 'style.css'), join(output, 'style.css'));
  // Versioned artifacts become reachable only after complete successful packaging.
  writeFileSync(join(output, 'manifest.next.json'), JSON.stringify(manifest, null, 2));
  renameSync(join(output, 'manifest.next.json'), join(output, 'manifest.json'));
  return manifest;
}
export async function packageApplication(root, app, artifacts, {output = artifacts} = {}) {
  return writePackage(root, app, output, await readApplication(app, artifacts));
}
if (process.argv[1] && resolve(process.argv[1]) === import.meta.filename) {
  const [, , root, app, output] = process.argv;
  const manifest = await packageApplication(root, app, output, {output: join(output, 'solo')});
  console.log(`Built ${manifest.settings.title}\nStatic files: ${join(output, 'solo')}`);
}
