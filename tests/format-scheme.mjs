// CLI regressions for the shared Snail formatter. The main suite supplies a
// freshly compiled program command; with only ROOT, exercise the shell launcher.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, readFileSync, rmSync, statSync, utimesSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';

const [root, ...supplied] = process.argv.slice(2);
const command = supplied.length ? supplied : [join(resolve(root), 'scripts/format-scheme')];
function run(args = [], input = '', cwd = root) {
  const result = spawnSync(command[0], [...command.slice(1), ...args], {
    input, cwd, encoding: 'utf8', timeout: 120_000, maxBuffer: 16 * 1024 * 1024,
  });
  assert.ifError(result.error);
  return result;
}
function format(source, width = 100) {
  const result = run(['--width', String(width)], source);
  assert.equal(result.status, 0, result.stderr);
  return result.stdout;
}
function example(source, expected, width = 100) {
  assert.equal(format(source, width), expected);
  assert.equal(format(expected, width), expected, 'formatting is idempotent');
}

// ---- Source and wrapping ----

example(`(import (scheme base) (rename (rnrs) (define-record-type record)))
(define-record-type <pair>
  (pair a b) pair? (a pair-a) (b pair-b))
(struct (Pair A) ((first A) (second A)))
(enum Shape (Circle ((radius I64))) (Dot))
`, `(import
 (scheme base)
 (rename (rnrs) (define-record-type record)))
(define-record-type <pair>
  (pair a b) pair?
  (a pair-a)
  (b pair-b))
(struct (Pair A)
  ((first A)
   (second A)))
(enum Shape (Circle ((radius I64))) (Dot))
`);
const literals = String.raw`;; (import (ignored) (ignored))
#| outer (import (ignored) (ignored)) #| nested |# |#
#;(import (ignored) (ignored))
(define chars '(#\( #\) #\; #\"))
(define |name(import (a) (b))| 1)
(define text "first
  (import (ignored) (ignored))
last")
`;
example(literals, literals);
const comments = String.raw`#; #;(import (ignored) (ignored)) '(struct X ((a I64)))
#;#u8(1 2 3) #;#((import (ignored) (ignored)))
#; (list #\) "a ) ( string" |a\| ) symbol|
    #| nested #| ( |# comment |# #;ignored
    (import (ignored) (ignored)))
(import (a) (b))
`;
example(comments, comments.replace('(import (a) (b))', '(import\n (a)\n (b))'));
const quotedName = '(define |two\n  lines(import (a) (b))| 1)\n';
example(quotedName, quotedName);
example(`(import (a) ; Keep this trailing comment.
        #| Keep this block comment. |# (b))
`, `(import
 (a) ; Keep this trailing comment.
 #| Keep this block comment. |#
 (b))
`);
example('(import (a) (b)\n', '(import\n (a)\n (b)\n');

example(`(define (f x) (let* ((a (foo x)) (b (bar a)) (c (baz b))) (+ a b c)))
(define (make-thing alpha beta gamma delta) (list alpha beta))
`, `(define (f x)
  (let* ((a (foo x))
         (b (bar a))
         (c (baz b)))
    (+ a b c)))
(define (make-thing alpha
                    beta
                    gamma
                    delta)
  (list alpha beta))
`, 40);
example(`(string-append "first part" (symbol->string name) "last part")
(error "a message that is long enough to matter")
(match option ((Some value) (display (string-append "found " value))) ((None) (display "nothing")))
`, `(string-append "first part"
               (symbol->string name)
               "last part")
(error
 "a message that is long enough to matter")
(match option
  ((Some value)
   (display
    (string-append "found " value)))
  ((None) (display "nothing")))
`, 40);
example(`(foo alpha beta gamma delta epsilon) ; fits: the comment does not count
(foo alpha beta gamma delta epsilon zeta) ; stays on the last line
(define message "a string much longer than forty columns cannot break")
`, `(foo alpha beta gamma delta epsilon) ; fits: the comment does not count
(foo alpha
     beta
     gamma
     delta
     epsilon
     zeta) ; stays on the last line
(define message
  "a string much longer than forty columns cannot break")
`, 40);
example(`(: run (impl (Fn Config (List String) -> Status ! fs console)))
(bytes #u8(1 2 3 4 5 6 7 8 9 10 11 12 13 14))
(display "one") (display "two") (display "three")
`, `(: run
   (impl (Fn Config
             (List String)
             ->
             Status
             ! fs console)))
(bytes
 #u8(1 2 3 4 5 6 7 8 9 10 11 12 13 14))
(display "one")
(display "two")
(display "three")
`, 40);

