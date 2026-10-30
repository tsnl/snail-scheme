// `./snail` asks stage 0 for its tools only when something stage 0's rule
// reads may have changed. The launcher runs here in a root of its own, with
// stage 0 (scripts/snail-tool) and Node replaced by scripts that count their
// calls, so nothing is built:
//
//   node tests/launcher.mjs ROOT
//
// A second call reuses the first's answer; an edit to a source, the runtime
// crate or stage 0's driver, a missing tool, and an edit made while stage 0
// runs each ask again; a file that is no input does not; a failure caches
// nothing; and `dev` keeps a list of its own.
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

// Stage 0 names two tools for `build` and four for `dev`, making each. It
// can be told to fail, or to edit a source while it runs.
const stage0 = `#!/bin/sh
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
echo "$1" >> "$root/stage0.calls"
[ -f "$root/stage0.fails" ] && exit 1
[ -f "$root/stage0.edits" ] && touch "$root/src/a.sld"
mkdir -p "$root/build"
case $1 in
  cli-tools) set -- cli runtime ;;
  dev-tools) set -- editor client cli runtime ;;
esac
for tool; do : > "$root/build/$tool.wasm"; echo "$root/build/$tool.wasm"; done
`;
const node = `#!/bin/sh
echo "$*" >> "${root}/node.calls"
`;

try {
  copyFileSync(join(repository, 'snail'), at('snail'));
  put('scripts/snail-tool', stage0);
  put('node', node);
  for (const name of ['snail', 'scripts/snail-tool', 'node']) chmodSync(at(name), 0o755);
  for (const name of ['src/a.sld', 'bootstrap/cli.sld', 'host/ide/ide.sld', 'host/browser/reload.sld',
    'host/browser/host.mjs', 'host/chibi/driver.sld', 'scripts/snail.scm', 'rust-toolchain.toml',
    'crates/snail-core-support/Cargo.toml', 'crates/snail-core-support/src/lib.rs']) put(name);

  const snail = (...args) => spawnSync(at('snail'), args, {env: {...process.env, NODE: at('node')}, encoding: 'utf8'});
  const build = () => {
    const result = snail('build', 'project', 'target');
    assert.equal(result.status, 0, result.stderr);
    return calls('stage0.calls').length;
  };

  assert.equal(build(), 1, 'the first call asks stage 0');
  assert.match(calls('node.calls')[0], new RegExp(`${at('build/cli.wasm')} ${root} ${at('build/runtime.wasm')} build project target$`));
  assert.equal(build(), 1, 'the second reuses its answer');

  for (const input of ['src/a.sld', 'host/ide/ide.sld', 'crates/snail-core-support/src/lib.rs', 'rust-toolchain.toml', 'host/chibi/driver.sld']) {
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

  const dev = snail('dev', 'project');
  assert.equal(dev.status, 0, dev.stderr);
  assert.deepEqual(calls('stage0.calls').slice(-1), ['dev-tools'], '`dev` asks for its own tools');
  assert.match(calls('node.calls').at(-1), / dev .*editor\.wasm .*client\.wasm project$/);
  snail('dev', 'project');
  assert.equal(calls('stage0.calls').length, 12, 'and keeps them apart from build');
  console.log('launcher: cached tools, inputs, missing tools, edits while building, failures and dev');
} finally {
  rmSync(root, {recursive: true, force: true});
}
