// Check the concrete URLs emitted by mdBook and the solo browser packager.
// This checks the upload tree, including references under the project URL prefix.
import assert from 'node:assert/strict';
import {lstatSync, readdirSync, readFileSync} from 'node:fs';
import {join, resolve} from 'node:path';

const base = new URL('https://tsnl.github.io/snail-scheme/');
const game = 'play/siegework/', guide = 'games/siegework.html';
const htmlReferences = /\b(?:href|src)\s*=\s*["']([^"']*)["']/g;
const cssReferences = /url\(\s*["']?([^"')]*?)["']?\s*\)/g;
const moduleImports = /\b(?:import|export)\s+(?:[^;'"()]*?\s+from\s*)?["']([^"']+)["']/g;
const dynamicImports = /\bimport\(\s*["']([^"']+)["']\s*\)/g;
const moduleURLs = /new URL\(\s*["']([^"']+)["']\s*,\s*import\.meta\.url\s*\)/g;

function publicFiles(root, directory = '') {
  const files = [];
  for (const name of readdirSync(join(root, directory))) {
    const path = directory + name, stat = lstatSync(join(root, path));
    assert.ok(!stat.isSymbolicLink(), `Pages artifact contains a symlink: ${path}`);
    if (stat.isDirectory()) files.push(...publicFiles(root, path + '/'));
    else {
      assert.ok(stat.isFile() && stat.nlink === 1, `Pages artifact requires independent regular files: ${path}`);
      files.push(path);
    }
  }
  return files;
}

function localReference(reference, source, files) {
  if (!reference || reference.startsWith('#')) return undefined;
  const url = new URL(reference.replaceAll('&amp;', '&'), new URL(source, base));
  if (url.origin !== base.origin) return undefined;
  assert.ok(url.pathname.startsWith(base.pathname), `${source}: URL escapes /snail-scheme/: ${reference}`);
  const path = decodeURIComponent(url.pathname.slice(base.pathname.length));
  const target = !path || path.endsWith('/') ? path + 'index.html'
    : files.has(path + '/index.html') ? path + '/index.html' : path;
  assert.ok(files.has(target), `${source}: missing local resource ${reference} (${target})`);
  return target;
}

function references(text, pattern) { return [...text.matchAll(pattern)].map(match => match[1]); }

function checkModule(text, source, files) {
  const imports = references(text, moduleImports);
  for (const reference of references(text, dynamicImports)) {
    // SoloSession loads this optional library only when saveService is present.
    if (source === game + 'lib/browser/solo.mjs' && reference === '../application/remote-saves.mjs') continue;
    imports.push(reference);
  }
  for (const reference of imports) {
    assert.ok(reference.startsWith('.'), `${source}: browser import must be relative: ${reference}`);
    localReference(reference, source, files);
  }
  for (const reference of references(text, moduleURLs)) localReference(reference, source, files);
}

function checkManifest(root, files) {
  const source = game + 'manifest.json', manifest = JSON.parse(readFileSync(join(root, source), 'utf8'));
  assert.equal(manifest.target, 'solo', 'Pages must contain the solo game');
  assert.equal(manifest.saveService, undefined, 'Pages must not require a save service');
  assert.match(manifest.settings.id, /^siegework-colony-v\d+$/);
  assert.equal(manifest.settings.title, 'Siegework');
  assert.match(manifest.module, /^simulation\.[a-f0-9]+\.wasm$/);
  assert.match(manifest.shader, /^shader\.[a-f0-9]+\.wgsl$/);
  localReference(manifest.module, source, files); localReference(manifest.shader, source, files);
  assert.equal(readFileSync(join(root, game, manifest.module)).subarray(0, 4).toString(), '\0asm');
  return manifest;
}

function checkNavigation(root, files) {
  for (const [source, destination] of [['index.html', 'games/index.html'], ['games/index.html', game + 'index.html'],
    [guide, game + 'index.html'], [game + 'index.html', guide]]) {
    const links = references(readFileSync(join(root, source), 'utf8'), htmlReferences);
    assert.ok(links.some(link => localReference(link, source, files) === destination), `${source}: missing link to ${destination}`);
  }
}

export function checkPages(root) {
  const files = new Set(publicFiles(root)), manifest = checkManifest(root, files);
  for (const file of files) {
    if (!/\.(html|css|mjs)$/.test(file)) continue;
    const text = readFileSync(join(root, file), 'utf8');
    if (file.endsWith('.mjs')) checkModule(text, file, files);
    else for (const reference of references(text, file.endsWith('.html') ? htmlReferences : cssReferences))
      localReference(reference, file, files);
  }
  checkNavigation(root, files);
  return {files: files.size, generation: manifest.generation};
}

if (process.argv[1] && resolve(process.argv[1]) === import.meta.filename) {
  if (process.argv.length !== 3) throw new Error('usage: node scripts/check-pages.mjs SITE-DIRECTORY');
  console.log(checkPages(resolve(process.argv[2])));
}
