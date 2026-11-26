// Source packages through the public command line, in independent checkouts.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {mkdir, mkdtemp, readFile, readdir, rename, rm, symlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {promisify} from 'node:util';

const exec = promisify(execFile), root = process.argv[2];
const area = await mkdtemp(join(tmpdir(), 'snail-packages-'));
const app = join(area, 'private app'), library = join(area, 'shared'), remote = join(area, 'upstream');
const snail = (...args) => exec(join(root, 'snail-scheme'), args, {cwd: app, maxBuffer: 16 * 1024 * 1024});
const git = (...args) => exec('git', ['-c', 'user.name=Snail', '-c', 'user.email=test@localhost',
  '-c', 'commit.gpgSign=false', ...args], {cwd: remote});
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
  const pinned = commit => `(words (git ${JSON.stringify(pathToFileURL(remote).href)} "${commit}"))`;
  await pkg(app, depends(standard, pinned('main')));
  await assert.rejects(snail('deps'), /full 40-digit lowercase Git commit ID/);
  await pkg(app, depends(standard, pinned('0'.repeat(40))));
  await assert.rejects(snail('deps'), /git failed/);
  const cache = join(app, 'build/.snail-packages');
  assert.deepEqual(await readdir(cache), []);
  await pkg(app, depends(standard, pinned(rev)));
  await assert.rejects(run(), /run snail-scheme deps/);
  const installs = await Promise.all([snail('deps'), snail('deps', '.')]);
  assert.equal(installs[0].stdout, installs[1].stdout);
  const checkouts = await readdir(cache);
  assert.equal(checkouts.length, 1);
  await rename(remote, join(area, 'offline'));
  assert.equal((await run()).stdout, 'pinned\n');
  const cached = join(cache, checkouts[0]);
  assert.equal(await readFile(join(cached, 'package.scm'), 'utf8'), '(package words (depends (data (path "data"))))');
  await put(cached, 'data/src/acme/messages/greeting.sld', textLibrary('acme messages greeting', 'edited pin'));
  await assert.rejects(run(), /modified Git package checkout/);
  console.log('source packages passed');
} finally {
  await rm(area, {recursive: true, force: true});
}
