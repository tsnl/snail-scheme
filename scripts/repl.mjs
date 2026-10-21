#!/usr/bin/env node
// The Scheme REPL: reads expressions at the terminal and evaluates them in a
// kernel, which keeps their definitions:  node repl.mjs KERNEL.wasm
// An expression may span lines. Tab completes the kernel's names. `,quit`
// or the end of input leaves. Control-C abandons the line being typed, or
// stops an evaluation: the kernel is then started again and the inputs that
// succeeded before are replayed into it, which restores their definitions.
import {readFile} from 'node:fs/promises';
import {createInterface} from 'node:readline';
import {Worker} from 'node:worker_threads';
import {kernelClient, balanced} from '../src/notebook/kernel.mjs';

// ---- The kernel ----

// Like a program run by scripts/run-lofi.mjs, the kernel's worker has room
// for deep recursion. `kernel` is a promise of the running kernel, which a
// restart replaces at once, so input typed meanwhile waits for the new one.
const limits = {stackSizeMb: 256, maxYoungGenerationSizeMb: 384};
const bytes = await readFile(process.argv[2] ?? usage());
const journal = [];
let kernel = startKernel(), running = null;

function usage() {
  console.error('usage: repl.mjs KERNEL.wasm');
  process.exit(1);
}

async function startKernel() {
  const client = kernelClient(new Worker(new URL('../src/notebook/worker.mjs', import.meta.url), {resourceLimits: limits}));
  await client.load(bytes);
  return client;
}

// Stops a kernel and replays the inputs that succeeded into a new one,
// showing nothing they print.
function restart(stopped) {
  stopped.terminate();
  kernel = startKernel().then(async client => {
    for (const text of journal) await client.evaluate(text);
    console.log(`; stopped; replayed ${journal.length} earlier inputs into a new kernel`);
    return client;
  });
}

async function evaluate(text) {
  const client = await kernel;
  running = client;
  try {
    if (show(await client.evaluate(text))) journal.push(text);
  } catch {
    await kernel;
  }
  running = null;
}

// ---- The terminal ----

function show({ok, output, value, error}) {
  if (output) process.stdout.write(output.endsWith('\n') ? output : `${output}\n`);
  if (value !== null) console.log(value);
  if (error) console.log(`; error: ${error}`);
  return ok;
}

// Completes the name being typed at the end of the line.
function complete(line, callback) {
  const word = line.match(/[^\s()'"]*$/)[0];
  kernel.then(client => client.names())
    .then(names => callback(null, [names.filter(name => name.startsWith(word)), word]), callback);
}

const terminal = createInterface({input: process.stdin, output: process.stdout, completer: complete, prompt: 'lofi> '});
let pending = '', lines = Promise.resolve();

// Lines are handled in order, each after the evaluation before it.
async function handle(line) {
  pending = pending ? `${pending}\n${line}` : line;
  if (pending.trim() === ',quit') { terminal.close(); return; }
  if (!balanced(pending)) { terminal.setPrompt('  ... '); terminal.prompt(); return; }
  const text = pending;
  pending = '';
  if (text.trim()) await evaluate(text);
  terminal.setPrompt('lofi> ');
  terminal.prompt();
}

terminal.on('line', line => { lines = lines.then(() => handle(line)); });

terminal.on('SIGINT', () => {
  if (running) { restart(running); return; }
  pending = '';
  terminal.write(null, {ctrl: true, name: 'e'});
  terminal.write(null, {ctrl: true, name: 'u'});
  process.stdout.write('\n');
  terminal.setPrompt('lofi> ');
  terminal.prompt();
});

terminal.on('close', () => lines.then(() => kernel).then(client => { client.terminate(); process.exit(0); }));

console.log('; Lofi Scheme. Tab completes a name; ,quit leaves.');
terminal.prompt();
