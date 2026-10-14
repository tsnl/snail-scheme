"""Typed source adapters for graph enumeration and shared permutations."""

import itertools
import math
import re

from data_ports import form, replace


# ---- Finite graph comparisons and ordinary list operations ----

GRAPHS_COMMON = ''';; Comparison codes: less=0, equal=1, more=2; no runtime symbols.
(define (integer-zero? n) (= n 0))
(define (bool-equal? left right) (if left right (not right)))
(define (list-for-each function values)
  (unless (null? values)
    (function (car values))
    (list-for-each function (cdr values))))
'''


def graphs_kernel(source):
    source = replace(source, '(zero? ', '(integer-zero? ', 2)
    source = replace(source, '(for-each\n', '(list-for-each\n')
    source = replace(source, '((= i limit))', '((= i limit) (unit))')
    for edge in ('x->y?', 'y->x?'):
        source = replace(source, '(eq? ' + edge, '(bool-equal? ' + edge)
    source = replace(source, '(error #f "???")', '(unreachable)', 2)
    source = replace(source, '(case (cmp-next-vertex graph perm x perm-x)',
                     '(let ((comparison (cmp-next-vertex graph perm x perm-x)))\n                               (cond')
    source = replace(source, '(case (cmp-next-vertex edge? perm root root)',
                     '(let ((comparison (cmp-next-vertex edge? perm root root)))\n                     (cond')
    tags = dict(less=0, equal=1, more=2)
    source, changes = re.subn(r"(?m)^(\s*)'(less|equal|more)(?=[)\s])",
                              lambda match: match[1] + str(tags[match[2]]), source)
    if changes != 5:
        raise ValueError('expected five graph comparison results')
    for tag, value in tags.items():
        source = source.replace('((' + tag + ')', '((= comparison ' + str(value) + ')')
    source = replace(source, '((equal more)', '((or (= comparison 1) (= comparison 2))')
    return replace(source, '(unreachable))))', '(unreachable)))))', 2)


# ---- Explicit cells preserve permutation tail sharing ----

MPERM_COMMON = '''(define (integer-zero? n) (= n 0))
(define (integer-positive? n) (> n 0))
(define (integer-max a b) (if (> a b) a b))
(define (nonempty-list? value) (not (null? value)))
(define (equal-permutation? left right)
  (if (null? left) (null? right)
      (and (not (null? right)) (= (car left) (car right))
           (equal-permutation? (cdr left) (cdr right)))))
'''
MPERM_PLAN = ''';; The upstream harness is invoked after the initial queue fill.
;; Capture its work and predicate here; the host calls bench after main returns.
(define-data PermutationPlan
  (make-permutation-plan
    (work (-> (Vector (List (List I64)))) permutation-work)
    (accept (-> (Vector (List (List I64))) Bool) permutation-accept)))
(define (run-benchmark-x m n k ell thunk accept)
  (make-permutation-plan thunk accept))
'''
MPERM_INPUTS = '''(define-extern native-count "benchmark" "count" (-> I64))
(define setup-count (native-count))
(define setup-m (hide setup-count setup-count))
(define input0 (hide setup-count (native-input-i64 (ann 0 I32))))
(define input1 (hide setup-count (native-input-i64 (ann 1 I32))))
(define input2 (hide setup-count (native-input-i64 (ann 2 I32))))
(define plan (MpermNKL-benchmark setup-m input0 input1 input2))
'''
MPERM_WORKER = '''(let ((work (permutation-work plan)) (accept (permutation-accept plan)))
    (if (accept
          (let loop ((i 0) (result (ann (empty-vector) (Vector (List (List I64))))))
            (if (< i count) (loop (+ i 1) (work)) result))) 1 0))'''
MPERM_CHEZ_HARNESS = '''(define (run-benchmark-x m n k ell thunk accept)
  (run-r7rs-benchmark
    (string-append "mperm:" (number->string m) ":" (number->string n)
                   ":" (number->string k) ":" (number->string ell))
    m thunk accept))
'''


def mperm_kernel(source):
    source = replace(source, '(zero? ', '(integer-zero? ', 4)
    source = replace(source, '(positive? ', '(integer-positive? ', 2)
    source = replace(source, '(max 0 ', '(integer-max 0 ')
    source = replace(source, '(pair? ', '(nonempty-list? ', 2)
    source = replace(source, '(let ((x x)\n        (perms (list x)))',
                     '(let ((x (ref x))\n        (perms (ref (cons x \'()))))')
    source = replace(source, '(set! x (revloop x n (list-tail x n)))',
                     '(ref-set! x (revloop (ref-get x) n (list-tail (ref-get x) n)))')
    source = replace(source, '(set! perms (cons x perms))',
                     '(ref-set! perms (cons (ref-get x) (ref-get perms)))')
    source = replace(source, '(P (length x))\n    perms)',
                     '(P (length (ref-get x)))\n    (ref-get perms))')
    source = replace(source, '(<= 0 ell k)', '(and (<= 0 ell) (<= ell k))')
    source = replace(source, '(- k ell 1)', '(- (- k ell) 1)')
    source = replace(source, '(equal? (car q0) (car qi))', '(equal-permutation? (car q0) (car qi))')
    source = replace(source, '(/ (* n (+ n 1) (factorial n)) 2)',
                     '(quotient (* (* n (+ n 1)) (factorial n)) 2)')
    label = form(source, '(id (string-append "mperm:"')
    source = replace(source, '(let (' + label + '\n            (queue ', '(let ((queue ')
    source = replace(source, '(run-benchmark-x id\n                       m', '(run-benchmark-x m n k ell')
    source = replace(source, form(source, '(begin (display "Incorrect arguments'), '(unreachable)')
    return replace(source, form(source, '(define (run-benchmark-x . args)'), '')


