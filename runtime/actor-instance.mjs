// Node/WASI embedding for the actor prototype. All roots stay in this instance.
import { readFile, mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { WASI } from 'node:wasi';
import { createFinalizers } from './host.mjs';

// ---- Instance startup ----

export async function loadInstance(filename) {
  const directory = resolve(process.env.SNAIL_TRACE_DIR ?? 'build/traces');
  await mkdir(directory, { recursive: true });
  const wasi = new WASI({ version: 'preview1', args: [filename],
    env: { SNAIL_TRACE_DIR: '/traces' }, preopens: { '/traces': directory } });
  let instance;
  const finalizers = createFinalizers((kind, id) => instance.exports['snail:drop-resource'](kind, id));
  const module = await WebAssembly.compile(await readFile(filename));
  instance = await WebAssembly.instantiate(module, {
    wasi_snapshot_preview1: wasi.wasiImport,
    'snail.host': { 'register-finalizer': finalizers.register, 'unregister-finalizer': finalizers.unregister },
  });
  wasi.initialize(instance);
  instance.exports.actor_initialize();
  return instance;
}

// ---- Instance-local roots ----

function stringRoot(api, text) {
  const characters = Array.from(text);
  const root = api.string_new(characters.length);
  characters.forEach((character, index) => api.string_set(root, index, character.codePointAt(0)));
  return root;
}

function stringValue(api, root) {
  const characters = [];
  for (let index = 0; index < api.length(root); index++) {
    characters.push(String.fromCodePoint(api.char_at(root, index)));
  }
  return characters.join('');
}

function callUnary(api, name, argument, roots) {
  const argumentsRoot = api.vector_new(1);
  roots.push(argumentsRoot);
  api.vector_set(argumentsRoot, 0, argument);
  const result = api[name](argumentsRoot);
  roots.push(result);
  return result;
}

export function invoke(instance, text) {
  const api = instance.exports;
  const roots = [stringRoot(api, text)];
  const decoded = callUnary(api, 'scheme:wire:decode-call', roots[0], roots);
  const method = api.at(decoded, 0), argumentsRoot = api.at(decoded, 1);
  roots.push(method, argumentsRoot);
  const name = `scheme:method:${stringValue(api, method)}`;
  if (typeof api[name] !== 'function') throw new Error(`unknown actor method: ${name}`);
  const result = api[name](argumentsRoot);
  roots.push(result);
  const reply = stringValue(api, callUnary(api, 'scheme:wire:encode-result', result, roots));
  for (const root of roots.reverse()) api.release(root);
  return reply;
}

// A trap can bypass Rust cleanup. The caller must destroy the failed instance;
// do not reenter it even to release AWI roots after an exception from invoke.
