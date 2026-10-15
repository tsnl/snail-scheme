"""Preserve Matrix's modular search, continuation order, and shared list tails."""

import hashlib
import itertools
import json
import difflib
import copy
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time

from data_ports import form


# ---- Each preparation process owns a bounded process group ----

def group_members(group):
    members = []
    for path in Path('/proc').glob('[0-9]*/stat'):
        try:
            fields = path.read_text().rsplit(')', 1)[1].split()
            if int(fields[2]) == group and fields[0] not in ('Z', 'X'):
                members.append(int(path.parent.name))
        except (OSError, ValueError, IndexError):
            pass
    return members


def clean_group(group):
    deadline = time.monotonic() + 5
    while True:
        try:
            os.killpg(group, signal.SIGKILL)
        except ProcessLookupError:
            pass
        members = group_members(group)
        if not members or time.monotonic() >= deadline:
            return members
        time.sleep(0.02)


def execute(command, cwd, environment, timeout=1200, stdin=None):
    started, command = time.perf_counter(), list(map(str, command))
    try:
        child = subprocess.Popen(command, cwd=cwd, env=environment, text=True,
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, start_new_session=True)
    except OSError as error:
        return dict(command=command, error=str(error), process_seconds=time.perf_counter() - started)
    return finish_process(child, command, started, timeout, stdin)


def finish_process(child, command, started, timeout, stdin):
    expired, stdout, stderr = False, '', ''
    try:
        stdout, stderr = child.communicate(stdin, timeout=timeout)
    except subprocess.TimeoutExpired:
        expired = True
        clean_group(child.pid)
        stdout, stderr = child.communicate(timeout=10)
    finally:
        remaining = clean_group(child.pid)
    return dict(command=command, returncode=child.returncode, stdout=stdout, stderr=stderr,
                timeout=expired, process_group=child.pid, executing_descendants=remaining,
                process_seconds=time.perf_counter() - started)


# ---- Explicit alternatives for the source's mixed pairs and messages ----

STRICT_TYPES = '''(define-overload - (-> I64 I64) (lambda (value) (i64-sub 0 value)))
(define-data (Permutation T)
  (no-permutation)
  (permutation (dispatch (-> I64 (PermutationReply T)) permutation-dispatch)))
(define-data (PermutationReply T)
  (current-object (value T current-value))
  (next-permutation (value (Permutation T) next-value))
  (remaining-objects (value (List T) remaining-values)))
(define-data (GcdResult T)
  (gcd-value (value T gcd-result-value))
  (gcd-negative (sign I64 gcd-sign) (magnitude I64 gcd-magnitude)))
(define-data PrimeList
  (no-primes)
  (prime-node (value I64 prime-value) (tail (Ref PrimeList) prime-tail)))
(define-data Answer
  (matrix-answer (value (List (List I64)) answer-matrix))
  (marker-answer (value String answer-marker)))
(define-data Best
  (best (size I64 best-size) (count I64 best-count) (answers (List Answer) best-answers)))
(: permutation? (All (T) (-> (Permutation T) Bool)))
(define (permutation? value)
  (match value ((no-permutation) #f) ((permutation dispatch) #t)))
(define (prime-null? value)
  (match value ((no-primes) #t) ((prime-node head tail) #f)))
(define (matrix-answer? value)
  (match value ((matrix-answer matrix) #t) ((marker-answer text) #f)))
'''
CHEZ_TYPES = '''(define-syntax : (syntax-rules () ((_ . signature) (begin))))
(define-syntax ann (syntax-rules () ((_ value type) value)))
(define (ref value) (vector value))
(define (ref-get value) (vector-ref value 0))
(define (ref-set! cell value) (vector-set! cell 0 value))
(define ref-eq? eq?)
(define (unit) (if #f #f))
(define (unreachable) (error 'matrix "invalid typed Matrix value"))
(define (no-permutation) #f)
(define (permutation dispatch) dispatch)
(define permutation-dispatch values)
(define permutation? procedure?)
(define (current-object value) (vector 0 value))
(define (next-permutation value) (vector 1 value))
(define (remaining-objects value) (vector 2 value))
(define (current-value value) (vector-ref value 1))
(define next-value current-value)
(define remaining-values current-value)
(define (gcd-value value) (vector 0 value))
(define gcd-result-value current-value)
(define (gcd-negative sign magnitude) (vector 1 sign magnitude))
(define (gcd-sign value) (vector-ref value 1))
(define (gcd-magnitude value) (vector-ref value 2))
(define (no-primes) '())
(define (prime-node value tail) (cons value tail))
(define prime-value car)
(define prime-tail cdr)
(define prime-null? null?)
(define (matrix-answer value) (vector 0 value))
(define (marker-answer value) (vector 1 value))
(define answer-matrix current-value)
(define answer-marker current-value)
(define (matrix-answer? value) (= (vector-ref value 0) 0))
(define (best size count answers) (vector size count answers))
(define (best-size value) (vector-ref value 0))
(define (best-count value) (vector-ref value 1))
(define (best-answers value) (vector-ref value 2))
'''
CONTROL = '''(define-syntax case
  (syntax-rules (else)
    ((_ key) (unreachable))
    ((_ key (else body ...)) (begin body ...))
    ((_ key ((datum ...) body ...) rest ...)
     (let ((value key))
       (if (or (= value datum) ...) (begin body ...) (case value rest ...))))))
(define-syntax map
  (syntax-rules ()
    ((_ procedure values) (map-one procedure values))
    ((_ procedure first second) (map-two procedure first second))))
'''
COMMON = ''';; These lists are persistent. Only the prime-list tail and last box
;; are mutable; the predicate closure continues to see the original head.
(define (caar values) (car (car values)))
(: list (All (T) (-> (Rest T) (List T))))
(define (list . values) values)
(: reverse (All (T) (-> (List T) (List T))))
(define (reverse values)
  (let loop ((tail values) (result '()))
    (if (null? tail) result (loop (cdr tail) (cons (car tail) result)))))
(: map-one (All (A B) (-> (-> A B) (List A) (List B))))
(define (map-one procedure values)
  (if (null? values) '()
      (let ((head (procedure (car values))))
        (cons head (map-one procedure (cdr values))))))
(: map-two (All (A B C) (-> (-> A B C) (List A) (List B) (List C))))
(define (map-two procedure first second)
  (if (null? first) '()
      (let ((head (procedure (car first) (car second))))
        (cons head (map-two procedure (cdr first) (cdr second))))))
(: exact-integer? (-> I64 Bool))
(define (exact-integer? value) #t)
(define (zero? value) (= value 0))
(define (even? value) (= (remainder value 2) 0))
(: expt (-> I64 I64 I64))
(define (expt base exponent)
  (if (< exponent 0) (unreachable)
      (let loop ((left exponent) (value 1))
        (if (= left 0) value (loop (- left 1) (* value base))))))
(: perm-now (All (T) (-> (Permutation T) T)))
(define (perm-now value) (current-value ((permutation-dispatch value) 0)))
(: perm-brother (All (T) (-> (Permutation T) (Permutation T))))
(define (perm-brother value) (next-value ((permutation-dispatch value) 1)))
(: perm-child (All (T) (-> (Permutation T) (Permutation T))))
(define (perm-child value) (next-value ((permutation-dispatch value) 2)))
(: perm-puke (All (T) (-> (Permutation T) (List T))))
(define (perm-puke value) (remaining-values ((permutation-dispatch value) 3)))
(define (prime-cons head tail) (prime-node head (ref tail)))
(define (prime-cdr value) (ref-get (prime-tail value)))
(define (prime-set-cdr! value tail) (ref-set! (prime-tail value) tail))
(: same-row? (-> (List I64) (List I64) Bool))
(define (same-row? left right)
  (if (null? left) (null? right)
      (and (not (null? right)) (= (car left) (car right))
           (same-row? (cdr left) (cdr right)))))
(: same-matrix? (-> (List (List I64)) (List (List I64)) Bool))
(define (same-matrix? left right)
  (if (null? left) (null? right)
      (and (not (null? right)) (same-row? (car left) (car right))
           (same-matrix? (cdr left) (cdr right)))))
(define (same-answer? left right)
  (if (matrix-answer? left)
      (and (matrix-answer? right) (same-matrix? (answer-matrix left) (answer-matrix right)))
      (and (not (matrix-answer? right)) (string=? (answer-marker left) (answer-marker right)))))
(define (same-answers? left right)
  (if (null? left) (null? right)
      (and (not (null? right)) (same-answer? (car left) (car right))
           (same-answers? (cdr left) (cdr right)))))
'''
DIAGNOSTICS = '''(define-extern write-character "benchmark" "write_character" (-> Char Unit))
(define (matrix-write-text text)
  (let loop ((index 0))
    (unless (= index (string-length text))
      (write-character (string-ref text index)) (loop (+ index 1)))))
(define (matrix-write-natural value)
  (unless (< value 10) (matrix-write-natural (quotient value 10)))
  (write-character (integer->char (+ 48 (remainder value 10)))))
(define (permutation-error code)
  (matrix-write-text "gen-perms: Bad msg: ~a; message code ")
  (if (< code 0)
      (begin (write-character #\\-) (matrix-write-natural (- code)))
      (matrix-write-natural code))
  (write-character #\\newline)
  (unreachable))
'''


