import {createWasi, instantiate} from '../../src/app/load.mjs';
import {programEntry} from '../../src/app/actors.mjs';
import {createControlHost} from '../../prototypes/ctl/runtime.mjs';

const output = document.querySelector('#output');
try {
  const host = createControlHost(), wasi = createWasi({print() {}});
  const imports = {'lofi.control.prototype': host.imports,
                   'lofi.control.test': {pause: host.suspending(() => new Promise(resolve => setTimeout(resolve, 5)))}};
  const program = await instantiate(await WebAssembly.compile(await (await fetch('../../build/tests/control.wasm')).arrayBuffer()),
                                    {...wasi.getImportObject(), ...imports});
  wasi.initialize(program); program.exports.main();
  const results = [];
  for (const [name, expected] of [['early', 42n], ['repeated', 12n], ['forwarding', 1033n], ['forwarding-abort', 77n],
                                ['nested', 115n], ['context', 107n], ['library-operation', 42n], ['polymorphic', 4n],
                                ['descendant-resume', 42n], ['surviving-clause', 143n]]) {
    const actual = await host.run(programEntry(program, name));
    if (actual !== expected || host.stats.tasks || host.stats.continuations || host.stats.boundaries)
      throw new Error(`${name}: ${actual}, ${JSON.stringify(host.stats)}`);
    results.push(`${name}: ${actual} ✓`);
  }
  for (const [name, message] of [['twice', 'only once'], ['crossing-resume', 'originating clause']]) {
    try { await host.run(programEntry(program, name)); throw new Error(`${name} was accepted`); }
    catch (error) { if (!error.message.includes(message)) throw error; }
    if (host.stats.tasks || host.stats.continuations || host.stats.boundaries) throw new Error(`${name} leaked stacks`);
    results.push(`${name} rejected ✓`);
  }
  results.push('All physical stacks settled.');
  output.textContent = results.join('\n');
  document.body.dataset.result = 'passed';
  console.log(output.textContent);
} catch (error) {
  output.textContent = error.stack;
  document.body.dataset.result = 'failed';
  console.error(error);
}
