// Source packages through the public command line, in independent checkouts.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {copyFile, mkdir, mkdtemp, readFile, readdir, rename, rm, stat, symlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {promisify} from 'node:util';

const exec = promisify(execFile), root = process.argv[2];
const area = await mkdtemp(join(tmpdir(), 'snail-packages-'));
const app = join(area, 'private app'), library = join(area, 'shared'), remote = join(area, 'upstream');
const snail = (...args) => exec(join(root, 'snail-scheme'), args, {cwd: app, maxBuffer: 16 * 1024 * 1024});
const gitAt = (cwd, ...args) => exec('git', ['-c', 'user.name=Snail', '-c', 'user.email=test@localhost',
  '-c', 'commit.gpgSign=false', '-c', 'tag.gpgSign=false', ...args], {cwd});
const git = (...args) => gitAt(remote, ...args);
const put = async (directory, name, text) => {
  const file = join(directory, name);
  await mkdir(dirname(file), {recursive: true});
  await writeFile(file, text);
};
const pkg = (directory, declaration) => put(directory, 'package.scm', declaration);
const textLibrary = (name, value) =>
  `(define-library (${name}) (export greeting) (import (snail core base))
     (begin (define (greeting) (→ String) ${JSON.stringify(value)})))`;
const program = '(import (snail core base) (snail core io) (acme messages greeting))\n' +
  '(define (main (out OutputPort)) (→ Unit) (write-line out (greeting)))\n';
const run = () => snail('run', '--target', 'node', 'main.scm');
const wat = () => snail('wat', '--target', 'node', 'main.scm');
const standard = `(snail-scheme (path ${JSON.stringify(root)}))`;
const depends = (...edges) => `(package private-app (depends ${edges.join(' ')}))`;

