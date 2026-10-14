"""Concrete result/cell adaptation and complete validation for upstream simplex."""

import math
import re
from fractions import Fraction
from itertools import combinations

from data_ports import form, replace


# ---- Scalar arithmetic and a closed result ----

STRICT_TYPES = '''(define-data SimplexResult
  (simplex-infeasible)
  (simplex-unbounded)
  (simplex-solved (values (List (Vector I64)) simplex-values)))
(define (list first second) (cons first (cons second '())))
;; These source-level overloads preserve the original arithmetic expressions.
;; Subtracting from negative zero also negates both signed zeros correctly.
(define-overload - (-> F64 F64) (lambda (x) (f64-sub -0.0 x)))
(define-overload / (-> F64 F64) (lambda (x) (f64-div 1.0 x)))
(define-overload + (-> I64 I64 I64 I64) (lambda (a b c) (+ (+ a b) c)))
(define-overload + (-> I64 I64 I64 I64 I64) (lambda (a b c d) (+ (+ (+ a b) c) d)))
(define-overload positive? (-> I64 Bool) (lambda (x) (> x 0)))
(define-overload positive? (-> F64 Bool) (lambda (x) (> x 0.0)))
(define (negative? x) (< x 0.0))
(define (zero? x) (= x 0))
(define (abs x) (if (= x 0.0) 0.0 (if (< x 0.0) (- x) x)))
'''
CHEZ_RESULTS = '''(define (simplex-infeasible) (vector 0))
(define (simplex-unbounded) (vector 1))
(define (simplex-solved values) (vector 2 values))
(define (simplex-original-value result)
  (case (vector-ref result 0)
    ((0) #f) ((1) #t) ((2) (vector-ref result 1))))
(define (unreachable) (error #f "This shouldn't happen"))
'''


def control_prelude(source):
    source = replace(source, '(syntax-rules (else)\n',
                     '(syntax-rules (else)\n    ((_) (unit))\n')
    return replace(source, '(define-syntax do\n  (syntax-rules ()\n',
                   '(define-syntax do\n  (syntax-rules ()\n'
                   '    ((_ bindings (test) body ...) (do bindings (test (unit)) body ...))\n')


# ---- Exact source edits keep the pivot algorithm visible ----

CELL_BINDINGS = (
    ('nl1', 'n', 1), ('ip', '0', 5), ('kp', '0', 2), ('bmax', '0.0', 2),
    ('one?', '#f', 4), ('pass2?', '#t', 3), ('q1', '0.0', 2),
    ('flag?', '#f', 1), ('qp', '0.0', 1), ('q0', '0.0', 1),
)


def explicit_cell(source, name, initializer, stores):
    # The ten binding names are unique after the simp3 parameter rename.
    # Preserve comments and strings; rewrite reads, then its binder and stores.
    tokens = r'"(?:[^"\\]|\\.)*"|;[^\n]*|[^\s()]+'
    source = re.sub(tokens, lambda token: '(ref-get ' + name + ')'
                    if token[0] == name else token[0], source)
    source = replace(source, '((ref-get ' + name + ') ' + initializer + ')',
                     '(' + name + ' (ref ' + initializer + '))')
    return replace(source, '(set! (ref-get ' + name + ')', '(ref-set! ' + name, stores)


def result_cases(source):
    final = form(source, '(and pass2?')
    body = final[len('(and pass2?'):-1]
    source = replace(source, final, '(if pass2?' + body + '\n         (simplex-infeasible))')
    source = replace(source, '((zero? ip) #t)', '((zero? ip) (simplex-unbounded))')
    return replace(source, '(list iposv izrov)', '(simplex-solved (list iposv izrov))')


def kernel(source):
    source = replace(source, '(error #f "This shouldn\'t happen")', '(unreachable)')
    pivot = form(source, '(define (simp3 one?)')
    renamed = replace(pivot, '(simp3 one?)', '(simp3 phase-one?)')
    renamed = replace(renamed, '(if one? 2 1)', '(if phase-one? 2 1)')
    source = result_cases(replace(source, pivot, renamed))
    for name, initializer, stores in CELL_BINDINGS:
        source = explicit_cell(source, name, initializer, stores)
    if '(set!' in source:
        raise ValueError('unadapted simplex scalar assignment')
    return source


