// Saved project text, through the same origin and path boundary as file reads.
import assert from 'node:assert/strict';
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
const service = await startDevelopment(root, project);
const search = async query => {
  const response = await service.get('/api/search?q=' + encodeURIComponent(query));
  assert.equal(response.status, 200); return response.json();
};
try {
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
  console.log('project-search: saved revisions, scalar locations, boundaries, and explicit limits');
} finally { await service.stop(); await rm(project, {recursive: true, force: true}); }
