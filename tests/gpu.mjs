// The `gpu` effect on Node, whose device is Dawn's (host/native/gpu.mjs):
// tests/gpu/node.scm runs the checks that need only a device, as the page
// does, and the splat renderer's training checks, on the GPU Dawn finds,
// and WebGPU reports no error. Its build is a package that depends on the
// webgpu and sharp packages, and runs as it would be shipped: Node finds
// both in the repository's node_modules, which `make fetch` installs. CI
// has no GPU, so `make test-gpu` runs this.
//
//   node tests/gpu.mjs ROOT
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {promisify} from 'node:util';
import {assertLines, deviceLines, trainingLines} from './gpu/expected.mjs';

const [root] = process.argv.slice(2);
const execute = promisify(execFile);
const built = (await execute(join(root, 'snail-scheme'), ['build', '--target', 'node', 'tests/gpu/node.scm'],
  {cwd: root})).stdout.trim();
const manifest = JSON.parse(await readFile(join(built, 'package.json'), 'utf8'));
assert.ok(manifest.dependencies.webgpu && manifest.dependencies.sharp, 'the package depends on webgpu and sharp');
const {stdout, stderr} = await execute(process.execPath, [join(built, 'main.mjs')], {cwd: root});
assert.deepEqual(stderr.split('\n').filter(line => line.startsWith('WebGPU')), [], 'WebGPU reported nothing');
const printed = stdout.trimEnd().split('\n');
assert.equal(printed[0], 'format: rgba8unorm');
assertLines(printed.slice(1), [...deviceLines, ...trainingLines]);
console.log('gpu on node, from its package: decoding, a lit, tone-mapped G-buffer, motion and ids, a compute pass, a scan, a sort, splats, tensor programs, the differentiable splat renderer and densification on Dawn passed');
