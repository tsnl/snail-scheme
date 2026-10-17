// Package browser libraries and build a finite protocol manifest from literal
// application declarations retained by the compiler. It does not reparse a
// potentially edited file or expand arbitrary user macros independently.
import {readFileSync, writeFileSync, mkdirSync, copyFileSync, renameSync} from 'node:fs';
import {join, dirname, resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {loadWasm, instantiate, invokeEntry, closeInstance} from '../lofi/execute.mjs';
import {ReducerRuntime} from '../application/runtime.mjs';
import {parseInputSettings} from './input.mjs';

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
  const input = parseInputSettings(settings);
  const select = (owner, binding) => {
    const handler = protocol.applications.find(app => app.owner === owner)?.handlers.find(h => h.binding === binding);
    if (!handler) throw new Error(`settings refer to unknown ${owner} handler: ${binding}`);
    return handler;
  };
  for (const binding of [settings.tick, settings.reset]) {
    if (select('match', binding).payload.length) throw new Error('clock and reset handlers require no payload');
  }
  for (const binding of settings.remoteHandlers) select('match', binding);
  for (const [binding, arity] of [[input.pointer.move, 2], [input.pointer.confirm, 0]]) {
    if (select('client', binding).payload.length !== arity) throw new Error('pointer handler payload does not match its input');
  }
  for (const command of [...input.keys.values(), ...input.buttons.values(), ...input.axes.flatMap(axis => [axis.negative, axis.positive])]) {
    if (select('client', command[0]).payload.length !== command.length - 1)
      throw new Error('input mapping does not match a typed client handler');
  }
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
function checkInitialProgram(bytes, manifest) {
  const runtime = new ReducerRuntime();
  try {
    runtime.replace(runtime.prepare(bytes, manifest));
    runtime.initialize(1); runtime.initialize(2); runtime.view();
    const marker = manifest.settings.runMarker;
    if (marker !== undefined && (!Number.isInteger(marker) || marker < 1 || marker >= runtime.snapshot(1).length))
      throw new Error('invalid run marker snapshot offset');
  } catch (error) { throw new Error(`application startup check failed: ${error.message}`, {cause: error}); }
  finally { runtime.close(); }
}
export function packageApplication(root, app, output) {
  const settings = JSON.parse(readFileSync(join(app, 'settings.json'), 'utf8'));
  const protocol = applicationManifest(JSON.parse(readFileSync(join(output, 'application.syntax.json'), 'utf8')), settings);
  checkSettings(settings, protocol);
  const wasm = readFileSync(join(output, 'simulation.wasm')), shader = shaderSource(join(output, 'shader.wasm'));
  const generation = hash(Buffer.concat([wasm, Buffer.from(shader + JSON.stringify(protocol) + JSON.stringify(settings))]));
  const moduleName = `simulation.${generation}.wasm`, shaderName = `shader.${generation}.wgsl`;
  const manifest = {...protocol, generation, module: moduleName, shader: shaderName, settings};
  checkInitialProgram(wasm, manifest);
  writeFileSync(join(output, moduleName), wasm); writeFileSync(join(output, shaderName), shader);
  for (const path of ['lofi/execute.mjs', 'application/runtime.mjs', 'application/authority.mjs',
    'application/sqlite.mjs', 'webgpu/quads.mjs', 'browser/client.mjs', 'browser/input.mjs', 'browser/server.mjs']) {
    const target = join(output, 'lib', path); mkdirSync(dirname(target), {recursive: true}); copyFileSync(join(root, 'src', path), target);
  }
  for (const asset of ['index.html', 'style.css']) copyFileSync(join(app, asset), join(output, asset));
  // Versioned artifacts become reachable only after complete successful packaging.
  writeFileSync(join(output, 'manifest.next.json'), JSON.stringify(manifest, null, 2));
  renameSync(join(output, 'manifest.next.json'), join(output, 'manifest.json'));
  return manifest;
}
if (process.argv[1] && resolve(process.argv[1]) === import.meta.filename) {
  const [, , root, app, output] = process.argv;
  const manifest = packageApplication(root, app, output);
  console.log(`Built ${manifest.settings.title}: ${join(output, 'manifest.json')}\nRun: node ${join(output, 'lib/browser/server.mjs')} ${output}`);
}
