// The page side of `lofi serve`, which the server adds to every page it
// serves. The reload client, src/app/reload.sld, runs as WebAssembly and
// decides what the page does about each build; this file binds it to the
// server's event stream, a notice over the page, and the application host,
// which relinks programs (`relinkModules` in host.mjs).

// ---- Notice ----

// One panel in a corner, styled here so that no application's stylesheet
// has to know about it.
const panelStyle = {position: 'fixed', left: '12px', bottom: '12px', zIndex: 2147483647, maxHeight: '50vh', overflow: 'auto',
  maxWidth: 'min(720px, calc(100vw - 24px))', padding: '10px 12px', borderRadius: '6px', whiteSpace: 'pre-wrap',
  font: '12px/1.45 ui-monospace, monospace', color: '#e8ecf2', boxShadow: '0 4px 16px rgba(0, 0, 0, 0.4)'};
const buttonStyle = {display: 'block', marginTop: '8px', padding: '4px 8px', border: '1px solid #3a4658', borderRadius: '4px',
  font: 'inherit', color: 'inherit', background: '#26324a', cursor: 'pointer'};

// Each action is a button's caption and its handler.
function createNotice() {
  const panel = document.createElement('div');
  panel.setAttribute('role', 'status');
  Object.assign(panel.style, panelStyle, {display: 'none'});
  document.body.append(panel);
  let timer = null;
  const hide = () => { clearTimeout(timer); panel.style.display = 'none'; };
  const show = (text, {failed = false, actions = [], seconds = 0} = {}) => {
    hide();
    panel.replaceChildren(text, ...actions.map(([caption, handler]) => button(caption, handler)));
    Object.assign(panel.style, {display: 'block', background: failed ? '#4a1c24' : '#1c2433', border: `1px solid ${failed ? '#c25b6a' : '#3a4658'}`});
    if (seconds) timer = setTimeout(hide, seconds * 1000);
  };
  return {show, hide};
}

function button(caption, handler) {
  const node = Object.assign(document.createElement('button'), {textContent: caption});
  Object.assign(node.style, buttonStyle);
  node.addEventListener('click', handler);
  return node;
}

// ---- The client ----

// The client is one linked module with its own runtime; it needs only
// standard output, and answers the rest of WASI with ENOSYS.
async function startClient(page) {
  let exports = null;
  const memory = () => new DataView(exports.memory.buffer);
  const wasi = {
    fd_write(fd, iovs, count, written) {
      let total = 0, text = '';
      for (let i = 0; i < count; i++) {
        const pointer = memory().getUint32(iovs + 8 * i, true), length = memory().getUint32(iovs + 8 * i + 4, true);
        text += new TextDecoder().decode(new Uint8Array(exports.memory.buffer, pointer, length));
        total += length;
      }
      (fd === 2 ? console.error : console.log)(text.trimEnd());
      memory().setUint32(written, total, true);
      return 0;
    },
    proc_exit(code) { throw new Error(`the reload client exited with status ${code}`); },
  };
  const module = await WebAssembly.compileStreaming(fetch('/.lofi/reload.wasm', {cache: 'no-store'}));
  for (const {module: from, name} of WebAssembly.Module.imports(module)) if (from === 'wasi_snapshot_preview1' && !wasi[name]) wasi[name] = () => 52;
  ({exports} = await WebAssembly.instantiate(module, {wasi_snapshot_preview1: wasi, 'snail.page': pageImports(page)}));
  exports._initialize();
  exports.main();
  return exports;
}

// Sends text a character at a time, then calls the entry point.
function enter(client, entry, text, ...numbers) {
  for (const character of text) client.reload_character(character.codePointAt(0));
  client[entry](...numbers);
}

// ---- Page commands ----

// Numbered as the `page` effect's commands in src/app/reload.sld. A relink
// waits for the one before it.
function pageImports(page) {
  let staged = [], current = '';
  const commands = [
    null,
    ([text], kind) => page.notice.show(text, {failed: kind === 1, seconds: kind === 2 ? 2 : 0}),
    () => page.notice.hide(),
    ([file, digest]) => restyle(file, digest),
    ([module]) => { page.relinking = page.relinking.then(() => relink(page, module, false)); },
    () => reloadPage(),
    ([text]) => page.notice.show(text, {failed: true, actions: [['Start over with the new program', () => startOver(page)],
                                                                ['Dismiss', () => page.notice.hide()]]}),
  ];
  return {
    'argument-character': code => { current += String.fromCodePoint(code); },
    'argument-end': () => { staged.push(current); current = ''; },
    command: (code, number) => { const args = staged; staged = []; commands[code](args, number); return 0; },
  };
}

function restyle(file, digest) {
  for (const link of document.querySelectorAll('link[rel="stylesheet"]')) {
    const url = new URL(link.href);
    if (url.pathname.endsWith(`/${file}`)) { url.searchParams.set('v', digest); link.href = url.href; }
  }
}

async function relink(page, module, fresh) {
  const host = await import('/host.mjs');
  try {
    for (const application of host.running) await host.relinkModules(application, module, {fresh});
    enter(page.client, 'reload_relinked', '', 0);
  } catch (error) {
    enter(page.client, 'reload_relinked', error.message, 1);
  }
}

function startOver(page) {
  page.relinking = page.relinking.then(async () => {
    const host = await import('/host.mjs');
    const first = JSON.parse(await (await fetch('/modules.json', {cache: 'no-store'})).text()).modules[0].name;
    for (const application of host.running) await host.relinkModules(application, first, {fresh: true});
    page.notice.hide();
  }).catch(error => page.notice.show(error.message, {failed: true}));
}

// The page loads again after every application's save is stored. Before
// the first build, the page is a placeholder without a host.
async function reloadPage() {
  const host = await import('/host.mjs').catch(() => null);
  await Promise.all((host?.running ?? []).map(application => host.saveApplication(application)));
  location.reload();
}

// ---- Events ----

const page = {notice: createNotice(), relinking: Promise.resolve(), client: null};
page.client = await startClient(page);
enter(page.client, 'reload_start', document.getElementById('lofi-manifest')?.textContent ?? '(files) (modules)');
new EventSource('/.lofi/events').addEventListener('message', message => enter(page.client, 'reload_event', message.data));
addEventListener('error', async event => {
  const running = (await import('/host.mjs').catch(() => null))?.running ?? [];
  const lines = [event.message, ...running.flatMap(application => application.errors)].join('\n');
  enter(page.client, 'reload_page_error', lines, running.some(application => !application.clock) ? 1 : 0);
});
