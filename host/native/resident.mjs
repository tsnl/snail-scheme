// The development service's builder: `snail resident PROJECT`, the command
// line's Snail program in a child process (bootstrap/cli.sld, "The resident
// builder"), which keeps each target's compiler session between builds.
// This module only frames its JSON lines, a request and then its reply, so
// a reply answers the oldest request still waiting. It is temporary: the
// service itself moves to Snail-Core (#567, step B).
import {execFileSync, spawn} from 'node:child_process';
import {join} from 'node:path';
import {createInterface} from 'node:readline';

// The command line and the runtime it links programs with, and the editor's
// formatter, built by stage 0 when their sources change.
export function editorTools(root) {
  return JSON.parse(execFileSync(join(root, 'scripts/snail-tool'), ['editor-tools'], {encoding: 'utf8'}));
}

export function startResident({root, project, tools}) {
  const child = spawn(process.execPath, ['--no-warnings', join(root, 'host/native/run-snail.mjs'),
    tools.cli, root, tools.runtime, 'resident', project], {stdio: ['pipe', 'pipe', 'pipe']});
  const waiting = [];
  let ended = null, stderr = '';
  createInterface({input: child.stdout}).on('line', line => waiting.shift()?.resolve(JSON.parse(line)));
  // What the resident writes to stderr is a panic's message, which its exit
  // reports; the end of it is enough.
  child.stderr.setEncoding('utf8').on('data', text => {
    process.stderr.write(text);
    stderr = (stderr + text).slice(-4096);
  });
  // A write after the child exits fails; its exit answers every request.
  child.stdin.on('error', () => {});
  const exited = new Promise(resolve => child.once('close', (code, signal) => {
    const message = stderr.trim();
    ended = new Error(`the resident builder exited with ${signal ?? `status ${code}`}${message ? `: ${message}` : ''}`);
    for (const reply of waiting.splice(0)) reply.reject(ended);
    resolve({code, signal, error: ended});
  }));
  function request(message) {
    if (ended) return Promise.reject(ended);
    const reply = Promise.withResolvers();
    waiting.push(reply);
    child.stdin.write(`${JSON.stringify(message)}\n`);
    return reply.promise;
  }
  return {
    started: new Promise((resolve, reject) => { child.once('spawn', resolve); child.once('error', reject); }),
    exited,
    get pid() { return child.exitCode === null && child.signalCode === null ? child.pid : -1; },
    build: (epoch, prefix) => request({kind: 'build', epoch, prefix}),
    publish: epoch => request({kind: 'publish', epoch}),
    discard: epoch => request({kind: 'discard', epoch}),
    // The resident finishes the request it is answering, then exits at the
    // end of its input.
    close() { child.stdin.end(); },
    kill() { child.kill('SIGKILL'); },
  };
}