# ---- Contracts constrain numbers without changing the algorithm ----

ROW = '(List I64)'
MATRIX = f'(List {ROW})'
FIELD = 'I64 I64 (-> I64 Bool) (-> I64 I64 I64) (-> I64 I64) (-> I64 I64 I64) (-> I64 I64)'
CONTRACTS = f'''(: div (-> I64 I64 I64))
(: mod (-> I64 I64 I64))
(: maximal? (-> {MATRIX} Bool))
(: zunda (-> (Permutation {ROW}) {MATRIX} Bool))
(: zebra (-> (Permutation {ROW}) (-> {ROW} (-> I64 I64))
               (-> {ROW} (-> I64 I64)) {MATRIX} I64 Bool))
(: zulu (-> {ROW} (-> I64 I64) {MATRIX} (-> {MATRIX} Bool) Bool))
(: all? (All (T) (-> (-> T Bool) (List T) Bool)))
(: gen-perms (All (T) (-> (List T) (Permutation T))))
(: fold (All (A S) (-> (List A) (-> A S S) S S)))
(: miota (-> I64 {ROW}))
(: proc->vector (-> I64 (-> I64 I64) (Vector I64)))
(: make-modular (All (T) (-> I64 (-> (-> {FIELD} T) T))))
(: extended-gcd (All (T) (-> I64 I64 (-> I64 I64 I64 T) (GcdResult T))))
(: make-row-reduce (-> {FIELD} (-> {MATRIX} {MATRIX})))
(: make-in-row-space? (-> {FIELD} (-> {MATRIX} (-> {ROW} Bool))))
(: make-modular-row-reduce (-> I64 (-> {MATRIX} {MATRIX})))
(: make-modular-in-row-space? (-> I64 (-> {MATRIX} (-> {ROW} Bool))))
(: find-prime (-> I64 I64))
(: det-upper-bound (-> I64 I64))
(: go (All (S) (-> I64 I64 (-> {MATRIX} S S) S S)))
(: go-folder (-> {MATRIX} Best Best))
(: really-go (-> I64 I64 (List Answer)))
(: remove-in-order (All (T) (-> (-> T Bool) (List T) (List T))))
(: fold-over-rows (All (S) (-> I64 (-> {ROW} S S) S S)))
(: fold-over-subs-of-size (All (T S) (-> (List T) I64 (-> (List T) S S) S S)))
'''


# ---- Counted reversible edits preserve the complete source kernel ----

def adaptation(source):
    ledger = []

    def edit(before, after, count=1, reason='concrete representation'):
        nonlocal source
        if source.count(before) != count:
            raise ValueError(f'expected {count} occurrences of {before!r}, got {source.count(before)}')
        ledger.append(dict(before=before, after=after, count=count, reason=reason))
        source = source.replace(before, after)

    edit("(define (chez-box x) (cons x '()))", '(define (chez-box x) (ref x))')
    edit('(define (chez-unbox x) (car x))', '(define (chez-unbox x) (ref-get x))')
    edit('(define (chez-set-box! x y) (set-car! x y))', '(define (chez-set-box! x y) (ref-set! x y))')
    edit('(if first-row-perm', '(if (permutation? first-row-perm)')
    for name, count in (('row-perm', 1), ('new-row-perm', 1)):
        edit(f'(not {name})', f'(not (permutation? {name}))', count)
    for variable, message, count in (('first-row-perm', 'brother', 1), ('first-row-perm', 'now', 1),
                                     ('first-row-perm', 'child', 1), ('row-perm', 'now', 2),
                                     ('row-perm', 'child', 2), ('row-perm', 'brother', 1)):
        edit(f"({variable} '{message})", f'(perm-{message} {variable})', count)
    permutation = form(source, '(define gen-perms')
    changed = permutation.replace('#f', '(no-permutation)').replace('(lambda (msg)', '(permutation (lambda (msg)')
    changed = changed.replace('((now)\n               (car zulu-future))', '((0)\n               (current-object (car zulu-future)))')
    changed = changed.replace('((brother)\n               (_-*-', '((1)\n               (next-permutation (_-*-')
    changed = changed.replace('past)))', 'past))))')
    changed = changed.replace('((child)\n               (gen-perms', '((2)\n               (next-permutation (gen-perms')
    changed = changed.replace('(fold past cons (cdr zulu-future))))', '(fold past cons (cdr zulu-future)))))', 1)
    changed = changed.replace('((puke)\n               (cons', '((3)\n               (remaining-objects (cons')
    changed = changed.replace('(fold past cons (cdr zulu-future))))\n              (else', '(fold past cons (cdr zulu-future)))))\n              (else')
    changed = changed.replace('(error \'gen-perms "Bad msg: ~a" msg)', '(permutation-error msg)') + ')'
    edit(permutation, changed, reason='retain lazy message closure; explicitly tag each reply and the absent cursor')
    edit('((= i number-of-cols))', '((= i number-of-cols) (unit))', reason='omitted do result is Unit')
    edit('((= i size))', '((= i size) (unit))', reason='omitted do result is Unit')
    edit('(cons -1 (- x))', '(gcd-negative -1 (- x))', reason='preserve original negative-input improper pair and skipped continuation')
    edit('(cont p p-a p-b)', '(gcd-value (cont p p-a p-b))')
    gcd = form(source, '(define extended-gcd')
    expanded = gcd.replace('(define extended-gcd', '(define (extended-gcd a b cont)')
    expanded = expanded.replace('    (lambda (a b cont)\n      (n->sgn/abs a', '    (n->sgn/abs a')[:-1]
    edit(gcd, expanded, reason='eta-expand the pure outer binding to satisfy the polymorphic value restriction')
    edit('(extended-gcd (+ i 1)\n                                                 modulus\n                                                 (lambda (gcd inverse ignore)\n                                                   inverse))',
         '(gcd-result-value (extended-gcd (+ i 1)\n                                                 modulus\n                                                 (lambda (gcd inverse ignore)\n                                                   inverse)))')
    prime = form(source, '(define find-prime')
    changed = prime.replace('(list 2)', '(prime-cons 2 (no-primes))').replace('(list trial)', '(prime-cons trial (no-primes))')
    for before, after in (('null?', 'prime-null?'), ('car', 'prime-value'), ('cdr', 'prime-cdr'), ('set-cdr!', 'prime-set-cdr!')):
        changed = re.sub(r'\(' + re.escape(before) + r'(?=\s)', '(' + after, changed)
    edit(prime, changed, reason='mutable prime spine retains original head and last-node aliases')
    edit('(car bsize.blen.blist)', '(best-size bsize.blen.blist)')
    edit('(cadr bsize.blen.blist)', '(best-count bsize.blen.blist)')
    edit('(cddr bsize.blen.blist)', '(best-answers bsize.blen.blist)')
    edit('(cons bsize\n                        (cons blen', '(best bsize\n                        blen')
    edit('(cons mat blist)', '(cons (matrix-answer mat) blist)')
    edit('(cons "..." blist)', '(cons (marker-answer "...") blist)')
    edit('                                     blist)))))', '                                     blist))))')
    edit('(list size 1 mat)', '(best size 1 (list (matrix-answer mat)))')
    edit('(cddr\n     (go number-of-cols', '(best-answers\n     (go number-of-cols')
    edit('(list -1 -1)', "(best -1 -1 '())")
    return source, ledger


