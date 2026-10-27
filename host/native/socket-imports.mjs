// The native socket effect boundary. Managed construction happens while the
// resumed task owns the scheduler permit; pending I/O touches native data only.
import {byteSnapshot} from '../browser/entry.mjs';

function buffer(api, bytes) {
  const target = api['socket:buffer'](bytes.length);
  for (let index = 0; index < bytes.length; index++) api['socket:put'](target, index, bytes[index]);
  return target;
}

function errorCode(api, code) {
  return api['socket:error-code'](buffer(api, new TextEncoder().encode(code)));
}

function address(api, endpoint) {
  const count = api['socket:address-length'](endpoint);
  let text = '';
  for (let index = 0; index < count; index++) text += String.fromCodePoint(api['socket:address-character'](endpoint, index));
  return text;
}

export function socketImports(program, scheduler, tcp, udp) {
  const helpers = () => {
    const current = program();
    return current.names ? current.linked.get('snail-core.socket').exports : current.runtime.exports;
  };

  // Socket successes never use strings; a string is an error code.
  // Cancellation and uncoded host failures must unwind the invocation.
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

  async function acquire(api, owner, operation, success, failure) {
    const result = await wait(operation, value => { if (typeof value !== 'string') owner.close(value.handle); });
    if (typeof result === 'string') return failure(errorCode(api, result));
    // Delivery transfers native ownership. If constructing the managed
    // wrapper traps, no Snail-Core code received the handle and it must be closed.
    try { return success(result); }
    catch (error) { owner.close(result.handle); throw error; }
  }

  async function listening(signal, address, port) {
    const handle = await tcp.listen(signal, address, port);
    // Capture native metadata with acquisition, before success waits in the
    // scheduler queue. A listener may close before that result is delivered.
    try { return {handle, port: tcp.port(handle)}; }
    catch (error) { tcp.close(handle); throw error; }
  }

  async function bound(signal, address, port) {
    const handle = await udp.bind(signal, address, port);
    try { return {handle, port: udp.port(handle)}; }
    catch (error) { udp.close(handle); throw error; }
  }

  function close(api, owner, handle) {
    if (!handle) return api['socket:close-error'](errorCode(api, 'EBADF'));
    owner.close(handle);
    return api['socket:closed']();
  }

  return {
    listen: new WebAssembly.Suspending(endpoint => {
      const api = helpers(), host = address(api, endpoint), port = api['socket:endpoint-port'](endpoint);
      return acquire(api, tcp, signal => listening(signal, host, port), result => api['tcp:listening'](result.handle, result.port), api['tcp:listen-error']);
    }),
    connect: new WebAssembly.Suspending(endpoint => {
      const api = helpers(), host = address(api, endpoint), port = api['socket:endpoint-port'](endpoint);
      return acquire(api, tcp, async signal => ({handle: await tcp.connect(signal, host, port)}), result => api['tcp:connected'](result.handle), api['tcp:connection-error']);
    }),
    accept: new WebAssembly.Suspending(listener => {
      const api = helpers(), id = api['tcp:listener-handle'](listener);
      return acquire(api, tcp, async signal => ({handle: await tcp.accept(signal, id)}), result => api['tcp:connected'](result.handle), api['tcp:connection-error']);
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
      return typeof count === 'string' ? api['socket:write-error'](errorCode(api, count)) : api['socket:written'](count);
    }),
    'finish-connection': new WebAssembly.Suspending(async (connection, grace) => {
      const api = helpers(), id = api['tcp:connection-handle'](connection);
      const result = await wait(signal => tcp.finish(signal, id, grace));
      return typeof result === 'string' ? api['socket:close-error'](errorCode(api, result)) : api['socket:closed']();
    }),
    'close-listener'(listener) { const api = helpers(); return close(api, tcp, api['tcp:listener-handle'](listener)); },
    'close-connection'(connection) { const api = helpers(); return close(api, tcp, api['tcp:connection-handle'](connection)); },
    bind: new WebAssembly.Suspending(endpoint => {
      const api = helpers(), host = address(api, endpoint), port = api['socket:endpoint-port'](endpoint);
      return acquire(api, udp, signal => bound(signal, host, port), result => api['udp:bound'](result.handle, result.port), api['udp:bind-error']);
    }),
    send: new WebAssembly.Suspending(async (socket, peer, pointer) => {
      const bytes = byteSnapshot(program().runtime.exports.memory, pointer), api = helpers();
      const id = api['udp:socket-handle'](socket), host = address(api, peer), port = api['socket:endpoint-port'](peer);
      const count = await wait(signal => udp.send(signal, id, host, port, bytes));
      return typeof count === 'string' ? api['socket:write-error'](errorCode(api, count)) : api['socket:written'](count);
    }),
    receive: new WebAssembly.Suspending(async (socket, maximum) => {
      const api = helpers(), id = api['udp:socket-handle'](socket);
      const packet = await wait(signal => udp.receive(signal, id, maximum));
      if (typeof packet === 'string') return api['udp:receive-error'](errorCode(api, packet));
      return api['udp:received'](buffer(api, new TextEncoder().encode(packet.address)), packet.port, buffer(api, packet.bytes));
    }),
    'close-udp'(socket) { const api = helpers(); return close(api, udp, api['udp:socket-handle'](socket)); },
  };
}
