// Build and run a shipped Node package per GPU workload. The compiler
// analyzes possible suspensions across a whole program. Combining graphics,
// tensors and splat training makes a single build much more expensive.
// Dawn uses the machine's GPU or the software driver lavapipe in CI.
//
//   node tests/gpu.mjs ROOT
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {promisify} from 'node:util';
import {assertLines, deviceLines, splatLines, tensorLines, trainingLines} from './gpu/expected.mjs';

const [root] = process.argv.slice(2);
const execute = promisify(execFile);
async function checkPackage(name, expected) {
  console.time(`Build ${name}`);
  const {stdout: directory} = await execute(join(root, 'snail-scheme'),
    ['build', '--target', 'node', `tests/gpu/${name}.scm`], {cwd: root});
  console.timeEnd(`Build ${name}`);
  const built = directory.trim();
  const manifest = JSON.parse(await readFile(join(built, 'package.json'), 'utf8'));
  assert.ok(manifest.dependencies.webgpu && manifest.dependencies['@napi-rs/canvas'], `GPU dependencies in ${name}`);
  console.time(`Run ${name}`);
  const {stdout, stderr} = await execute(process.execPath, [join(built, 'main.mjs')], {cwd: root});
  console.timeEnd(`Run ${name}`);
  assert.deepEqual(stderr.split('\n').filter(line => line.startsWith('WebGPU')), [], `WebGPU errors in ${name}`);
  assertLines(stdout.trimEnd().split('\n'), expected);
}

await checkPackage('node', ['format: rgba8unorm', ...deviceLines]);
await checkPackage('tensors', tensorLines);
await checkPackage('splat-training', [...splatLines, ...trainingLines]);
