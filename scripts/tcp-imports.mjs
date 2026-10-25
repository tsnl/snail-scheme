// The native TCP effect boundary. Managed construction happens while the
// resumed task owns the scheduler permit; pending I/O touches native data only.
import {byteSnapshot} from '../src/app/entry.mjs';

function buffer(api, bytes) {
  const target = api['tcp:buffer'](bytes.length);
  for (let index = 0; index < bytes.length; index++) api['tcp:put'](target, index, bytes[index]);
  return target;
}

function errorCode(api, code) {
  return api['tcp:error-code'](buffer(api, new TextEncoder().encode(code)));
}

function address(api, endpoint) {
  const count = api['tcp:address-length'](endpoint);
  let text = '';
  for (let index = 0; index < count; index++) text += String.fromCodePoint(api['tcp:address-character'](endpoint, index));
  return text;
}

export function tcpImports(program, scheduler, tcp) {
  const helpers = () => {
    const current = program();
    return current.names ? current.linked.get('lofi.tcp').exports : current.runtime.exports;
  };

  // TCP successes are acquisitions, counts, bytes or EOF; a string is an error
  // code. Cancellation and uncoded host failures must unwind the invocation.
  function wait(operation, discard) {
    return scheduler.suspend(async signal => {
      try { return await operation(signal); }
      catch (error) {
        signal.throwIfAborted();
        if (!(error instanceof Error) || typeof error.code !== 'string' || !/^[A-Z][A-Z0-9_]*$/.test(error.code)) throw error;
        return error.code;
      }
    }, discard);
  }

  async function acquire(api, operation, success, failure) {
    const result = await wait(operation, value => { if (typeof value !== 'string') tcp.close(value.handle); });
    if (typeof result === 'string') return failure(errorCode(api, result));
    // Delivery transfers native ownership. If constructing the managed
    // wrapper traps, no Lofi code received the handle and it must be closed.
    try { return success(result); }
    catch (error) { tcp.close(result.handle); throw error; }
  }

  async function listening(signal, address, port) {
    const handle = await tcp.listen(signal, address, port);
    // Capture native metadata with acquisition, before success waits in the
    // scheduler queue. A listener may close before that result is delivered.
    try { return {handle, port: tcp.port(handle)}; }
    catch (error) { tcp.close(handle); throw error; }
  }

  function close(api, handle) {
    if (!handle) return api['tcp:close-error'](errorCode(api, 'EBADF'));
    tcp.close(handle);
    return api['tcp:closed']();
  }

  return {
    listen: new WebAssembly.Suspending(endpoint => {
      const api = helpers(), host = address(api, endpoint), port = api['tcp:endpoint-port'](endpoint);
      return acquire(api, signal => listening(signal, host, port), result => api['tcp:listening'](result.handle, result.port), api['tcp:listen-error']);
    }),
    connect: new WebAssembly.Suspending(endpoint => {
      const api = helpers(), host = address(api, endpoint), port = api['tcp:endpoint-port'](endpoint);
      return acquire(api, async signal => ({handle: await tcp.connect(signal, host, port)}), result => api['tcp:connected'](result.handle), api['tcp:connection-error']);
    }),
    accept: new WebAssembly.Suspending(listener => {
      const api = helpers(), id = api['tcp:listener-handle'](listener);
      return acquire(api, async signal => ({handle: await tcp.accept(signal, id)}), result => api['tcp:connected'](result.handle), api['tcp:connection-error']);
    }),
    read: new WebAssembly.Suspending(async (connection, maximum) => {
      const api = helpers(), id = api['tcp:connection-handle'](connection);
      const bytes = await wait(signal => tcp.read(signal, id, maximum));
      if (typeof bytes === 'string') return api['tcp:read-error'](errorCode(api, bytes));
      return bytes === null ? api['tcp:eof']() : api['tcp:received'](buffer(api, bytes));
    }),
    write: new WebAssembly.Suspending(async (connection, pointer) => {
      // Copy before projecting the token: any Wasm call can reuse staging.
      const bytes = byteSnapshot(program().runtime.exports.memory, pointer), api = helpers();
      const id = api['tcp:connection-handle'](connection), count = await wait(signal => tcp.write(signal, id, bytes));
      return typeof count === 'string' ? api['tcp:write-error'](errorCode(api, count)) : api['tcp:written'](count);
    }),
    'close-listener'(listener) { const api = helpers(); return close(api, api['tcp:listener-handle'](listener)); },
    'close-connection'(connection) { const api = helpers(); return close(api, api['tcp:connection-handle'](connection)); },
  };
}
