// The reload client's binding, shared by the pages `lofi serve` serves
// (reload.mjs) and the browser IDE. The client, src/app/reload.sld, runs as
// WebAssembly and decides what the page does about each build; this file
// performs its commands with a notice over the page and what the page gives
// it: how to relink its programs and how to reload.

// ---- Notice ----

// One panel in a corner, styled here so that no application's stylesheet
// has to know about it.
const panelStyle = {position: 'fixed', left: '12px', bottom: '12px', zIndex: 2147483647, maxHeight: '50vh', overflow: 'auto',
  maxWidth: 'min(720px, calc(100vw - 24px))', padding: '10px 12px', borderRadius: '6px', whiteSpace: 'pre-wrap',
  font: '12px/1.45 ui-monospace, monospace', color: '#e8ecf2', boxShadow: '0 4px 16px rgba(0, 0, 0, 0.4)'};
const buttonStyle = {display: 'block', marginTop: '8px', padding: '4px 8px', border: '1px solid #3a4658', borderRadius: '4px',
  font: 'inherit', color: 'inherit', background: '#26324a', cursor: 'pointer'};

// Each action is a button's caption and its handler.
export function createNotice() {
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

// `page` gives the notice, `relink(module, fresh)`, which resolves once
// every program on the page is relinked, and `reloadPage()`. The client is
// one linked module with its own runtime; it needs only standard output,
// and the rest of WASI answers ENOSYS.
export async function createReloadClient(bytes, page) {
  const module = await WebAssembly.compile(bytes);
  const client = {exports: null};
  const wasi = clientWasi(client);
  for (const {module: from, name} of WebAssembly.Module.imports(module)) if (from === 'wasi_snapshot_preview1' && !wasi[name]) wasi[name] = () => 52;
  ({exports: client.exports} = await WebAssembly.instantiate(module, {wasi_snapshot_preview1: wasi, 'snail.page': pageImports(client, page)}));
  client.exports._initialize();
  client.exports.main();
  return {
    start: manifest => enter(client, 'reload_start', manifest),
    event: text => enter(client, 'reload_event', text),
    pageError: (text, stopped) => enter(client, 'reload_page_error', text, stopped ? 1 : 0),
  };
}

function clientWasi(client) {
  const memory = () => new DataView(client.exports.memory.buffer);
  return {
    fd_write(fd, iovs, count, written) {
      let total = 0, text = '';
      for (let i = 0; i < count; i++) {
        const pointer = memory().getUint32(iovs + 8 * i, true), length = memory().getUint32(iovs + 8 * i + 4, true);
        text += new TextDecoder().decode(new Uint8Array(client.exports.memory.buffer, pointer, length));
        total += length;
      }
      (fd === 2 ? console.error : console.log)(text.trimEnd());
      memory().setUint32(written, total, true);
      return 0;
    },
    proc_exit(code) { throw new Error(`the reload client exited with status ${code}`); },
  };
}

// Sends text a character at a time, then calls the entry point.
function enter(client, entry, text, ...numbers) {
  for (const character of text) client.exports.reload_character(character.codePointAt(0));
  client.exports[entry](...numbers);
}

// ---- Page commands ----

// Numbered as the `page` effect's commands in src/app/reload.sld. The
// client asks for one relink at a time.
function pageImports(client, page) {
  let staged = [], current = '';
  const commands = [
    null,
    ([text], kind) => page.notice.show(text, {failed: kind === 1, seconds: kind === 2 ? 2 : 0}),
    () => page.notice.hide(),
    ([file, digest]) => restyle(file, digest),
    ([module], fresh) => page.relink(module, fresh === 1)
      .then(() => enter(client, 'reload_relinked', '', 0), error => enter(client, 'reload_relinked', error.message, 1)),
    () => page.reloadPage(),
    ([text]) => page.notice.show(text, {failed: true, actions: [['Start over with the new program', () => enter(client, 'reload_start_over', '')],
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
