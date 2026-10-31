// How a native interface answers the shell: with a number, -1 for a
// failure, and holding the number and byte strings the answer carries
// until it answers again, for the shell to read first. A failure's first
// byte string is its error code. The table of what each operation answers
// is in src/snail/runtime/native/socket.sld and process.sld. Nothing
// managed crosses: the shell builds its values from what it reads.
import {coded} from '../browser/tasks.mjs';

export const isCoded = error => error instanceof Error && typeof error.code === 'string' && /^[A-Z][A-Z0-9_]*$/.test(error.code);

export function heldAnswers(tasks) {
  let held = {number: 0, strings: []};
  const answer = ({value = 0, number = 0, strings = []}) => { held = {number, strings}; return value; };
  const failed = code => ({value: -1, strings: [new TextEncoder().encode(code)]});

  return {
    answer,
    failed,
    // Starts `operation` for `ticket`: `deliver` makes the answer of its
    // value, and `dispose` releases a value no task finished, as when an
    // accepted connection's task was dropped. A coded failure answers -1;
    // any other traps the task that finishes it.
    start(ticket, operation, deliver, dispose = () => {}) {
      tasks.start(Number(ticket), coded(operation),
                  outcome => 'code' in outcome ? failed(outcome.code) : deliver(outcome.value),
                  outcome => { if ('value' in outcome) dispose(outcome.value); });
    },
    // An operation that answers at once with 0, or with its coded failure.
    immediately(operation) {
      try { operation(); return answer({}); }
      catch (error) { if (!isCoded(error)) throw error; return answer(failed(error.code)); }
    },
    imports: {
      finish: ticket => answer(tasks.finish(Number(ticket))),
      'held-number': () => held.number,
      'held-length': position => held.strings[position].length,
      'held-byte': (position, index) => held.strings[position][index],
    },
  };
}
