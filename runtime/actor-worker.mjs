// One subprocess, one Scheme library instance. Process exit closes WASI files
// even when a trap or infinite loop prevents Scheme/Rust cleanup from running.
import { loadInstance, invoke } from './actor-instance.mjs';
import { frame, unframe } from './actors.mjs';

const instance = await loadInstance(process.argv[2]);
process.send('(ready)');

// Any decoding, invocation, or encoding failure terminates this worker. Calls
// run to completion here; other actors execute concurrently in other processes.
// An uncaught exception exits immediately; no queued call can reenter the instance.
process.on('message', text => {
  const call = unframe(text);
  process.send(frame(call.connection, call.request, invoke(instance, call.datum)));
});
process.on('disconnect', () => process.exit(0));