# ---- Original complete predicate over the concrete solved payload ----

EXPECTED_PRELUDE = '''(define-extern native-expected-length "benchmark" "expected_length" (-> I64))
(define-extern native-expected-i64 "benchmark" "expected_i64" (-> I64 I64))
(define (expected-integer cursor)
  (let ((value (native-expected-i64 (ref-get cursor))))
    (ref-set! cursor (+ (ref-get cursor) 1))
    value))
(define (expected-index-vector cursor)
  (let* ((size (expected-integer cursor)) (result (make-vector size 0)))
    (let loop ((index 0))
      (if (= index size) result
          (begin (vector-set! result index (expected-integer cursor))
                 (loop (+ index 1)))))))
(define (expected-index-vectors)
  (let* ((cursor (ref 0)) (size (expected-integer cursor)))
    (let loop ((left size))
      (if (= left 0)
          (if (= (ref-get cursor) (native-expected-length)) '() (unreachable))
          (let ((row (expected-index-vector cursor)))
            (cons row (loop (- left 1))))))))
'''
PREDICATE = '''(define (same-index-vector? left right)
  (and (= (vector-length left) (vector-length right))
       (let loop ((index 0))
         (or (= index (vector-length left))
             (and (= (vector-ref left index) (vector-ref right index))
                  (loop (+ index 1)))))))
(define (same-index-vectors? left right)
  (if (null? left) (null? right)
      (and (not (null? right)) (same-index-vector? (car left) (car right))
           (same-index-vectors? (cdr left) (cdr right)))))
(define (simplex-accepted? result expected)
  (match result
    ((simplex-infeasible) #f)
    ((simplex-unbounded) #f)
    ((simplex-solved values) (same-index-vectors? values expected))))
'''


def encoded_expected(vectors):
    return [len(vectors), *(value for row in vectors for value in [len(row), *row])]


def worker():
    return '''(if (simplex-accepted?
    (let loop ((i 0) (result (simplex-infeasible)))
      (if (< i count) (loop (+ i 1) (test (hide count input0))) result)) expected) 1 0)'''


# ---- Separate complete-result and ordered-mutation probes ----

