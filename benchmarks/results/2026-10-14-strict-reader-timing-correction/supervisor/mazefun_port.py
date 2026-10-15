"""Keep the functional maze's linked lists, cavity labels and complete grid."""

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from data_ports import form, replace
from string_port import exact_json_integer


# ---- Coordinates are the cell labels, not separately wrapped payloads ----

STRICT_TYPES = '''(define-data Cavity
  (wall) (coordinate (row I64 coordinate-row) (column I64 coordinate-column)))
(define wall-value (wall))
(define (open-cell? value)
  (match value ((wall) #f) ((coordinate row column) #t)))
(define-data Dimensions
  (dimensions (rows I64 dimension-rows) (columns I64 dimension-columns)))
(define-data MazeResult
  (maze-initial) (maze-error) (maze-grid (rows (List (List Bool)) maze-rows))
  (maze-other))
(define maze-initial-value (maze-initial))
(define maze-error-value (maze-error))
(define maze-other-value (maze-other))
(define (maze-kind value)
  (match value ((maze-initial) 0) ((maze-error) 1)
    ((maze-grid rows) 2) ((maze-other) 3)))
'''
CHEZ_TYPES = '''(define-syntax : (syntax-rules () ((_ . signature) (begin))))
(define-syntax ann (syntax-rules () ((_ value type) value)))
(define wall-value (vector 0))
(define (coordinate row column) (vector 1 row column))
(define (open-cell? value) (= (vector-ref value 0) 1))
(define (coordinate-row value) (vector-ref value 1))
(define (coordinate-column value) (vector-ref value 2))
(define (dimensions rows columns) (vector rows columns))
(define (dimension-rows value) (vector-ref value 0))
(define (dimension-columns value) (vector-ref value 1))
(define maze-initial-value (vector 0))
(define maze-error-value (vector 1))
(define maze-other-value (vector 3))
(define (maze-grid rows) (vector 2 rows))
(define (maze-kind value) (vector-ref value 0))
(define (maze-rows value) (vector-ref value 1))
'''
COMMON = ''';; Position lists contain Coordinate values by construction. Writes
;; share that same label; they never add a cell wrapper or copy its coordinates.
(define (same-bool? left right) (if left right (not right)))
(define (maze-even? value) (= (remainder value 2) 0))
(define (maze-odd? value) (not (maze-even? value)))
(define (same-cavity? left right)
  (if (open-cell? left)
      (and (open-cell? right) (= (coordinate-row left) (coordinate-row right))
           (= (coordinate-column left) (coordinate-column right)))
      (not (open-cell? right))))
(define (cavity-member? value values)
  (and (not (null? values))
       (or (same-cavity? value (car values)) (cavity-member? value (cdr values)))))
(: singleton (All (T) (-> T (List T))))
(define (singleton value) (cons value '()))
(: append-two (All (T) (-> (List T) (List T) (List T))))
(define (append-two first last)
  (if (null? first) last (cons (car first) (append-two (cdr first) last))))
(: append-four (All (T) (-> (List T) (List T) (List T) (List T) (List T))))
(define (append-four first second third last)
  (append-two first (append-two second (append-two third last))))
(: maze-map (All (A B) (-> (-> A B) (List A) (List B))))
(define (maze-map procedure values)
  (if (null? values) '()
      (let ((head (procedure (car values))))
        (cons head (maze-map procedure (cdr values))))))
(define (same-row? left right)
  (if (null? left) (null? right)
      (and (not (null? right)) (same-bool? (car left) (car right))
           (same-row? (cdr left) (cdr right)))))
(define (same-grid? left right)
  (if (null? left) (null? right)
      (and (not (null? right)) (same-row? (car left) (car right))
           (same-grid? (cdr left) (cdr right)))))
(define (same-maze? actual expected)
  (and (= (maze-kind actual) (maze-kind expected))
       (if (= (maze-kind actual) 2) (same-grid? (maze-rows actual) (maze-rows expected))
           (not (= (maze-kind actual) 3)))))
'''
CONTRACTS = '''(: foldr (All (A B) (-> (-> A B B) B (List A) B)))
(: foldl (All (A B) (-> (-> B A B) B (List A) B)))
(: for (All (T) (-> I64 I64 (-> I64 T) (List T))))
(: concat (All (T) (-> (List (List T)) (List T))))
(: list-read (All (T) (-> (List T) I64 T)))
(: list-write (All (T) (-> (List T) I64 T (List T))))
(: list-remove-pos (All (T) (-> (List T) I64 (List T))))
(: make-matrix (All (T) (-> I64 I64 (-> I64 I64 T) (List (List T)))))
(: matrix-read (All (T) (-> (List (List T)) I64 I64 T)))
(: matrix-write (All (T) (-> (List (List T)) I64 I64 T (List (List T)))))
(: matrix-size (All (T) (-> (List (List T)) Dimensions)))
(: matrix-map (All (A B) (-> (-> A B) (List (List A)) (List (List B)))))
(: shuffle (All (T) (-> (List T) (List T))))
(: shuffle-aux (All (T) (-> (List T) I64 (List T))))
(: make-maze (-> I64 I64 MazeResult))
'''


