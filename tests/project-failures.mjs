// A project build that fails reports the error it met and keeps nothing it
// made: the generations it created are discarded, even when that cleanup
// fails too, and the outputs of earlier builds stay published. `snail build`
// shows all but the failing cleanup from outside.
//   node tests/project-failures.mjs ROOT
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import fs from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promisify} from 'node:util';
import {createProjectBuilder, projectTools} from '../host/native/project.mjs';

const execute = promisify(execFile), root = process.argv[2];
const project = fs.mkdtempSync(join(tmpdir(), 'snail-failures-project-'));
const working = fs.mkdtempSync(join(tmpdir(), 'snail-failures-compiler-'));
const write = (name, text) => { const path = join(project, name); fs.mkdirSync(join(path, '..'), {recursive: true}); fs.writeFileSync(path, text); };
const build = target => execute(join(root, 'snail'), ['build', project, target], {timeout: 120_000, killSignal: 'SIGKILL'});
const inventory = () => fs.readdirSync(join(project, 'build')).sort();

// ---- Through the command line ----

async function throughTheCommandLine() {
  // The checker finds a linear value's misuse, and the passes after
  // specialization the control effects an implementation may not yield
  // to; those errors reach the user through a build as a type error does.
  write('project.datum', '((build-target main (program (entry "main.sld"))))');
  write('main.sld', '(import (snail core base)) (ann "wrong type" I64)');
  await assert.rejects(build('main'), /expected I64, found String/);
  for (const name of ['error-control-implementation', 'error-once-capture']) {
    write('main.sld', fs.readFileSync(join(root, `tests/programs/${name}.sld`), 'utf8'));
    const expected = fs.readFileSync(join(root, `tests/programs/${name}.err`), 'utf8').trim();
    await assert.rejects(build('main'), error => error.stderr.includes(expected));
  }
  assert.deepEqual(inventory(), [], 'a failed build discards the generation it created');

  // A producer reads real input files when the build runs it, and is
  // compiled and run in private compiler scratch, so the project's build
  // directory holds only the target's generation and its link.
  write('project.datum', '((build-target main (program (entry "main.sld") (library-roots (".")))))');
  write('main.sld', '(import (snail core base) (generated flag)) (ann value String)');
  write('flag.txt', 'valid');
  write('generated/flag.sld', `(generate-library (generated flag)
    (import (snail core base) (snail core io) (snail shell syntax))
    (library-syntax (list "generated" "flag") (list "value") (list (list "snail" "core" "base"))
      (list (form ":" (list (SymbolSyntax "value") (SymbolSyntax "String")))
        (form "define" (list (SymbolSyntax "value")
          (if (string=? (read-file "${project}/flag.txt") "valid")
            (StringSyntax "ok") (SymbolSyntax "unknown-generated-name")))))))`);
  await build('main');
  const published = fs.readlinkSync(join(project, 'build/main'));
  assert.deepEqual(inventory(), [published, 'main']);
  assert.deepEqual(fs.readdirSync(join(project, 'build', published)).sort(), ['.snail-target', 'program.wasm'],
    'producer programs use private compiler scratch');
  write('flag.txt', 'invalid');
  await assert.rejects(build('main'), /unknown-generated-name/);
  assert.deepEqual(inventory(), [published, 'main'], 'a failed build leaves the published generation');
  assert.equal(fs.readlinkSync(join(project, 'build/main')), published);
}

// ---- In process until step 7 ----

// Cleanup that fails still attempts every generation the build created, and
// the error the build met is the one reported. Only a patch in this process
// can make the builder's removals fail; step 7 replaces this builder with the
// resident compiler's build library, which takes the case with it.
async function inProcess() {
  fs.cpSync(join(root, 'tests/artifacts/project'), project, {recursive: true});
  write('client-public/nested/data.bin', Buffer.from([65, 0, 255]));
  write('admin-public/admin.bin', Buffer.from([99]));
  const server = fs.readFileSync(join(project, 'server.sld'), 'utf8');
  const builder = await createProjectBuilder({root, project, tools: projectTools(root), directory: working});
  const remove = fs.rmSync;
  let attempts = 0;
  fs.rmSync = function(path, options) {
    if (options?.recursive && String(path).startsWith(join(project, 'build/.snail-'))) {
      attempts++;
      throw new Error('injected generation cleanup failure');
    }
    return remove(path, options);
  };
  syncBuiltinESMExports();
  try {
    // Three: client and admin, which server embeds, and server's own,
    // created before its compile met the type error.
    write('server.sld', `${server}\n(ann "wrong type" I64)`);
    assert.throws(() => builder.build(builder.describe(), ['server']), /expected I64, found String/);
    assert.equal(attempts, 3, 'cleanup attempts every generation, preserving the source failure');
    // One more: planning meets the unbound name as soon as the producer has
    // run, so only client, which the producer embeds, was built. Admin,
    // which its output embeds, and server never were.
    write('server.sld', `${server}\n(missing-function)`);
    assert.throws(() => builder.build(builder.describe(), ['server']), /missing-function/);
    assert.equal(attempts, 4, 'an expansion error builds only what planning waited on');
  } finally {
    fs.rmSync = remove; syncBuiltinESMExports();
    builder.close();
  }
}

try {
  await throughTheCommandLine();
  await inProcess();
} finally {
  fs.rmSync(project, {recursive: true, force: true});
  fs.rmSync(working, {recursive: true, force: true});
}
console.log('project failures passed');
