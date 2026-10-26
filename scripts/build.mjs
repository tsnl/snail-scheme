#!/usr/bin/env node
// A cold build immediately accepts the shared builder's completed candidate.
import {mkdirSync, mkdtempSync, rmSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {createProjectBuilder, projectTools, publishProject} from './project.mjs';

function request([root, ...args]) {
  const mode = args[0] === '--release' ? (args.shift(), 'release') : 'debug';
  if (args.length !== 2) throw new Error('usage: lofi build [--release] PROJECT TARGET');
  return {root, project: resolve(args[0]), target: args[1], mode};
}

async function build(job) {
  const tools = projectTools(job.root);
  mkdirSync(join(job.root, 'build/lofi-run'), {recursive: true});
  const directory = mkdtempSync(join(job.root, 'build/lofi-run/project-'));
  let builder, failure;
  try {
    builder = await createProjectBuilder({...job, tools, directory});
    publishProject(builder.build(builder.describe(), [job.target], job.mode));
  } catch (error) { failure = error; }
  try { builder?.close(); } catch (error) { failure ??= error; }
  try { rmSync(directory, {recursive: true, force: true}); } catch (error) { failure ??= error; }
  if (failure) throw failure;
  return join(job.project, 'build', job.target);
}

try { console.log(await build(request(process.argv.slice(2)))); }
catch (error) {
  console.error(`lofi: ${error.message}`);
  process.exitCode = 1;
}