PROBE_COMMON = '''(define writes (ref (ann '() (List F64))))
(define (record-matrix-write i j value)
  (ref-set! writes (cons value (cons (i64->f64 j) (cons (i64->f64 i) (ref-get writes))))))
(define (reverse-floats values tail)
  (if (null? values) tail (reverse-floats (cdr values) (cons (car values) tail))))
(define (encode-float-vector values tail)
  (let loop ((i (- (vector-length values) 1)) (result tail))
    (if (< i 0) (cons (i64->f64 (vector-length values)) result)
        (loop (- i 1) (cons (vector-ref values i) result)))))
(define (encode-index-vector values tail)
  (let loop ((i (- (vector-length values) 1)) (result tail))
    (if (< i 0) (cons (i64->f64 (vector-length values)) result)
        (loop (- i 1) (cons (i64->f64 (vector-ref values i)) result)))))
(define (encode-index-vectors values tail)
  (define (visit values)
    (if (null? values) tail (encode-index-vector (car values) (visit (cdr values)))))
  (cons (i64->f64 (length values)) (visit values)))
(define (encode-tableau matrix tail)
  (let loop ((i (- (vector-length matrix) 1)) (result tail))
    (if (< i 0) (cons (i64->f64 (vector-length matrix)) result)
        (loop (- i 1) (encode-float-vector (vector-ref matrix i) result)))))
(define (same-float? left right)
  (and (= left right)
       (or (not (= left 0.0)) (= (/ 1.0 left) (/ 1.0 right)))))
(define (same-floats? left right)
  (if (null? left) (null? right)
      (and (not (null? right)) (same-float? (car left) (car right))
           (same-floats? (cdr left) (cdr right)))))
'''
STRICT_ENCODER = '''(define (encode-simplex result tail)
  (match result
    ((simplex-infeasible) (cons 0.0 tail))
    ((simplex-unbounded) (cons 1.0 tail))
    ((simplex-solved values) (cons 2.0 (encode-index-vectors values tail)))))
'''
CHEZ_ENCODER = '''(define (encode-simplex result tail)
  (cond ((eq? result #f) (cons 0.0 tail))
        ((eq? result #t) (cons 1.0 tail))
        (else (cons 2.0 (encode-index-vectors result tail)))))
'''
PREDICATE_PROBE = '''(define (predicate-result mode)
  (let ((first (vector 4 1 3 2)) (second (vector 0 5 7 6)))
    (cond ((= mode 0) (simplex-solved (list first second)))
          ((= mode 1) (simplex-infeasible))
          ((= mode 2) (simplex-unbounded))
          ((= mode 3) (simplex-solved '()))
          ((= mode 4) (simplex-solved (cons first (list second first))))
          ((= mode 5) (simplex-solved (list (vector 4 1 3) second)))
          ((= mode 6) (simplex-solved (list first (vector 0 5 7 6 0))))
          ((= mode 7) (simplex-solved (list (vector 5 1 3 2) second)))
          ((= mode 8) (simplex-solved (list (vector 4 1 4 2) second)))
          ((= mode 9) (simplex-solved (list first (vector 0 5 7 5))))
          ((= mode 10) (simplex-solved (list second first)))
          (else (unreachable)))))
(define (simplex-predicate-probe mode)
  (if (simplex-accepted? (predicate-result mode)
                       (list (vector 4 1 3 2) (vector 0 5 7 6))) 1 0))
'''
PROBE_RESULT = '''(define (probe-result matrix m1 m2 m3)
  (ref-set! writes '())
  (let ((result (simplex matrix m1 m2 m3)))
    (encode-simplex result
      (encode-tableau matrix
        (cons (i64->f64 (length (ref-get writes)))
              (reverse-floats (ref-get writes) '()))))))
'''
PROBE_INPUTS = '''(define-extern native-vector-f64 "benchmark" "vector_f64" (-> I32 I64 F64))
(define-extern native-expected-f64 "benchmark" "expected_f64" (-> I64 F64))
(define-extern native-expected-length "benchmark" "expected_length" (-> I64))
(define (input-tableau)
  (let* ((rows (native-input-i64 (ann 3 I32)))
         (columns (native-input-i64 (ann 4 I32)))
         (matrix (make-vector rows (ann (empty-vector) (Vector F64)))))
    (let row ((i 0))
      (if (= i rows) matrix
          (let ((values (make-vector columns 0.0)))
            (let column ((j 0))
              (unless (= j columns)
                (vector-set! values j (native-vector-f64 (ann 5 I32) (+ (* i columns) j)))
                (column (+ j 1))))
            (vector-set! matrix i values)
            (row (+ i 1)))))))
(define (expected-floats)
  (let loop ((i (native-expected-length)) (result '()))
    (if (= i 0) result
        (loop (- i 1) (cons (native-expected-f64 (- i 1)) result)))))
(: simplex-probe (-> I64 I64))
(define (simplex-probe ignored)
  (if (same-floats?
        (probe-result (input-tableau) (native-input-i64 (ann 0 I32))
                      (native-input-i64 (ann 1 I32)) (native-input-i64 (ann 2 I32)))
        (expected-floats)) 1 0))
'''
CHEZ_PROBE_INPUT = '''(let* ((action (read)) (matrix (read))
         (m1 (read)) (m2 (read)) (m3 (read)) (expected (read)))
  (write (if (= action 2) (simplex-predicate-probe m1)
             (let ((actual (probe-result matrix m1 m2 m3)))
               (if (= action 0) actual (same-floats? actual expected)))))
  (newline))
'''


def traced_kernel(source):
    return replace(source, '(vector-set! (vector-ref a i) j x)',
                   '(begin (vector-set! (vector-ref a i) j x) (record-matrix-write i j x))')