# ---- Counted substitutions preserve the original recursion and list work ----

def coordinate_roles(source):
    source = replace(source, '(cons (length mat) (length (car mat)))',
                     '(dimensions (length mat) (length (car mat)))')
    for pair, count in (('(cons i j)', 2), ('(cons (- i 1) j)', 1),
                        ('(cons (+ i 1) j)', 1), ('(cons i (- j 1))', 1),
                        ('(cons i (+ j 1))', 1)):
        source = replace(source, pair, pair.replace('(cons ', '(coordinate '), count)
    for name, count in (('pos', 5), ('nc', 1), ('size', 1)):
        accessors = ('dimension-rows', 'dimension-columns') if name == 'size' else ('coordinate-row', 'coordinate-column')
        for operation, accessor in zip(('car', 'cdr'), accessors):
            source = replace(source, f'({operation} {name})', f'({accessor} {name})', count)
    return source


def cell_roles(source):
    source = replace(source, '(coordinate i j)\n                                      #f)',
                     '(coordinate i j)\n                                      wall-value)')
    source = replace(source, '(member (car lst) (cdr lst))', '(cavity-member? (car lst) (cdr lst))')
    source = replace(source, '(equal? cavity-id old-cavity-id)', '(same-cavity? cavity-id old-cavity-id)')
    source = replace(source, '(equal? (even? i) (even? j))', '(same-bool? (even? i) (even? j))')
    for cell in ('(matrix-read cave (- i 1) j)', '(matrix-read cave (+ i 1) j)',
                 '(matrix-read cave i (- j 1))', '(matrix-read cave i (+ j 1))'):
        source = replace(source, cell, '(open-cell? ' + cell + ')')
    return source


def kernel(source):
    source = cell_roles(coordinate_roles(source))
    source = replace(source, '(foldr append ', '(foldr append-two ')
    source = replace(source, '(append (if ', '(append-four (if ')
    source = replace(source, '(list (coordinate ', '(singleton (coordinate ', 5)
    source = replace(source, '(map ', '(maze-map ', 3)
    source = replace(source, '(even? ', '(maze-even? ', 4)
    source = replace(source, '(odd? ', '(maze-odd? ', 2)
    source = replace(source, "'error", 'maze-error-value')
    source = replace(source, "(matrix-map (lambda (x) (if x '_ '*)) cave)",
                     '(maze-grid (matrix-map open-cell? cave))')
    return CONTRACTS + source


# ---- The actual Scheme reader classifies complete expected datums ----

CLASSIFIER = '''(define (maze-mark? value) (or (eq? value '_) (eq? value '*)))
(define (maze-row? value) (and (list? value) (for-all maze-mark? value)))
(define (maze-grid? value) (and (list? value) (for-all maze-row? value)))
(define (maze-expected-kind value)
  (cond ((eq? value #f) 0) ((eq? value 'error) 1)
        ((maze-grid? value) 2) (else 3)))
'''
INPUT_DECODER = '''(import (chezscheme))
''' + CLASSIFIER + '''(define (emit value) (display value) (newline))
(define (read-i64)
  (let ((value (read)))
    (unless (and (integer? value) (exact? value) (<= (- (expt 2 63)) value (- (expt 2 63) 1)))
      (error 'mazefun "expected an exact signed 64-bit input" value))
    (emit value)))
(read-i64) (read-i64) (read-i64)
(let* ((value (read)) (kind (maze-expected-kind value)))
  (when (eof-object? value) (error 'mazefun "missing expected datum"))
  (emit kind)
  (when (= kind 2)
    (emit (length value))
    (for-each (lambda (row)
                (emit (length row))
                (for-each (lambda (mark) (emit (if (eq? mark '_) 1 0))) row)) value)))
'''


def specification(data):
    chez = shutil.which(os.environ.get('CHEZ', 'scheme'))
    if not chez:
        raise ValueError('Chez is required to read the original maze input')
    with tempfile.TemporaryDirectory(prefix='mazefun-input-') as temporary:
        source = Path(temporary) / 'read-input.scm'
        source.write_text(INPUT_DECODER)
        run = subprocess.run([chez, '--program', str(source)], input=data.decode(),
                             text=True, capture_output=True, timeout=30)
    if run.returncode or run.stderr:
        raise ValueError('mazefun input reader failed: ' + run.stderr)
    count, n, m, *expected = map(int, run.stdout.split())
    return dict(name='mazefun', count=exact_json_integer(count),
                inputs=list(map(exact_json_integer, (n, m))), expected=expected,
                result_kind='i64-list-values', barriers_per_iteration=2, setup_barriers=0,
                input_decoder=dict(tool=chez, sha256=hashlib.sha256(Path(chez).read_bytes()).hexdigest(),
                                   source=INPUT_DECODER, stdin=data.decode(), stdout=run.stdout))


