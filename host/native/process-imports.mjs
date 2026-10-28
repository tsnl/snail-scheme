// The native process effect boundary, bound as socket-imports.mjs binds
// sockets. Managed construction happens while the resumed task owns the
// scheduler permit; pending I/O touches native data only.
import {byteSnapshot} from '../browser/entry.mjs';

const coded = error => error instanceof Error && typeof error.code === 'string' && /^[A-Z][A-Z0-9_]*$/.test(error.code);

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

export function processImports(program, scheduler, processes) {
  const helpers = () => {
    const current = program();
    return current.names ? current.linked.get('snail-core.process').exports : current.runtime.exports;
  };

  // Process successes never use strings; a string is an error code.
  // Cancellation and uncoded host failures must unwind the invocation.
  function suspended(operation, discard) {
    return scheduler.suspend(async signal => {
      try { return await operation(signal); }
      catch (error) {
        signal.throwIfAborted();
        if (!coded(error)) throw error;
        return error.code;
      }
    }, discard);
  }

  // Operations that finish at once report coded failures the same way.
  function immediately(operation) {
    const api = helpers();
    try { operation(api); return api['process:done'](); }
    catch (error) {
      if (!coded(error)) throw error;
      return api['process:unit-error'](errorCode(api, error.code));
    }
  }

  // Delivery transfers native ownership. If constructing the managed
  // wrapper traps, no Snail-Core code received the handle and it must be closed.
  async function spawn(command) {
    const api = helpers(), [directory, executable, ...args] = commandParts(api, command);
    const result = await suspended(signal => processes.spawn(signal, directory, executable, args),
                                   value => { if (typeof value !== 'string') processes.close(value.handle); });
    if (typeof result === 'string') return api['process:spawn-error'](errorCode(api, result));
    try { return api['process:spawned'](result.handle, result.pid); }
    catch (error) { processes.close(result.handle); throw error; }
  }

  return {
    spawn: new WebAssembly.Suspending(spawn),
    'read-output': new WebAssembly.Suspending(async (child, stream, maximum) => {
      const api = helpers(), id = api['process:handle'](child), descriptor = api['process:stream-descriptor'](stream);
      const bytes = await suspended(signal => processes.read(signal, id, descriptor, maximum));
      if (typeof bytes === 'string') return api['process:read-error'](errorCode(api, bytes));
      return bytes === null ? api['process:eof']() : api['process:received'](buffer(api, bytes));
    }),
    'write-input': new WebAssembly.Suspending(async (child, pointer) => {
      // Copy before projecting the token: any Wasm call can reuse staging.
      const bytes = byteSnapshot(program().runtime.exports.memory, pointer), api = helpers();
      const id = api['process:handle'](child), count = await suspended(signal => processes.write(signal, id, bytes));
      return typeof count === 'string' ? api['process:write-error'](errorCode(api, count)) : api['process:written'](count);
    }),
    'close-input': child => immediately(api => processes.closeInput(api['process:handle'](child))),
    'send-signal': (child, signal) => immediately(api => processes.kill(api['process:handle'](child), api['process:signal-number'](signal))),
    'wait-exit': new WebAssembly.Suspending(async child => {
      const api = helpers(), id = api['process:handle'](child), exit = await suspended(signal => processes.wait(signal, id));
      if (typeof exit === 'string') return api['process:exit-error'](errorCode(api, exit));
      return 'code' in exit ? api['process:exited'](exit.code) : api['process:signaled'](buffer(api, new TextEncoder().encode(exit.signal)));
    }),
    'close-process': child => immediately(api => {
      const id = api['process:handle'](child);
      if (!id) throw Object.assign(new Error('process handle is foreign'), {code: 'EBADF'});
      processes.close(id);
    }),
  };
}
