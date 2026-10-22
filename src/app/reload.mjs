// Live reload for the pages that `lofi serve` serves. scripts/develop.mjs
// adds this module to each page with the manifest of the build the page
// came from, and every event at /.lofi/events carries the manifest of the
// build being served, so comparing the two tells what changed, however many
// events the page missed.
//
// - A changed module replaces the one each application runs, keeping the
//   application's state (`replaceModule` in host.mjs).
// - A changed style sheet is fetched again.
// - Any other change reloads the page, after saving.
// - A failed build, a module that cannot take over the state, or an
//   uncaught error is shown over the page; the old module keeps its state.

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

// ---- Builds ----

// The manifest of what this page runs. It changes only as builds are
// applied, so it never claims more than the page has.
const loaded = JSON.parse(document.getElementById('lofi-manifest')?.textContent ?? '{}');

function changesFrom(manifest) {
  return [...new Set([...Object.keys(loaded), ...Object.keys(manifest)])].filter(name => loaded[name] !== manifest[name]);
}

// The host is imported only when needed: before the first build succeeds,
// the page is a placeholder without one.
function loadHost() {
  return import('/host.mjs').catch(() => null);
}

// Brings the page up to the build in `manifest`, returning the files it
// changed, or null when the page reloads or a module could not take over.
// A page without a running application has nothing to keep.
async function applyBuild(manifest, notice) {
  const changed = changesFrom(manifest);
  if (!changed.length) return changed;
  const host = await loadHost();
  if (!host?.running.length || changed.some(file => !(file in manifest) || !(file.endsWith('.css') || file === 'app.wasm'))) {
    await Promise.all((host?.running ?? []).map(application => host.saveApplication(application)));
    location.reload();
    return null;
  }
  changed.filter(file => file.endsWith('.css')).forEach(file => restyle(file, manifest[file]));
  return !changed.includes('app.wasm') || await replaceModules(host, manifest['app.wasm'], notice) ? changed : null;
}

function restyle(file, digest) {
  for (const link of document.querySelectorAll('link[rel="stylesheet"]')) {
    const url = new URL(link.href);
    if (url.pathname.endsWith(`/${file}`)) { url.searchParams.set('v', digest); link.href = url.href; }
  }
  loaded[file] = digest;
}

// The module counts as loaded even if it fails, so it is not tried again
// until a build changes it.
async function replaceModules(host, digest, notice) {
  loaded['app.wasm'] = digest;
  for (const application of host.running)
    if (!await replace(host, application, digest, notice)) return false;
  return true;
}

function moduleUrl(application, digest) {
  const url = new URL(application.url, location.href);
  url.searchParams.set('v', digest);
  return url.href;
}

// When the new module cannot take over the state, the old one keeps it,
// and starting over is the developer's choice.
async function replace(host, application, digest, notice) {
  try {
    await host.replaceModule(application, moduleUrl(application, digest));
    return true;
  } catch (error) {
    notice.show(`The new module could not restore the running state; the old module is still running.\n\n${error.message}`, {
      failed: true,
      actions: [['Start over with the new module', () => startOver(host, application, digest, notice)], ['Dismiss', notice.hide]],
    });
    return false;
  }
}

async function startOver(host, application, digest, notice) {
  try {
    await host.replaceModule(application, moduleUrl(application, digest), {fresh: true});
    notice.hide();
  } catch (error) {
    notice.show(`The new module could not start.\n\n${error.message}`, {failed: true});
  }
}

// An uncaught error, such as a trap or the exit a panic calls, comes with
// the lines the modules last wrote to standard error. A trap during a
// display frame stops the clock with the state as it was before the update
// that trapped; the next build that replaces the module resumes it.
async function explainError(event, notice) {
  const running = (await loadHost())?.running ?? [];
  const stopped = running.some(application => !application.clock);
  notice.show([event.message, ...running.flatMap(application => application.errors),
               ...(stopped ? ['', 'The application stopped. Fix it and save: the next build resumes from the state before the trap.'] : [])]
    .join('\n'), {failed: true});
}

// ---- Events ----

// Applies the build an event describes, then shows the event's state.
async function receive(event, notice) {
  const changed = await applyBuild(event.manifest, notice);
  if (changed === null) return;
  if (event.state === 'building') notice.show('Building...');
  else if (event.state === 'failed') notice.show(event.message, {failed: true});
  else if (changed.length) notice.show(`Reloaded ${changed.join(', ')}, built in ${event.milliseconds} ms`, {seconds: 2});
  else notice.hide();
}

// Events are received one at a time, in order, so a later build never
// lands before an earlier one.
const notice = createNotice();
let receiving = Promise.resolve();
new EventSource('/.lofi/events').addEventListener('message', message => {
  receiving = receiving.then(() => receive(JSON.parse(message.data), notice));
});
addEventListener('error', event => explainError(event, notice));
