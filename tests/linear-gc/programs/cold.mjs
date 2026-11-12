// Cold application runs, including engine compilation, initialization and main.
// Every child runs alone. Invoke this script inside the build's memory limit.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtempSync, readFileSync, rmSync, mkdirSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {spawnSync} from 'node:child_process';

const [baselineRoot, baselineWasm, mvpRoot, mvpWasm, optimizedRoot, optimizedWasm, output] = process.argv.slice(2);
assert.ok(output, 'cold.mjs BASELINE_ROOT BASELINE_WASM MVP_ROOT MVP_WASM OPT_ROOT OPT_WASM OUTPUT');
const variants = [
  {label: 'wasmgc', root: baselineRoot, wasm: baselineWasm},
  {label: 'linear-mvp', root: mvpRoot, wasm: mvpWasm},
  {label: 'linear-opt', root: optimizedRoot, wasm: optimizedWasm},
];
mkdirSync(output, {recursive: true});
let expected;
for (let round = 0; round < 3; round++) {
  const order = [...variants.slice(round), ...variants.slice(0, round)];
  for (const variant of order) for (const engine of ['node', 'wasmtime']) {
    const scratch = mkdtempSync(join(tmpdir(), 'snail-cold-'));
    try {
      const wasm = resolve(variant.wasm), root = resolve(variant.root);
      const bytes = readFileSync(wasm), timing = join(scratch, 'time');
      const command = engine === 'node'
        ? [process.execPath, '--no-warnings', join(root, 'host/native/run-snail.mjs'), wasm]
        : [join(root, 'build/snail'), 'run-wasm', wasm];
      const result = spawnSync(process.env.SNAIL_BENCH_TIME ?? 'time',
        ['-f', '%e %U %S %M', '-o', timing, ...command], {encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
      assert.ifError(result.error);
      assert.equal(result.status, 0, result.stderr);
      expected ??= result.stdout;
      assert.equal(result.stdout, expected, 'all engines and variants produce the same application output');
      const [elapsed_s, user_s, system_s, max_rss_kib] = readFileSync(timing, 'utf8').trim().split(/\s+/).map(Number);
      const record = {variant: variant.label, engine, round: round + 1, command,
        sha256: createHash('sha256').update(bytes).digest('hex'), wasm_bytes: bytes.length,
        elapsed_s, user_s, system_s, max_rss_kib, stdout: result.stdout, stderr: result.stderr};
      writeFileSync(join(output, `${variant.label}-${engine}-${round + 1}.json`), JSON.stringify(record, null, 2) + '\n');
    } finally { rmSync(scratch, {recursive: true}); }
  }
}
