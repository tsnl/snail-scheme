// A generated library whose recipe reads a zip archive's members from the
// web into the machine's cache ((snail shell web zip)), against a server
// here that answers ranges of tests/programs/data/notes.zip:
//
//   node tests/web-zip.mjs ROOT
//
// The first build asks for the archive's length, its end and the members
// the recipe wants, and links them; the program reads them back. The next
// build asks the server for nothing, and one with a member gone from the
// cache asks for that member alone. An archive whose end is not the
// pinned one fails the build, naming the digest it has, as does a server
// that answers a part with the whole file, one that answers with another
// part, and one that answers 404.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promisify} from 'node:util';

const execute = promisify(execFile), root = process.argv[2];
const archive = await readFile(join(root, 'tests/programs/data/notes.zip'));

// The archive's end, from its directory on: Zip64's end record, 56 bytes
// before its locator, says where the directory starts.
const record = archive.length - 22 - 20 - 56;
const end = archive.subarray(Number(archive.readBigUInt64LE(record + 48)));
const pin = createHash('sha256').update(end).digest('hex');

// What the server was asked for, as `METHOD RANGE PATH`.
const asked = [];
const server = createServer((request, response) => {
  const range = /^bytes=(\d+)-(\d+)$/.exec(request.headers.range ?? '');
  asked.push(`${request.method} ${request.headers.range ?? '-'} ${request.url}`);
  if (request.url === '/missing.zip') return response.writeHead(404).end();
  if (request.method === 'HEAD') return response.writeHead(200, {'Content-Length': archive.length}).end();
  if (!range || request.url === '/whole.zip') return response.writeHead(200).end(archive);
  // The shifted archive answers each part one byte later than asked.
  const shift = request.url === '/shifted.zip' ? 1 : 0;
  const [first, last] = [Number(range[1]) + shift, Number(range[2]) + shift];
  response.writeHead(206, {'Content-Range': `bytes ${first}-${last}/${archive.length}`});
  response.end(archive.subarray(first, last + 1));
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const url = name => `http://127.0.0.1:${server.address().port}/${name}`;

const workspace = await mkdtemp(join(tmpdir(), 'snail-web-zip-'));
const cache = join(workspace, 'cache');
const put = async (name, text) => {
  await mkdir(join(workspace, name, '..'), {recursive: true});
  await writeFile(join(workspace, name), text);
};

// The library of the archive's members but its empty one, each linked
// from the cache; the program prints each one's name and length.
const recipe = (address, end) => `(generate-library (sample notes)
  (import
   (snail core base)
   (only (snail core io) Fs ProcessEnvironment)
   (only (snail shell web) Web)
   (snail shell web zip)
   (snail shell syntax))
  (lambda ((fs Fs) (web Web) (environment ProcessEnvironment))
    (library-syntax (list "sample" "notes")
                    (list "notes")
                    (list (list "snail" "core" "base") (list "snail" "shell" "resource"))
                    (list (linked-files "notes"
                                        (zip-members fs web (machine-cache environment)
                                                     (new WebZip (url "${address}") (end "${end}"))
                                                     (lambda (name) (not (string=? name "notes/empty.txt")))))))))
`;
const program = `(import
 (snail core base)
 (snail core io)
 (snail shell resource)
 (sample notes))

(define (main (resources Resources) (out OutputPort)) (→ Unit)
  (for-each (lambda (note)
              (write-line out (string-append (● note first) " "
                                             (show (array-length (read-resource resources (● note second)))))))
            notes))
`;
const run = () => execute(join(root, 'snail-scheme'), ['run', '--target', 'node', 'main.scm'],
                          {cwd: workspace, env: {...process.env, XDG_CACHE_HOME: cache}});
const failure = async () => {
  const outcome = await run().then(() => null, error => error.stderr);
  assert.ok(outcome, 'the build fails');
  return outcome;
};
const printed = ['notes/stored.txt 15', 'notes/fixed.txt 40', 'notes/dynamic.txt 1990', 'notes/run.bin 605',
                 'notes/stored-blocks.bin 768', 'notes/skewed.bin 4096'];

try {
  await put('src/sample/notes.sld', recipe(url('notes.zip'), pin));
  await put('main.scm', program);

  const first = await run();
  assert.deepEqual(first.stdout.trim().split('\n'), printed);
  assert.deepEqual(asked.slice(0, 3).map(line => line.split(' ')[0]), ['HEAD', 'GET', 'GET'],
                   'the length, the last bytes, then the end');
  assert.equal(asked.length, 3 + printed.length, 'then each wanted member, once');
  assert.deepEqual(await readFile(join(cache, 'snail-scheme', 'zip', `${pin}.end`)), end, 'the end is kept as pinned');
  assert.equal((await readFile(join(cache, 'snail-scheme', 'zip', pin, 'notes/fixed.txt'), 'utf8')),
               'A short line, coded by the fixed codes.\n');

  asked.length = 0;
  assert.deepEqual((await run()).stdout.trim().split('\n'), printed);
  assert.deepEqual(asked, [], 'a build that finds the members kept asks for nothing');

  await rm(join(cache, 'snail-scheme', 'zip', pin, 'notes/run.bin'));
  assert.deepEqual((await run()).stdout.trim().split('\n'), printed);
  assert.equal(asked.length, 1, 'a member gone from the cache is fetched alone');
  assert.match(asked[0], /^GET bytes=\d+-\d+ \/notes\.zip$/);

  const other = '0'.repeat(64);
  await put('src/sample/notes.sld', recipe(url('notes.zip'), other));
  assert.match(await failure(), new RegExp(`the end of \\S+ has the SHA-256 ${pin}, not the pinned ${other}`));

  await put('src/sample/notes.sld', recipe(url('whole.zip'), `${pin.slice(0, 63)}x`));
  assert.match(await failure(), /the server answers with the whole file, not a part of it/);

  await put('src/sample/notes.sld', recipe(url('shifted.zip'), `${pin.slice(0, 63)}z`));
  assert.match(await failure(), /the server answers with another part than was asked for/);

  await put('src/sample/notes.sld', recipe(url('missing.zip'), `${pin.slice(0, 63)}y`));
  assert.match(await failure(), /cannot read \S+missing\.zip: the server answers 404/);
} finally {
  server.close();
  await rm(workspace, {recursive: true, force: true});
}
