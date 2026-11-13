// Write the small three-module workloads used by session.sld. The baseline
// spelling differs only where its callable-class syntax requires dyn.
import {mkdir, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import assert from 'node:assert/strict';

const [directory, variant] = process.argv.slice(2);
assert(directory && ['baseline', 'current'].includes(variant));
for (const kind of ['ordinary', 'provider']) {
  const root = join(directory, `${kind}-${variant}`), provider = kind === 'provider';
  await mkdir(join(root, 'sample'), {recursive: true});
  const definitions = Array.from({length: 30}, (_, n) =>
    `(define (helper-${n} (x I64)) (→ I64) (i64-add x ${n}))`).join('\n');
  const callable = variant === 'baseline' ? '(dyn (Fn A → I64))' : '(Fn A → I64)';
  const source = amount => `(define-library (sample helper) (export compute${provider ? ' Value value' : ''})
  (import (snail core forms) (snail core primitive)) (begin
  ${definitions}
  (define (compute (x I64)) (→ I64) (i64-add x ${amount}))
  ${provider ? `(typeclass (Value A) (: value ${callable}))
  (instance (Value I64) (define value (lambda (x) (compute x))))` : ''}))\n`;
  await writeFile(join(root, 'before.sld'), source(1));
  await writeFile(join(root, 'after.sld'), source(2));
  await writeFile(join(root, 'sample/helper.sld'), source(1));
  await writeFile(join(root, 'sample/consumer.sld'), `(define-library (sample consumer) (export answer)
  (import (snail core forms) (snail core primitive) (sample helper))
  (begin (define (answer) (→ I64) (${provider ? 'value (ann 41 I64)' : 'compute 41'}))))\n`);
  await writeFile(join(root, 'main.sld'), `(import (snail core forms) (snail core primitive) (sample consumer))
  (define (main) (→ Unit) (answer) (unit))\n`);
}
