// Execute one compiled recipe with explicit source context and foreign services.
// The recipe streams its generated library source, one Unicode scalar per call,
// through lofi:generator/character. The provider scope ends before the text is written.
import {readFileSync, writeFileSync} from 'node:fs';
import {dirname, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {loadWasm, instantiate, invokeEntry, closeInstance, scalarProvider}
  from '../src/lofi/compiler/execute.mjs';

// ---- Provider ownership and the descriptor's source context ----

async function openProviders(modulePath, sourcePath, libraryKey) {
  if (!modulePath) return {providers: new Map(), close() {}};
  const factory = await import(pathToFileURL(resolve(modulePath)).href);
  const context = Object.freeze({sourcePath: resolve(sourcePath), sourceDirectory: dirname(resolve(sourcePath)),
    libraryKey: Object.freeze(JSON.parse(libraryKey))});
  return await factory.createProviders(context);
}

// ---- Generated text arrives through one reserved provider ----

function generateText(code, providers) {
  if (!(providers instanceof Map)) throw new TypeError('provider factory must return a provider Map');
  if (providers.has('lofi:generator')) throw new TypeError('provider module lofi:generator is reserved');
  const characters = [];
  const output = scalarProvider({character: value => { characters.push(String.fromCodePoint(value)); }},
    [['character', 1, false]]);
  const instance = instantiate(code, new Map([...providers, ['lofi:generator', output]]));
  try { invokeEntry(instance, []); } finally { closeInstance(instance); }
  return characters.join('');
}

async function produce(binary, sourcePath, libraryKey, modulePath) {
  const code = loadWasm(readFileSync(binary));
  const scope = await openProviders(modulePath, sourcePath, libraryKey);
  if (!scope || typeof scope.close !== 'function') throw new TypeError('provider factory must return providers and close');
  let failed = false, primary;
  try {
    return generateText(code, scope.providers);
  } catch (failure) { failed = true; primary = failure; throw failure; }
  finally {
    try { await scope.close(); }
    catch (cleanup) { throw failed ? new AggregateError([primary, cleanup], 'generator and provider cleanup failed') : cleanup; }
  }
}

function describeFailure(failure) {
  const nested = failure instanceof AggregateError ? failure.errors : [failure?.cause].filter(Boolean);
  return [failure?.stack ?? String(failure), ...nested.map(describeFailure)].join('\nCaused by: ');
}

// ---- Explicit artifact and output paths ----

const arguments_ = process.argv.slice(2);
if (arguments_.length !== 5) throw new TypeError('expected artifact, output, descriptor, key and provider module arguments');
const [binary, output, sourcePath, libraryKey, modulePath] = arguments_;
try {
  writeFileSync(output, await produce(binary, sourcePath, libraryKey, modulePath));
} catch (failure) {
  writeFileSync(`${output}.error`, describeFailure(failure));
  process.exitCode = 1;
}
