// Optional single-user save service. A static file host serves the application;
// this process receives checkpoints and never loads application code or ticks.
import {createServer} from 'node:http';
import {Readable} from 'node:stream';
import {openSaveStore, saveService} from './service.mjs';

const port = Number(process.env.PORT ?? 4174), store = openSaveStore(process.argv[2] ?? 'saves.sqlite');
const respondHttp = saveService(store, {origin: process.env.SAVE_ORIGIN});
const server = createServer(async (incoming, outgoing) => {
  try {
    const body = ['GET', 'HEAD'].includes(incoming.method) ? undefined : Readable.toWeb(incoming);
    const request = new Request(`http://127.0.0.1:${port}${incoming.url}`, {method: incoming.method, headers: incoming.headers,
      ...(body ? {body, duplex: 'half'} : {})});
    const response = await respondHttp(request);
    outgoing.writeHead(response.status, Object.fromEntries(response.headers));
    outgoing.end(Buffer.from(await response.arrayBuffer()));
  } catch (error) { outgoing.writeHead(500); outgoing.end('Save service failed'); console.error(error); }
});
server.listen(port, '127.0.0.1', () => console.log(`Checkpoint service: http://127.0.0.1:${port}/saves/`));
function close() { server.close(() => store.close()); }
process.once('SIGTERM', close); process.once('SIGINT', close);
