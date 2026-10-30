// The native socket effect boundary. Managed construction happens in the
// finishing task's own Wasm call; pending I/O touches native data only.
import {coded} from '../browser/tasks.mjs';
import {byteSnapshot} from '../browser/load.mjs';

function buffer(api, bytes) {
  const target = api['socket:buffer'](bytes.length);
  for (let index = 0; index < bytes.length; index++) api['socket:put'](target, index, bytes[index]);
  return target;
}

function errorCode(api, code) {
  return api['socket:error-code'](buffer(api, new TextEncoder().encode(code)));
}

// An endpoint crosses as its address, whose four octets are the I32's
// unsigned bits, most significant first, and its port. (snail shell
// socket)'s `endpoint` parsed both, so neither is checked here.
const dotted = address => [24, 16, 8, 0].map(shift => (address >>> shift) & 255).join('.');

// Each operation that waits is started by `start-NAME`, which reads its
// arguments at once, and finished by one `finish` (tasks.mjs). Each finish
// import has its own name, since its result type differs.
export function socketImports(program, tasks, tcp, udp) {
  const helpers = () => {
    const current = program();
    return current.names ? current.linked.get('snail.shell.socket').exports : current.runtime.exports;
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

  // Delivery transfers native ownership. If constructing the managed
  // wrapper traps, no Snail-Core code received the handle and it must be closed.
  function acquire(ticket, owner, failure, operation, wrap) {
    start(ticket, failure, operation, (api, result) => {
      try { return wrap(api, result); }
      catch (error) { owner.close(result.handle); throw error; }
    }, result => owner.close(result.handle));
  }

  async function listening(signal, address, port, backlog) {
    const handle = await tcp.listen(signal, address, port, backlog);
    // Capture native metadata with acquisition, before success waits for
    // its finish. A listener may close before that result is delivered.
    try { return {handle, port: tcp.port(handle)}; }
    catch (error) { tcp.close(handle); throw error; }
  }

  async function bound(signal, address, port, queued) {
    const handle = await udp.bind(signal, address, port, queued);
    try { return {handle, port: udp.port(handle)}; }
    catch (error) { udp.close(handle); throw error; }
  }

  function close(api, owner, handle) {
    if (!handle) return api['socket:close-error'](errorCode(api, 'EBADF'));
    owner.close(handle);
    return api['socket:closed']();
  }

  const finish = ticket => tasks.finish(Number(ticket));
  return {
    'start-listen'(ticket, address, port, backlog) {
      acquire(ticket, tcp, 'tcp:listen-error', signal => listening(signal, dotted(address), port, backlog),
              (api, result) => api['tcp:listening'](result.handle, result.port));
    },
    'start-connect'(ticket, address, port) {
      acquire(ticket, tcp, 'tcp:connection-error', async signal => ({handle: await tcp.connect(signal, dotted(address), port)}),
              (api, result) => api['tcp:connected'](result.handle));
    },
    'start-accept'(ticket, listener) {
      const id = helpers()['tcp:listener-handle'](listener);
      acquire(ticket, tcp, 'tcp:connection-error', async signal => ({handle: await tcp.accept(signal, id)}),
              (api, result) => api['tcp:connected'](result.handle));
    },
    'start-read'(ticket, connection, maximum) {
      const id = helpers()['tcp:connection-handle'](connection);
      start(ticket, 'tcp:read-error', signal => tcp.read(signal, id, maximum),
            (api, bytes) => bytes === null ? api['tcp:eof']() : api['tcp:received'](buffer(api, bytes)));
    },
    'start-write'(ticket, connection, pointer) {
      // Copy before projecting the token: any Wasm call can reuse staging.
      const bytes = byteSnapshot(program().runtime.exports.memory, pointer);
      const id = helpers()['tcp:connection-handle'](connection);
      start(ticket, 'socket:write-error', signal => tcp.write(signal, id, bytes), (api, count) => api['socket:written'](count));
    },
    'start-finish-connection'(ticket, connection, grace) {
      const id = helpers()['tcp:connection-handle'](connection);
      start(ticket, 'socket:close-error', signal => tcp.finish(signal, id, grace), api => api['socket:closed']());
    },
    'close-listener'(listener) { const api = helpers(); return close(api, tcp, api['tcp:listener-handle'](listener)); },
    'close-connection'(connection) { const api = helpers(); return close(api, tcp, api['tcp:connection-handle'](connection)); },
    'start-bind'(ticket, address, port, queued) {
      acquire(ticket, udp, 'udp:bind-error', signal => bound(signal, dotted(address), port, queued),
              (api, result) => api['udp:bound'](result.handle, result.port));
    },
    'start-send'(ticket, socket, address, port, pointer) {
      const bytes = byteSnapshot(program().runtime.exports.memory, pointer), id = helpers()['udp:socket-handle'](socket);
      start(ticket, 'socket:write-error', signal => udp.send(signal, id, dotted(address), port, bytes), (api, count) => api['socket:written'](count));
    },
    'start-receive'(ticket, socket, maximum) {
      const id = helpers()['udp:socket-handle'](socket);
      start(ticket, 'udp:receive-error', signal => udp.receive(signal, id, maximum),
            (api, packet) => api['udp:received'](buffer(api, new TextEncoder().encode(packet.address)), packet.port, buffer(api, packet.bytes)));
    },
    'close-udp'(socket) { const api = helpers(); return close(api, udp, api['udp:socket-handle'](socket)); },
    'finish-listen': finish, 'finish-connect': finish, 'finish-accept': finish, 'finish-read': finish,
    'finish-write': finish, 'finish-finish-connection': finish, 'finish-bind': finish, 'finish-send': finish,
    'finish-receive': finish,
  };
}
