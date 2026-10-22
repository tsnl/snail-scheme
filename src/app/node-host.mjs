// Node exits when it has no referenced platform work, even if a JSPI actor
// is awaiting its mailbox. Own one process-lifetime token until the host
// drains. This timer neither polls actors nor schedules their execution.
import {setInterval, clearInterval} from 'node:timers';

export async function runHost(host, initial) {
  const lifetime = setInterval(() => {}, 2 ** 31 - 1);
  try { return await host.run(initial); }
  finally { clearInterval(lifetime); }
}