def kernel(source):
    return CONTRACTS + adaptation(source)[0]


# ---- Complete expected values are read before the original worker ----

INPUTS = '''(define-extern native-expected-i64 "benchmark" "expected_i64" (-> I64 I64))
(define expected-cursor (ref 0))
(define (read-expected-integer)
  (let ((value (native-expected-i64 (ref-get expected-cursor))))
    (ref-set! expected-cursor (+ 1 (ref-get expected-cursor))) value))
(define (read-expected-row count)
  (if (= count 0) '()
      (let ((head (read-expected-integer))) (cons head (read-expected-row (- count 1))))))
(define (read-expected-matrix count)
  (if (= count 0) '()
      (let ((head (read-expected-row (read-expected-integer))))
        (cons head (read-expected-matrix (- count 1))))))
(define (read-expected-answers count)
  (if (= count 0) '()
      (let ((head (if (= (read-expected-integer) 0)
                      (matrix-answer (read-expected-matrix (read-expected-integer)))
                      (marker-answer (read-expected-string (read-expected-integer))))))
        (cons head (read-expected-answers (- count 1))))))
(define (read-expected-string count)
  (let ((value (make-string count)))
    (let loop ((index 0))
      (if (= index count) value
          (begin (string-set! value index (integer->char (read-expected-integer)))
                 (loop (+ index 1)))))))
(define input0 (native-input-i64 (ann 0 I32)))
(define input1 (native-input-i64 (ann 1 I32)))
(define expected-false? (= (native-input-i64 (ann 2 I32)) 1))
(define expected (read-expected-answers (read-expected-integer)))
'''
WORKER = '''(if (<= count 0) (if expected-false? 1 0)
  (let loop ((i 1) (result (really-go (hide count input0) (hide count input1))))
    (if (< i count)
        (loop (+ i 1) (really-go (hide count input0) (hide count input1)))
        (if (and (not expected-false?) (same-answers? result expected)) 1 0))))'''
CHEZ_BOUNDARY = '''(define (matrix-read-answers value)
  (and value (map-one (lambda (answer)
                       (if (string? answer) (marker-answer answer) (matrix-answer answer))) value)))
(define (matrix-same-result? value expected)
  (if value (and expected (same-answers? value expected)) (not expected)))
(define (permutation-error code)
  (display "gen-perms: Bad msg: ~a; message code ") (display code) (newline)
  (flush-output-port (current-output-port))
  (unreachable))
'''


def encode_answers(answers):
    if answers is False:
        return [0]
    encoded = [len(answers)]
    for answer in answers:
        if isinstance(answer, str):
            encoded.extend([1, len(answer), *map(ord, answer)])
        else:
            encoded.extend([0, len(answer)])
            for row in answer:
                encoded.extend([len(row), *row])
    return encoded


def specification(data):
    from measure import input_values
    count, columns, size, answers = input_values(data.decode())
    return dict(name='matrix', count=count, inputs=[columns, size, 0],
                expected=encode_answers(answers), original_expected=answers,
                result_kind='i64-list-values', barriers_per_iteration=2)


def adapt_chez_harness(source, reverse=False):
    replacements = [('(output (read))', '(output (matrix-read-answers (read)))'),
                    ('(equal? result output)', '(matrix-same-result? result output)')]
    for before, after in replacements:
        before, after = (after, before) if reverse else (before, after)
        if source.count(before) != 1:
            raise ValueError('Matrix harness boundary must occur once: ' + before)
        source = source.replace(before, after)
    return source


def chez_helpers():
    common = COMMON
    # Chez supplies these standard bindings and forbids redefining imports in
    # a compiled R6RS program. The identical adapted kernel uses those bindings.
    for name in ('caar', 'list', 'reverse', 'exact-integer?', 'zero?', 'even?', 'expt'):
        common = common.replace(form(common, '(define (' + name + ' '), '')
    return CHEZ_TYPES + common + CHEZ_BOUNDARY


# ---- Supplemental observations exercise callbacks and shared identities ----

