// What `lofi serve` adds to every page it serves: the reload client
// (reload-client.mjs), fed the page's manifest and the server's events, and
// given the application host to relink and save programs with. Before the
// first build succeeds the page is a placeholder that runs no program. The
// host loads only when needed, so a host file that fails to load leaves the
// client running to reload the page once it is fixed.
import {createReloadClient, restyleLinks} from './reload-client.mjs';

const loadHost = () => import('/host.mjs').catch(() => null);

const client = await createReloadClient(new Uint8Array(await (await fetch('/.lofi/reload.wasm', {cache: 'no-store'})).arrayBuffer()), {
  restyle: restyleLinks,
  relink: async (module, fresh) => (await loadHost()).relinkAll(module, fresh),
  save: async () => (await loadHost())?.saveAll(),
});
client.start(document.getElementById('lofi-manifest')?.textContent ?? '(files) (modules)');
new EventSource('/.lofi/events').addEventListener('message', message => client.event(message.data));

// An uncaught error comes with the lines the programs last wrote to standard
// error, and whether a trap ended an application entry.
addEventListener('error', async event => {
  const running = (await loadHost())?.running ?? [];
  client.pageError([event.message, ...running.flatMap(application => application.errors)].join('\n'),
                   running.some(application => application.runtime.execution.queue.closed));
});
