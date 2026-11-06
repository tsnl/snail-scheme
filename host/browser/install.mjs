// Browser-owned installation offers survive application generations. The host
// retains the opaque event; Scheme decides when to ask and what to show.
let offer = null, installed = false;
addEventListener('beforeinstallprompt', event => {
  if (typeof event.prompt !== 'function') return;
  event.preventDefault(); offer = event;
});
addEventListener('appinstalled', () => { installed = true; offer = null; });

// Results agree with (snail shell dom page): accepted, dismissed,
// unavailable, needs another gesture, failed, or already installed. Acceptance is distinct
// from the later appinstalled event.
const ACCEPTED = 0, DISMISSED = 1, UNAVAILABLE = 2, GESTURE = 3, FAILED = 4, ALREADY = 5;
const status = () => installed || matchMedia('(display-mode: standalone)').matches || navigator.standalone === true ? 2 : offer ? 1 : 0;

function prompt() {
  if (status() === 2) return Promise.resolve(ALREADY);
  if (!offer) return Promise.resolve(UNAVAILABLE);
  // A queued Scheme command can still use the initiating click's transient
  // activation. If it expired, keep the offer for the next explicit click.
  if (!navigator.userActivation?.isActive) return Promise.resolve(GESTURE);
  const current = offer; offer = null;
  try {
    return Promise.resolve(current.prompt()).then(result => result ?? current.userChoice)
      .then(choice => choice?.outcome === 'accepted' ? ACCEPTED : choice?.outcome === 'dismissed' ? DISMISSED : FAILED, () => FAILED);
  } catch { return Promise.resolve(FAILED); }
}

// A browser dialog itself cannot be cancelled, but a stopped task must stop
// waiting for it. The eventual browser outcome retains no Wasm task state.
function whileRunning(signal, pending, stopped) {
  return new Promise(resolve => {
    const finish = value => { signal.removeEventListener('abort', abort); resolve(value); };
    const abort = () => finish(stopped);
    signal.addEventListener('abort', abort, {once: true});
    pending.then(finish, () => finish(stopped));
    if (signal.aborted) abort();
  });
}

export function webAppImports(runtime) {
  const tasks = () => runtime.execution.tasks;
  return {
    'installation-status': status,
    'start-install'(ticket) {
      tasks().start(Number(ticket), signal => signal.aborted ? FAILED : whileRunning(signal, prompt(), FAILED), result => result);
    },
    'finish-install': ticket => tasks().finish(Number(ticket)),
    'fullscreen': () => document.fullscreenElement ? 1 : 0,
    'start-fullscreen'(ticket, enter) {
      tasks().start(Number(ticket), signal => {
        if (signal.aborted) return 0;
        try {
          const pending = enter ? document.documentElement.requestFullscreen() : document.exitFullscreen();
          return whileRunning(signal, Promise.resolve(pending).then(() => 1, () => 0), 0);
        } catch { return 0; }
      }, result => result);
    },
    'finish-fullscreen': ticket => tasks().finish(Number(ticket)),
  };
}
