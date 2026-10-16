import assert from 'node:assert/strict';
import {appendFileSync, readFileSync} from 'node:fs';
import {join, basename} from 'node:path';

export function createProviders(context) {
  assert(Object.isFrozen(context));
  assert(Object.isFrozen(context.libraryKey));
  assert.equal(basename(context.sourcePath), `${context.libraryKey.at(-1)}.sld`);
  const output = process.env.LOFI_GENERATION_TEST_OUTPUT;
  const log = action => appendFileSync(join(output, 'providers.jsonl'), JSON.stringify({action, ...context}) + '\n');
  log('open');
  const module = new WebAssembly.Module(readFileSync(join(output, 'provider.wasm')));
  const provider = new WebAssembly.Instance(module, {host: {offset: () => Number(readFileSync(join(context.sourceDirectory, 'input.txt'), 'utf8'))}});
  return {providers: new Map([['tests.source', provider]]), close() { log('close'); }};
}
