// Creation shares the editor's path boundary and never replaces a leaf.
import assert from 'node:assert/strict';
import {mkdtemp, mkdir, writeFile, readFile, symlink, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {startDevelopment} from './development-service.mjs';

const root = process.argv[2], project = await mkdtemp(join(tmpdir(), 'snail-create-'));
await writeFile(join(project, 'project.datum'), '()');
await writeFile(join(project, 'kept.txt'), 'do not replace');
await mkdir(join(project, 'existing'));
await symlink('missing', join(project, 'link.txt'));
await symlink('existing', join(project, 'linked'));
const service = await startDevelopment(root, project);
const create = (kind, path) => service.command(`/api/${kind}?path=${encodeURIComponent(path)}`);
try {
  assert.equal((await create('directory', 'agent-core')).status, 201);
  assert.equal((await create('file', 'agent-core/main.sld')).status, 201);
  assert.equal(await readFile(join(project, 'agent-core/main.sld'), 'utf8'), '');
  const responses = await Promise.all([create('file', 'race.txt'), create('file', 'race.txt')]);
  assert.deepEqual(responses.map(result => result.status).sort(), [201, 409]);
  for (const [kind, path] of [['file', 'kept.txt'], ['file', 'link.txt'], ['directory', 'existing'], ['directory', 'linked']]) {
    assert.equal((await create(kind, path)).status, 409, path);
  }
  assert.equal(await readFile(join(project, 'kept.txt'), 'utf8'), 'do not replace');
  for (const path of ['../escape', '/absolute', 'a/../escape', 'a//b', './dot', '.git/config', 'build/new', 'nul\0', 'back\\slash']) {
    assert.equal((await create('directory', path)).status, 400, path);
  }
  assert.equal((await create('file', 'unsupported.bin')).status, 400);
  assert.equal((await create('file', 'linked/escape.sld')).status, 400);
  assert.equal((await create('file', 'absent/main.sld')).status, 404);
  assert.equal((await service.request('/api/file?path=foreign.sld', 'POST', {Origin: 'https://foreign.example'})).status, 403);
  assert.equal((await create('directory', 'empty')).status, 201);
  const projectReply = await (await service.get('/api/project')).json();
  assert.deepEqual(projectReply.directories, ['agent-core', 'empty', 'existing']);
  assert.ok(projectReply.files.includes('agent-core/main.sld'));
  console.log('project-create: exclusive creation, empty directories, and project path/origin boundaries');
} finally { await service.stop(); await rm(project, {recursive: true, force: true}); }