# ---- Complete ordered values in supplemental modules ----

LIST_ENCODERS = '''(define (encode-values values tail)
  (if (null? values) tail
      (cons (car values) (encode-values (cdr values) tail))))
(define (encode-permutation values tail)
  (cons (length values) (encode-values values tail)))
(define (encode-permutations values tail)
  (define (visit values)
    (if (null? values) tail
        (encode-permutation (car values) (visit (cdr values)))))
  (cons (length values) (visit values)))
'''
GRAPH_ENCODERS = '''(define (encode-graph graph tail)
  (let loop ((index (- (vector-length graph) 1)) (result tail))
    (if (< index 0) (cons (vector-length graph) result)
        (loop (- index 1) (encode-permutation (vector-ref graph index) result)))))
(define (encode-graphs graphs)
  (define (visit graphs)
    (if (null? graphs) '()
        (encode-graph (car graphs) (visit (cdr graphs)))))
  (cons (length graphs) (visit graphs)))
'''
GRAPH_PROBE = '''(: enumeration-probe (-> I64 I64))
(define (enumeration-probe count)
  (if (same-i64-list? (encode-graphs (run input0)) (expected-list)) 1 0))
'''
MPERM_PROBE_PLAN = '''(define-data QueueProbe
  (capture-queue
    (queue (Vector (List (List I64))) captured-queue)
    (work (-> (Vector (List (List I64)))) captured-work)
    (accept (-> (Vector (List (List I64))) Bool) captured-accept)))
'''
MPERM_PROBE_CHEZ = '''(define (capture-queue queue work accept) (vector queue work accept))
(define (captured-queue plan) (vector-ref plan 0))
(define (captured-work plan) (vector-ref plan 1))
(define (captured-accept plan) (vector-ref plan 2))
'''
MPERM_QUEUE_ENCODER = '''(define (encode-queue queue tail)
  (let loop ((index (- (vector-length queue) 1)) (result tail))
    (if (< index 0) (cons (vector-length queue) result)
        (loop (- index 1) (encode-permutations (vector-ref queue index) result)))))
(define (queue-history m n k ell)
  (let* ((plan (MpermNKL-benchmark m n k ell))
         (queue (captured-queue plan)) (work (captured-work plan)))
    (let loop ((left m) (initial (encode-queue queue '())))
      (if (= left 0)
          (append-values initial (cons (if ((captured-accept plan) queue) 1 0) '()))
          (let ((result (work)))
            (if (not (vector-eq? result queue)) (unreachable)
                (append-values initial (loop (- left 1) (encode-queue result '())))))))))
(define (append-values left right)
  (if (null? left) right (cons (car left) (append-values (cdr left) right))))
'''
MPERM_PROBE = '''(: enumeration-probe (-> I64 I64))
(define (enumeration-probe count)
  (if (same-i64-list? (encode-permutations (permutations (one..n input0)) '())
                    (expected-list)) 1 0))
(: queue-probe (-> I64 I64))
(define (queue-probe count)
  (if (same-i64-list? (queue-history count input0 input1 input2) (expected-list)) 1 0))
(: predicate-probe (-> I64 I64))
(define (predicate-probe mode)
  (if (same-i64-list? (cons (predicate-result mode input0 input1 input2) '())
                    (expected-list)) 1 0))
'''
MPERM_PREDICATE_PROBE = '''(define (change-permutation-sum values)
  (cons (car values)
        (cons (cons (+ 1 (car (car (cdr values)))) (cdr (car (cdr values))))
              (cdr (cdr values)))))
(define (change-first-permutation values)
  (let ((first (car values)))
    (cons (cons (car (cdr first)) (cons (car first) (cdr (cdr first)))) (cdr values))))
(define (predicate-result mode n k ell)
  (let* ((plan (MpermNKL-benchmark 1 n k ell)) (queue ((captured-work plan)))
         (first (vector-ref queue 0)) (last (integer-max 0 (- (- k ell) 1))))
    (cond ((= mode 1) (vector-set! queue 0 (change-permutation-sum first)))
          ((= mode 2) (vector-set! queue 0 (change-first-permutation first)))
          ((= mode 3) (vector-set! queue last '()))
          ((= mode 4) (vector-set! queue 0 '()))
          ((= mode 5) (vector-set! queue 0 '()) (vector-set! queue last '()))
          (else (unit)))
    (if ((captured-accept plan) queue) 1 0)))
'''


