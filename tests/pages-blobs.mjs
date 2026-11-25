// Exercise a complete staged release, including byte ranges across a 25 MB boundary.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, readFile, readdir, rm, stat, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promisify} from 'node:util';
import {blobPartSize, objectPath, partPath} from '../host/browser/load.mjs';

const root = process.argv[2], dir = await mkdtemp(join(tmpdir(), 'snail-pages-blobs-'));
const input = join(dir, 'input'), site = join(dir, 'site');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const pack = () => promisify(execFile)('python3', [join(root, 'host/cloudflare/pack.py'), input, site]);
const binary = Buffer.alloc(blobPartSize * 2, 33);
binary.set([70, 71, 72, 73], blobPartSize - 2);
const large = binary.subarray(0, blobPartSize + 21), digest = hash(large);
const loose = '/wide scene.wasm', stored = '/app/' + objectPath(digest);
async function write(path, data) {
  await mkdir(join(input, path, '..'), {recursive: true});
  await writeFile(join(input, path), data);
}

try {
  await write('small.txt', 'small');
  await write('exact.bin', binary.subarray(0, blobPartSize));
  await pack();
  assert.deepEqual((await readdir(site)).sort(), ['exact.bin', 'small.txt']);
  await write(loose, binary);
  await write('app/' + partPath(digest, 0), large.subarray(0, blobPartSize));
  await write('app/' + partPath(digest, 1), large.subarray(blobPartSize));
  await pack();
  await assert.rejects(stat(join(site, loose)), {code: 'ENOENT'});
  await assert.rejects(stat(join(site, stored)), {code: 'ENOENT'});
  const parts = join(site, '_snail_parts', hash(binary));
  assert.deepEqual((await readdir(parts)).sort(), ['0', '1']);
  for (const i of ['0', '1']) assert.equal((await stat(join(parts, i))).size, blobPartSize);

  // ASSETS serves the files in the actual release. This variant deliberately
  // serves whole parts even on a range request, as a plain static server may do.
  const assets = {async fetch(request) {
    return new Response(await readFile(join(site, decodeURIComponent(new URL(request.url).pathname))));
  }};
  globalThis.FixedLengthStream = class extends TransformStream { constructor() { super(); } };
  const worker = (await import('data:text/javascript;base64,' + (await readFile(join(site, '_worker.js'))).toString('base64'))).default;
  const get = (path, options) => worker.fetch(new Request(new URL(path, 'https://snail.test'), options), {ASSETS: assets});
  assert.equal(await (await get('/small.txt')).text(), 'small');
  for (const [url, bytes, type] of [[loose, binary, 'application/wasm'], [stored, large, 'application/octet-stream']]) {
    const head = await get(url, {method: 'HEAD'});
    assert.equal(head.status, 200);
    assert.equal(head.headers.get('Content-Length'), String(bytes.length));
    assert.equal(head.headers.get('Content-Type'), type);
    assert.equal((await head.arrayBuffer()).byteLength, 0);
    assert.equal((await get(url, {headers: {'If-None-Match': head.headers.get('etag')}})).status, 304);
    const complete = await get(url);
    assert.equal(hash(Buffer.from(await complete.arrayBuffer())), hash(bytes));
    const last = bytes.length - 1;
    for (const [range, start, end] of [['24999998-25000001', blobPartSize - 2, blobPartSize + 1], ['-3', last - 2, last], [last + '-', last, last]]) {
      const reply = await get(url, {headers: {Range: 'bytes=' + range}});
      assert.equal(reply.status, 206);
      assert.equal(reply.headers.get('Content-Range'), 'bytes ' + start + '-' + end + '/' + bytes.length);
      assert.deepEqual(Buffer.from(await reply.arrayBuffer()), bytes.subarray(start, end + 1));
    }
    const invalid = await get(url, {headers: {Range: 'bytes=' + bytes.length + '-'}});
    assert.equal(invalid.status, 416);
    assert.equal(invalid.headers.get('Content-Range'), 'bytes */' + bytes.length);
  }
  // An incomplete input cannot replace a working release. Removing all large
  // inputs on the next build removes the obsolete function and its routes.
  await write('app/' + partPath(digest, 1), Buffer.alloc(large.length - blobPartSize));
  await assert.rejects(pack(), /does not match its SHA-256/);
  assert.equal(hash(Buffer.from(await (await get(stored)).arrayBuffer())), digest);
  await rm(join(input, 'app', partPath(digest, 0)));
  await assert.rejects(pack(), /incomplete multipart resource/);
  assert.equal(await (await get('/small.txt')).text(), 'small');
  await rm(join(input, 'app'), {recursive: true});
  await rm(join(input, loose));
  await pack();
  assert.deepEqual((await readdir(site)).sort(), ['exact.bin', 'small.txt']);
  console.log('Pages packs exact boundaries, preserves public URLs and streams whole files and ranges');
} finally { await rm(dir, {recursive: true, force: true}); }
