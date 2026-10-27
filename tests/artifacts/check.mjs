// Execute embedded artifacts after static compilation, cached compilation,
// and a byte change with no source edit. Generic callers must update too.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createAssembler} from '../../host/native/assemble.mjs';

const [assemblerPath, runtimePath, directory, expectedPath] = process.argv.slice(2);
const assemble = await createAssembler(await readFile(assemblerPath));
const runner = fileURLToPath(new URL('../../host/native/run-snail.mjs', import.meta.url));
const expected = await readFile(expectedPath, 'utf8');

async function execute(output, names, wanted) {
  for (const name of names) await writeFile(join(output, name + '.wasm'), assemble(await readFile(join(output, name + '.wat'), 'utf8')));
  const manifest = join(output, 'modules.json');
  await writeFile(manifest, JSON.stringify({runtime: runtimePath, modules: names.map(name => ({name, file: name + '.wasm'}))}));
  const result = spawnSync(process.execPath, ['--no-warnings', runner, manifest], {encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout + result.stderr, wanted);
}

await execute(directory, ['program'], expected);
for (const generation of ['first', 'unchanged', 'changed']) {
  const output = join(directory, generation);
  const names = (await readFile(join(output, 'modules'), 'utf8')).split('\n');
  await execute(output, names, generation === 'changed' ? expected.replaceAll('65,0,255', '90,0,255') : expected);
}
assert.equal(await readFile(join(directory, 'unchanged/compiled'), 'utf8'), '', 'identical files preserve emission');
assert.deepEqual((await readFile(join(directory, 'changed/compiled'), 'utf8')).split('\n').sort(), ['generated.assets', 'main', 'sample.consumer', 'sample.generic'], 'artifact stamps invalidate a generic importer with no artifact request of its own');
console.log('artifact resolution: static and cached Wasm contain the current files');