# ---- Decode expectation lists before timing; compare complete lists inside ----

INPUTS = '''(define-extern native-expected-i64 "benchmark" "expected_i64" (-> I64 I64))
(define expected-cursor (ref 0))
(define (read-expected-i64)
  (let ((value (native-expected-i64 (ref-get expected-cursor))))
    (ref-set! expected-cursor (+ (ref-get expected-cursor) 1)) value))
(define (read-expected-row size)
  (if (= size 0) '()
      (let ((head (= (read-expected-i64) 1)))
        (cons head (read-expected-row (- size 1))))))
(define (read-expected-rows size)
  (if (= size 0) '()
      (let ((head (read-expected-row (read-expected-i64))))
        (cons head (read-expected-rows (- size 1))))))
(define (read-expected-maze)
  (let ((kind (read-expected-i64)))
    (if (= kind 0) maze-initial-value
        (if (= kind 1) maze-error-value
            (if (= kind 2) (maze-grid (read-expected-rows (read-expected-i64))) maze-other-value)))))
(define input0 (native-input-i64 (ann 0 I32)))
(define input1 (native-input-i64 (ann 1 I32)))
(define expected-maze (read-expected-maze))
'''
WORKER = '''(let loop ((i 0) (result maze-initial-value))
  (if (< i count)
      (loop (+ i 1) (make-maze (hide count input0) (hide count input1)))
      (if (same-maze? result expected-maze) 1 0)))'''
CHEZ_BOUNDARY = CLASSIFIER + '''(define (read-expected-maze value)
  (case (maze-expected-kind value)
    ((0) maze-initial-value) ((1) maze-error-value)
    ((2) (maze-grid (maze-map (lambda (row) (maze-map (lambda (mark) (eq? mark '_)) row)) value)))
    (else maze-other-value)))
(define (original-maze value)
  (case (maze-kind value)
    ((0) #f) ((1) 'error)
    ((2) (maze-map (lambda (row) (maze-map (lambda (mark) (if mark '_ '*)) row)) (maze-rows value)))
    (else (error 'mazefun "impossible actual result"))))
'''


def adapt_harness(source, reverse=False):
    edits = (('(output (read))', '(output (read-expected-maze (read)))'),
             ('(equal? result output)', '(same-maze? (if result result maze-initial-value) output)'),
             ('(write result)', '(write (if result (original-maze result) #f))'))
    for before, after in edits:
        source = replace(source, after if reverse else before, before if reverse else after)
    return source


# ---- Separate complete-value, cavity-order and persistent-sharing probes ----

PROBE_COMMON = '''(: emit-sequence (All (T) (-> (-> T Unit) (List T) Unit)))
(define (emit-sequence emit-value values)
  (emit-i64 (length values))
  (let loop ((values values))
    (unless (null? values) (emit-value (car values)) (loop (cdr values)))))
(define (emit-mark value) (emit-i64 (mark-code value)))
(define (emit-row row) (emit-sequence emit-mark row))
(define (emit-result value)
  (emit-i64 (maze-kind value))
  (when (= (maze-kind value) 2) (emit-sequence emit-row (maze-rows value))))
(define (emit-coordinate value)
  (emit-i64 (coordinate-row value)) (emit-i64 (coordinate-column value)))
(define (emit-cavity value)
  (emit-i64 (if (open-cell? value) 1 0))
  (when (open-cell? value) (emit-coordinate value)))
(define (emit-cave-row row) (emit-sequence emit-cavity row))
(define (probe-trace n m)
  (let* ((holes (probe-holes n m)) (ordered (shuffle holes)))
    (emit-sequence emit-coordinate holes) (emit-sequence emit-coordinate ordered)
    (let loop ((holes ordered) (cave (probe-initial n m)))
      (unless (null? holes)
        (let* ((hole (car holes)) (next (try-to-pierce hole cave)))
          (emit-coordinate hole) (emit-sequence emit-cave-row next)
          (loop (cdr holes) next))))))
(: probe (-> I64 I64 I64 I64))
(define (probe command n m)
  (if (= command 0) (emit-result (make-maze n m)) (probe-trace n m)) 1)
'''
CHEZ_SHARING = """(define (probe-sharing)
  (let* ((grid (probe-initial 3 3))
         (first (list-read grid 0)) (middle (list-read grid 1)) (last (list-read grid 2))
         (label (coordinate 9 7)) (written (matrix-write grid 1 1 label))
         (row (list-read written 1)) (removed (list-remove-pos first 1))
         (appended (append first middle)))
    (for-each (lambda (value) (emit-i64 (if value 1 0)))
      (list (not (eq? written grid)) (not (eq? (cdr written) (cdr grid)))
            (eq? (cddr written) (cddr grid)) (eq? (list-read written 0) first)
            (eq? (list-read written 2) last) (not (eq? row middle))
            (not (eq? (cdr row) (cdr middle))) (eq? (cddr row) (cddr middle))
            (eq? (list-read row 1) label) (not (eq? (list-read middle 1) label))
            (not (eq? removed first)) (eq? (cdr removed) (cddr first))
            (eq? (list-remove-pos first 0) (cdr first))
            (not (eq? appended first)) (eq? (cdddr appended) middle)))))
"""


