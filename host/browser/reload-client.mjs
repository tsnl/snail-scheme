// The reload client's binding for the pages `./scripts/snail-tool serve` serves
// (reload.mjs). The client, host/browser/reload.sld,
// runs as WebAssembly and decides what the page does about each build; this
// file performs its commands with a notice over the page and what the page
// gives it: how to fetch a style sheet again, relink its programs and save
// them before it reloads.
import {commandImports, createWasi, instantiate} from './load.mjs';

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

// `page` gives `restyle(file, digest, base)`, `relink(module, fresh,
// manifest)`, which resolves once every program on the page is relinked
// from the modules.json at `manifest`, or the one each was linked from when
// that is empty, and `save()`, which resolves once every program's save is
// stored. The client is one linked
// module with its own runtime.
export async function createReloadClient(bytes, page) {
  const client = {exports: null, page, notice: createNotice()};
  const wasi = createWasi({print: (fd, line) => (fd === 2 ? console.error : console.log)(line)});
  const imports = {...wasi.getImportObject(), 'snail.page': commandImports(pageCommands(client))};
  const instance = await instantiate(await WebAssembly.compile(bytes), imports);
  wasi.initialize(instance);
  client.exports = instance.exports;
  client.exports.main();
  return {
    start: manifest => enter(client, 'reload_start', manifest),
    event: text => enter(client, 'reload_event', text),
    pageError: (text, stopped) => enter(client, 'reload_page_error', text, stopped ? 1 : 0),
  };
}

// Sends text a character at a time, then calls the entry point.
function enter(client, entry, text, ...numbers) {
  for (const character of text) client.exports.reload_character(character.codePointAt(0));
  client.exports[entry](...numbers);
}

// ---- Page commands ----

// The `page` effect's commands, by the names host/browser/reload.sld gives them.
// A notice is lasting (0), a failure (1) or brief (2). The client asks for
// one relink at a time.
function pageCommands(client) {
  const {page, notice} = client;
  return {
    notice([text], kind) { notice.show(text, {failed: kind === 1, seconds: kind === 2 ? 2 : 0}); },
    hide() { notice.hide(); },
    restyle([file, digest, base]) { page.restyle(file, digest, base); },
    relink([module, manifest], fresh) {
      page.relink(module, fresh === 1, manifest || undefined).then(() => enter(client, 'reload_relinked', '', 0), error => enter(client, 'reload_relinked', error.message, 1));
    },
    reload() { page.save().then(() => location.reload()); },
    'offer-fresh-start'([text]) {
      notice.show(text, {failed: true, actions: [['Start over with the new program', () => enter(client, 'reload_start_over', '')],
                                                 ['Dismiss', () => notice.hide()]]});
    },
  };
}

// A page's style sheets, linked by URL, fetched again with the new digest,
// from the base of the build they now belong to when there is one.
export function restyleLinks(file, digest, base) {
  for (const link of document.querySelectorAll('link[rel="stylesheet"]')) {
    const url = new URL(link.href);
    if (!url.pathname.endsWith(`/${file}`)) continue;
    const next = base ? new URL(base + file, location.href) : url;
    next.searchParams.set('v', digest);
    link.href = next.href;
  }
}
