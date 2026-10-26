// Checking runs the compiler's semantic passes, with only required inputs built.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import fs from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promisify} from 'node:util';
import {createProjectBuilder, projectTools} from '../host/native/project.mjs';

const execute = promisify(execFile), root = process.argv[2];
const project = fs.mkdtempSync(join(tmpdir(), 'lofi-check-project-'));
const working = fs.mkdtempSync(join(tmpdir(), 'lofi-check-compiler-'));
const write = (name, text) => { const path = join(project, name); fs.mkdirSync(join(path, '..'), {recursive: true}); fs.writeFileSync(path, text); };
const command = args => execute(join(root, 'lofi'), args, {timeout: 120_000, killSignal: 'SIGKILL'});
const check = () => command(['check', project]);
const inventory = () => fs.readdirSync(join(project, 'build')).sort();
let builder;

try {
  write('project.datum', '((build-target first (program (entry "main.sld"))) (build-target second (browser (entry "second.sld"))))');
  write('main.sld', `(import (lofi base) (lofi io)) (write-file "${project}/must-not-run" "executed")`);
  write('second.sld', '(import (lofi base)) (unit)');
  assert.deepEqual(await check(), {stdout: '', stderr: ''});
  assert.equal(fs.existsSync(join(project, 'must-not-run')), false);
  assert.equal(fs.existsSync(join(project, 'build')), false, 'root checks allocate no output generations');

  write('second.sld', '(import (lofi base)) (ann "wrong type" I64)');
  await assert.rejects(check(), /expected I64, found String/);
  for (const name of ['error-handler-method', 'error-once-capture']) {
    write('second.sld', fs.readFileSync(join(root, `tests/programs/${name}.sld`), 'utf8'));
    const expected = fs.readFileSync(join(root, `tests/programs/${name}.err`), 'utf8').trim();
    await assert.rejects(check(), error => error.stderr.includes(expected));
  }
  assert.equal(fs.existsSync(join(project, 'build')), false);

  write('project.datum', '((build-target main (program (entry "main.sld") (library-roots (".")))))');
  write('main.sld', '(import (lofi base) (generated flag)) (ann value String)');
  write('flag.txt', 'valid');
  write('generated/flag.sld', `(generate-library (generated flag)
    (import (lofi base) (lofi io) (lofi syntax))
    (library-syntax (list "generated" "flag") (list "value") (list (list "lofi" "base"))
      (list (form ":" (list (SymbolSyntax "value") (SymbolSyntax "String")))
        (form "define" (list (SymbolSyntax "value")
          (if (string=? (read-file "${project}/flag.txt") "valid")
            (StringSyntax "ok") (SymbolSyntax "unknown-generated-name")))))))`);
  await check();
  write('flag.txt', 'invalid');
  await assert.rejects(check(), /unknown-generated-name/);
  assert.equal(fs.existsSync(join(project, 'build')), false, 'producer programs use private compiler scratch');

  // Browser roots precede server: checking them must not satisfy later
  // requests for their actual files from a producer and generated syntax.
  fs.cpSync(join(root, 'tests/artifacts/project'), project, {recursive: true});
  write('client-public/nested/data.bin', Buffer.from([65, 0, 255]));
  write('admin-public/admin.bin', Buffer.from([99]));
  await command(['build', project, 'server']);
  const before = inventory(), published = ['client', 'admin', 'server'].map(name => fs.readlinkSync(join(project, 'build', name)));
  const server = fs.readFileSync(join(project, 'server.sld'), 'utf8');
  assert.deepEqual(await check(), {stdout: '', stderr: ''});
  assert.deepEqual(inventory(), before, 'successful checking discards every dependency generation');

  write('server.sld', `${server}\n(missing-function)`);
  await assert.rejects(check(), /missing-function/);
  assert.deepEqual(inventory(), before, 'a failed root also discards completed dependencies');
  assert.deepEqual(['client', 'admin', 'server'].map(name => fs.readlinkSync(join(project, 'build', name))), published);

  builder = await createProjectBuilder({root, project, tools: projectTools(root), directory: working});
  const remove = fs.rmSync;
  let attempts = 0;
  fs.rmSync = function(path, options) {
    if (options?.recursive && String(path).startsWith(join(project, 'build/.lofi-'))) {
      attempts++;
      throw new Error('injected generation cleanup failure');
    }
    return remove(path, options);
  };
  syncBuiltinESMExports();
  try {
    assert.throws(() => builder.check(builder.describe()), /missing-function/);
    write('server.sld', server);
    assert.throws(() => builder.check(builder.describe()), /injected generation cleanup failure/);
  }
  finally { fs.rmSync = remove; syncBuiltinESMExports(); }
  assert.equal(attempts, 4, 'cleanup attempts every dependency, preserving an earlier source failure');
  for (const name of inventory()) if (!before.includes(name)) fs.rmSync(join(project, 'build', name), {recursive: true});

  write('server.sld', server);
  write('client.sld', '(import (lofi base) (lofi artifact)) (artifact-bundle "admin")');
  write('admin.sld', '(import (lofi base) (lofi artifact)) (artifact-bundle "client")');
  await assert.rejects(check(), /client -> admin -> client/);
  assert.deepEqual(inventory(), before, 'cycles through a checked root remove failed generations');
  write('client.sld', '(import (lofi base) (lofi artifact)) (artifact-bundle "client")');
  await assert.rejects(check(), /client -> client/);
  assert.deepEqual(inventory(), before);
} finally {
  builder?.close();
  fs.rmSync(project, {recursive: true, force: true});
  fs.rmSync(working, {recursive: true, force: true});
}
console.log('project check: all roots, specialization, ownership, real inputs, cycles and cleanup');
