// The browser IDE: edit an application's libraries and watch it change as
// you type, with nothing installed. The toolchain runs in a worker
// (toolchain.mjs): the development loop of `lofi serve`, compiler included,
// with files in memory. The application runs here, linked from the modules
// the loop builds, and the reload client decides what each build changes.
import {relinkModules, running, startApplication} from './host.mjs';
import {createNotice, createReloadClient} from './reload-client.mjs';

// ---- The toolchain ----

const worker = new Worker(new URL('./toolchain.mjs', import.meta.url), {type: 'module'});
const reads = new Map();
let nextRead = 0;

// The files builds write, as the loop's routes map them.
function read(path) {
  return new Promise((resolve, reject) => {
    const id = nextRead++;
    reads.set(id, bytes => bytes ? resolve(bytes) : reject(new Error(`no file at ${path}`)));
    worker.postMessage({type: 'read', id, path});
  });
}

// ---- The editor ----

// Lists the application's libraries; editing one sends it to the loop,
// which waits for the typing to settle before it builds.
function createEditor(files, root) {
  const select = document.getElementById('file'), text = document.getElementById('source');
  const paths = Object.keys(files).filter(path => path.startsWith(`${root}/`) && path.endsWith('.sld')).sort();
  for (const path of paths) select.append(new Option(path.slice(root.length + 1), path));
  const show = () => { text.value = files[select.value]; };
  select.addEventListener('change', show);
  text.addEventListener('input', () => {
    files[select.value] = text.value;
    worker.postMessage({type: 'edit', path: select.value, text: text.value});
  });
  show();
}

// ---- The application ----

// The application starts with the first build, and the reload client with
// that build's manifest, `(built MILLISECONDS MANIFEST)`. Until then the
// client has an empty one, and shows only the loop's progress and failures.
async function startPage(application) {
  const notice = createNotice();
  const client = await createReloadClient(new Uint8Array(await (await fetch('reload.wasm')).arrayBuffer()), {
    notice,
    relink: async (module, fresh) => { for (const app of running) await relinkModules(app, module, {fresh}); },
    reloadPage: () => location.reload(),
  });
  client.start('(files) (modules)');
  return async text => {
    if (running.length || !text.startsWith('(built')) return client.event(text);
    await application();
    notice.hide();
    client.start(text.slice(text.indexOf('(files'), -1));
    document.body.dataset.ready = 'true';
  };
}

const root = '/app';
const files = await (await fetch('files.json')).json();
createEditor(files, root);
const receive = await startPage(() => startApplication({canvas: document.getElementById('view'), overlay: document.getElementById('overlay'),
                                                       storageKey: 'lofi-ide', manifest: '/modules.json', read}));
worker.onmessage = ({data}) => {
  if (data.type === 'read') { reads.get(data.id)(data.bytes); reads.delete(data.id); }
  else if (data.type === 'event') receive(data.text);
  else if (data.type === 'log') (data.error ? console.error : console.log)(data.text.trimEnd());
};
worker.postMessage({type: 'start', files, application: root});