def chez_probe_source(source, adapted, ref_helpers):
    compatibility = '''(define-syntax ann (syntax-rules () ((_ value type) value)))
(define (i64->f64 x) (inexact x))
'''
    result = replace(PROBE_RESULT, '(encode-simplex result', '(encode-simplex (simplex-original-value result)') if adapted else PROBE_RESULT
    original_results = '''(define (simplex-infeasible) #f)
(define (simplex-unbounded) #t)
(define (simplex-solved values) values)
(define (unreachable) (error #f "invalid predicate probe"))
'''
    predicate = '(define (simplex-accepted? result expected) (equal? VALUE expected))\n'
    predicate = predicate.replace('VALUE', '(simplex-original-value result)' if adapted else 'result')
    helpers = ref_helpers + compatibility + (CHEZ_RESULTS if adapted else original_results)
    return ('(import (chezscheme))\n' + helpers + PROBE_COMMON + traced_kernel(source)
            + CHEZ_ENCODER + result + predicate + PREDICATE_PROBE + CHEZ_PROBE_INPUT)


def probe_input(case, expected=None):
    rows = ['#(' + ' '.join(map(repr, row)) + ')' for row in case['matrix']]
    matrix = '#(' + ' '.join(rows) + ')'
    data = [str(int(expected is not None)), matrix, *map(str, case['counts'])]
    data.append('#f' if expected is None else '(' + ' '.join(map(repr, expected)) + ')')
    return '\n'.join(data) + '\n'


def probe_specification(case, expected):
    matrix = case['matrix']
    return dict(name='simplex-probe', count=1,
                inputs=[*case['counts'], len(matrix), len(matrix[0]),
                        [value for row in matrix for value in row]],
                expected=expected, result_kind='f64-vector-values',
                export='simplex-probe', barriers_per_iteration=0)


def fixtures():
    # Each matrix is objective row, original constraints, auxiliary row.
    data = [
        ('bounded-one', (1, 0, 0), [[0, 1], [2, -1], [0, 0]]),
        ('bounded-two', (2, 0, 0), [[0, 1, 2], [2, -1, 0], [3, 0, -1], [0, 0, 0]]),
        ('ratio-tie', (2, 0, 0), [[0, 1, 0], [2, -1, -1], [2, -1, 0], [0, 0, 0]]),
        ('duplicate-constraint', (2, 0, 0), [[0, 1], [2, -1], [2, -1], [0, 0]]),
        ('greater-equal', (1, 1, 0), [[0, 1], [3, -1], [1, -1], [0, 0]]),
        ('equality', (0, 0, 1), [[0, 1], [2, -1], [0, 0]]),
        ('zero-equality', (0, 0, 1), [[0, -1], [0, -1], [0, 0]]),
        ('infeasible', (1, 1, 0), [[0, 1], [1, -1], [2, -1], [0, 0]]),
        ('unbounded', (0, 0, 0), [[0, 1], [0, 0]]),
        ('unbounded-after-pivot', (1, 0, 0), [[0, 1, 1], [1, -1, 0], [0, 0, 0]]),
        ('no-improvement', (1, 0, 0), [[0, -1], [2, -1], [0, 0]]),
        ('canonical-tableau', (2, 1, 1),
         [[0, 1, 1, 3, -0.5], [740, -1, 0, -2, 0], [0, 0, -2, 0, 7],
          [0.5, 0, -1, 1, -2], [9, -1, -1, -1, -1], [0, 0, 0, 0, 0]]),
    ]
    result = [dict(label=label, counts=list(counts), matrix=[list(map(float, row)) for row in matrix])
              for label, counts, matrix in data]
    result[5]['source_discrepancy'] = dict(source_status=1, independent_status=2,
        reason='Phase one removes the only candidate, but simp1 still reads l1[0] when nl1 is zero.')
    return result


# ---- Independent small rational linear-program oracle ----

