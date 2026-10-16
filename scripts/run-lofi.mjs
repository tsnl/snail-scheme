#!/usr/bin/env node
import {readFile} from 'node:fs/promises';
import {WASI} from 'node:wasi';

// ---- One reactor initialization and one program invocation ----

function resultStatus(value) {
  if (value === undefined) return 0;
  if ((typeof value === 'number' || typeof value === 'bigint') && value >= 0 && value <= 255) {
    return Number(value);
  }
  return 1;
}

async function run(filename, arguments_) {
  const wasi = new WASI({version: 'preview1', args: [filename, ...arguments_],
    env: {...process.env, SNAIL_CWD: process.cwd()}, preopens: {'/': '/'}, returnOnExit: true});
  const {instance} = await WebAssembly.instantiate(await readFile(filename), wasi.getImportObject());
  let status = 1;
  try {
    wasi.initialize(instance);
    status = resultStatus(instance.exports.main());
  } finally {
    if (instance.exports['close-resources']() !== 0 && status === 0) status = 1;
  }
  return status;
}

const [filename, ...arguments_] = process.argv.slice(2);
try {
  if (!filename) throw new Error('usage: run-lofi.mjs MODULE.wasm [ARGUMENT ...]');
  process.exitCode = await run(filename, arguments_);
} catch (error) {
  console.error(`snail-lofi: ${error.message}`);
  process.exitCode = 1;
}
