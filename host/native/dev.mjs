// One project development process. The browser edits native files; compilation
// stays in the service's resident worker. Application launching follows later.
import {resolve} from 'node:path';
import {editorTools} from './project.mjs';
import {serveProject} from './project-http.mjs';

function options(arguments_) {
  let port = 8000;
  if (arguments_[0] === '--port') {
    const text = arguments_[1];
    if (!/^\d+$/.test(text ?? '') || Number(text) > 65535) throw new Error('port must be an integer from 0 to 65535');
    port = Number(text); arguments_ = arguments_.slice(2);
  }
  if (arguments_.length !== 1 || arguments_[0].startsWith('-')) throw new Error('usage: snail dev [--port PORT] PROJECT');
  return {project: resolve(arguments_[0]), port};
}

try {
  const [root, ...arguments_] = process.argv.slice(2), chosen = options(arguments_);
  const service = await serveProject({root, ...chosen, tools: editorTools(root)});
  const stop = () => { void service.close().catch(() => {}); };
  process.once('SIGINT', stop); process.once('SIGTERM', stop);
  console.log(`editing ${chosen.project} at ${service.url}/`);
  await service.closed;
} catch (error) {
  console.error(`snail dev: ${error.message}`);
  process.exitCode = 1;
}
