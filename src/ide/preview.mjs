// The IDE's preview: the application as a page `lofi serve` would serve it,
// in a frame of its own, so its styles and keys stay out of the editor. Its
// files come from the toolchain worker through a port the IDE hands over,
// with the latest build that succeeded; build events come from the IDE. As
// on a served page, the reload client decides what each build changes, and
// reloading reloads only this frame.
import {relinkModules, running, saveApplication, startApplication} from './host.mjs';
import {createNotice, createReloadClient} from './reload-client.mjs';

const {port, built, storageKey} = await connect();
const read = createReader(port);

const client = await createReloadClient(new Uint8Array(await (await fetch('./reload.wasm')).arrayBuffer()), {
  notice: createNotice(),
  restyle: file => restyle(read, file),
  async relink(module, fresh) { for (const application of running) await relinkModules(application, module, {fresh}); },
  async reloadPage() {
    await Promise.all(running.map(application => saveApplication(application)));
    location.reload();
  },
});
// Events that arrive while the application starts wait for the client.
const early = [];
let deliver = text => early.push(text);
addEventListener('message', ({data}) => { if (data.type === 'event') deliver(data.text); });

// Before any build succeeds, the client has nothing to compare and shows
// the loop's progress; the first build that succeeds reloads the frame,
// which then starts the application from it.
if (built) {
  const manifest = built.slice(built.indexOf('(files'), -1);
  await Promise.all(styleSheets(manifest).map(file => restyle(read, file)));
  await startApplication({canvas: document.getElementById('view'), overlay: document.getElementById('overlay'), storageKey,
                          manifest: '/modules.json', read});
  client.start(manifest);
  document.body.dataset.ready = 'true';
} else client.start('(files) (modules)');
deliver = text => client.event(text);
early.forEach(deliver);

// ---- The IDE ----

function connect() {
  return new Promise(resolve => {
    addEventListener('message', function connected({data, ports}) {
      if (data.type !== 'connect') return;
      removeEventListener('message', connected);
      resolve({port: ports[0], built: data.built, storageKey: data.storageKey});
    });
    parent.postMessage({type: 'preview-ready'}, '*');
  });
}

// A file the last build wrote, by the path a page would fetch it at.
function createReader(port) {
  const waiting = new Map();
  let next = 0;
  port.onmessage = ({data}) => { waiting.get(data.id)?.(data.bytes); waiting.delete(data.id); };
  return path => new Promise((resolve, reject) => {
    const id = next++;
    waiting.set(id, bytes => (bytes ? resolve(bytes) : reject(new Error(`no file at ${path}`))));
    port.postMessage({type: 'read', id, path});
  });
}

// ---- Style sheets ----

// The project's style sheets, which the manifest lists among its files;
// the host's own is linked from the IDE's site.
function styleSheets(manifest) {
  return [...manifest.matchAll(/\("([^"]+\.css)" "/g)].map(match => match[1]).filter(file => file !== 'style.css');
}

async function restyle(read, file) {
  const style = document.querySelector(`style[data-file="${file}"]`) ?? document.head.appendChild(document.createElement('style'));
  style.dataset.file = file;
  style.textContent = new TextDecoder().decode(await read(`/${file}`));
}
