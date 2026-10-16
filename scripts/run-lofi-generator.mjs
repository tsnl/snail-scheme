// Execute one compiled recipe with explicit source context and foreign services.
// The provider scope ends before the owned transfer is written to the receiver.
import {readFileSync, writeFileSync} from 'node:fs';
import {dirname, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {loadWasm} from '../src/snail-lofi/execute.mjs';
import {invokeLibraryGenerator, libraryTransferJSON} from '../src/snail-lofi/library-builder.mjs';

// ---- Provider ownership and the descriptor's source context ----

async function openProviders(modulePath, sourcePath, libraryKey) {
  if (!modulePath) return {providers: new Map(), close() {}};
  const factory = await import(pathToFileURL(resolve(modulePath)).href);
  const context = Object.freeze({sourcePath: resolve(sourcePath), sourceDirectory: dirname(resolve(sourcePath)),
    libraryKey: Object.freeze(JSON.parse(libraryKey))});
  return await factory.createProviders(context);
}

async function produce(binary, sourcePath, libraryKey, modulePath) {
  const code = loadWasm(readFileSync(binary));
  const scope = await openProviders(modulePath, sourcePath, libraryKey);
  if (!scope || typeof scope.close !== 'function') throw new TypeError('provider factory must return providers and close');
  let failed = false, primary;
  try {
    if (!(scope.providers instanceof Map)) throw new TypeError('provider factory must return a provider Map');
    return libraryTransferJSON(invokeLibraryGenerator(code, scope.providers));
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

// ---- Explicit artifact and transfer paths ----

const arguments_ = process.argv.slice(2);
if (arguments_.length !== 5) throw new TypeError('expected artifact, transfer, descriptor, key and provider module arguments');
const [binary, packet, sourcePath, libraryKey, modulePath] = arguments_;
try {
  writeFileSync(packet, await produce(binary, sourcePath, libraryKey, modulePath));
} catch (failure) {
  writeFileSync(`${packet}.error`, describeFailure(failure));
  process.exitCode = 1;
}
