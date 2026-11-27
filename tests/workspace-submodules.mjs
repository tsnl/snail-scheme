// A named workspace base follows an already provisioned submodule by its
// GitHub repository, wherever the application keeps the checkout.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {copyFile, mkdir, mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promisify} from 'node:util';

const root = process.argv[2], execute = promisify(execFile);
const area = await mkdtemp(join(tmpdir(), 'snail-named-base-'));
const app = join(area, 'app'), upstream = join(area, 'upstream');
const manifest = 'snail-scheme-workspace.datum', repo = 'github.com:Acme/Shared';
const checkout = 'tool sources/shared', section = 'submodule.Shared "local".source';
const env = {...process.env, GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1',
  GIT_TERMINAL_PROMPT: '0', GIT_ALLOW_PROTOCOL: 'file'};

const git = (cwd, ...args) => execute('git',
  ['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false', ...args],
  {cwd, env});
const setting = (key, value) => git(app, 'config', '--file', '.gitmodules', key, value);
const snail = (action, cwd = app) => execute(join(root, 'snail-scheme'),
  [action, '--target', 'node', 'main.scm'], {cwd, env: {...env, GIT_ALLOW_PROTOCOL: ''}, maxBuffer: 8 * 1024 * 1024});
const extend = (cwd, id) => writeFile(join(cwd, manifest), `(workspace (extends ${JSON.stringify(id)}))\n`);

try {
  await mkdir(join(upstream, 'src/acme'), {recursive: true});
  await extend(upstream, root);
  await writeFile(join(upstream, 'src/acme/name.sld'), `(define-library (acme name)
  (export greeting)
  (import (snail core base))
  (begin (define (greeting) (→ String) "from the submodule")))\n`);
  await git(upstream, 'init', '--quiet');
  await git(upstream, 'add', '.');
  await git(upstream, 'commit', '--quiet', '-m', 'Base fixture');

  await mkdir(app);
  await git(app, 'init', '--quiet');
  await git(app, 'submodule', 'add', '--quiet', '--name', 'Shared "local".source', upstream, checkout);
  await extend(app, repo);
  await writeFile(join(app, 'main.scm'), `(import (snail core base) (snail core io) (acme name))
(define (main (out OutputPort)) (→ Unit) (write-line out (greeting)))\n`);

  // Only the local fixture clone uses a transport. Published submodule URLs
  // exercise the lookup with every Git transport disabled in Snail.
  await setting(section + '.url', 'https://github.com/acme/shared.git');
  assert.equal((await snail('run')).stdout, 'from the submodule\n');
  await setting(section + '.url', 'git@github.com:ACME/SHARED.git');
  assert.equal((await snail('build')).stdout.trim(), join(app, 'build/main'));
  await setting(section + '.url', 'ssh://git@github.com/Acme/Shared.git');
  assert.match((await snail('wat')).stdout, /^\(module/);

  // Each layer reads its own .gitmodules even when the build starts in a child.
  const child = join(area, 'child');
  await mkdir(child);
  await extend(child, '../app');
  await copyFile(join(app, 'main.scm'), join(child, 'main.scm'));
  assert.equal((await snail('run', child)).stdout, 'from the submodule\n');

  await setting('submodule.other.url', 'https://github.com/acme/shared');
  await setting('submodule.other.path', 'second copy');
  await assert.rejects(snail('wat'), e => e.stderr.includes('multiple submodules')
    && e.stderr.includes(checkout) && e.stderr.includes('second copy'));
  await git(app, 'config', '--file', '.gitmodules', '--remove-section', 'submodule.other');

  await extend(app, 'github.com:other/shared');
  await assert.rejects(snail('wat'), e => e.stderr.includes('other/shared') && e.stderr.includes('.gitmodules'));
  await extend(app, 'github.com:acme');
  await assert.rejects(snail('wat'), /expected github.com:OWNER\/REPO/);
  await extend(app, repo);
  await git(app, 'submodule', 'deinit', '--quiet', '--force', '--', checkout);
  await assert.rejects(snail('build'), e => e.stderr.includes(checkout)
    && e.stderr.includes('git submodule update --init --recursive'));
  console.log('named workspace bases passed');
} finally {
  await rm(area, {recursive: true, force: true});
}
