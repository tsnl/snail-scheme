// A kernel in a worker: a browser Web Worker or a Node worker thread. The
// page or terminal sends the kernel's bytes, then text to evaluate, and gets
// back what src/notebook/kernel.mjs returns; see `kernelClient` there.
import {createKernel} from './kernel.mjs';

const port = globalThis.WorkerGlobalScope ? self : (await import('node:worker_threads')).parentPort;
let kernel = null;

async function answer({id, kind, argument}) {
  try {
    if (kind === 'load') kernel = await createKernel(argument);
    const result = kind === 'evaluate' ? kernel.evaluate(argument) : kind === 'names' ? kernel.names() : null;
    port.postMessage({id, result});
  } catch (error) {
    port.postMessage({id, error: error.message});
  }
}

if (port.on) port.on('message', answer);
else port.addEventListener('message', event => answer(event.data));
