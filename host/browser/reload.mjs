// What `snail dev` and `./scripts/snail-tool serve` add to every page they
// serve: the reload client (reload-client.mjs), fed the page's manifest and
// the server's events, and given the application host to relink and save
// programs with. The client's program and the events are beside this
// script, under the server's .snail/, and the host is the page's own,
// where the page's base puts it, so this is the module the page started
// its applications with. Under `./scripts/snail-tool serve` the page is a
// placeholder until the first build succeeds. The host loads only when
// needed, so a host file that fails to load leaves the client running to
// reload the page once it is fixed.
import {createReloadClient, restyleLinks} from './reload-client.mjs';

const loadHost = () => import(new URL('host.mjs', document.baseURI).href).catch(() => null);
const beside = file => new URL(file, import.meta.url);

const client = await createReloadClient(new Uint8Array(await (await fetch(beside('reload.wasm'), {cache: 'no-store'})).arrayBuffer()), {
  restyle: restyleLinks,
  relink: async (module, fresh, manifest) => (await loadHost()).relinkAll(module, fresh, manifest),
  save: async () => (await loadHost())?.saveAll(),
});
client.start(document.getElementById('snail-manifest')?.textContent ?? '(files) (modules)');
new EventSource(beside('events')).addEventListener('message', message => client.event(message.data));

// An uncaught error comes with the lines the programs last wrote to standard
// error, and whether a trap ended an application entry.
addEventListener('error', async event => {
  const running = (await loadHost())?.running ?? [];
  client.pageError([event.message, ...running.flatMap(application => application.errors)].join('\n'),
                   running.some(application => application.runtime.execution.queue.closed));
});
