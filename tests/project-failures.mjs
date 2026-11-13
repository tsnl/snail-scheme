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
const build = (target, flags = [], env = {}) => execute(join(root, 'snail'), ['build', ...flags, project, target],
  {env: {...process.env, NO_COLOR: undefined, FORCE_COLOR: '0', ...env}, timeout: 120_000, killSignal: 'SIGKILL'});
const inventory = () => fs.readdirSync(join(project, 'build')).sort();

function jsonFailure(error) {
  assert.equal(error.code, 1);
  assert.equal(error.stdout, '');
  assert.ok(!error.stderr.includes('\x1b'));
  return error.stderr.trim().split('\n').map(line => JSON.parse(line));
}

async function throughTheCommandLine() {
  // The checker finds a linear value's misuse, and the passes after
  // specialization the control effects an implementation may not yield
  // to; those errors reach the user through a build as a type error does.
  write('project.datum', '((build-target main (program (entry "main.sld"))))');
  write('main.sld', '(import (snail core base)) (define (main) (→ Unit) (drop (ann "wrong type" I64)))');
  await assert.rejects(build('main'), /expected I64, found String/);
  // Text has one marker per diagnostic; JSON records preserve the same
  // order and source points and are directly parseable even with forced color.
  write('main.sld', `(import (snail core base))
    (define (first) (→ I64) (missing-first))
    (define (second) (→ I64) (missing-second))`);
  await assert.rejects(build('main'), error => {
    assert.equal(error.code, 1);
    assert.equal(error.stdout, '');
    assert.equal(error.stderr.match(/^ERROR /gm)?.length, 2);
    assert.match(error.stderr, /main\.sld:2:.*missing-first[\s\S]*main\.sld:3:.*missing-second/);
    assert.ok(!error.stderr.includes('\x1b'));
    return true;
  });
  await assert.rejects(build('main', [], {FORCE_COLOR: '1'}), error => {
    assert.equal(error.stderr.match(/\x1b\[31;1mERROR\x1b\[0m /g)?.length, 2);
    return true;
  });
  await assert.rejects(build('main', [], {FORCE_COLOR: '1', NO_COLOR: '1'}), error => {
    assert.match(error.stderr, /^ERROR /);
    assert.ok(!error.stderr.includes('\x1b'));
    return true;
  });
  const checkSourceErrors = error => {
    const errors = jsonFailure(error);
    assert.deepEqual(errors.map(error => error.severity), ['error', 'error']);
    assert.deepEqual(errors.map(error => error.source.file), [join(project, 'main.sld'), join(project, 'main.sld')]);
    assert.deepEqual(errors.map(error => error.source.line), [2, 3]);
    assert.match(errors[0].message, /missing-first/);
    assert.match(errors[1].message, /missing-second/);
    return true;
  };
  for (const flags of [['--error-format=json'], ['--release', '--error-format=json'], ['--error-format=json', '--release']]) {
    await assert.rejects(build('main', flags, {FORCE_COLOR: '1'}), checkSourceErrors);
  }
  for (const stage of ['', 'chez']) {
    await assert.rejects(execute(join(root, 'scripts/snail-tool'), ['wat', '--error-format=json', join(project, 'main.sld')],
      {env: {...process.env, SNAIL_STAGE0: stage, FORCE_COLOR: '1', NO_COLOR: undefined}, timeout: 120_000}), checkSourceErrors);
  }
  await assert.rejects(build('main', ['--error-format=json', '--bad-option']), error => {
    const errors = jsonFailure(error);
    assert.equal(errors.length, 1);
    assert.equal(errors[0].source, null);
    assert.match(errors[0].message, /usage|unknown option/);
    return true;
  });
  await assert.rejects(build('main', ['--error-format=yaml']), error => {
    assert.match(error.stderr, /^ERROR /);
    return true;
  });
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
  await assert.rejects(build('main', ['--error-format=json']), error => {
    const errors = jsonFailure(error);
    assert.equal(errors.length, 1);
    assert.equal(errors[0].source, null);
    assert.match(errors[0].message, /main\.sld: no such file or directory/);
    return true;
  });
  assert.deepEqual(inventory(), [], 'a build of a missing entry makes nothing');

  // A producer reads real input files when the build runs it, and is
  // compiled and run in private compiler scratch, so the project's build
  // directory holds only the target's generation and its link.
  write('project.datum', '((build-target main (program (entry "main.sld") (library-roots (".")))))');
  write('main.sld', '(import (snail core base) (generated flag)) (define (main) (→ Unit) (drop (ann value String)))');
  write('flag.txt', 'valid');
  write('generated/flag.sld', `(generate-library (generated flag)
    (import (snail core base) (snail core io) (snail shell syntax))
    (library-syntax (list "generated" "flag") (list "value") (list (list "snail" "core" "base"))
      (list (form "define" (list (SymbolSyntax "value")
        (form "→" (list (SymbolSyntax "String")))
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
