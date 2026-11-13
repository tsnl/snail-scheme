// A blocking stage-zero file lock must not prevent another Chez thread from
// collecting and releasing that lock. Run in a child with an external deadline:
// the broken foreign-call convention also blocks a Scheme watchdog's collection.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promisify} from 'node:util';

const root = process.argv[2], directory = await mkdtemp(join(tmpdir(), 'snail-chez-lock-'));
try {
  const source = join(directory, 'lock.scm');
  await writeFile(source, `(import (chezscheme))
(library-directories (cons (string-append (cadr (command-line)) "/host/chez") (library-directories)))
(import (snail stage0 system))
(define path (caddr (command-line)))
(define holder (open-replacing-output-file path))
(define waiter (open-replacing-output-file path))
(define mutex (make-mutex))
(define changed (make-condition))
(define started? #f)
(define done? #f)
(file-lock holder lock/exclusive)
(fork-thread
  (lambda ()
    (with-mutex mutex (set! started? #t) (condition-signal changed))
    (file-lock waiter lock/exclusive)
    (file-lock waiter lock/unlock)
    (with-mutex mutex (set! done? #t) (condition-signal changed))))
(with-mutex mutex
  (let wait () (unless started? (condition-wait changed mutex) (wait))))
;; Let the waiter enter flock before asking every active thread to collect.
(sleep (make-time 'time-duration 50000000 0))
(collect-rendezvous)
(file-lock holder lock/unlock)
(with-mutex mutex
  (let wait () (unless done? (condition-wait changed mutex) (wait))))
(close-port waiter)
(close-port holder)
(display "collected while waiting\\n")
`);
  const {stdout} = await promisify(execFile)(process.env.CHEZ ?? 'scheme',
    ['--script', source, root, join(directory, 'lock')], {timeout: 15_000});
  assert.equal(stdout, 'collected while waiting\n');
} finally {
  await rm(directory, {recursive: true, force: true});
}
