// Exercise workspace discovery through the launcher, including paths that
// collide even though the program never imports them.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {mkdir, mkdtemp, rm, symlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {promisify} from 'node:util';

const root = process.argv[2];
const area = await mkdtemp(join(tmpdir(), 'snail-workspaces-'));
const app = join(area, 'app'), team = join(area, 'shared/team');
const nested = join(app, 'tools'), manifest = 'snail-scheme-workspace.datum';
const execute = promisify(execFile);
const snail = (action, file = 'main.scm') => execute(join(root, 'snail-scheme'),
  [action, '--target', 'node', file], {cwd: nested, maxBuffer: 8 * 1024 * 1024});

async function put(path, text) {
  await mkdir(dirname(path), {recursive: true});
  await writeFile(path, text);
}

const extendsPath = path => `(workspace (extends ${JSON.stringify(path)}))\n`;

try {
  await put(join(team, manifest), extendsPath(root));
  await mkdir(join(team, 'child'));
  // Resolve a link before applying ..; the lexical parent is a different repo.
  await symlink(join(team, 'child'), join(area, 'alias'));
  await put(join(app, manifest), extendsPath('../alias/..'));
  await put(join(team, 'src/demo/shared.sld'), `(define-library (demo shared)
  (export answer)
  (import (snail core base))
  (begin (define (answer) (→ I64) 42)))\n`);
  await put(join(app, 'src/demo/local.sld'), `(define-library (demo local)
  (export message)
  (import (snail core base) (demo shared))
  (begin (define (message) (→ String) (show (answer)))))\n`);
  await put(join(nested, 'main.scm'), `(import (snail core base) (snail core io) (demo local))
(define (main (out OutputPort)) (→ Unit) (write-line out (message)))\n`);
  await mkdir(join(nested, 'src')); // An incidental src/ below the declaration.
  assert.equal((await snail('run')).stdout, '42\n');
  assert.equal((await snail('build')).stdout.trim(), join(app, 'build/tools/main'));
  assert.match((await snail('wat')).stdout, /^\(module/);

  // A nearer declaration selects its own root. It may contain only scripts.
  await rm(join(nested, 'src'), {recursive: true});
  await put(join(nested, manifest), extendsPath('..'));
  assert.equal((await snail('build')).stdout.trim(), join(nested, 'build/main'));
  await rm(join(nested, manifest));

  const asset = 'src/demo/unused.txt', a = join(app, asset), b = join(team, asset);
  await put(a, 'app');
  await put(b, 'base');
  const bothOwners = error => error.stderr.includes('workspace source conflict')
    && error.stderr.includes(a) && error.stderr.includes(b);
  await assert.rejects(snail('build'), bothOwners);
  await rm(a);
  await mkdir(a);
  await assert.rejects(snail('wat'), bothOwners);
  await rm(a, {recursive: true});

  // A third layer can conflict with the app across a disjoint middle layer.
  await put(join(app, 'src/snail/core/base.sld'), '');
  await assert.rejects(snail('wat'), error => error.stderr.includes(join(root, 'src/snail/core/base.sld'))
    && error.stderr.includes(join(app, 'src/snail/core/base.sld')));
  await rm(join(app, 'src/snail'), {recursive: true});

  await symlink(app, join(team, 'back'));
  await put(join(team, manifest), extendsPath('back'));
  await assert.rejects(snail('wat'), error => error.stderr.includes('workspace base cycle')
    && error.stderr.includes(app) && error.stderr.includes(team));
  await put(join(app, manifest), '(workspace (extends "one") (extends "two"))');
  await assert.rejects(snail('wat'), error => error.stderr.includes(manifest) && error.stderr.includes('expected'));
  await put(join(app, manifest), extendsPath('missing'));
  await assert.rejects(snail('build'), error => error.stderr.includes(join(app, 'missing')));
  await put(join(app, manifest), '(workspace)');
  await assert.rejects(snail('wat'), /library not found/);

  // An older compiler checkout can be the terminal base without a manifest.
  const old = join(area, 'older');
  await mkdir(old);
  await symlink(join(root, 'src'), join(old, 'src'));
  await put(join(team, manifest), extendsPath(old));
  await put(join(app, manifest), extendsPath('../shared/team'));
  assert.equal((await snail('run')).stdout, '42\n');
  console.log('workspaces passed');
} finally {
  await rm(area, {recursive: true, force: true});
}
