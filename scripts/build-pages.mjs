#!/usr/bin/env node
// Assemble only generated public files. Compiler intermediates never enter Pages.
import {existsSync, realpathSync, rmSync} from 'node:fs';
import {join, resolve, sep} from 'node:path';
import {spawnSync} from 'node:child_process';
import {packageApplication} from '../src/browser/build.mjs';
import {checkPages} from './check-pages.mjs';

const root = resolve(import.meta.dirname, '..');
const site = join(root, 'build/pages'), scratch = join(root, 'build/pages-game');

function compiledInput(args) {
  if (!args.length) return undefined;
  if (args.length !== 2 || args[0] !== '--game-artifacts')
    throw new Error('usage: node scripts/build-pages.mjs [--game-artifacts DIRECTORY]');
  const directory = realpathSync(resolve(args[1]));
  for (const output of [site, scratch])
    if (directory === output || directory.startsWith(output + sep)) throw new Error('game artifacts must be outside Pages output directories');
  for (const file of ['simulation.wasm', 'shader.wasm', 'application.syntax.json'])
    if (!existsSync(join(directory, file))) throw new Error(`missing compiled game artifact: ${join(directory, file)}`);
  return directory;
}

function run(command, args) {
  const result = spawnSync(command, args, {cwd: root, stdio: 'inherit'});
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} failed (${result.signal ?? result.status})`);
}

const reused = compiledInput(process.argv.slice(2));
if (!reused) {
  rmSync(scratch, {recursive: true, force: true});
  run(process.env.CHIBI ?? 'chibi-scheme', ['-I', join(root, 'bootstrap'), join(root, 'apps/siegework/build.scm'), root, scratch]);
} else console.log(`Reusing compiled game inputs from ${reused}; compiler was not run.`);
rmSync(site, {recursive: true, force: true});
run(join(root, 'scripts/book'), ['build', '--dest-dir', site]);
await packageApplication(root, join(root, 'apps/siegework'), reused ?? scratch, {output: join(site, 'play/siegework')});
const checked = checkPages(site);
console.log(`Pages ready: ${site}\nChecked ${checked.files} files under /snail-scheme/; Siegework ${checked.generation}.`);