// A spelling convention, not a list of known macros. Near misses stay calls.
for (const name of ['let', 'let*', 'result-let*', 'custom-let', 'custom-let*',
                    'and-let*', 'def-let', 'def-let*', '-let', '-let*']) {
  example(`(${name} ((a (Ok 1)))\n(Ok a))\n`, `(${name} ((a (Ok 1)))\n  (Ok a))\n`);
  const indent = ' '.repeat(name.length + 3);
  example(`(${name} ((a (foo x)) (b (bar a)) (c (baz b))) (+ a b c) (Ok c))\n`,
    `(${name} ((a (foo x))\n${indent}(b (bar a))\n${indent}(c (baz b)))\n  (+ a b c)\n  (Ok c))\n`, 40);
}
for (const name of ['let', 'retry-let']) {
  const indent = ' '.repeat(name.length + 8);
  example(`(${name} loop ((a (foo x)) (b (bar a)) (c (baz b))) (+ a b c))\n`,
    `(${name} loop ((a (foo x))\n${indent}(b (bar a))\n${indent}(c (baz b)))\n  (+ a b c))\n`, 40);
}
for (const name of ['outlet', 'letdown', 'custom-let-values', 'custom-let*later']) {
  example(`(${name} x\ny)\n`, `(${name} x\n${' '.repeat(name.length + 2)}y)\n`);
}
const fits = `(list "${'x'.repeat(89)}" b)\n`;
const long = `(list "${'x'.repeat(90)}" b)\n`;
assert.equal(run([], fits).stdout, fits);
assert.equal(run([], long).stdout, `(list "${'x'.repeat(90)}"\n      b)\n`);
for (const text of ['', '(display "λ 🐌")', '(display "λ 🐌")\n']) example(text, text);

// ---- Files, diagnostics and status ----

const directory = mkdtempSync(join(tmpdir(), 'snail-format-'));
try {
  const names = ['first file.sld', 'second.sld', 'unchanged.sld'];
  const paths = names.map(name => join(directory, name));
  const source = '(import (a) (b))\n';
  const expected = '(import\n (a)\n (b))\n';
  paths.forEach((path, index) => writeFileSync(path, index === 2 ? expected : source));
  paths.forEach(path => utimesSync(path, 1, 1));
  const checked = run(['--check', ...names], '', directory);
  assert.equal(checked.status, 1);
  assert.equal(checked.stdout, '');
  for (const name of names.slice(0, 2)) assert.ok(checked.stderr.includes(`${name}: needs formatting`));
  assert.ok(!checked.stderr.includes(names[2]));
  for (const path of paths) assert.equal(statSync(path).mtimeMs, 1000, 'checking never writes');
  assert.equal(readFileSync(paths[0], 'utf8'), source);
  const written = run(['--write', ...names], '', directory);
  assert.equal(written.status, 0, written.stderr);
  assert.equal(written.stdout, '');
  for (const path of paths) assert.equal(readFileSync(path, 'utf8'), expected);
  assert.equal(statSync(paths[2]).mtimeMs, 1000, 'unchanged files are not rewritten');
  const clean = run(['--check', ...paths]);
  assert.equal(clean.status, 0, clean.stderr);
  assert.equal(clean.stdout, '');
  assert.equal(clean.stderr, '');
  const times = paths.map(path => statSync(path).mtimeMs);
  assert.equal(run(['--write', ...paths]).status, 0);
  assert.deepEqual(paths.map(path => statSync(path).mtimeMs), times);
  assert.notEqual(run(['--check', join(directory, 'missing.sld')]).status, 0);
} finally {
  rmSync(directory, {recursive: true, force: true});
}
for (const args of [['--check'], ['--write'], ['--unknown'], ['--width'],
                   ...['0', '-1', 'x', '40x', '9223372036854775808'].map(n => ['--width', n])]) {
  const bad = run(args);
  assert.notEqual(bad.status, 0, `reject ${args.join(' ')}`);
  assert.equal(bad.stdout, '');
  assert.notEqual(bad.stderr, '');
}

// The tool used by make check leaves every tracked Scheme source unchanged.
const files = spawnSync('git', ['ls-files', '-z', '*.scm', '*.sld'], {cwd: root, encoding: 'utf8'});
assert.equal(files.status, 0, files.stderr);
const tracked = files.stdout.split('\0').filter(Boolean).map(file => resolve(root, file));
const checked = run(['--check', ...tracked]);
assert.equal(checked.status, 0, checked.stderr);
assert.equal(checked.stdout, '');
console.log('formatter: source, binding conventions, wrapping, stdin, files, diagnostics and tracked sources');
