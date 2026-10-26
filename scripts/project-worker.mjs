// The compiler and its opaque Sessions stay in this worker. Only parsed project
// descriptions, completed generation paths and diagnostics cross to the parent.
import {parentPort, workerData} from 'node:worker_threads';
import {CompilerCrashed} from './compiler.mjs';
import {createProjectBuilder, discardProject} from './project.mjs';

const builder = await createProjectBuilder(workerData);

function crashed(error) {
  for (; error; error = error.cause) if (error instanceof CompilerCrashed) return true;
  return false;
}

function build({id, prefix}) {
  let description = null, candidate = null;
  try {
    description = builder.describe();
    candidate = builder.build(description, null, 'development', prefix);
    parentPort.postMessage({id, description, candidate, diagnostics: []});
  } catch (error) {
    if (candidate) discardProject(candidate); // A failed handoff retains ownership here.
    if (crashed(error)) throw error;
    parentPort.postMessage({id, description, candidate: null,
      diagnostics: [{severity: 'error', message: error.message}]});
  }
}

parentPort.on('message', message => {
  if (message.kind === 'build') build(message);
  else if (message.kind === 'close') { builder.close(); parentPort.close(); }
  else throw new Error(`unknown project worker command ${message.kind}`);
});
parentPort.postMessage({kind: 'ready'});