PROBE_COMMON = '''(define (emit-bool value) (emit-i64 (if value 1 0)))
(: emit-list (All (T) (-> (-> T Unit) (List T) Unit)))
(define (emit-list emit values)
  (emit-i64 (length values))
  (let loop ((tail values))
    (unless (null? tail) (emit (car tail)) (loop (cdr tail)))))
(define (emit-row value) (emit-list emit-i64 value))
(define (emit-matrix value) (emit-list emit-row value))
(define (emit-refs value) (emit-list (lambda (cell) (emit-i64 (ref-get cell))) value))
(define (emit-answer value)
  (if (probe-matrix-answer? value)
      (begin (emit-i64 0) (emit-matrix (probe-answer-matrix value)))
      (begin (emit-i64 1) (emit-list (lambda (char) (emit-i64 (char->integer char)))
                                  (string->list (probe-answer-marker value))))))
(define (emit-best value)
  (emit-i64 (probe-best-size value)) (emit-i64 (probe-best-count value))
  (emit-list emit-answer (probe-best-answers value)))
(define (observe-primes primes last)
  (emit-i64 900)
  (let loop ((tail primes))
    (unless (probe-prime-null? tail)
      (emit-i64 (probe-prime-value tail)) (loop (probe-prime-cdr tail))))
  (emit-i64 0) (emit-i64 (probe-prime-value last))
  (let loop ((tail primes))
    (if (probe-prime-null? (probe-prime-cdr tail))
        (emit-bool (probe-prime-same? tail last))
        (loop (probe-prime-cdr tail)))))
(define (probe-numbers)
  (fold (list -7 -6 0 6 7)
        (lambda (x state)
          (fold (list -3 3)
                (lambda (y state) (emit-i64 (div x y)) (emit-i64 (mod x y)) state) state)) 0)
  (fold (list 0 1 2 3 4 5 6)
        (lambda (size state) (emit-i64 (det-upper-bound size)) state) 0)
  (fold (list 30 -30)
        (lambda (a state)
          (fold (list 21 -21)
                (lambda (b state)
                  (emit-gcd (extended-gcd a b (lambda (g x y)
                    (emit-i64 901) (emit-i64 g) (emit-i64 x) (emit-i64 y) (+ g 40)))) state) state)) 0)
  ((make-modular 7)
   (lambda (zero one zero? add negate multiply reciprocal)
     (emit-i64 zero) (emit-i64 one) (emit-bool (zero? -14))
     (emit-i64 (add -4 3)) (emit-i64 (negate 3)) (emit-i64 (multiply -3 4))
     (fold (list 1 2 3 4 5 6) (lambda (value state) (emit-i64 (reciprocal value)) state) 0))))
(define (probe-row-and-subset-order)
  (emit-i64 (fold-over-rows 3 (lambda (row count) (emit-row row) (+ count 1)) 0))
  (let ((universe (list 10 20 30 40)))
    (fold (list 0 1 2 3 4 5)
          (lambda (size state)
            (emit-i64 size)
            (emit-i64 (fold-over-subs-of-size universe size
                       (lambda (subset count) (emit-row subset) (+ count 1)) 0)) state) 0)))
(define (probe-permutation-tree cursor)
  (when (probe-permutation? cursor)
    (emit-i64 (ref-get (probe-perm-now cursor)))
    (emit-refs (probe-perm-puke cursor))
    (probe-permutation-tree (probe-perm-child cursor))
    (probe-permutation-tree (probe-perm-brother cursor))))
(define (probe-order-and-aliases)
  (probe-row-and-subset-order)
  (let* ((first (ref 1)) (second (ref 2)) (third (ref 3))
         (values (list first second third)) (cursor (gen-perms values)))
    (probe-permutation-tree cursor)
    (ref-set! (probe-perm-now (probe-perm-brother cursor)) 20)
    (emit-refs values)
    (emit-bool (ref-eq? (probe-perm-now cursor) first))
    (emit-bool (ref-eq? (probe-perm-now (probe-perm-child cursor)) second))
    (let ((selected (remove-in-order (lambda (cell)
                      (emit-i64 902) (emit-i64 (ref-get cell)) (= (ref-get cell) 20)) values)))
      (emit-refs selected)
      (emit-bool (ref-eq? (car selected) first))
      (emit-bool (ref-eq? (car (cdr selected)) third)))
    (emit-bool (all? (lambda (cell) (emit-i64 903) (emit-i64 (ref-get cell))
                      (< (ref-get cell) 10)) values)))
  (emit-bool (all? (lambda (value) (unreachable)) (ann '() (List I64))))
  (let ((values (proc->vector 4 (lambda (index)
                  (emit-i64 904) (emit-i64 index) (* index index)))))
    (emit-row (vector->list values))))
(define (probe-linear-algebra)
  (let ((reduce (make-modular-row-reduce 7)))
    (emit-matrix (reduce '()))
    (emit-matrix (reduce (list (list 0 0 0) (list 0 0 0))))
    (emit-matrix (reduce (list (list 0 2 4) (list 3 1 -1) (list 6 2 -2))))
    (emit-matrix (reduce (list (list 1 1 1) (list 1 -1 1) (list 1 1 -1)))))
  (let ((test ((make-modular-in-row-space? 7) (list (list 1 2 3) (list 2 4 6)))))
    (fold (list (list 0 0 0) (list 3 6 9) (list 1 1 1) (list -1 -2 -3))
          (lambda (row state) (emit-bool (test row)) state) 0))
  (fold probe-maximal-matrices
        (lambda (matrix state) (emit-bool (maximal? matrix)) state) 0))
(define (probe-collector)
  (let* ((matrix (list (list 1)))
         (old (let loop ((left 2998) (state (probe-best -1 -1 '())))
                (if (= left 0) state (loop (- left 1) (go-folder matrix state)))))
         (added (go-folder matrix old))
         (marked (go-folder matrix added))
         (capped (go-folder matrix marked)))
    (emit-best (go-folder '() old))
    (emit-best added) (emit-best marked) (emit-best capped)
    (emit-bool (probe-same-answers? (probe-best-answers marked) (probe-best-answers capped)))
    (emit-bool (probe-same-answers? (list (probe-marker-answer "..."))
                                   (list (probe-marker-answer "..x"))))
    (emit-best (go-folder (list (list 1) (list -1)) capped))
    (emit-best (go-folder matrix (probe-best -1 -1 '())))))
(define (probe-zulu)
  (fold (list (list 1 1 1) (list 1 -1 -1) (list 1 1 -1))
        (lambda (row state)
          (let ((values (list->vector row)))
            (emit-bool (zulu (list 1 1 -1) (lambda (index) (vector-ref values index))
                         (list (list 0 1 2))
                         (lambda (partitions) (emit-i64 905) (emit-matrix partitions) #t)))) state) 0))
(: probe (-> I64 I64 I64 I64))
(define (probe mode columns size)
  (cond ((= mode 0) (emit-list emit-answer (really-go columns size)))
        ((= mode 1) (probe-numbers) (unit))
        ((= mode 2) (probe-order-and-aliases))
        ((= mode 3) (probe-linear-algebra) (unit))
        ((= mode 4) (probe-collector))
        ((= mode 5) (emit-i64 (find-prime columns)))
        ((= mode 6) (probe-zulu) (unit))
        ((= mode 7) (probe-bad-message))
        ((= mode 8)
         (emit-i64 (go columns size (lambda (matrix count)
                       (emit-matrix matrix) (+ count 1)) 0)))
        (else (emit-list emit-answer (really-go columns size))
              (emit-list emit-answer (really-go columns size))))
  1)
'''
STRICT_PROBE = '''(define-extern emit-i64 "benchmark" "emit_i64" (-> I64 Unit))
(define probe-matrix-answer? matrix-answer?)
(define probe-answer-matrix answer-matrix)
(define probe-answer-marker answer-marker)
(define probe-matrix-answer matrix-answer)
(define probe-marker-answer marker-answer)
(define probe-same-answers? same-answers?)
(define probe-best best)
(define probe-best-size best-size)
(define probe-best-count best-count)
(define probe-best-answers best-answers)
(define probe-prime-null? prime-null?)
(define probe-prime-value prime-value)
(define probe-prime-cdr prime-cdr)
(define (probe-prime-same? left right) (ref-eq? (prime-tail left) (prime-tail right)))
(define probe-permutation? permutation?)
(define probe-perm-now perm-now)
(define probe-perm-brother perm-brother)
(define probe-perm-child perm-child)
(define probe-perm-puke perm-puke)
(define (emit-gcd value)
  (match value
    ((gcd-value answer) (emit-i64 0) (emit-i64 answer))
    ((gcd-negative sign magnitude) (emit-i64 1) (emit-i64 sign) (emit-i64 magnitude))))
(define (probe-bad-message)
  ((permutation-dispatch (gen-perms (list 1))) 99)
  (unit))
'''
ORIGINAL_PROBE = '''(define-syntax : (syntax-rules () ((_ . signature) (begin))))
(define-syntax ann (syntax-rules () ((_ value type) value)))
(define (unit) (if #f #f))
(define (unreachable) (error 'matrix-probe "unexpected evaluation"))
(define (ref value) (vector value))
(define (ref-get cell) (vector-ref cell 0))
(define (ref-set! cell value) (vector-set! cell 0 value))
(define ref-eq? eq?)
(define (probe-matrix-answer? value) (not (string? value)))
(define probe-answer-matrix values)
(define probe-answer-marker values)
(define probe-matrix-answer values)
(define probe-marker-answer values)
(define probe-same-answers? equal?)
(define (probe-best size count answers) (cons size (cons count answers)))
(define probe-best-size car)
(define probe-best-count cadr)
(define probe-best-answers cddr)
(define probe-prime-null? null?)
(define probe-prime-value car)
(define probe-prime-cdr cdr)
(define probe-prime-same? eq?)
(define (probe-permutation? value) (if value #t #f))
(define (probe-perm-now value) (value 'now))
(define (probe-perm-brother value) (value 'brother))
(define (probe-perm-child value) (value 'child))
(define (probe-perm-puke value) (value 'puke))
(define (emit-gcd value)
  (if (pair? value)
      (begin (emit-i64 1) (emit-i64 (car value)) (emit-i64 (cdr value)))
      (begin (emit-i64 0) (emit-i64 value))))
(define (probe-bad-message) ((gen-perms '(1)) 'unsupported-message))
'''


def maximal_fixtures():
    first, rest = [1, 1, 1], [[1, 1, -1], [1, -1, 1], [1, -1, -1]]
    return [[first], [first, first], *[[first, row] for row in rest],
            *[[first, *rows] for rows in itertools.permutations(rest, 2)], [first, *rest]]


def scheme_value(value):
    if isinstance(value, bool):
        return '#t' if value else '#f'
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, int):
        return str(value)
    return '(' + ' '.join(map(scheme_value, value)) + ')'


def scheme_list(value):
    if isinstance(value, int):
        return str(value)
    return '(list ' + ' '.join(map(scheme_list, value)) + ')'


def observed_kernel(source):
    before = '(chez-set-box! last entry)'
    if source.count(before) != 1:
        raise ValueError('one prime append site is required')
    return source.replace(before, '(begin ' + before + ' (observe-primes primes (chez-unbox last)))')


def strict_probe(original, prelude):
    return (prelude + STRICT_TYPES + CONTROL + COMMON + DIAGNOSTICS + STRICT_PROBE
            + observed_kernel(kernel(original)) +
            '(define probe-maximal-matrices ' + scheme_list(maximal_fixtures()) + ')\n' + PROBE_COMMON + '(unit)\n')


def chez_probe(original, adapted):
    interface = STRICT_PROBE.replace('(define-extern emit-i64 "benchmark" "emit_i64" (-> I64 Unit))\n', '')
    interface = interface.replace(form(interface, '(define (emit-gcd '), '''(define (emit-gcd value)
  (if (= (vector-ref value 0) 0)
      (begin (emit-i64 0) (emit-i64 (gcd-result-value value)))
      (begin (emit-i64 1) (emit-i64 (gcd-sign value)) (emit-i64 (gcd-magnitude value)))))''')
    helpers = chez_helpers() + interface if adapted else ORIGINAL_PROBE
    source = observed_kernel(kernel(original) if adapted else original)
    return ('(import (except (chezscheme) div mod))\n'
            '(define (exact-integer? value) (and (exact? value) (integer? value)))\n' + helpers +
            '(define (emit-i64 value) (write value) (newline))\n' + source +
            '(define probe-maximal-matrices ' + scheme_list(maximal_fixtures()) + ')\n' + PROBE_COMMON +
            '(let* ((mode (read)) (columns (read)) (size (read))) (probe mode columns size))\n')


