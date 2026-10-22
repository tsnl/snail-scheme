// What `lofi serve` adds to every page it serves: the reload client
// (reload-client.mjs), fed the page's manifest and the server's events, and
// given the application host to relink programs with. Before the first
// build succeeds the page is a placeholder without a host.
import {createNotice, createReloadClient, restyleLinks} from './reload-client.mjs';

const loadHost = () => import('/host.mjs').catch(() => null);

const client = await createReloadClient(new Uint8Array(await (await fetch('/.lofi/reload.wasm', {cache: 'no-store'})).arrayBuffer()), {
  notice: createNotice(),
  restyle: restyleLinks,
  async relink(module, fresh) {
    const host = await loadHost();
    for (const application of host.running) await host.relinkModules(application, module, {fresh});
  },
  // The page loads again after every application's save is stored.
  async reloadPage() {
    const host = await loadHost();
    await Promise.all((host?.running ?? []).map(application => host.saveApplication(application)));
    location.reload();
  },
});
client.start(document.getElementById('lofi-manifest')?.textContent ?? '(files) (modules)');
new EventSource('/.lofi/events').addEventListener('message', message => client.event(message.data));

// An uncaught error comes with the lines the programs last wrote to standard
// error, and whether a trap stopped a clock.
addEventListener('error', async event => {
  const running = (await loadHost())?.running ?? [];
  client.pageError([event.message, ...running.flatMap(application => application.errors)].join('\n'),
                   running.some(application => !application.clock));
});
