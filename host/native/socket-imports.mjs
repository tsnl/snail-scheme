// The native socket boundary, src/snail/runtime/native/socket.sld. Every
// argument and answer is a number (answers.mjs); pending I/O touches
// native data only.
import {byteSnapshot} from '../browser/load.mjs';
import {heldAnswers} from './answers.mjs';

// An endpoint crosses as its address, whose four octets are the I32's
// unsigned bits, most significant first, and its port. (snail shell
// socket)'s `endpoint` parsed both, so neither is checked here.
const dotted = address => [24, 16, 8, 0].map(shift => (address >>> shift) & 255).join('.');
const fault = code => Object.assign(new Error(code), {code});
const encode = text => new TextEncoder().encode(text);

// Each operation that waits is started by `start-NAME`, which reads its
// arguments at once, and answered by `finish` with its ticket (tasks.mjs).
export function socketImports(program, tasks, tcp, udp) {
  const {start, immediately, imports} = heldAnswers(tasks);
  const memory = () => program().runtime.exports.memory;

  // Capture native metadata with acquisition, before success waits for
  // its finish. A listener may close before that result is delivered.
  async function listening(signal, address, port, backlog) {
    const handle = await tcp.listen(signal, address, port, backlog);
    try { return {handle, port: tcp.port(handle)}; }
    catch (error) { tcp.close(handle); throw error; }
  }

  async function bound(signal, address, port, queued) {
    const handle = await udp.bind(signal, address, port, queued);
    try { return {handle, port: udp.port(handle)}; }
    catch (error) { udp.close(handle); throw error; }
  }

  // Handle 0 is a token from another handler, which names nothing here.
  const close = (owner, handle) => immediately(() => {
    if (!handle) throw fault('EBADF');
    owner.close(handle);
  });
  const acquired = result => ({value: result.handle, number: result.port});
  // An answer that carries nothing but its number.
  const bare = value => ({value});

  return {
    ...imports,
    'start-listen'(ticket, address, port, backlog) {
      start(ticket, signal => listening(signal, dotted(address), port, backlog), acquired, result => tcp.close(result.handle));
    },
    'start-connect'(ticket, address, port) {
      start(ticket, signal => tcp.connect(signal, dotted(address), port), bare, handle => tcp.close(handle));
    },
    'start-accept'(ticket, listener) {
      start(ticket, signal => tcp.accept(signal, listener), bare, handle => tcp.close(handle));
    },
    'start-read'(ticket, connection, maximum) {
      start(ticket, signal => tcp.read(signal, connection, maximum),
            bytes => bytes === null ? {value: 0} : {value: 1, strings: [bytes]});
    },
    'start-write'(ticket, connection, pointer) {
      const bytes = byteSnapshot(memory(), pointer);
      start(ticket, signal => tcp.write(signal, connection, bytes), bare);
    },
    'start-finish-connection'(ticket, connection, grace) {
      start(ticket, signal => tcp.finish(signal, connection, grace), () => ({}));
    },
    'close-tcp': handle => close(tcp, handle),
    'start-bind'(ticket, address, port, queued) {
      start(ticket, signal => bound(signal, dotted(address), port, queued), acquired, result => udp.close(result.handle));
    },
    'start-send'(ticket, socket, address, port, pointer) {
      const bytes = byteSnapshot(memory(), pointer);
      start(ticket, signal => udp.send(signal, socket, dotted(address), port, bytes), bare);
    },
    'start-receive'(ticket, socket, maximum) {
      start(ticket, signal => udp.receive(signal, socket, maximum),
            packet => ({number: packet.port, strings: [encode(packet.address), packet.bytes]}));
    },
    'close-udp': handle => close(udp, handle),
  };
}
