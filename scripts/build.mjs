#!/usr/bin/env node
// A cold build immediately accepts the shared builder's completed candidate.
import {mkdirSync, mkdtempSync, rmSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {isMainThread, parentPort, Worker, workerData} from 'node:worker_threads';
import {createProjectBuilder, projectTools, publishProject} from './project.mjs';

function request([root, ...args]) {
  const mode = args[0] === '--release' ? (args.shift(), 'release') : 'debug';
  if (args.length !== 2) throw new Error('usage: lofi build [--release] PROJECT TARGET');
  return {root, project: resolve(args[0]), target: args[1], mode};
}

if (isMainThread) {
  let directory;
  try {
    const job = request(process.argv.slice(2)), tools = projectTools(job.root);
    mkdirSync(join(job.root, 'build/lofi-run'), {recursive: true});
    directory = mkdtempSync(join(job.root, 'build/lofi-run/project-'));
    const worker = new Worker(new URL(import.meta.url), {workerData: {...job, tools, directory}, resourceLimits: {maxYoungGenerationSizeMb: 384}});
    process.exitCode = 1;
    worker.on('message', output => { console.log(output); process.exitCode = 0; });
    worker.on('error', error => console.error(`lofi: ${error.message}`));
    worker.on('exit', code => { if (code) process.exitCode = 1; rmSync(directory, {recursive: true, force: true}); });
  } catch (error) {
    if (directory) rmSync(directory, {recursive: true, force: true});
    console.error(`lofi: ${error.message}`);
    process.exitCode = 1;
  }
} else {
  const builder = await createProjectBuilder(workerData);
  try {
    publishProject(builder.build(builder.describe(), [workerData.target], workerData.mode));
    parentPort.postMessage(join(workerData.project, 'build', workerData.target));
  } finally { builder.close(); }
}