def construction_probes(source):
    functions = []
    for name, prefix in (('initial', '(cave\n'), ('holes', '(possible-holes\n')):
        binding = form(source, prefix)
        expression = binding[binding.index('\n') + 1:-1].strip()
        functions.append(f'(define (probe-{name} n m) {expression})\n')
    return ''.join(functions)


def strict_probe(source, prelude):
    interface = '''(define-extern emit-i64 "probe" "emit" (-> I64 Unit))
(define (mark-code value) (if value 1 0))
'''
    return prelude + STRICT_TYPES + COMMON + source + construction_probes(source) + interface + PROBE_COMMON


def chez_probe(source, adapted):
    helpers = CHEZ_TYPES + COMMON if adapted else '''(define-syntax : (syntax-rules () ((_ . signature) (begin))))
(define coordinate cons)
(define (coordinate-row value) (car value))
(define (coordinate-column value) (cdr value))
(define (open-cell? value) (if value #t #f))
(define (maze-kind value) (cond ((eq? value #f) 0) ((eq? value 'error) 1) (else 2)))
(define (maze-rows value) value)
'''
    mark = '(if value 1 0)' if adapted else "(if (eq? value '_) 1 0)"
    return ('(import (chezscheme))\n' + helpers + source + construction_probes(source)
            + f'(define (mark-code value) {mark})\n(define (emit-i64 value) (write value) (newline))\n'
            + PROBE_COMMON + CHEZ_SHARING.replace('(append first middle)', '(append-two first middle)' if adapted else '(append first middle)')
            + '(let* ((command (read)) (n (read)) (m (read))) (if (= command 2) (probe-sharing) (probe command n m)))\n')


PROBE_HOST = '''import fs from 'node:fs';
import assert from 'node:assert/strict';
const [artifact, command, n, m] = process.argv.slice(2);
const values = [];
const {instance} = await WebAssembly.instantiate(fs.readFileSync(artifact),
  {probe: {emit: value => values.push(Number(value))}});
instance.exports.main();
assert.equal(instance.exports.probe(BigInt(command), BigInt(n), BigInt(m)), 1n);
console.log(JSON.stringify(values));
'''


def output_fixtures():
    return ((1, 1), (1, 7), (7, 1), (3, 3), (3, 5), (5, 3), (5, 5), (11, 11),
            (0, 1), (1, 0), (2, 3), (3, 2), (-1, 3), (3, -1), (-1, -1))


def original_datum(encoded):
    kind, *values = encoded
    if kind in (0, 1):
        assert not values
        return '#f' if kind == 0 else 'error'
    assert kind == 2
    cursor, rows = iter(values), []
    for _ in range(next(cursor)):
        marks = [next(cursor) for _ in range(next(cursor))]
        assert all(mark in (0, 1) for mark in marks)
        rows.append('(' + ' '.join('_' if mark else '*' for mark in marks) + ')')
    assert list(cursor) == []
    return '(' + ' '.join(rows) + ')'


def harness_fixtures(grids):
    cases = [(f'grid-{n}-{m}', 1, n, m, original_datum(result), True)
             for (n, m), result in grids.items()]
    cases += [('zero-count', 0, 3, 3, '#f', True), ('negative-count', -1, 3, 3, '#false', True),
              ('zero-wrong', 0, 3, 3, '()', False), ('even-escaped', 1, 2, 3, '|error|', True)]
    wrong = ('((_ _ _) (* * _) (_ _ *))', '((_ _ _) (* * _) (_ _ _ _))',
             '((_ _ _) (* *))', '((_ _ _) (* * _) (_ _ _) ())', '(())', '()',
             '((_ _ _) (* * _) (_ _ #f))', '((_ . _))', '(#t)', '#((_))',
             '"error"', '"ok"', 'other', 'error', '#f', '1', '1.0')
    cases += [(f'wrong-{index}', 1, 3, 3, datum, False) for index, datum in enumerate(wrong)]
    return [(label, f'{count}\n{n}\n{m}\n{datum}\n', accepted)
            for label, count, n, m, datum, accepted in cases]
