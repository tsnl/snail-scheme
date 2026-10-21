// Live reload for the pages that `lofi serve` serves: scripts/develop.mjs
// adds this module to each page and reports every build through the events
// at /.lofi/events.
//
// - A new module replaces the one each application runs, keeping the
//   application's state (`replaceModule` in host.mjs).
// - A changed style sheet is fetched again.
// - A changed page or host script reloads the page, after saving.
// - A failed build, a module that cannot take over the state, or an
//   uncaught error is shown over the page; the old module keeps its state.

// ---- Notice ----

// One panel in a corner, styled here so that no application's stylesheet
// has to know about it. Each action is a button's caption and its handler.
function createNotice() {
  const panel = document.createElement('div');
  panel.setAttribute('role', 'status');
  Object.assign(panel.style, {position: 'fixed', left: '12px', bottom: '12px', zIndex: 2147483647, display: 'none',
    maxWidth: 'min(720px, calc(100vw - 24px))', maxHeight: '50vh', overflow: 'auto', padding: '10px 12px', borderRadius: '6px',
    font: '12px/1.45 ui-monospace, monospace', whiteSpace: 'pre-wrap', color: '#e8ecf2', boxShadow: '0 4px 16px rgba(0, 0, 0, 0.4)'});
  document.body.append(panel);
  let timer = null;
  return {
    show(text, {failed = false, actions = [], seconds = 0} = {}) {
      clearTimeout(timer);
      panel.replaceChildren(text, ...actions.map(([caption, handler]) => button(caption, handler)));
      Object.assign(panel.style, {display: 'block', background: failed ? '#4a1c24' : '#1c2433',
        border: `1px solid ${failed ? '#c25b6a' : '#3a4658'}`});
      if (seconds) timer = setTimeout(() => { panel.style.display = 'none'; }, seconds * 1000);
    },
    hide() { clearTimeout(timer); panel.style.display = 'none'; },
  };
}

function button(caption, handler) {
  const node = document.createElement('button');
  node.textContent = caption;
  Object.assign(node.style, {display: 'block', marginTop: '8px', font: 'inherit', color: 'inherit', background: '#26324a',
    border: '1px solid #3a4658', borderRadius: '4px', padding: '4px 8px', cursor: 'pointer'});
  node.addEventListener('click', handler);
  return node;
}

// ---- Builds ----

// The host is imported only when needed: before the first build succeeds,
// the page is a placeholder without one.
function loadHost() {
  return import('/host.mjs').catch(() => null);
}

function moduleUrl(application, build) {
  const url = new URL(application.url, location.href);
  url.searchParams.set('build', build);
  return url.href;
}

// A page without a running application has nothing to keep, and a page or
// host script can change only by loading the page again.
async function applyBuild({build, changed, milliseconds}, notice) {
  if (!changed.length) { notice.hide(); return; }
  const host = await loadHost();
  if (!host?.running.length || changed.some(file => file.endsWith('.mjs') || file.endsWith('.html'))) {
    await Promise.all((host?.running ?? []).map(application => host.saveApplication(application)));
    location.reload();
    return;
  }
  changed.filter(file => file.endsWith('.css')).forEach(file => restyle(file, build));
  for (const application of changed.includes('app.wasm') ? host.running : [])
    if (!await replace(host, application, build, notice)) return;
  notice.show(`Reloaded ${changed.join(', ')}, built in ${milliseconds} ms`, {seconds: 2});
}

function restyle(file, build) {
  for (const link of document.querySelectorAll('link[rel="stylesheet"]')) {
    const url = new URL(link.href);
    if (url.pathname.endsWith(`/${file}`)) { url.searchParams.set('build', build); link.href = url.href; }
  }
}

// When the new module cannot take over the state, the old one keeps it,
// and starting over is the developer's choice.
async function replace(host, application, build, notice) {
  try {
    await host.replaceModule(application, moduleUrl(application, build));
    return true;
  } catch (error) {
    notice.show(`The new module could not restore the running state; the old module is still running.\n\n${error.message}`, {
      failed: true,
      actions: [['Start over with the new module', () => startOver(host, application, build, notice)], ['Dismiss', () => notice.hide()]],
    });
    return false;
  }
}

async function startOver(host, application, build, notice) {
  try {
    await host.replaceModule(application, moduleUrl(application, build), {fresh: true});
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

const notice = createNotice();
const events = new EventSource('/.lofi/events');
events.addEventListener('status', event => {
  const status = JSON.parse(event.data);
  if (status.state === 'failed') notice.show(status.message, {failed: true});
});
events.addEventListener('building', () => notice.show('Building...'));
events.addEventListener('built', event => applyBuild(JSON.parse(event.data), notice));
events.addEventListener('failed', event => notice.show(JSON.parse(event.data).message, {failed: true}));
addEventListener('error', event => explainError(event, notice));
