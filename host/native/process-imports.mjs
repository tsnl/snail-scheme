// The native process effect boundary, bound as socket-imports.mjs binds
// sockets. Managed construction happens in the finishing task's own Wasm
// call; pending I/O touches native data only.
import {coded} from '../browser/tasks.mjs';
import {byteSnapshot} from '../browser/load.mjs';
import {replaceProcess, runChild} from './process.mjs';

const isCoded = error => error instanceof Error && typeof error.code === 'string' && /^[A-Z][A-Z0-9_]*$/.test(error.code);

function buffer(api, bytes) {
  const target = api['process:buffer'](bytes.length);
  for (let index = 0; index < bytes.length; index++) api['process:put'](target, index, bytes[index]);
  return target;
}

function errorCode(api, code) {
  return api['process:error-code'](buffer(api, new TextEncoder().encode(code)));
}

// A command crosses as its parts: the directory, the program, then the arguments.
function commandParts(api, command) {
  const parts = api['process:command-parts'](command), texts = [];
  for (let part = 0; part < api['process:part-count'](parts); part++) {
    let text = '';
    for (let index = 0; index < api['process:part-length'](parts, part); index++) {
      text += String.fromCodePoint(api['process:part-character'](parts, part, index));
    }
    texts.push(text);
  }
  return texts;
}

// Each operation that waits is started by `start-NAME` and finished by one
// `finish`, as socket-imports.mjs does.
export function processImports(program, tasks, processes, termination) {
  const helpers = () => {
    const current = program();
    return current.names ? current.linked.get('snail.shell.process').exports : current.runtime.exports;
  };

  // `deliver` builds the managed success; `failure` names the helper that
  // builds the Err of a coded failure. `dispose` releases a success that
  // no task finished.
  function start(ticket, failure, operation, deliver, dispose = () => {}) {
    tasks.start(Number(ticket), coded(operation),
                      outcome => {
                        const api = helpers();
                        return 'code' in outcome ? api[failure](errorCode(api, outcome.code)) : deliver(api, outcome.value);
                      },
                      outcome => { if ('value' in outcome) dispose(outcome.value); });
  }

  // Operations that finish at once report coded failures the same way.
  function immediately(operation) {
    const api = helpers();
    try { operation(api); return api['process:done'](); }
    catch (error) {
      if (!isCoded(error)) throw error;
      return api['process:unit-error'](errorCode(api, error.code));
    }
  }

  const finish = ticket => tasks.finish(Number(ticket));
  return {
    // Delivery transfers native ownership. If constructing the managed
    // wrapper traps, no Snail-Core code received the handle and it must be closed.
    'start-spawn'(ticket, command) {
      const [directory, executable, ...args] = commandParts(helpers(), command);
      start(ticket, 'process:spawn-error', signal => processes.spawn(signal, directory, executable, args),
            (api, result) => {
              try { return api['process:spawned'](result.handle, result.pid); }
              catch (error) { processes.close(result.handle); throw error; }
            },
            result => processes.close(result.handle));
    },
    'start-read-output'(ticket, child, stream, maximum) {
      const api = helpers(), id = api['process:handle'](child), descriptor = api['process:stream-descriptor'](stream);
      start(ticket, 'process:read-error', signal => processes.read(signal, id, descriptor, maximum),
            (api, bytes) => bytes === null ? api['process:eof']() : api['process:received'](buffer(api, bytes)));
    },
    'start-write-input'(ticket, child, pointer) {
      // Copy before projecting the token: any Wasm call can reuse staging.
      const bytes = byteSnapshot(program().runtime.exports.memory, pointer), id = helpers()['process:handle'](child);
      start(ticket, 'process:write-error', signal => processes.write(signal, id, bytes), (api, count) => api['process:written'](count));
    },
    'close-input': child => immediately(api => processes.closeInput(api['process:handle'](child))),
    'send-signal': (child, signal) => immediately(api => processes.kill(api['process:handle'](child), api['process:signal-number'](signal))),
    'start-wait-exit'(ticket, child) {
      const id = helpers()['process:handle'](child);
      start(ticket, 'process:exit-error', signal => processes.wait(signal, id),
            (api, exit) => 'code' in exit ? api['process:exited'](exit.code)
                                          : api['process:signaled'](buffer(api, new TextEncoder().encode(exit.signal))));
    },
    // The signal's number is delivered once the waiting task finishes,
    // which settles the delivery for `termination`, as dropping it does.
    'start-termination'(ticket) {
      start(ticket, null, signal => termination.wait(signal),
            (api, number) => { termination.settled(); return api['process:received-signal'](number); },
            () => termination.settled());
    },
    'close-process': child => immediately(api => {
      const id = api['process:handle'](child);
      if (!id) throw Object.assign(new Error('process handle is foreign'), {code: 'EBADF'});
      processes.close(id);
    }),
    // The input is copied before the command is projected: any Wasm call
    // can reuse staging. The program waits here until the child exits.
    'run'(command, pointer) {
      const input = byteSnapshot(program().runtime.exports.memory, pointer), api = helpers();
      const [directory, executable, ...args] = commandParts(api, command);
      let result;
      try { result = runChild(directory, executable, args, input); }
      catch (error) {
        if (!isCoded(error)) throw error;
        return api['process:run-error'](errorCode(api, error.code));
      }
      return api['process:captured'](result.code, buffer(api, new TextEncoder().encode(result.signal)),
                                     buffer(api, result.stdout), buffer(api, result.stderr));
    },
    // Returns only when the process could not be replaced.
    'exec'(command) {
      const api = helpers(), [directory, executable, ...args] = commandParts(api, command);
      return errorCode(api, replaceProcess(directory, executable, args));
    },
    'finish-spawn': finish, 'finish-read-output': finish, 'finish-write-input': finish,
    'finish-wait-exit': finish, 'finish-termination': finish,
  };
}