def solve_equations(rows, rhs):
    matrix = [list(row) + [value] for row, value in zip(rows, rhs)]
    for column in range(len(rows)):
        pivot = next((i for i in range(column, len(rows)) if matrix[i][column]), None)
        if pivot is None:
            return None
        matrix[column], matrix[pivot] = matrix[pivot], matrix[column]
        divisor = matrix[column][column]
        matrix[column] = [value / divisor for value in matrix[column]]
        for i in range(len(rows)):
            if i != column:
                factor = matrix[i][column]
                matrix[i] = [a - factor * b for a, b in zip(matrix[i], matrix[column])]
    return [row[-1] for row in matrix]


def constraints(case):
    m1, m2, _ = case['counts']
    result = []
    for index, row in enumerate(case['matrix'][1:-1]):
        kind = '<=' if index < m1 else '>=' if index < m1 + m2 else '='
        result.append(([-Fraction(str(x)) for x in row[1:]], Fraction(str(row[0])), kind))
    return result


def feasible(point, rows):
    if any(x < 0 for x in point):
        return False
    for coefficients, rhs, kind in rows:
        value = sum(a * x for a, x in zip(coefficients, point))
        if (value > rhs if kind == '<=' else value < rhs if kind == '>=' else value != rhs):
            return False
    return True


def vertices(rows, size, normalized=False):
    axes = [([Fraction(int(i == j)) for j in range(size)], Fraction(0)) for i in range(size)]
    boundaries = [(a, b) for a, b, _ in rows] + axes
    prefix = [([Fraction(1)] * size, Fraction(1))] if normalized else []
    result = []
    for selected in combinations(boundaries, size - len(prefix)):
        equations = prefix + list(selected)
        point = solve_equations([a for a, _ in equations], [b for _, b in equations])
        if point is not None and feasible(point, rows):
            result.append(point)
    return result


def independent_lp(case):
    rows, objective = constraints(case), [Fraction(str(x)) for x in case['matrix'][0][1:]]
    points = vertices(rows, len(objective))
    if not points:
        return dict(status=0, explanation='No feasible vertex in the nonnegative orthant.')
    rays = vertices([(a, Fraction(0), kind) for a, _, kind in rows], len(objective), normalized=True)
    improving = next((ray for ray in rays if sum(a * x for a, x in zip(objective, ray)) > 0), None)
    if improving is not None:
        return dict(status=1, feasible_point=list(map(str, points[0])), improving_ray=list(map(str, improving)))
    value = max(sum(a * x for a, x in zip(objective, point)) for point in points)
    value += Fraction(str(case['matrix'][0][0]))
    return dict(status=2, objective=str(value), feasible_vertices=len(points))


# ---- Decode every field and replay every recorded matrix store ----

def decode_probe(values):
    stream = iter(values)
    def count():
        value = next(stream)
        if not math.isfinite(value) or value < 0 or value != int(value):
            raise ValueError('invalid encoded count or index')
        return int(value)
    status = count()
    vectors = [[count() for _ in range(count())] for _ in range(count())] if status == 2 else None
    matrix = [[next(stream) for _ in range(count())] for _ in range(count())]
    writes = [next(stream) for _ in range(count())]
    if status not in (0, 1, 2) or list(stream) or len(writes) % 3:
        raise ValueError('invalid complete simplex encoding')
    return dict(status=status, vectors=vectors, matrix=matrix, writes=writes)


def check_store_replay(case, decoded):
    matrix = [row.copy() for row in case['matrix']]
    for offset in range(0, len(decoded['writes']), 3):
        i, j, value = decoded['writes'][offset:offset + 3]
        if i != int(i) or j != int(j) or not (0 <= i < len(matrix) and 0 <= j < len(matrix[int(i)])):
            raise ValueError('invalid matrix store coordinate')
        matrix[int(i)][int(j)] = value
    actual = [[value.hex() for value in row] for row in decoded['matrix']]
    if actual != [[value.hex() for value in row] for row in matrix]:
        raise ValueError('recorded stores do not reconstruct every final tableau element')


