// Exercise failures against a real assembled artifact; never mutate the upload.
import assert from 'node:assert/strict';
import {cpSync, linkSync, mkdtempSync, readFileSync, rmSync, symlinkSync, unlinkSync, writeFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {checkPages} from '../scripts/check-pages.mjs';

const site = resolve(process.argv[2] ?? 'build/pages');
const manifest = JSON.parse(readFileSync(join(site, 'play/siegework/manifest.json'), 'utf8'));
checkPages(site);
console.log('ok - book, game, help, modules and manifest assets resolve under /snail-scheme/');

function rejects(label, change, expected) {
  const copy = mkdtempSync(join(tmpdir(), 'snail-pages-check-'));
  try {
    cpSync(site, copy, {recursive: true}); change(copy);
    assert.throws(() => checkPages(copy), expected);
    console.log(`ok - ${label}`);
  } finally { rmSync(copy, {recursive: true, force: true}); }
}

rejects('missing Wasm is rejected', copy => unlinkSync(join(copy, 'play/siegework', manifest.module)), /missing local resource/);
rejects('root-relative resources cannot escape the project prefix', copy => {
  writeFileSync(join(copy, 'bad.html'), '<script src="/lib/browser/solo.mjs"></script>');
}, /URL escapes/);
rejects('module imports must exist', copy => {
  writeFileSync(join(copy, 'play/siegework/lib/bad.mjs'), "import './missing.mjs';");
}, /missing local resource/);
rejects('interface stylesheet must exist', copy => {
  unlinkSync(join(copy, 'play/siegework/lib/ui/style.css'));
}, /missing local resource/);
rejects('game must link to its player guide', copy => {
  const path = join(copy, 'play/siegework/index.html');
  writeFileSync(path, readFileSync(path, 'utf8').replace('games/siegework.html', 'games/index.html'));
}, /missing link to games\/siegework.html/);
rejects('symlinks cannot enter the Pages artifact', copy => {
  symlinkSync('index.html', join(copy, 'linked.html'));
}, /contains a symlink/);
rejects('hardlinks cannot enter the Pages artifact', copy => {
  linkSync(join(copy, 'index.html'), join(copy, 'linked.html'));
}, /independent regular files/);
