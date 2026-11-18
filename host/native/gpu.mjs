// The `gpu` effect on Node: host/browser/gpu.mjs's objects and commands
// over Dawn, the WebGPU implementation Chromium uses, through Dawn's own
// Node binding, dawn.node. Dawn runs in this process and is called
// directly, where Chromium's runs in a GPU process that every call is sent
// to. The binding is the webgpu package's (github.com/dawn-gpu/node-webgpu)
// at SNAIL_WEBGPU, which nix-shell pins and sets (shell.nix). It loads at
// the program's first `request-device`, so a program that never asks for
// a device needs none.
//
// SNAIL_DAWN holds Dawn's own options, separated by spaces, as `create`
// takes them: `backend=vulkan`, `adapter=NAME`, and toggles turned on with
// `enable-dawn-features=A,B` and off with `disable-dawn-features=A,B`. A
// browser must guard against the pages it runs, and Dawn does so by
// default; a program that trusts its own commands and shaders can turn
// the guards off:
//
//   SNAIL_DAWN='enable-dawn-features=skip_validation,disable_robustness,disable_workgroup_init'
//
// Dawn then checks no call, compiles shaders without bounds checks on
// their memory, and leaves workgroup memory as it finds it. A mistake is
// then undefined behavior, not an error: an invalid shader aborts the
// process, and reading past an array reads anything. Buffers stay zeroed
// before their first use, as WebGPU promises and (snail shell tensor)
// relies on, since a program's params start at zeros; that costs a
// resource's first use, not each dispatch. On an RTX 5090 the guards cost
// little: turning them off saves a tenth of a microsecond of the 1.4 that
// encoding a dispatch takes (doc/book/graphics/plan.md).
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createGpu, requestDevice} from '../browser/gpu.mjs';

// `program` gives the running program, whose memory holds staged Bytes;
// `tasks` are its tasks. Node has no canvas, so the program has no
// screen.
export function nodeGpu(program, tasks) {
  const execution = {tasks, get entry() { return program().exports; }};
  return createGpu(null, {execution}, nodeDevice);
}

// One device per run. The program's own targets are rgba8unorm, which
// reads back as a PNG's bytes. The device keeps Dawn's instance, the
// object `create` answers: dawn.node polls it while any work is pending,
// and an instance the collector frees crashes the process at the next
// poll, so it must stay reachable as long as the device works.
let shared = null;
function nodeDevice() {
  shared ??= opened();
  return shared;
}

async function opened() {
  const where = process.env.SNAIL_WEBGPU;
  if (!where) throw new Error('Node has no WebGPU here: SNAIL_WEBGPU names the webgpu package, as nix-shell sets it');
  const {create, globals} = await import(pathToFileURL(join(where, 'index.js')).href);
  Object.assign(globalThis, globals);
  const instance = create((process.env.SNAIL_DAWN ?? '').split(/\s+/).filter(Boolean));
  const {device, optional} = await requestDevice(instance);
  return {device, context: null, format: 'rgba8unorm', optional, instance};
}