# ---- Independent finite models check the meaning of the observed algorithm ----

def reduced_basis(matrix, prime):
    rows, pivot = [[value % prime for value in row] for row in matrix], 0
    for column in range(len(rows[0]) if rows else 0):
        choices = [index for index in range(pivot, len(rows)) if rows[index][column]]
        if not choices:
            continue
        rows[pivot], rows[choices[0]] = rows[choices[0]], rows[pivot]
        inverse = pow(rows[pivot][column], -1, prime)
        rows[pivot] = [value * inverse % prime for value in rows[pivot]]
        for index in range(len(rows)):
            if index != pivot:
                factor = rows[index][column]
                rows[index] = [(a - factor * b) % prime for a, b in zip(rows[index], rows[pivot])]
        pivot += 1
    return rows[:pivot]


def signed_permutation_maximal(matrix):
    original = tuple(itertools.chain.from_iterable(matrix))
    for rows in itertools.permutations(matrix):
        for signs in itertools.product((1, -1), repeat=len(rows) - 1):
            normalized = [[1] * len(rows[0])]
            normalized += [[a * b * sign for a, b in zip(rows[0], row)] for row, sign in zip(rows[1:], signs)]
            for columns in itertools.permutations(range(len(rows[0]))):
                candidate = tuple(row[column] for row in normalized for column in columns)
                if candidate > original:
                    return False
    return True


def next_prime(bound):
    candidate = max(2, bound + 1)
    while any(candidate % divisor == 0 for divisor in range(2, int(candidate ** 0.5) + 1)):
        candidate += 1
    return candidate


