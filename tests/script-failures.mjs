// A script build that fails reports the error it met and keeps nothing it
// made: the generation it created is discarded, and the output of an
// earlier build stays published, as `snail-scheme build` shows from outside.
//   node tests/script-failures.mjs ROOT
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import fs from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promisify} from 'node:util';

const execute = promisify(execFile), root = process.argv[2];
const project = fs.mkdtempSync(join(tmpdir(), 'snail-failures-workspace-'));
const write = (name, text) => { const path = join(project, name); fs.mkdirSync(join(path, '..'), {recursive: true}); fs.writeFileSync(path, text); };
const build = () => execute(join(root, 'snail-scheme'), ['build', '--target', 'node', 'main.scm'], {cwd: project, timeout: 120_000, killSignal: 'SIGKILL'});
const inventory = () => fs.readdirSync(join(project, 'build')).sort();

async function throughTheCommandLine() {
  // The checker's solver finds a class with no instance; that error
  // reaches the user through a build as a type error does.
  fs.mkdirSync(join(project, 'src'));
  write('main.scm', '(import (snail core base)) (define (main) (→ Unit) (ann "wrong type" I64) (unit))');
  await assert.rejects(build(), /expected I64, found String/);
  for (const name of ['error-instance']) {
    write('main.scm', fs.readFileSync(join(root, `tests/programs/${name}.sld`), 'utf8'));
    const expected = fs.readFileSync(join(root, `tests/programs/${name}.err`), 'utf8').trim();
    await assert.rejects(build(), error => error.stderr.includes(expected));
  }
  assert.deepEqual(inventory(), [], 'a failed build discards the generation it created');
  // A producer reads real input files when the build runs it, and is
  // compiled and run in private compiler scratch, so the workspace's build
  // directory holds only the script's generation and its link.
  write('main.scm', '(import (snail core base) (generated flag)) (define (main) (→ Unit) (ann (value) String) (unit))');
  write('flag.txt', 'valid');
  write('src/generated/flag.sld', `(generate-library (generated flag)
    (import (snail core base) (snail core io) (snail shell syntax))
    (lambda ((fs Fs))
      (library-syntax (list "generated" "flag") (list "value") (list (list "snail" "core" "base"))
        (list (form "define" (list (form "value" (Nil))
          (form "→" (list (SymbolSyntax "String")))
            (if (string=? (read-file fs "${project}/flag.txt") "valid")
              (StringSyntax "ok") (SymbolSyntax "unknown-generated-name"))))))))`);
  await build();
  const published = fs.readlinkSync(join(project, 'build/main'));
  assert.deepEqual(inventory(), [published, 'main']);
  assert.deepEqual(fs.readdirSync(join(project, 'build', published)).sort(),
    ['.snail-target', 'host', 'main.mjs', 'main.wasm', 'package.json'],
    'producer programs use private compiler scratch');
  write('flag.txt', 'invalid');
  await assert.rejects(build(), /unknown-generated-name/);
  assert.deepEqual(inventory(), [published, 'main'], 'a failed build leaves the published generation');
  assert.equal(fs.readlinkSync(join(project, 'build/main')), published);
}

try {
  await throughTheCommandLine();
} finally {
  fs.rmSync(project, {recursive: true, force: true});
}
console.log('script failures passed');
