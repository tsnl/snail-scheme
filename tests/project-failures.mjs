// A project build that fails reports the error it met and keeps nothing it
// made: the generations it created are discarded, and the outputs of earlier
// builds stay published, as `snail build` shows from outside.
//   node tests/project-failures.mjs ROOT
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import fs from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promisify} from 'node:util';

const execute = promisify(execFile), root = process.argv[2];
const project = fs.mkdtempSync(join(tmpdir(), 'snail-failures-project-'));
const write = (name, text) => { const path = join(project, name); fs.mkdirSync(join(path, '..'), {recursive: true}); fs.writeFileSync(path, text); };
const build = target => execute(join(root, 'snail'), ['build', project, target], {timeout: 120_000, killSignal: 'SIGKILL'});
const inventory = () => fs.readdirSync(join(project, 'build')).sort();

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
  // An entry that is not there is a diagnostic naming it, as an editor's
  // deletion leaves it, and not a failure of the builder.
  fs.rmSync(join(project, 'main.sld'));
  await assert.rejects(build('main'), error => /main\.sld: no such file or directory/.test(error.stderr)
    && !/os error/.test(error.stderr));
  assert.deepEqual(inventory(), [], 'a build of a missing entry makes nothing');

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

try {
  await throughTheCommandLine();
} finally {
  fs.rmSync(project, {recursive: true, force: true});
}
console.log('project failures passed');
