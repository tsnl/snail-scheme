import {readFile} from 'node:fs/promises';
import {createHost} from '../../src/app/actors.mjs';
import {runHost} from '../../src/app/node-host.mjs';

const programs = {};
for (const name of ['client', 'server']) programs[name] = async () => ({module: await WebAssembly.compile(await readFile(`build/actors/${name}.wasm`))});
const host = createHost({programs, print: (actor, fd, line) => console.log(`${actor}: ${line}`)});
const failures = await runHost(host, ['client']);
for (const {name, error} of failures) console.error(name, error);
process.exitCode = failures.length ? 1 : 0;
