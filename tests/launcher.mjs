// `./snail-scheme` asks stage 0 for its tools only when something stage 0's
// rule reads may have changed. The launcher runs here in a root of its own,
// with stage 0 (scripts/bootstrap) and Node replaced by scripts that count
// their calls, so nothing is built:
//
//   node tests/launcher.mjs ROOT
//
// A second call reuses the first's answer; an edit to a source, the runtime
// crate or stage 0, a missing tool, and an edit made while stage 0 runs each
// ask again; a file that is no input does not; a failure caches nothing;
// and every command shares the answer.
import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

const repository = process.argv[2];
const root = mkdtempSync(join(tmpdir(), 'snail-launcher-'));
const at = name => join(root, name);
const put = (name, text = '') => {
  mkdirSync(join(at(name), '..'), {recursive: true});
  writeFileSync(at(name), text);
};
const touch = name => execFileSync('touch', [at(name)]);
const calls = name => existsSync(at(name)) ? readFileSync(at(name), 'utf8').split('\n').filter(Boolean) : [];

// Stage 0 names the command line and the two runtimes, making each. It can
// be told to fail, or to edit a source while it runs.
const stage0 = `#!/bin/sh
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
echo bootstrap >> "$root/stage0.calls"
[ -f "$root/stage0.fails" ] && exit 1
[ -f "$root/stage0.edits" ] && touch "$root/src/a.sld"
mkdir -p "$root/build"
for tool in cli runtime toolchain; do : > "$root/build/$tool.wasm"; echo "$root/build/$tool.wasm"; done
`;
// Node records its arguments.
const node = `#!/bin/sh
echo "$*" >> "${root}/node.calls"
`;

try {
  copyFileSync(join(repository, 'snail-scheme'), at('snail-scheme'));
  put('scripts/bootstrap', stage0);
  put('node', node);
  for (const name of ['snail-scheme', 'scripts/bootstrap', 'node']) chmodSync(at(name), 0o755);
  for (const name of ['src/a.sld', 'bootstrap/cli.scm',
    'host/browser/host.mjs', 'host/chez/load.scm', 'rust-toolchain.toml',
    'crates/snail-scheme-support/Cargo.toml', 'crates/snail-scheme-support/src/lib.rs']) put(name);

  const snail = (...args) => spawnSync(at('snail-scheme'), args, {env: {...process.env, NODE: at('node')}, encoding: 'utf8'});
  const tools = `${at('build/cli.wasm')} ${root} ${at('build/runtime.wasm')} ${at('build/toolchain.wasm')}`;
  const build = () => {
    const result = snail('build', 'project', 'target');
    assert.equal(result.status, 0, result.stderr);
    return calls('stage0.calls').length;
  };

  assert.equal(build(), 1, 'the first call asks stage 0');
  assert.match(calls('node.calls')[0], new RegExp(`${tools} build project target$`));
  assert.equal(build(), 1, 'the second reuses its answer');

  for (const input of ['src/a.sld', 'bootstrap/cli.scm', 'crates/snail-scheme-support/src/lib.rs', 'rust-toolchain.toml', 'host/chez/load.scm']) {
    const before = calls('stage0.calls').length;
    touch(input);
    assert.equal(build(), before + 1, `an edit to ${input} asks again`);
    assert.equal(build(), before + 1);
  }
  touch('host/browser/host.mjs');
  assert.equal(build(), 6, 'a file stage 0 does not read is no reason to ask');

  rmSync(at('build/cli.wasm'));
  assert.equal(build(), 7, 'a missing tool asks again');
  assert.ok(existsSync(at('build/cli.wasm')));

  put('stage0.edits');
  touch('src/a.sld');
  assert.equal(build(), 8);
  rmSync(at('stage0.edits'));
  assert.equal(build(), 9, 'an edit made while stage 0 runs is newer than its answer');
  assert.equal(build(), 9);

  put('stage0.fails');
  touch('src/a.sld');
  const before = calls('node.calls').length;
  assert.notEqual(snail('build', 'project', 'target').status, 0, "stage 0's failure is the command's");
  assert.equal(calls('node.calls').length, before, 'and runs nothing');
  rmSync(at('stage0.fails'));
  assert.equal(build(), 11, 'a failure keeps no answer');

  for (const command of [['lsp'], ['run', 'project', 'target'], ['format', '--check', 'a.sld']]) {
    const result = snail(...command);
    assert.equal(result.status, 0, result.stderr);
    assert.match(calls('node.calls').at(-1), new RegExp(`${tools} ${command.join(' ')}$`));
  }
  assert.equal(calls('stage0.calls').length, 11, 'every command shares the answer');
  for (const unknown of ['dev', 'watch']) assert.notEqual(snail(unknown).status, 0, `${unknown} is refused`);
  console.log('launcher: cached tools, inputs, missing tools, edits while building, failures, every command');
} finally {
  rmSync(root, {recursive: true, force: true});
}