def mperm_probe_kernel(source, adapted):
    if adapted:
        return replace(source, '(run-benchmark-x m n k ell', '(capture-queue queue')
    source = replace(source, '(run-benchmark-x id\n                       m', '(capture-queue queue')
    return replace(source, form(source, '(define (run-benchmark-x . args)'), '')


def chez_probe_source(name, kernel, helpers):
    prelude = '(import (chezscheme))\n' + helpers + '(define (vector-eq? x y) (eq? x y))\n'
    encoders = LIST_ENCODERS + (GRAPH_ENCODERS if name == 'graphs' else MPERM_QUEUE_ENCODER)
    operation = '(encode-graphs (run n))' if name == 'graphs' else "(encode-permutations (permutations (one..n n)) '())"
    if name == 'mperm':
        prelude += MPERM_PROBE_CHEZ
        encoders += MPERM_PREDICATE_PROBE
        operation = f"(cond ((= action 0) {operation}) ((= action 1) (queue-history m n k ell)) (else (list (predicate-result m n k ell))))"
    return prelude + kernel + encoders + f'''(let* ((action (read)) (m (read)) (n (read))
       (k (read)) (ell (read)) (expected (read)) (actual {operation}))
  (write (if expected (equal? actual expected) actual)) (newline))
'''


# ---- Independent finite graph and permutation oracles ----


def take_values(tokens):
    size = next(tokens)
    if size < 0:
        raise ValueError('negative sequence length')
    return [next(tokens) for _ in range(size)]


def decode_graphs(values, size):
    tokens, graphs = iter(values), []
    for _ in range(next(tokens)):
        if next(tokens) != size:
            raise ValueError('wrong graph size')
        graphs.append([take_values(tokens) for _ in range(size)])
    if next(tokens, None) is not None:
        raise ValueError('trailing graph encoding')
    return graphs


def graph_orbit(graph):
    size = len(graph)
    return min(tuple(int(permutation[to] in graph[permutation[from_]])
                     for from_ in range(size) for to in range(size))
               for prefix in itertools.permutations(range(size - 1))
               for permutation in [(*prefix, size - 1)])


def root_reaches_all(graph):
    reached, pending = set(), [len(graph) - 1]
    while pending:
        vertex = pending.pop()
        if vertex not in reached:
            reached.add(vertex)
            pending.extend(graph[vertex])
    return len(reached) == len(graph)


def check_graphs(values, size):
    graphs = decode_graphs(values, size)
    for graph in graphs:
        if any(len(row) > 2 or len(set(row)) != len(row) or vertex in row or size - 1 in row
               or any(edge < 0 or edge >= size for edge in row) for vertex, row in enumerate(graph)):
            raise ValueError('invalid bounded graph edge list')
        if not root_reaches_all(graph):
            raise ValueError('graph is not reachable from the distinguished root')
    orbits = {graph_orbit(graph) for graph in graphs}
    if len(orbits) != len(graphs) or orbits != exhaustive_graph_orbits(size):
        raise ValueError('missing or duplicate graph isomorphism class')
    return dict(graphs=len(graphs), all_values_checked=True, exhaustive_orbits=len(orbits))


def exhaustive_graph_orbits(size):
    rows = [[list(edges) for degree in range(min(2, size - 1) + 1)
             for edges in itertools.combinations([other for other in range(size - 1) if other != vertex], degree)]
            for vertex in range(size)]
    return {graph_orbit(graph) for graph in itertools.product(*rows) if root_reaches_all(graph)}


def permutation_values(size):
    current, result = list(range(1, size + 1)), []

    def visit(n):
        if n > 1:
            for _ in range(n - 1):
                visit(n - 1)
                current[:n] = reversed(current[:n])
                result.append(list(current))
            visit(n - 1)

    result.append(list(current))
    visit(size)
    return list(reversed(result))


def encode_permutations(values):
    return [len(values), *(item for value in values for item in [len(value), *value])]


def queue_values(m, n, k, ell):
    permutations = permutation_values(n)
    queue, result = [permutations if i < k - ell else [] for i in range(k)], []
    for step in range(m + 1):
        result += [k, *(value for entry in queue for value in encode_permutations(entry))]
        if step != m:
            queue[k - ell:] = [permutations] * ell
            queue = queue[ell:] + [[]] * ell
    return result + [int(ell < k)]


def check_permutations(values, size):
    expected = encode_permutations(permutation_values(size))
    if values != expected or expected[0] != math.factorial(size):
        raise ValueError('incorrect complete permutation sequence')
    return dict(permutations=expected[0], all_values_checked=True,
                sum=expected[0] * size * (size + 1) // 2)