def check_solution(case, decoded, oracle):
    basic, nonbasic = decoded['vectors']
    size, rows = len(case['matrix'][0]) - 1, len(case['matrix']) - 2
    if len(basic) != rows or len(nonbasic) != size or sorted(basic + nonbasic) != list(range(size + rows)):
        raise ValueError('basis/nonbasis are not the complete variable partition')
    point = [0.0] * size
    for i, variable in enumerate(basic):
        if variable < size:
            point[variable] = decoded['matrix'][i + 1][0]
    objective = case['matrix'][0][0] + sum(a * x for a, x in zip(case['matrix'][0][1:], point))
    if not all(math.isclose(value, float(Fraction(oracle['objective'])), rel_tol=1e-12, abs_tol=1e-12)
               for value in (objective, decoded['matrix'][0][0])):
        raise ValueError('basis objective differs from independent rational optimum')
    for coefficients, rhs, kind in constraints(case):
        slack = sum(float(a) * x for a, x in zip(coefficients, point)) - float(rhs)
        if (slack > 1e-12 if kind == '<=' else slack < -1e-12 if kind == '>=' else abs(slack) > 1e-12):
            raise ValueError('returned basis is not feasible')
    if any(value < -1e-12 for value in point):
        raise ValueError('returned basis has a negative original variable')


def check_oracle(case, values):
    decoded, oracle = decode_probe(values), independent_lp(case)
    discrepancy = case.get('source_discrepancy')
    if discrepancy:
        if decoded['status'] != discrepancy['source_status'] or oracle['status'] != discrepancy['independent_status']:
            raise ValueError('recorded upstream discrepancy changed')
    elif decoded['status'] != oracle['status']:
        raise ValueError('original simplex status disagrees with independent rational LP')
    check_store_replay(case, decoded)
    if decoded['status'] == 2:
        check_solution(case, decoded, oracle)
    return dict(independent_lp=oracle, complete_values_checked=True,
                source_status=decoded['status'], source_matches_independent=decoded['status'] == oracle['status'],
                source_discrepancy=discrepancy,
                ordered_matrix_stores=len(decoded['writes']) // 3)


def invalid_fixtures():
    original = fixtures()[0]
    result = []
    for index in range(3):
        counts = original['counts'].copy()
        counts[index] = -1
        result.append(dict(original, label='negative-m' + str(index + 1), counts=counts))
    result.append(dict(original, label='wrong-row-count', counts=[2, 0, 0]))
    result.append(dict(original, label='negative-rhs', matrix=[[0.0, 1.0], [-1.0, -1.0], [0.0, 0.0]]))
    return result


def encoded_payload_positions(values):
    # The canonical solved value has two index vectors, then all matrix rows.
    if values[:2] != [2.0, 2.0]:
        raise ValueError('negative probes require a solved two-vector result')
    cursor, vectors = 2, []
    for _ in range(2):
        size = int(values[cursor])
        vectors.append(list(range(cursor + 1, cursor + size + 1)))
        cursor += size + 1
    rows, matrix = int(values[cursor]), []
    cursor += 1
    for _ in range(rows):
        size = int(values[cursor])
        matrix.extend(range(cursor + 1, cursor + size + 1))
        cursor += size + 1
    return vectors, matrix, cursor + 1


def changed_expectations(values):
    vectors, matrix, trace = encoded_payload_positions(values)
    positions = [('status', 0), ('result-length', 1), ('basis-length', 2),
                 ('basis-first', vectors[0][0]), ('basis-middle', vectors[0][2]),
                 ('nonbasis-last', vectors[1][-1]), ('tableau-first', matrix[0]),
                 ('tableau-middle', matrix[len(matrix) // 2]), ('tableau-last', matrix[-1]),
                 ('store-coordinate', trace), ('store-value', trace + 2), ('last-store', len(values) - 1)]
    result = [('short-output', values[:-1]), ('long-output', values + [0.0])]
    for label, index in positions:
        changed = values.copy()
        changed[index] += 1.0
        result.append((label, changed))
    changed = values.copy()
    changed[trace:trace + 6] = values[trace + 3:trace + 6] + values[trace:trace + 3]
    result.append(('reordered-stores', changed))
    changed = values.copy()
    index = next(i for i in matrix if values[i] == 0.0)
    changed[index] = -values[index]
    return result + [('signed-zero', changed)]
