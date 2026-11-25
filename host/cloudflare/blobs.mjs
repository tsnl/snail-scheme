// pack.py embeds the URL table and partSize above this module in _worker.js.
// Each entry holds the logical length, SHA-256, part directory and MIME type.
function byteRange(header, size) {
  const range = /^bytes=(\d*)-(\d*)$/i.exec(header ?? '');
  if (!range || !(range[1] || range[2])) return undefined;
  const start = range[1] ? Number(range[1]) : Math.max(0, size - Number(range[2]));
  const end = range[1] && range[2] ? Math.min(Number(range[2]), size - 1) : size - 1;
  return start <= end ? [start, end] : null;
}

// Pages normally honors the part range. If an asset is served whole, trim
// its stream locally. A short or missing part fails the transfer.
async function copyPart(assets, url, size, start, end, writer, signal) {
  const partial = start !== 0 || end !== size - 1;
  const headers = partial ? {Range: 'bytes=' + start + '-' + end} : {};
  const response = await assets.fetch(new Request(url, {headers, signal}));
  let offset = 0;
  if (response.status === 206 && response.headers.get('Content-Range') === 'bytes ' + start + '-' + end + '/' + size)
    offset = start;
  else if (response.status !== 200) throw new Error('unavailable blob part ' + url.pathname);
  for await (const bytes of response.body) {
    const next = offset + bytes.length;
    if (next > start) await writer.write(bytes.subarray(Math.max(0, start - offset), end + 1 - offset));
    if (next > end) return;
    offset = next;
  }
  throw new Error('short blob part ' + url.pathname);
}

async function sendParts(request, assets, prefix, size, start, end, writer) {
  try {
    for (let i = Math.floor(start / partSize); i <= Math.floor(end / partSize); i++) {
      const offset = i * partSize, length = Math.min(partSize, size - offset);
      const url = new URL(prefix + '/' + i, request.url);
      await copyPart(assets, url, length, Math.max(0, start - offset), Math.min(length - 1, end - offset), writer, request.signal);
    }
    await writer.close();
  } catch (reason) { await writer.abort(reason).catch(() => {}); }
}

export default {
  fetch(request, env) {
    let path;
    try { path = decodeURIComponent(new URL(request.url).pathname); }
    catch { return new Response(null, {status: 400}); }
    const blob = blobs.get(path);
    if (!blob) return env.ASSETS.fetch(request);
    if (request.method !== 'GET' && request.method !== 'HEAD')
      return new Response(null, {status: 405, headers: {Allow: 'GET, HEAD'}});
    const [size, digest, prefix, type] = blob, tag = '"' + digest + '"';
    const headers = new Headers({'Content-Type': type, 'Accept-Ranges': 'bytes', ETag: tag,
      'Cache-Control': prefix.startsWith('/_snail_parts/') ? 'public, max-age=0, must-revalidate' : 'public, max-age=31536000, immutable'});
    const tags = (request.headers.get('If-None-Match') ?? '').split(',').map(t => t.trim().replace(/^W\//, ''));
    if (tags.includes(tag) || tags.includes('*')) return new Response(null, {status: 304, headers});
    const validator = request.headers.get('If-Range');
    const range = request.method === 'GET' && (!validator || validator === tag)
      ? byteRange(request.headers.get('Range'), size) : undefined;
    if (range === null) {
      headers.set('Content-Range', 'bytes */' + size);
      return new Response(null, {status: 416, headers});
    }
    const [start, end] = range ?? [0, size - 1], length = end - start + 1;
    headers.set('Content-Length', String(length));
    if (range) headers.set('Content-Range', 'bytes ' + start + '-' + end + '/' + size);
    if (request.method === 'HEAD') return new Response(null, {headers});
    // workerd uses a FixedLengthStream to put Content-Length on the wire.
    const stream = new FixedLengthStream(length);
    sendParts(request, env.ASSETS, prefix, size, start, end, stream.writable.getWriter());
    return new Response(stream.readable, {status: range ? 206 : 200, headers});
  },
};
