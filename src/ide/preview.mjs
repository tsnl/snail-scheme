// The IDE's preview: the application as a page `lofi serve` would serve it,
// in a frame of its own, so its styles and keys stay out of the editor. Its
// files come from the toolchain worker through a port the IDE hands over,
// with the latest build that succeeded; build events come from the IDE. As
// on a served page, the reload client decides what each build changes, and
// reloading reloads only this frame.
import {relinkAll, saveAll, startApplication} from './host.mjs';
import {manifestText, readEvent} from './load.mjs';
import {createReloadClient} from './reload-client.mjs';

const {port, built, storageKey} = await connect();
const read = createReader(port);

const client = await createReloadClient(new Uint8Array(await (await fetch('./reload.wasm')).arrayBuffer()), {
  restyle: file => restyle(read, file),
  relink: relinkAll,
  save: saveAll,
});
// While the application starts, only the newest event waits for the client:
// each one carries the whole manifest of its build.
let waiting = null;
let deliver = text => { waiting = text; };
addEventListener('message', ({data}) => { if (data.type === 'event') deliver(data.text); });

// The IDE's shortcuts work while the application has the keys, unless the
// application takes the chord itself.
addEventListener('keydown', event => {
  if ((event.ctrlKey || event.metaKey) && !event.defaultPrevented) {
    parent.postMessage({type: 'chord', code: event.code, shiftKey: event.shiftKey, altKey: event.altKey, ctrlKey: true}, '*');
    if (['KeyS', 'KeyB', 'Backslash'].includes(event.code) || (event.code === 'KeyF' && event.shiftKey)) event.preventDefault();
  }
});

// Before any build succeeds, the client has nothing to compare and shows
// the loop's progress; the first build that succeeds reloads the frame,
// which then starts the application from it.
if (built) {
  const {manifest} = readEvent(built);
  await Promise.all(styleSheets(manifest).map(file => restyle(read, file)));
  await startApplication({canvas: document.getElementById('view'), overlay: document.getElementById('overlay'), storageKey,
                          manifest: '/modules.json', read});
  client.start(manifestText(manifest));
  document.body.dataset.ready = 'true';
} else client.start('(files) (modules)');
deliver = text => client.event(text);
if (waiting) deliver(waiting);

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
  return manifest.files.map(([file]) => file).filter(file => file.endsWith('.css') && file !== 'style.css');
}

async function restyle(read, file) {
  const style = document.querySelector(`style[data-file="${file}"]`) ?? document.head.appendChild(document.createElement('style'));
  style.dataset.file = file;
  style.textContent = new TextDecoder().decode(await read(`/${file}`));
}
