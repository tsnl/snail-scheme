import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {openCompilerService} from '../../src/lofi/compiler/service.mjs';

const directory = process.argv[2];
if (process.argv[3] === '--worker') {
  const scope = openCompilerService({timeout: 10000,
    chibi: fileURLToPath(new URL('../target/debug/chibi-adversary', import.meta.url))});
  try {
    const functions = scope.providers.get('lofi.compiler').exports;
    assert.equal(functions['result-ok'](functions['map-empty']()), 1);
  } finally { scope.close(); }
} else {
  // The host cannot answer until this process observes its progress. This
  // proves stderr is visible during the synchronous call, before its response.
  const record = join(directory, 'progress-host.json');
  const worker = spawn(process.execPath, [fileURLToPath(import.meta.url), directory, '--worker'], {
    env: {...process.env, LOFI_SERVICE_TEST_HOST: record, LOFI_SERVICE_TEST_MODE: 'progress-request'},
    stdio: ['ignore', 'pipe', 'pipe'],
    timeout: 15000,
  });
  let diagnostics = '', released = false;
  worker.stderr.setEncoding('utf8');
  worker.stderr.on('data', chunk => {
    diagnostics += chunk;
    if (!released && diagnostics.includes('[lofi] blocked phase started\n')) {
      released = true;
      worker.stderr.pause();
      setTimeout(() => worker.stderr.resume(), 100);
      writeFileSync(join(JSON.parse(readFileSync(record, 'utf8')).directory, 'release'), '');
    }
  });
  const status = await new Promise((resolve, reject) => {
    worker.once('error', reject);
    worker.once('close', resolve);
  });
  assert.equal(status, 0, diagnostics);
  assert(released, 'compiler progress must arrive before the host can complete');
  assert(diagnostics.endsWith('x'.repeat(512000) + '\n[lofi] burst completed\n'),
    'completion drains every diagnostic byte, including after stderr backpressure');
  console.log('PASS live stderr during synchronous compiler service requests');
}
