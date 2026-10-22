// The in-process assembler end to end, without Binaryen:
//
//   node tests/assembler.mjs ASSEMBLER.wasm RUNTIME.wasm PROGRAM.wat EXPECTED.out
//
// The assembler, itself running as Wasm, turns the compiler's text into a
// module; the module runs with the Rust runtime as a separate instance,
// which it imports as snail.library, and must print what the program's
// expected output says. Broken text must fail with its line and column.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createAssembler} from '../scripts/assemble.mjs';

const runner = fileURLToPath(new URL('../scripts/run-lofi.mjs', import.meta.url));

// The module runs as the one library of a modules.json, in a child process,
// so its standard output can be compared.
async function test([assemblerPath, runtimePath, programPath, expectedPath]) {
  const assemble = await createAssembler(await readFile(assemblerPath));
  assert.throws(() => assemble('(module\n  (func (result i32) (i32.bogus)))'), /:2:23/, 'broken text names its line and column');
  const directory = await mkdtemp(join(tmpdir(), 'lofi-assembler-'));
  try {
    await writeFile(join(directory, 'program.wasm'), assemble(await readFile(programPath, 'utf8')));
    await writeFile(join(directory, 'modules.json'), JSON.stringify({runtime: runtimePath, modules: [{name: 'program', file: 'program.wasm'}]}));
    const run = spawnSync(process.execPath, ['--no-warnings', runner, join(directory, 'modules.json')], {encoding: 'utf8'});
    assert.equal(run.stdout + run.stderr, await readFile(expectedPath, 'utf8'));
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
  console.log('assembler: the module it assembled runs');
}

await test(process.argv.slice(2));
