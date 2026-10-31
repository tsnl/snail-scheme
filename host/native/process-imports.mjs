// The native process boundary, src/snail/runtime/native/process.sld,
// answered as socket-imports.mjs answers. Pending I/O touches native data
// only.
import {byteSnapshot, stagedStrings} from '../browser/load.mjs';
import {heldAnswers, isCoded} from './answers.mjs';
import {resolve} from 'node:path';
import {isExecutable, replaceProcess, runChild} from './process.mjs';

const fault = code => Object.assign(new Error(code), {code});
const encode = text => new TextEncoder().encode(text);

// How a child ended: Node gives its exit code, or the name of the signal
// that ended it.
const ended = exit => 'code' in exit ? {value: 0, number: exit.code} : {value: 1, strings: [encode(exit.signal)]};

export function processImports(program, tasks, processes, termination) {
  const {answer, failed, start, immediately, imports} = heldAnswers(tasks);
  const memory = () => program().runtime.exports.memory;
  // The command sent last: its directory, the program's path, the name it
  // is run as, then its arguments.
  const command = stagedStrings();

  return {
    ...imports,
    ...command.imports,
    // A directory and a path: whether the path, taken from the directory,
    // names a regular file this process may execute.
    executable() {
      const [directory, path] = command.take();
      return isExecutable(resolve(directory, path)) ? 1 : 0;
    },
    'start-spawn'(ticket) {
      const [directory, program, name, ...args] = command.take();
      start(ticket, signal => processes.spawn(signal, directory, program, name, args),
            result => ({value: result.handle, number: result.pid}), result => processes.close(result.handle));
    },
    'start-read-output'(ticket, child, descriptor, maximum) {
      start(ticket, signal => processes.read(signal, child, descriptor, maximum),
            bytes => bytes === null ? {value: 0} : {value: 1, strings: [bytes]});
    },
    'start-write-input'(ticket, child, pointer) {
      const bytes = byteSnapshot(memory(), pointer);
      start(ticket, signal => processes.write(signal, child, bytes), count => ({value: count}));
    },
    'close-input': child => immediately(() => processes.closeInput(child)),
    'send-signal': (child, number) => immediately(() => processes.kill(child, number)),
    'start-wait-exit'(ticket, child) {
      start(ticket, signal => processes.wait(signal, child), ended);
    },
    // The signal's number is delivered once the waiting task finishes,
    // which settles the delivery for `termination`, as dropping it does.
    'start-termination'(ticket) {
      start(ticket, signal => termination.wait(signal),
            number => { termination.settled(); return {value: number}; },
            () => termination.settled());
    },
    // Handle 0 is a token from another handler, which names nothing here.
    'close-process': child => immediately(() => {
      if (!child) throw fault('EBADF');
      processes.close(child);
    }),
    // The program waits here until the child exits.
    run(pointer) {
      const input = byteSnapshot(memory(), pointer), [directory, program, name, ...args] = command.take();
      let result;
      try { result = runChild(directory, program, name, args, input); }
      catch (error) {
        if (!isCoded(error)) throw error;
        return answer(failed(error.code));
      }
      return answer({value: result.code < 0 ? 1 : 0, number: result.code,
                     strings: [encode(result.signal), result.stdout, result.stderr]});
    },
    // Answers only when the process could not be replaced.
    exec() {
      const [directory, program, name, ...args] = command.take();
      return answer(failed(replaceProcess(directory, program, name, args)));
    },
  };
}
