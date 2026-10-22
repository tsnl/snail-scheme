// A subprocess proves that idle mailboxes keep Node alive, while completed
// actors release its process-lifetime token without an explicit exit call.
import {readFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {createHost} from '../../src/app/actors.mjs';
import {runHost} from '../../src/app/node-host.mjs';

const [file, mode] = process.argv.slice(2);
const load = async () => file.endsWith('.json') ?
  {manifest: file, read: path => readFile(resolve(dirname(file), path))} :
  {module: await WebAssembly.compile(await readFile(file))};
const host = createHost({programs: {bootstrap: load, server: load}, imports: name => ({'snail.test': {
  role: () => { if (name === 'server') console.log('waiting'); return name === 'bootstrap' ? 0 : 1; },
  target: () => 0, trace() {}, observe: value => console.log(`reply:${value}`),
  wait: new WebAssembly.Suspending(() => Promise.resolve()),
}})});
const errors = await runHost(host, [mode === 'idle' ? 'server' : 'bootstrap']);
for (const {error} of errors) console.error(error);
process.exitCode = errors.length ? 1 : 0;