try {
  await pkg(app, depends('(left (path "../left"))', '(right (path "../right"))'));
  await pkg(join(area, 'left'), '(package left (depends (shared (path "../shared"))))');
  await symlink(library, join(area, 'alias'));
  await pkg(join(area, 'right'), '(package right (depends (shared (path "../alias"))))');
  await pkg(library, `(package shared (export "acme") (depends ${standard}))`);
  await put(library, 'src/acme/messages/greeting.sld', textLibrary('acme messages greeting', 'shared checkout'));
  await put(library, 'src/private/secret.sld', textLibrary('private secret', 'private'));
  await put(app, 'main.scm', program);
  await put(app, 'src/acme/messages/beside.txt', 'shared directory');
  // The toolchain's own app sources stay out of its export.
  await put(app, 'src/apps/siegework/main.scm', 'owned by the private app');
  const members = (await snail('deps')).stdout.trim().split('\n').map(line => line.split(' ')[0]).sort();
  assert.deepEqual(members, ['left', 'private-app', 'right', 'shared', 'snail-scheme']);
  assert.equal((await run()).stdout, 'shared checkout\n');
  assert.match((await wat()).stdout, /^\(module/);
  assert.equal((await snail('build', '--target', 'browser', 'main.scm')).stdout.trim(), join(app, 'build/main'));
  await put(app, 'main.scm', program.replace('(acme messages greeting)', '(private secret)'));
  await assert.rejects(wat(), /library not found: \(private secret\)/);
  await put(app, 'main.scm', program.replace('(acme messages greeting)', '(acme .. private secret)'));
  await assert.rejects(wat(), /library name made of path components/);
  await put(app, 'main.scm', program);
  await put(library, 'src/acme/messages/greeting.sld', textLibrary('acme messages greeting', 'edited'));
  assert.equal((await run()).stdout, 'edited\n');

  // A dependency's generator imports through the package graph, and links
  // its input beside the original recipe in the checkout.
  await put(library, 'src/acme/messages/input.txt', ' from a linked file');
  await put(library, 'src/acme/messages/generated.sld', `(generate-library (acme messages generated)
    (import (snail core base) (snail shell syntax) (snail shell resource) (snail shell utf8)
            (acme messages greeting))
    (lambda ((resources Resources))
      (let ((text (match (utf8->string (read-resource resources (link-file "input.txt")))
                    ((Ok text) text) ((Err _) (panic "expected UTF-8")))))
        (library-syntax (list "acme" "messages" "generated") (list "greeting")
          (list (list "snail" "core" "base"))
          (list (form "define" (list (form "greeting" (Nil)) (form "→" (list (SymbolSyntax "String")))
                    (StringSyntax (string-append (greeting) text)))))))))`);
  await put(app, 'main.scm', program.replace('(acme messages greeting)', '(acme messages generated)'));
  assert.equal((await run()).stdout, 'edited from a linked file\n');
  await put(app, 'main.scm', program);

  // Even identical, unused assets cannot be supplied twice. Shared empty
  // directories merge; a file and an empty directory cannot occupy one path.
  await put(library, 'src/acme/messages/beside.txt', 'shared directory');
  await assert.rejects(wat(), error => error.stderr.includes('conflicting src/acme/messages/beside.txt') &&
    error.stderr.includes('private-app') && error.stderr.includes('shared'));
  await rm(join(library, 'src/acme/messages/beside.txt'));
  await mkdir(join(library, 'src/acme/messages/beside.txt'));
  await assert.rejects(run(), /conflicting src\/acme\/messages\/beside.txt/);
  await rm(join(app, 'src/acme/messages/beside.txt'));
  await mkdir(join(app, 'src/acme/messages/beside.txt'));
  await put(app, 'src/snail/core/base.sld', 'duplicate');
  await assert.rejects(snail('deps'), /conflicting src\/snail\/core\/base.sld/);
  await rm(join(app, 'src/snail/core/base.sld'));

  await pkg(join(area, 'right'), '(package right (depends (shared (path "../other"))))');
  await pkg(join(area, 'other'), '(package shared)');
  await assert.rejects(snail('deps'), /package shared has two sources/);
  await pkg(join(area, 'right'), '(package right (depends (private-app (path "../private app"))))');
  await assert.rejects(snail('deps'), /private-app → right → private-app/);
  await pkg(join(area, 'right'), '(package wrong-name)');
  await assert.rejects(snail('deps'), /expected package right, found wrong-name/);
  await pkg(app, '(package private-app)');
  await assert.rejects(wat(), /library not found: \(snail core base\)/);

  // Fetch the exact commit from a local Git remote, including another
  // package inside it. Move the remote away after installation to exercise
  // offline builds. Concurrent installs publish just one finished checkout.
  await pkg(remote, '(package words (depends (data (path "data"))))');
  await pkg(join(remote, 'data'), '(package data)');
  await put(remote, 'data/src/acme/messages/greeting.sld', textLibrary('acme messages greeting', 'pinned'));
  await git('init', '--quiet');
  await git('add', '.');
  await git('commit', '--quiet', '-m', 'First greeting');
  const rev = (await git('rev-parse', 'HEAD')).stdout.trim();
  await put(remote, 'data/src/acme/messages/greeting.sld', textLibrary('acme messages greeting', 'new HEAD'));
  await git('commit', '--quiet', '-am', 'Change the greeting on the branch');
  const url = pathToFileURL(remote).href;
  const pinned = ref => `(words (git ${JSON.stringify(url)} ${JSON.stringify(ref)}))`;
  const lock = join(app, 'package.lock'), cache = join(app, 'build/.snail-packages');
  await git('branch', 'branch-only');
  await git('branch', 'stable'); // The tag of the same name identifies a different commit.
  await git('tag', 'stable', rev);
  await git('tag', '-am', 'first release', 'releases/v1', rev);
  await git('tag', 'not-a-commit', `${rev}^{tree}`);
  await git('tag', 'nested/refs/tags/absent', rev); // ls-remote matches ref tails.

  for (const ref of ['branch-only', 'absent', rev.slice(0, 8)]) {
    await pkg(app, depends(standard, pinned(ref)));
    await assert.rejects(snail('deps'), /Git tag not found/);
  }
  await pkg(app, depends(standard, pinned('refs/heads/stable')));
  await assert.rejects(snail('deps'), /expected a Git tag or full commit hash/);
  await pkg(app, depends(standard, pinned('stable^{tree}')));
  await assert.rejects(snail('deps'), /invalid Git tag/);
  await pkg(app, depends(standard, pinned('0'.repeat(40))));
  await assert.rejects(snail('deps'), /git failed/);
  await pkg(app, depends(standard, pinned('not-a-commit')));
  await assert.rejects(snail('deps'), /git failed/);
  assert.deepEqual(await readdir(cache), []);
  await assert.rejects(readFile(lock), {code: 'ENOENT'});

  await pkg(app, depends(standard, pinned(rev.toUpperCase())));
  await assert.rejects(run(), /run snail-scheme deps/);
  await snail('deps');
  await assert.rejects(readFile(lock), {code: 'ENOENT'}); // The hash pins itself.
  const [checkout] = await readdir(cache);
  const cached = join(cache, checkout);
  const declared = depends(standard, pinned('refs/tags/releases/v1'), pinned(rev),
    '(bundle (path "../bundle"))');
  await pkg(join(area, 'bundle'), `(package bundle (depends ${pinned('stable')}))`);
  await pkg(app, declared);
  await assert.rejects(run(), /unlocked Git tag.*run snail-scheme deps/);
  const installs = await Promise.all([snail('deps'), snail('deps', '.')]);
  assert.equal(installs[0].stdout, installs[1].stdout);
  assert.deepEqual(await readdir(cache), [checkout], 'two tags and a hash share the checkout');
  const pins = await readFile(lock, 'utf8');
  assert.equal(pins, `(package-lock\n  ("${url}" "releases/v1" "${rev}")\n  ("${url}" "stable" "${rev}"))\n`);
  const originalWrite = (await stat(lock, {bigint: true})).mtimeNs;
  await snail('deps');
  assert.equal((await stat(lock, {bigint: true})).mtimeNs, originalWrite);
  await git('tag', '-f', 'releases/v1', 'HEAD');
  await git('tag', '-d', 'stable');

  // A collaborator with only the manifest and lock can reinstall the original
  // commits, including the transitive tag that disappeared from the remote.
  const fresh = join(area, 'fresh');
  await pkg(fresh, declared);
  await copyFile(lock, join(fresh, 'package.lock'));
  await put(fresh, 'main.scm', program);
  await snail('deps', fresh);
  assert.equal((await snail('run', '--target', 'node', join(fresh, 'main.scm'))).stdout, 'pinned\n');

  // A bad lock reports its error in place. Removing a pin lets the next
  // install resolve that tag again.
  await pkg(fresh, depends(standard, pinned('releases/v1')));
  const freshLock = join(fresh, 'package.lock');
  const badPin = `(package-lock ("${url}" "releases/v1" "broken"))\n`;
  await writeFile(freshLock, badPin);
  await assert.rejects(snail('deps', fresh), /expected a full commit hash in package.lock/);
  assert.equal(await readFile(freshLock, 'utf8'), badPin);
  await writeFile(freshLock, '(package-lock)\n');
  await snail('deps', fresh);
  assert.equal((await snail('run', '--target', 'node', join(fresh, 'main.scm'))).stdout, 'new HEAD\n');

  // A failed graph never publishes a new tag selection. Changing the
  // manifest to a new tag advances the commit and prunes old pins.
  await git('tag', 'v2');
  await pkg(app, depends(standard, pinned('releases/v1'), pinned('v2')));
  await assert.rejects(snail('deps'), /package words has two sources/);
  assert.equal(await readFile(lock, 'utf8'), pins);
  await pkg(app, depends(standard, pinned('v2')));
  await snail('deps');
  assert.equal((await run()).stdout, 'new HEAD\n');
  const next = (await git('rev-parse', 'HEAD')).stdout.trim();
  assert.equal(await readFile(lock, 'utf8'), `(package-lock\n  ("${url}" "v2" "${next}"))\n`);

  await pkg(app, declared);
  await writeFile(lock, pins);
  await rename(remote, join(area, 'offline'));
  await snail('deps');
  assert.equal((await run()).stdout, 'pinned\n');
  assert.equal(await readFile(join(cached, 'package.scm'), 'utf8'), '(package words (depends (data (path "data"))))');
  await put(cached, 'data/src/acme/messages/greeting.sld', textLibrary('acme messages greeting', 'edited pin'));
  await assert.rejects(run(), /modified Git package checkout/);

  // Full Git object IDs also cover SHA-256 repositories.
  const sha256 = join(area, 'sha256');
  await pkg(sha256, '(package newer)');
  await gitAt(sha256, 'init', '--quiet', '--object-format=sha256');
  await gitAt(sha256, 'add', '.');
  await gitAt(sha256, 'commit', '--quiet', '-m', 'First package');
  await gitAt(sha256, 'tag', '-am', 'release', 'v1');
  const longHash = (await gitAt(sha256, 'rev-parse', 'HEAD')).stdout.trim();
  const longUrl = pathToFileURL(sha256).href;
  assert.equal(longHash.length, 64);
  await pkg(app, depends(`(newer (git "${longUrl}" "v1"))`, `(newer (git "${longUrl}" "${longHash}"))`));
  assert.equal((await snail('deps')).stdout.split('\n').filter(line => line.startsWith('newer ')).length, 1);
  assert.equal(await readFile(lock, 'utf8'), `(package-lock\n  ("${longUrl}" "v1" "${longHash}"))\n`);
  console.log('source packages passed');
} finally {
  await rm(area, {recursive: true, force: true});
}
