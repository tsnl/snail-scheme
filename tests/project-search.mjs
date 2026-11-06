// Saved project text, through the same origin and path boundary as file reads.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtemp, mkdir, writeFile, symlink, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {startDevelopment} from './development-service.mjs';

const root = process.argv[2], project = await mkdtemp(join(tmpdir(), 'snail-search-'));
await mkdir(join(project, 'lib'));
await writeFile(join(project, 'project.datum'), '()');
await writeFile(join(project, 'main.sld'), '; NeedLE\n');
await writeFile(join(project, 'lib/notes.txt'), '😀 needle\r\nsecond NEEDLE\rthird needle\n');
await writeFile(join(project, 'binary.txt'), Buffer.from([0xff, 0x6e]));
await writeFile(join(project, 'zero.txt'), 'needle\0');
await symlink('/etc/passwd', join(project, 'outside.txt'));
const git = (...args) => execFileSync('git', args, {cwd: project, stdio: 'pipe'});
git('init', '-q');
git('config', 'core.excludesFile', '/dev/null');
await writeFile(join(project, '.gitignore'), 'ignored.txt\nignored/\n');
await writeFile(join(project, 'ignored.txt'), 'needle');
await mkdir(join(project, 'ignored'));
await writeFile(join(project, 'ignored/hidden.txt'), 'needle');
await writeFile(join(project, 'ignored/tracked.txt'), 'tracked');
git('add', '-f', 'ignored/tracked.txt');
// A tracked submodule does not poison the outer repository's ignore query.
await mkdir(join(project, 'vendor'));
await writeFile(join(project, 'vendor/file.txt'), 'vendor');
git('update-index', '--add', '--cacheinfo', '160000,1111111111111111111111111111111111111111,vendor');
const service = await startDevelopment(root, project);
const search = async query => {
  const response = await service.get('/api/search?q=' + encodeURIComponent(query));
  assert.equal(response.status, 200); return response.json();
};
try {
  const listing = await (await service.get('/api/project')).json();
  assert.ok(listing.files.includes('.gitignore'));
  assert.ok(listing.files.includes('ignored/tracked.txt'));
  assert.ok(listing.files.includes('vendor/file.txt'));
  assert.ok(listing.directories.includes('ignored'), 'parents of tracked files remain');
  assert.ok(!listing.files.includes('ignored.txt'));
  assert.ok(!listing.files.includes('ignored/hidden.txt'));
  assert.equal((await service.get('/api/file?path=ignored.txt')).status, 200, 'ignores are not an access restriction');
  const found = await search('needle');
  assert.deepEqual(found.hits.map(({path, line, column}) => [path, line, column]), [
    ['lib/notes.txt', 1, 3], ['lib/notes.txt', 2, 8], ['lib/notes.txt', 3, 7], ['main.sld', 1, 3],
  ]);
  assert.equal(found.skipped, 2); assert.equal(found.limited, false);
  const file = await (await service.get('/api/file?path=lib%2Fnotes.txt')).json();
  assert.equal(found.hits[0].revision, file.revision);
  assert.equal(found.hits[0].snippet, '😀 needle');
  assert.equal((await search('absent')).hits.length, 0);
  for (const query of ['', 'x'.repeat(129), '\n', '\0']) {
    assert.equal((await service.get('/api/search?q=' + encodeURIComponent(query))).status, 400);
  }
  assert.equal((await service.request('/api/search?q=needle', 'GET', {Origin: 'https://foreign.example'})).status, 403);
  await writeFile(join(project, 'many.txt'), 'match\n'.repeat(201));
  const capped = await search('match');
  assert.equal(capped.hits.length, 200); assert.equal(capped.limited, true);
  await writeFile(join(project, 'many.txt'), 'match\n'.repeat(200));
  assert.equal((await search('match')).limited, false, 'exactly 200 hits is complete');
  await writeFile(join(project, 'large.txt'), 'x'.repeat(4095) + '\r\n' + ('x'.repeat(4094) + '\r\n').repeat(980));
  let finished = false;
  const pending = search('absent').then(result => { finished = true; return result; });
  assert.equal((await service.get('/api/status')).status, 200, 'search yields to other requests');
  assert.equal(finished, false, 'status answers before the large CRLF scan finishes');
  assert.equal((await pending).limited, true, 'the scan budget is explicit even with no hits');
  // Editing the rule file uses ordinary revisions and invalidates the listing.
  const events = await service.events();
  try {
    await service.until(() => events.seen.some(event => event.kind === 'snapshot'), 'initial snapshot');
    const version = events.seen.findLast(event => event.kind === 'snapshot').data.files;
    const ignore = await (await service.get('/api/file?path=.gitignore')).json();
    const body = 'ignored/\n';
    const saved = await service.request('/api/file?path=.gitignore', 'PUT',
      {Origin: service.url, 'Content-Type': 'text/plain', 'Content-Length': Buffer.byteLength(body), 'If-Match': JSON.stringify(ignore.revision)}, body);
    assert.equal(saved.status, 200, saved.text);
    await service.until(() => events.seen.some(event => event.kind === 'snapshot' && event.data.files > version), 'rule change invalidation');
    const changed = await (await service.get('/api/project')).json();
    assert.ok(changed.files.includes('ignored.txt'));
    assert.ok((await search('needle')).hits.some(hit => hit.path === 'ignored.txt'));
  } finally { await events.close(); }
  console.log('project-search: ignore visibility, tracked files, rule edits, revisions, scalar locations, and limits');
} finally { await service.stop(); await rm(project, {recursive: true, force: true}); }
