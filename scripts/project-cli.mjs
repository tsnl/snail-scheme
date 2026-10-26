#!/usr/bin/env node
// A cold build publishes one candidate. Run then becomes that exact program.
import {mkdirSync, mkdtempSync, rmSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {createProjectBuilder, projectTools, publishProject} from './project.mjs';

function request([root, action, ...args]) {
  const mode = action === 'build' && args[0] === '--release' ? (args.shift(), 'release') : 'debug';
  if (!['build', 'run'].includes(action) || args.length < 2 || (action === 'build' && args.length !== 2)) {
    throw new Error('usage: lofi build [--release] PROJECT BUILD-TARGET | lofi run PROJECT RUN-TARGET [ARGUMENT ...]');
  }
  return {root, action, project: resolve(args[0]), target: args[1], args: args.slice(2), mode};
}

async function build(job) {
  const tools = projectTools(job.root);
  mkdirSync(join(job.root, 'build/lofi-run'), {recursive: true});
  const directory = mkdtempSync(join(job.root, 'build/lofi-run/project-'));
  let builder, result, failure;
  try {
    builder = await createProjectBuilder({...job, tools, directory});
    const description = builder.describe();
    const run = job.action === 'run' ? description.runs.find(run => run.name === job.target) : null;
    if (job.action === 'run' && !run) throw new Error(`unknown project run target ${job.target}`);
    const target = run?.build ?? job.target;
    const candidate = builder.build(description, [target], job.mode);
    result = {directory: candidate.targets.find(output => output.name === target).directory,
      args: [...(run?.args ?? []), ...job.args]};
    publishProject(candidate);
  } catch (error) { failure = error; }
  try { builder?.close(); } catch (error) { failure ??= error; }
  try { rmSync(directory, {recursive: true, force: true}); } catch (error) { failure ??= error; }
  if (failure) throw failure;
  return result;
}

try {
  const job = request(process.argv.slice(2)), result = await build(job);
  if (job.action === 'build') console.log(join(job.project, 'build', job.target));
  else process.execve(process.execPath, [process.execPath, '--no-warnings',
    join(job.root, 'scripts/run-lofi.mjs'), join(result.directory, 'program.wasm'), ...result.args], process.env);
}
catch (error) {
  console.error(`lofi: ${error.message}`);
  process.exitCode = 1;
}
