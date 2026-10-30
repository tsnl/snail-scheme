// `snail dev` serving a browser target, from outside
// (tests/development-service.mjs): the applications' origin, apart from
// the editor's, lists the browser targets; /NAME/ is the latest build's page
// based in that build, with its manifest and the reload client;
// /NAME/.snail/builds/EPOCH/ serves that build's files and never a newer
// build's; /NAME/.snail/events tells a page of the latest build; a build two
// publications old is reclaimed and answers 404; and the origin refuses
// another host and anything but a read.
//   node tests/project-bundles.mjs ROOT
import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {startDevelopment} from './development-service.mjs';

const root = process.argv[2], project = fs.realpathSync(fs.mkdtempSync(join(tmpdir(), 'snail-project-bundles-')));
const source = join(project, 'main.sld');
const program = text => `(import (snail core base) (snail core io)) (write-line "${text}")`;
fs.writeFileSync(join(project, 'project.datum'),
  '((build-target site (browser (entry "main.sld") (public "public"))) (build-target tool (program (entry "main.sld"))))');
fs.mkdirSync(join(project, 'public'));
fs.writeFileSync(join(project, 'public/index.html'), '<!doctype html>\n<title>site</title>\n');
fs.writeFileSync(source, program('one'));

// A request to the applications' origin, with the Host header given.
function request(origin, path, method = 'GET', host = new URL(origin).host) {
  return new Promise((resolve, reject) => {
    const outgoing = http.request(new URL(path, origin), {method, headers: {Host: host}}, response => {
      let text = '';
      response.setEncoding('utf8');
      response.on('data', chunk => { text += chunk; });
      response.on('end', () => resolve({status: response.statusCode, type: response.headers['content-type'], text}));
    });
    outgoing.on('error', reject);
    outgoing.end();
  });
}

// The first event a page's stream sends, after its retry interval.
function firstEvent(url) {
  return new Promise((resolve, reject) => {
    const outgoing = http.get(url, response => {
      let text = '';
      response.setEncoding('utf8');
      response.on('data', chunk => {
        text += chunk;
        const event = /^retry: \d+\n\n((?:data: .*\n)+)\n/.exec(text);
        if (event) { outgoing.destroy(); resolve(event[1].replace(/^data: /gm, '').trimEnd()); }
      });
    });
    outgoing.on('error', reject);
  });
}

const service = await startDevelopment(root, project);
try {
  const first = await service.settled(0);
  const site = first.published.targets.find(target => target.name === 'site');
  assert.match(site.url, /^http:\/\/127\.0\.0\.1:\d+\/site\/$/);
  assert.equal(first.published.targets.find(target => target.name === 'tool').url, undefined, 'only browser targets are served');
  const origin = new URL(site.url).origin, get = path => request(origin, path);
  assert.notEqual(origin, service.url, "the applications' origin is apart from the editor's");
  assert.match((await get('/')).text, /<a href="\/site\/">site<\/a>/);
  assert.equal((await get('/tool/')).status, 404, 'a program target is not served');

  // The page names its build, whose files are all there, and loads the
  // reload client, which hears of the build the page was served from.
  const pinned = id => `/site/.snail/builds/${id}/`;
  const page = (await get('/site/')).text;
  assert.ok(page.startsWith(`<!doctype html><base href="${pinned(first.id)}">`));
  assert.match(page, new RegExp(`<script type="application/snail-manifest" id="snail-manifest">\\(base "${pinned(first.id)}"\\) \\(files .*\\("host\\.mjs" "[0-9a-f]{64}"\\).*\\) \\(modules \\("snail\\.core\\.base" "modules/[^"]+"\\)`));
  assert.match(page, /<script type="module" src="\/site\/\.snail\/reload\.mjs"><\/script>/);
  for (const file of ['reload.mjs', 'reload-client.mjs', 'load.mjs', 'reload.wasm']) {
    assert.equal((await get(`/site/.snail/${file}`)).status, 200, file);
  }
  assert.match(await firstEvent(`${origin}/site/.snail/events`), new RegExp(`^\\(built \\d+ \\(base "${pinned(first.id)}"\\)`));
  const manifest = await get(pinned(first.id) + 'modules.json');
  assert.equal(manifest.status, 200);
  assert.equal(manifest.type, 'application/json');
  const {runtime, modules} = JSON.parse(manifest.text);
  for (const file of [runtime, 'host.mjs', ...modules.map(module => module.file)]) {
    assert.equal((await get(pinned(first.id) + file)).status, 200, file);
  }

  // Only reads, and only for the origin's own host.
  assert.equal((await request(origin, '/site/', 'GET', 'attacker.example')).status, 403);
  assert.equal((await request(origin, '/site/', 'POST')).status, 405);

  // A new build moves the page, and the earlier build's files stay as they were.
  fs.writeFileSync(source, program('two'));
  const second = await service.rebuilt();
  assert.ok((await get('/site/')).text.includes(`<base href="${pinned(second.id)}">`));
  assert.match(await firstEvent(`${origin}/site/.snail/events`), new RegExp(`^\\(built \\d+ \\(base "${pinned(second.id)}"\\)`));
  assert.equal((await get(pinned(first.id) + 'modules.json')).text, manifest.text, "a build's files never change");
  assert.notEqual((await get(pinned(second.id) + 'modules.json')).text, manifest.text);

  // The one after that reclaims the first, whose files are then gone.
  fs.writeFileSync(source, program('three'));
  const third = await service.rebuilt();
  const gone = await get(pinned(first.id) + 'modules.json');
  assert.equal(gone.status, 404);
  assert.match(gone.text, new RegExp(`build ${first.id} is no longer served`));
  assert.equal(fs.existsSync(site.directory), false, 'its generation is reclaimed');
  assert.equal((await get(pinned(second.id) + 'modules.json')).status, 200, 'the build before the latest stays');
  assert.ok((await get('/site/')).text.includes(`<base href="${pinned(third.id)}">`));
  console.log("project bundles: the applications' origin, pinned builds, the reload client, reclamation and refusals");
} finally {
  await service.stop();
  fs.rmSync(project, {recursive: true, force: true});
}
