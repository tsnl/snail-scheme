// The `gpu` effect on Node, whose device is Dawn's (host/native/gpu.mjs):
// tests/gpu/node.scm runs the checks that need only a device, as the page
// does, on the GPU Dawn finds, and WebGPU reports no error. nix-shell
// gives Dawn (SNAIL_WEBGPU); SNAIL_DAWN may choose the adapter or turn
// Dawn's guards off. CI has no GPU, so `make test-gpu` runs this.
//
//   node tests/gpu.mjs ROOT
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {join} from 'node:path';
import {promisify} from 'node:util';
import {assertLines, deviceLines} from './gpu/expected.mjs';

const [root] = process.argv.slice(2);
const {stdout, stderr} = await promisify(execFile)(join(root, 'snail-scheme'),
  ['run', '--target', 'node', 'tests/gpu/node.scm'], {cwd: root});
assert.deepEqual(stderr.split('\n').filter(line => line.startsWith('WebGPU')), [], 'WebGPU reported nothing');
const printed = stdout.trimEnd().split('\n');
assert.equal(printed[0], 'format: rgba8unorm');
assertLines(printed.slice(1), deviceLines);
console.log('gpu on node: a lit, tone-mapped G-buffer, motion and ids, a compute pass, a scan, a sort, splats, tensor programs and the differentiable splat renderer on Dawn passed');
