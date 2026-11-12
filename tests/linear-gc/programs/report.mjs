// Summarize raw samples without hiding per-process results in the JSON files.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
const [directory, candidate = 'linear-mvp', reference = 'wasmgc'] = process.argv.slice(2);
const median = values => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];
for (const engine of ['node', 'wasmtime']) {
  const load = variant => Promise.all([1, 2, 3].map(round =>
    readFile(join(directory, `${variant}-${engine}-${round}.json`), 'utf8').then(JSON.parse)));
  const [baseline, current] = await Promise.all([load(reference), load(candidate)]);
  console.log(`\n${engine}; milliseconds per batch, median of 27 samples (three fresh processes).\n`);
  console.log(`| Workload | ${reference} | ${candidate} | Ratio | Process ratios |`);
  console.log('| --- | ---: | ---: | ---: | --- |');
  for (let i = 0; i < baseline[0].workloads.length; i++) {
    const before = baseline.map(run => run.workloads[i]), after = current.map(run => run.workloads[i]);
    for (const run of [...before, ...after]) {
      assert.equal(run.name, before[0].name);
      assert.equal(run.count, before[0].count);
      assert.equal(run.checksum, before[0].checksum);
    }
    const b = median(before.flatMap(run => run.samples_ms)), a = median(after.flatMap(run => run.samples_ms));
    const ratios = before.map((run, j) => (after[j].median_ms / run.median_ms).toFixed(2)).join(', ');
    console.log(`| ${before[0].name} | ${b.toFixed(3)} | ${a.toFixed(3)} | ${(a / b).toFixed(2)}× | ${ratios} |`);
  }
  for (const [variant, runs] of [[reference, baseline], [candidate, current]]) {
    console.log(`${variant}: ${runs[0].wasm_bytes} bytes; compile ${median(runs.map(run => run.compile_ms)).toFixed(2)} ms; ` +
      `initialize ${median(runs.map(run => run.initialize_ms)).toFixed(2)} ms; ` +
      `peak RSS ${median(runs.map(run => run.max_rss_kib))} KiB.`);
  }
}