def determinant_bound(size):
    root = next(value for value in range(size + 1) if value * value >= size)
    return size ** (size // 2) * (root if size % 2 else 1)


def small_search(columns, size):
    candidates = [[1, *tail] for tail in itertools.product((1, -1), repeat=columns - 1)]
    prime, accepted = next_prime(determinant_bound(size)), []
    for count in range(1, len(candidates) + 1):
        for tail in itertools.combinations(candidates[1:], count - 1):
            matrix = [candidates[0], *tail]
            independent = all(len(reduced_basis(subset, prime)) == len(subset)
                              for subset in itertools.combinations(matrix, min(count, size)))
            if independent and signed_permutation_maximal(matrix):
                accepted.append(matrix)
    largest = max(map(len, accepted))
    return sorted(matrix for matrix in accepted if len(matrix) == largest)


def prime_observations(bound):
    values, primes = [], [2]
    if bound < 2:
        return values
    for candidate in range(3, next_prime(bound) + 1, 2):
        if all(candidate % divisor for divisor in range(2, int(candidate ** 0.5) + 1)):
            primes.append(candidate)
            values.extend([900, *primes, 0, candidate, 1])
    return values


def numeric_oracle():
    values = []
    for x, y in itertools.product((-7, -6, 0, 6, 7), (-3, 3)):
        values.extend([(x // abs(y)) * (1 if y > 0 else -1), x % abs(y)])
    values += [determinant_bound(size) for size in range(7)]
    values += [901, 3, -2, 3, 0, 43, 1, -1, 21, 1, -1, 30, 1, -1, 30]
    # The source stores the signed Bezout coefficient, not its least residue.
    return values + [0, 1, 1, 6, 4, 2, 1, -3, -2, 2, 3, -1]


def order_oracle():
    values = []
    for row in itertools.product((1, -1), repeat=3):
        values.extend([3, *row])
    values.append(8)
    for size in range(6):
        subsets = list(itertools.combinations((10, 20, 30, 40), size))
        values.append(size)
        for subset in subsets:
            values.extend([size, *subset])
        values.append(len(subsets))
    values += permutation_observations([1, 2, 3])
    return values + [3, 1, 20, 3, 1, 1, 902, 1, 902, 20, 902, 3,
                     2, 1, 3, 1, 1, 903, 1, 903, 20, 0, 1,
                     904, 0, 904, 1, 904, 2, 904, 3, 4, 0, 1, 4, 9]


def permutation_observations(objects):
    values = []
    for position, first in enumerate(objects):
        rest = objects[:position] + objects[position + 1:]
        values.extend([first, len(objects), first, *rest])
        values.extend(permutation_observations(rest))
    return values


def read_matrix(tokens):
    return [[next(tokens) for _ in range(next(tokens))] for _ in range(next(tokens))]


def check_linear_algebra(values):
    originals = [[], [[0, 0, 0], [0, 0, 0]], [[0, 2, 4], [3, 1, -1], [6, 2, -2]],
                 [[1, 1, 1], [1, -1, 1], [1, 1, -1]]]
    tokens = iter(values)
    for original in originals:
        actual = read_matrix(tokens)
        if reduced_basis(actual, 7) != reduced_basis(original, 7):
            raise ValueError('row reduction changed the mathematical row space')
        rank = len(reduced_basis(original, 7))
        if len(actual) != rank or len(reduced_basis(original + actual, 7)) != rank:
            raise ValueError('independent rank/span check rejected row reduction')
        pivots = [next(index for index, value in enumerate(row) if value % 7) for row in actual]
        if pivots != sorted(set(pivots)) or any(row[index] != 1 for row, index in zip(actual, pivots)):
            raise ValueError('row reduction did not produce the original echelon contract')
    expected = [1, 1, 0, 1] + list(map(int, map(signed_permutation_maximal, maximal_fixtures())))
    if list(tokens) != expected:
        raise ValueError('row-space or signed-permutation result differs from the independent model')


def collector_oracle():
    matrix = [[1]]
    old, added = [matrix] * 2998, [matrix] * 2999
    marked = ['...', *added]
    values = []
    for count, answers in ((2998, old), (2999, added), (3000, marked), (3001, marked)):
        values += [1, count, *encode_answers(answers)]
    return values + [1, 0, 2, 1, *encode_answers([[[1], [-1]]]), 1, 1, *encode_answers([matrix])]


def check_go_callbacks(values, columns, size):
    prefix = prime_observations(determinant_bound(size))
    if values[:len(prefix)] != prefix:
        raise ValueError('go callback trace changed prime generation')
    count, tokens = values[-1], iter(values[len(prefix):-1])
    matrices = [read_matrix(tokens) for _ in range(count)]
    if list(tokens) or not all(map(signed_permutation_maximal, matrices)):
        raise ValueError('go callbacks contain an invalid maximal matrix')
    largest = max(map(len, matrices))
    if sorted(matrix for matrix in matrices if len(matrix) == largest) != small_search(columns, size):
        raise ValueError('go callback payloads disagree with the independent small search')


# ---- Native scalar providers retain all expected data and opacity calls ----

NATIVE_HEADER = '''#include <stdint.h>
int64_t input_i64(int32_t);
int64_t expected_i64(int64_t);
int64_t hide_i64(int64_t);
void write_character(uint32_t);
void emit_i64(int64_t);
'''
NATIVE_PROVIDER = '''#include "native-provider.h"
#include <assert.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
static int64_t inputs[3], *expected, expected_count;
static uint64_t barriers;
void load_inputs(const char *path) {
    FILE *file = fopen(path, "r"); assert(file);
    for (int index = 0; index < 3; index++) assert(fscanf(file, "%" SCNd64, &inputs[index]) == 1);
    assert(fscanf(file, "%" SCNd64, &expected_count) == 1);
    assert(expected_count > 0 && expected_count < 1000000);
    expected = malloc((size_t)expected_count * sizeof(*expected)); assert(expected);
    for (int64_t index = 0; index < expected_count; index++)
        assert(fscanf(file, "%" SCNd64, &expected[index]) == 1);
    int64_t extra; assert(fscanf(file, "%" SCNd64, &extra) == EOF); fclose(file);
}
int64_t input_i64(int32_t index) { assert(index >= 0 && index < 3); return inputs[index]; }
int64_t expected_i64(int64_t index) { assert(index >= 0 && index < expected_count); return expected[index]; }
int64_t hide_i64(int64_t value) { barriers++; return value; }
uint64_t barrier_count(void) { return barriers; }
void emit_i64(int64_t value) { printf("%" PRId64 "\\n", value); }
void write_character(uint32_t value) {
    if (value < 128) { putchar(value); fflush(stdout); return; }
    unsigned width = value < 2048 ? 2 : value < 65536 ? 3 : 4;
    unsigned first[] = {0, 0, 192, 224, 240};
    putchar(first[width] | (value >> (6 * (width - 1))));
    for (unsigned index = width - 1; index; index--)
        putchar(128 | ((value >> (6 * (index - 1))) & 63));
    fflush(stdout);
}
'''
NATIVE_ENTRY = '''#include "native-provider.h"
#include <assert.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void guest_main(void) __asm__("wasm.main");
void load_inputs(const char *);
uint64_t barrier_count(void);
EXPORT
int main(int argc, char **argv) {
    native_host_init(argc, argv); native_module_init();
    SETUP
    guest_main();
    INVOKE
    return native_finish(0);
}
'''
NATIVE_BENCH = '''extern int64_t bench(int64_t) __asm__("wasm.bench");'''
NATIVE_BENCH_INVOKE = '''int64_t count = strtoll(argv[1], NULL, 10);
    struct timespec before, after;
    assert(clock_gettime(CLOCK_MONOTONIC, &before) == 0);
    int64_t result = bench(count);
    assert(clock_gettime(CLOCK_MONOTONIC, &after) == 0);
    double seconds = (double)(after.tv_sec - before.tv_sec) + (double)(after.tv_nsec - before.tv_nsec) / 1e9;
    printf("{\\"result\\":%" PRId64 ",\\"barriers\\":%" PRIu64 ",\\"seconds\\":%.9f}\\n", result, barrier_count(), seconds);'''
PROBE_HOST = '''import fs from 'node:fs';
const [artifact, mode, columns, size] = process.argv.slice(2);
const imports = {benchmark: {
  emit_i64: value => process.stdout.write(value.toString() + '\\n'),
  write_character: value => fs.writeSync(1, String.fromCodePoint(value)),
}};
const {instance} = await WebAssembly.instantiate(fs.readFileSync(artifact), imports);
instance.exports.main();
if (instance.exports.probe(BigInt(mode), BigInt(columns), BigInt(size)) !== 1n)
  throw new Error('probe did not finish');
'''


def checked_run(command, directory, path, environment, driver, stdin=None, timeout=1200):
    record = execute(command, directory, environment, timeout=timeout, stdin=stdin)
    record.update(cwd=str(directory), timeout_seconds=timeout)
    driver.save(path, record)
    driver.require_success(record)
    if record['timeout'] or record['executing_descendants']:
        raise RuntimeError('Matrix process supervision failed: ' + str(record))
    return record


def build_strict(directory, tools, environment, driver, export='bench'):
    checked_run([driver.ROOT / 'scripts/build-strict', '--export', export,
                 directory / 'strict.scm', directory / 'strict.wasm'], driver.ROOT,
                directory / 'strict-build.json', environment, driver)
    checked_run([tools['WASM_DIS'], directory / 'strict.wasm', '-o', directory / 'strict.optimized.wat'],
                driver.ROOT, directory / 'strict-disassembly.json', environment, driver)


def build_chez(directory, runner, tools, environment, driver):
    command, run = runner.chez_commands(directory, str(directory / 'program.scm'))
    command[0] = run[0] = tools['CHEZ']
    checked_run(command, directory, directory / 'chez-build.json', environment, driver)
    return run


def build_native(directory, tools, environment, driver, probe=False, count_barriers=True):
    provider = NATIVE_PROVIDER if count_barriers else NATIVE_PROVIDER.replace('barriers++; ', '')
    (directory / 'native-provider.h').write_text(NATIVE_HEADER)
    (directory / 'native-provider.c').write_text(provider)
    export = 'extern int64_t probe(int64_t, int64_t, int64_t) __asm__("wasm.probe");' if probe else NATIVE_BENCH
    invoke = 'assert(probe(strtoll(argv[1], NULL, 10), strtoll(argv[2], NULL, 10), strtoll(argv[3], NULL, 10)) == 1);' if probe else NATIVE_BENCH_INVOKE
    entry = NATIVE_ENTRY.replace('EXPORT', export).replace('INVOKE', invoke)
    (directory / 'native-entry.c').write_text(entry.replace('SETUP', 'assert(argc == 4);' if probe else 'assert(argc == 3); load_inputs(argv[2]);'))
    checked_run([driver.ROOT / 'scripts/build-native', '--wasm', '--c-provider', 'benchmark',
                 directory / 'native-provider.h', directory / 'native-provider.c', '--entry-c',
                 directory / 'native-entry.c', directory / 'strict.wasm', directory / 'native'],
                driver.ROOT, directory / 'native-build.json', environment, driver)


# ---- Preparation keeps source proof, full runs, and probes separate ----

def source_proof(directory, driver):
    adapted, original, typed = driver.matched_chez_source('matrix', directory)
    changed, edits = adaptation(original)
    restored = changed
    for edit in reversed(edits):
        if restored.count(edit['after']) != edit['count']:
            raise ValueError('Matrix edit is not reversibly located: ' + edit['after'])
        restored = restored.replace(edit['after'], edit['before'])
    if restored != original or CONTRACTS + changed != typed:
        raise ValueError('Matrix adaptation failed exact reverse reconstruction')
    (directory / 'original-kernel.scm').write_text(original)
    (directory / 'adapted-kernel.scm').write_text(typed)
    target = directory / 'same-source-chez'
    target.mkdir()
    (target / 'program.scm').write_text(adapted)
    driver.save(directory / 'adaptation-ledger.json', edits)
    for label, before, after in [('kernel', original, typed), ('complete-source', (directory / 'program.scm').read_text(), adapted)]:
        (directory / (label + '-adaptation.patch')).write_text(''.join(difflib.unified_diff(
            before.splitlines(True), after.splitlines(True), fromfile='original', tofile='adapted')))
    driver.save(directory / 'source-proof.json', dict(reversible_kernel=True, same_adapted_kernel=True,
        original_kernel_sha256=hashlib.sha256(original.encode()).hexdigest(),
        adapted_kernel_sha256=hashlib.sha256(typed.encode()).hexdigest(), edit_count=len(edits),
        predicate='same complete ordered values, with explicit answer variants and the original initial false result'))


def native_inputs(directory, spec, label):
    path = directory / ('native-input-' + label + '.txt')
    path.write_text(' '.join(map(str, [*spec['inputs'], len(spec['expected']), *spec['expected']])) + '\n')
    return path


def validate_canonical(directory, runner, tools, environment, driver, native=False):
    spec, records = driver.load(directory / 'spec.json'), []
    for count in (1, 2, spec['count']):
        selected = dict(spec, count=count)
        path = directory / f'validation-spec-{count}.json'
        driver.save(path, selected)
        if native:
            command = [directory / 'native', str(count), native_inputs(directory, selected, str(count))]
            record = checked_run(command, directory, directory / f'native-validation-{count}.json', environment, driver)
            result = json.loads(record['stdout'])
            if result['result'] != 1 or result['barriers'] != 2 * count or record['stderr']:
                raise ValueError('native Matrix result or opacity count differs')
            records.append(dict(record, system='native', count=count))
            continue
        for suffix in ('.raw.wasm', ''):
            command = [tools['NODE'], directory.parent / 'host.mjs', directory / ('strict.wasm' + suffix), path, '--validate']
            record = checked_run(command, directory, directory / f'wasm-validation-{count}{suffix}.json', environment, driver)
            records.append(dict(record, system='raw' if suffix else 'optimized', count=count))
        for system in ('original', 'same-source-chez'):
            target = directory if system == 'original' else directory / system
            data = runner.input_data((directory / 'input.txt').read_bytes(), count).decode()
            record = checked_run([tools['CHEZ'], '--program', target / 'program.so'], target,
                                 target / f'validation-{count}.json', environment, driver, stdin=data)
            if record['stderr'] or runner.parse_result(record['stdout'], 'chez', 'matrix')['status'] != 'ok':
                raise ValueError('Chez Matrix rejected its complete canonical expected matrices')
            records.append(dict(record, system=system, count=count, stdin=data))
    driver.save(directory / ('native-validation.json' if native else 'canonical-validation.json'), records)


def build_probes(directory, runner, tools, environment, driver):
    original = (directory / 'original-kernel.scm').read_text()
    target = directory / 'probe'
    target.mkdir()
    (target / 'strict.scm').write_text(strict_probe(original, driver.PRELUDE))
    (target / 'host.mjs').write_text(PROBE_HOST)
    build_strict(target, tools, environment, driver, 'probe')
    build_native(target, tools, environment, driver, probe=True)
    for system, adapted in (('original', False), ('adapted', True)):
        control = target / system
        control.mkdir()
        (control / 'program.scm').write_text(chez_probe(original, adapted))
        build_chez(control, runner, tools, environment, driver)


def probe_command(directory, system, tools, mode, columns, size):
    target, arguments = directory / 'probe', list(map(str, (mode, columns, size)))
    if system in ('original', 'adapted'):
        return [tools['CHEZ'], '--program', target / system / 'program.so'], ' '.join(arguments)
    if system == 'native':
        return [target / 'native', *arguments], None
    suffix = '.raw.wasm' if system == 'raw' else ''
    return [tools['NODE'], target / 'host.mjs', target / ('strict.wasm' + suffix), *arguments], None


def probe_oracle(mode, columns, size, canonical):
    if mode in (0, 9):
        answers = canonical if (columns, size) == (5, 5) else small_search(columns, size)
        values = prime_observations(determinant_bound(size)) + encode_answers(answers)
        return values * (2 if mode == 9 else 1)
    if mode == 1:
        return numeric_oracle()
    if mode == 2:
        return order_oracle()
    if mode == 4:
        return collector_oracle()
    if mode == 5:
        return prime_observations(columns) + [next_prime(columns)]
    if mode == 6:
        return [0, 1, 905, 2, 2, 1, 0, 1, 2, 1]
    return None


def validate_probe_case(directory, case, tools, environment, driver):
    label, mode, columns, size = case
    expected = probe_oracle(mode, columns, size, driver.load(directory / 'spec.json')['original_expected'])
    records, reference = [], None
    for system in ('original', 'adapted', 'raw', 'optimized', 'native'):
        command, stdin = probe_command(directory, system, tools, mode, columns, size)
        record = execute(command, directory / 'probe', environment, stdin=stdin)
        records.append(dict(record, system=system, stdin=stdin))
        driver.save(directory / 'probe' / (label + '.json'), records)
        driver.require_success(record)
        if record['stderr'] or record['timeout'] or record['executing_descendants']:
            raise ValueError('Matrix observation process did not complete cleanly')
        values = list(map(int, record['stdout'].split()))
        if reference is None:
            reference = values
        if values != reference or (expected is not None and values != expected):
            raise ValueError('Matrix full observation mismatch: ' + label + '/' + system)
        if mode == 3:
            check_linear_algebra(values)
        if mode == 8:
            check_go_callbacks(values, columns, size)
    driver.save(directory / 'probe' / (label + '-expected.json'), dict(values=expected, original=reference))


def validate_probes(directory, tools, environment, driver):
    cases = [('canonical-once', 0, 5, 5), ('canonical-reset', 9, 5, 5),
             ('small-2-2', 0, 2, 2), ('small-3-2', 0, 3, 2), ('small-3-3', 0, 3, 3),
             ('small-3-4', 0, 3, 4), ('numbers', 1, 0, 0), ('order-aliases', 2, 0, 0),
             ('linear-algebra', 3, 0, 0), ('collector-cap', 4, 0, 0),
             ('prime-empty', 5, 1, 0), ('prime-chain', 5, 20, 0), ('zulu', 6, 0, 0),
             ('go-callback-order', 8, 3, 3)]
    for case in cases:
        validate_probe_case(directory, case, tools, environment, driver)
    driver.save(directory / 'probe' / 'validated.json', dict(cases=cases, canonical_internal_trace_invocations=1,
                repeated_call_trace_invocations=2, full_count_internal_trace=False))


def prepare_case(directory, runner, tools, environment, driver):
    source_proof(directory, driver)
    build_strict(directory, tools, environment, driver)
    run = build_chez(directory, runner, tools, environment, driver)
    build_chez(directory / 'same-source-chez', runner, tools, environment, driver)
    validate_canonical(directory, runner, tools, environment, driver)
    build_native(directory, tools, environment, driver)
    validate_canonical(directory, runner, tools, environment, driver, native=True)
    build_probes(directory, runner, tools, environment, driver)
    validate_probes(directory, tools, environment, driver)
    validate_predicates(directory, runner, tools, environment, driver)
    validate_bad_message(directory, tools, environment, driver)
    prepare_native_timing(directory, tools, environment, driver)
    retain_toolchain(directory, tools, environment, driver)
    prepare_rust(directory, tools, environment, driver)
    validate_supervision(directory, environment, driver)
    return dict(name='matrix', status='ready', spec=driver.load(directory / 'spec.json'), chez_command=run,
                systems=['strict', 'chez', 'chez-adapted'],
                hashes={str(path.relative_to(directory)): driver.digest(path) for path in directory.rglob('*') if path.is_file()})


# ---- Freeze the native timing provider and the Rust algorithm/layout control ----

def prepare_native_timing(directory, tools, environment, driver):
    target = directory / 'native-timing'
    target.mkdir()
    shutil.copy2(directory / 'strict.wasm', target / 'strict.wasm')
    build_native(target, tools, environment, driver, count_barriers=False)
    spec = driver.load(directory / 'spec.json')
    record = checked_run([target / 'native', spec['count'], native_inputs(target, spec, 'canonical')],
                         target, target / 'canonical-validation.json', environment, driver)
    result = json.loads(record['stdout'])
    if result['result'] != 1 or result['barriers'] != 0 or record['stderr']:
        raise ValueError('non-counting native artifact did not pass the full original workload')
    original, timing = (directory / 'native-provider.c').read_text(), (target / 'native-provider.c').read_text()
    if timing.replace('int64_t hide_i64(int64_t value) { return value; }',
                      'int64_t hide_i64(int64_t value) { barriers++; return value; }') != original:
        raise ValueError('native timing provider changed beyond barrier counting')


def retain_toolchain(directory, tools, environment, driver):
    records = {}
    for name, arguments in [('RUSTC', ['--version', '--verbose']), ('CARGO', ['--version']),
                            ('CLANG', ['--version']), ('LLD', ['--version']),
                            ('NODE', ['-p', 'JSON.stringify(process.versions)'])]:
        record = checked_run([tools[name], *arguments], driver.ROOT,
                             directory / ('tool-' + name.lower() + '.json'), environment, driver)
        records[name] = dict(record, path=tools[name], sha256=driver.digest(tools[name]))
    record = checked_run([tools['RUSTC'], '--print', 'sysroot'], driver.ROOT,
                         directory / 'rust-sysroot.json', environment, driver)
    root = Path(record['stdout'].strip())
    files = [root / 'bin/rustc', *root.glob('lib/*.so'), *root.glob('lib/*.so.*')]
    for target in ('x86_64-unknown-linux-gnu', 'wasm32-wasip1'):
        files += [path for path in (root / 'lib/rustlib' / target).rglob('*') if path.is_file()]
    driver.save(directory / 'toolchain.json', dict(tools=records, rust_files={str(path): driver.digest(path) for path in files},
                environment={name: environment.get(name) for name in ('BINARYEN_CORES', 'RUSTUP_TOOLCHAIN',
                    'NODE_OPTIONS', 'NODE_V8_COVERAGE', 'NODE_DEBUG', 'NODE_DEBUG_NATIVE', 'LD_PRELOAD',
                    'SNAIL_NATIVE_GC_INTERVAL', 'SNAIL_GC_STATS', 'SNAIL_GC_HEAP_BYTES', 'SNAIL_GC_MIN_BYTES')}))


RUST_WASM_FEATURES = ['--mvp-features', '--enable-mutable-globals',
    '--enable-nontrapping-float-to-int', '--enable-bulk-memory', '--enable-sign-ext',
    '--enable-reference-types', '--enable-multivalue', '--enable-extended-const',
    '--enable-bulk-memory-opt', '--enable-call-indirect-overlong']


def prepare_rust(directory, tools, environment, driver):
    original, target = driver.ROOT / 'benchmarks/wasm-reference', directory / 'rust-reference'
    shutil.copytree(original / 'src', target / 'src')
    for name in ('Cargo.toml', 'Cargo.lock', 'run-wasi.mjs'):
        shutil.copy2(original / name, target / name)
    build_rust(target, tools, environment, driver)
    if (target / 'src/bin/matrix.rs').read_bytes() != (original / 'src/bin/matrix.rs').read_bytes():
        raise ValueError('Rust Matrix control must use the unchanged reference source')
    validate_rust(directory, target, tools, environment, driver)


def build_rust(target, tools, environment, driver):
    environment = dict(environment, CARGO_TARGET_DIR=str(target / 'target'))
    commands = [('tests', ['test', '--offline', '--bin', 'matrix']),
                ('native-build', ['rustc', '--offline', '--release', '--bin', 'matrix', '--', '--emit=asm,llvm-ir']),
                ('wasm-build', ['rustc', '--offline', '--release', '--target', 'wasm32-wasip1', '--bin', 'matrix', '--', '--emit=llvm-ir'])]
    for label, arguments in commands:
        checked_run([tools['CARGO'], *arguments], target, target / (label + '.json'), environment, driver)
    shutil.copy2(target / 'target/release/matrix', target / 'matrix.native')
    shutil.copy2(target / 'target/wasm32-wasip1/release/matrix.wasm', target / 'matrix.raw.wasm')
    checked_run([tools['WASM_OPT'], '-O3', '-g', *RUST_WASM_FEATURES, target / 'matrix.raw.wasm', '-o', target / 'matrix.wasm'],
                target, target / 'wasm-optimize.json', environment, driver)
    checked_run([tools['WASM_DIS'], target / 'matrix.wasm', '-o', target / 'matrix.wat'],
                target, target / 'wasm-disassemble.json', environment, driver)


def rust_commands(target, tools):
    host = [tools['NODE'], '--disable-warning=ExperimentalWarning', target / 'run-wasi.mjs']
    return [('native', [target / 'matrix.native']), ('raw-wasm', [*host, target / 'matrix.raw.wasm']),
            ('optimized-wasm', [*host, target / 'matrix.wasm'])]


def validate_rust(directory, target, tools, environment, driver):
    canonical, records = driver.load(directory / 'spec.json'), []
    fixtures = [(2500, 5, 5, canonical['original_expected']),
                *[(1, columns, size, small_search(columns, size)) for columns, size in ((2, 2), (3, 2), (3, 3), (3, 4))]]
    for count, columns, size, expected in fixtures:
        data = f'{count}\n{columns}\n{size}\n' + scheme_value(expected) + '\n'
        for system, command in rust_commands(target, tools):
            label = f'{system}-{count}-{columns}-{size}'
            record = checked_run(command, target, target / (label + '.json'), environment, driver, stdin=data)
            first = record['stdout'].splitlines()[0]
            if record['stderr'] or not first.startswith('Result: ') or driver.input_values(first[8:]) != [expected]:
                raise ValueError('Rust complete Matrix result differs from the mathematical/source control')
            records.append(dict(record, system=system, stdin=data, complete_ordered_output=True))
    driver.save(target / 'validation.json', records)


# ---- Tests ----

def predicate_fixtures(spec):
    original = spec['original_expected']
    wrong = copy.deepcopy(original)
    wrong[2][3][4] *= -1
    missing_row, missing_entry = copy.deepcopy(original), copy.deepcopy(original)
    missing_row[2].pop()
    missing_entry[2][3].pop()
    extra_entry = copy.deepcopy(original)
    extra_entry[2][3].append(1)
    swapped_rows = copy.deepcopy(original)
    swapped_rows[2][2], swapped_rows[2][3] = swapped_rows[2][3], swapped_rows[2][2]
    return [('wrong-entry', 1, wrong, False), ('missing-matrix', 1, original[:-1], False),
            ('extra-matrix', 1, original + [original[0]], False), ('matrix-order', 1, list(reversed(original)), False),
            ('row-order', 1, swapped_rows, False), ('missing-row', 1, missing_row, False),
            ('missing-entry', 1, missing_entry, False), ('extra-entry', 1, extra_entry, False),
            ('wrong-variant', 1, ['...'], False), ('zero-false', 0, False, True),
            ('negative-false', -2, False, True), ('zero-empty', 0, [], False)]


def predicate_execution(directory, system, tools, spec, expected, label, environment, driver):
    if system == 'native':
        command = [directory / 'native', spec['count'], native_inputs(directory, spec, label)]
        return execute(command, directory, environment), None
    if system in ('original', 'adapted'):
        target = directory if system == 'original' else directory / 'same-source-chez'
        data = f"{spec['count']}\n{spec['inputs'][0]}\n{spec['inputs'][1]}\n{scheme_value(expected)}\n"
        return execute([tools['CHEZ'], '--program', target / 'program.so'], target, environment, stdin=data), data
    path = directory / ('predicate-' + label + '.json')
    driver.save(path, spec)
    suffix = '.raw.wasm' if system == 'raw' else ''
    command = [tools['NODE'], directory.parent / 'host.mjs', directory / ('strict.wasm' + suffix), path, '--validate']
    return execute(command, directory, environment), None


def predicate_accepted(record, system, runner):
    if record['timeout'] or record['executing_descendants']:
        raise ValueError('predicate child did not terminate cleanly')
    if system in ('raw', 'optimized'):
        if record['returncode'] == 0:
            return json.loads(record['stdout'])['result'] == '1'
        if "actual: '0'" not in record['stderr'] or 'AssertionError' not in record['stderr']:
            raise ValueError('predicate failed without a checked false result')
        return False
    if record['returncode'] != 0 or record['stderr']:
        raise ValueError('predicate process failed before checking its result')
    if system == 'native':
        return json.loads(record['stdout'])['result'] == 1
    return runner.parse_result(record['stdout'], 'chez', 'matrix')['status'] == 'ok'


def validate_predicates(directory, runner, tools, environment, driver):
    original, records = driver.load(directory / 'spec.json'), []
    for label, count, expected, accepted in predicate_fixtures(original):
        spec = dict(original, count=count, expected=encode_answers(expected),
                    inputs=[*original['inputs'][:2], int(expected is False)])
        for system in ('original', 'adapted', 'raw', 'optimized', 'native'):
            record, stdin = predicate_execution(directory, system, tools, spec, expected, label, environment, driver)
            records.append(dict(record, label=label, system=system, stdin=stdin, expected_acceptance=accepted))
            driver.save(directory / 'predicate-validation.json', records)
            if predicate_accepted(record, system, runner) != accepted:
                raise ValueError('Matrix complete predicate accepted the wrong value: ' + label + '/' + system)


def validate_bad_message(directory, tools, environment, driver):
    records = []
    for system in ('original', 'adapted', 'raw', 'optimized', 'native'):
        command, stdin = probe_command(directory, system, tools, 7, 0, 0)
        record = execute(command, directory / 'probe', environment, stdin=stdin)
        records.append(dict(record, system=system, stdin=stdin))
        driver.save(directory / 'bad-message-validation.json', records)
        if record['returncode'] == 0 or record['timeout'] or record['executing_descendants']:
            raise ValueError('invalid permutation message must reject normally without a timeout')
        diagnostic = record['stdout'] + record['stderr']
        if 'gen-perms' not in diagnostic or 'Bad msg:' not in diagnostic:
            raise ValueError('invalid permutation message lost its diagnostic context')
        if system == 'original':
            if 'unsupported-message' not in diagnostic:
                raise ValueError('original invalid-message irritant was lost')
        elif record['stdout'] != 'gen-perms: Bad msg: ~a; message code 99\n':
            raise ValueError('adapted closed-message diagnostic differs')


def validate_supervision(directory, environment, driver):
    cases = [('vanished-leader', 'pass', 5, False),
             ('pipe-closing-child', 'import os,time\npid=os.fork()\nif pid==0:\n os.close(0);os.close(1);os.close(2);time.sleep(60)\nelse: print(pid,flush=True)', 5, False),
             ('timeout-child', 'import os,time\npid=os.fork()\nif pid==0:\n os.close(0);os.close(1);os.close(2);time.sleep(60)\nelse:\n print(pid,flush=True);time.sleep(60)', 0.2, True)]
    records = []
    for label, source, timeout, expired in cases:
        record = execute([sys.executable, '-c', source], directory, environment, timeout=timeout)
        records.append(dict(record, label=label))
        driver.save(directory / 'supervision-validation.json', records)
        if record['timeout'] != expired or record['executing_descendants'] or (not expired and record['returncode'] != 0):
            raise ValueError('bounded process group cleanup failed: ' + label)
