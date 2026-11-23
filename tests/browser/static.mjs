import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {extname, join, normalize} from 'node:path';

const types = {'.html': 'text/html', '.mjs': 'text/javascript', '.css': 'text/css', '.wasm': 'application/wasm'};

export function serve(directory) {
  const server = createServer(async (request, response) => {
    const path = normalize(decodeURIComponent(new URL(request.url, 'http://host').pathname)).replace(/^\/+/, '');
    try {
      const bytes = await readFile(join(directory, path === '' ? 'index.html' : path));
      response.writeHead(200, {'content-type': types[extname(path || 'index.html')] ?? 'application/octet-stream'});
      response.end(bytes);
    } catch {
      response.writeHead(404);
      response.end();
    }
  });
  return new Promise(resolve => server.listen(0, '127.0.0.1', () => resolve(server)));
}
