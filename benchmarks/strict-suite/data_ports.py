"""Source-preserving adapters and structural oracles for the two data ports."""

import re


# ---- Exact source edits ----


def replace(source, old, new, count=1):
    if source.count(old) != count:
        raise ValueError(f'expected {count} source occurrences of {old!r}')
    return source.replace(old, new)


def form(source, prefix):
    if source.count(prefix) != 1:
        raise ValueError(f'expected one form starting with {prefix!r}')
    start, depth = source.index(prefix), 0
    for token in re.finditer(r'"(?:[^"\\]|\\.)*"|;[^\n]*|[()]', source[start:]):
        depth += (token.group() == '(') - (token.group() == ')')
        if depth == 0:
            return source[start:start + token.end()]
    raise ValueError('unclosed source form')


# ---- Closed immutable paraffin variants ----

PARAFFINS_SCHEMA = """(define-data Radical (H) (C (first Radical) (second Radical) (third Radical)))
(define-data Paraffin
  (BCP (first Radical) (second Radical))
  (CCP (first Radical) (second Radical) (third Radical) (fourth Radical)))
"""
PARAFFINS_PRELUDE = PARAFFINS_SCHEMA + """(define (max a b) (if (> a b) a b))
(define (odd? n) (not (= (remainder n 2) 0)))
"""
PARAFFINS_CHEZ = """(define (H) (vector 'H))
(define (C a b c) (vector 'C a b c))
(define (BCP a b) (vector 'BCP a b))
(define (CCP a b c d) (vector 'CCP a b c d))
"""


def paraffins_kernel(source):
    source = replace(source, "'(H)", "(cons (H) '())")
    for tag in ('CCP', 'BCP', 'C'):
        source = replace(source, "(vector '" + tag, '(' + tag)
    return source


# Prefix tags are H=0, C=1, BCP=2, CCP=3. Each list starts with its
# product count. This preserves every branch and the canonical output order.
PARAFFINS_ENCODER = """(define (encode-radical value tail)
  (match value
    ((H) (cons 0 tail))
    ((C a b c) (cons 1 (encode-radical a (encode-radical b (encode-radical c tail)))))))
(define (encode-paraffin value tail)
  (match value
    ((BCP a b) (cons 2 (encode-radical a (encode-radical b tail))))
    ((CCP a b c d)
     (cons 3 (encode-radical a (encode-radical b (encode-radical c (encode-radical d tail))))))))
(define (encode-products values tail)
  (if (null? values) tail
      (encode-paraffin (car values) (encode-products (cdr values) tail))))
(define (encode-result result)
  (let ((first (vector-ref result 0)) (second (vector-ref result 1)))
    (cons (length first) (encode-products first (cons (length second) (encode-products second '()))))))
"""
PARAFFINS_PROBE = PARAFFINS_ENCODER + """(: paraffins-probe (-> I64 I64))
(define (paraffins-probe count)
  (if (same-i64-list? (encode-result (gen input0)) (expected-list)) 1 0))
"""
PARAFFINS_CHEZ_ENCODER = """(define (encode-radical value tail)
  (if (hydrogen? value) (cons 0 tail)
      (cons 1 (encode-radical (vector-ref value 1)
                 (encode-radical (vector-ref value 2) (encode-radical (vector-ref value 3) tail))))))
(define (encode-paraffin value tail)
  (let ((tail (if (eq? (vector-ref value 0) 'CCP)
                  (encode-radical (vector-ref value 3) (encode-radical (vector-ref value 4) tail)) tail)))
    (cons (if (eq? (vector-ref value 0) 'BCP) 2 3)
          (encode-radical (vector-ref value 1) (encode-radical (vector-ref value 2) tail)))))
""" + PARAFFINS_ENCODER[PARAFFINS_ENCODER.index('(define (encode-products'):]


def paraffins_chez_probe(kernel, adapted):
    hydrogen = "(eq? (vector-ref value 0) 'H)" if adapted else "(eq? value 'H)"
    return ('(import (chezscheme))\n' + (PARAFFINS_CHEZ if adapted else '') + kernel
            + '(define (hydrogen? value) ' + hydrogen + ')\n' + PARAFFINS_CHEZ_ENCODER
            + '(let* ((n (read)) (expected (read)) (actual (encode-result (gen n))))\n'
            + '  (write (if expected (equal? actual expected) actual)) (newline))\n')


def radical_carbons(tokens):
    tag = next(tokens)
    if tag == 0:
        return 0
    if tag != 1:
        raise ValueError('invalid radical prefix tag')
    return 1 + sum(radical_carbons(tokens) for _ in range(3))


def check_paraffins_encoding(values, carbons, expected_count):
    tokens, count = iter(values), 0
    for tag, arity, center in ((2, 2, 0), (3, 4, 1)):
        size = next(tokens)
        if size < 0:
            raise ValueError('negative product count')
        for _ in range(size):
            if next(tokens) != tag or center + sum(radical_carbons(tokens) for _ in range(arity)) != carbons:
                raise ValueError('wrong paraffin variant or carbon count')
        count += size
    if next(tokens, None) is not None or count != expected_count:
        raise ValueError('wrong total product count or trailing encoding')


# ---- Explicit Ref edges and preserved diagnostics in gcbench ----

GC_TEXT = ['\n', ' Total memory available= ???????? bytes', '  Free memory= ???????? bytes',
           'Garbage Collector Test', 'GCBench: Top down construction',
           'GCBench: Bottom up construction', 'GCBench: Main', 'Failed']
GC_SIZES = [(' Stretching memory with a binary tree of depth ', ''),
            (' Creating a long-lived binary tree of depth ', ''),
            (' Creating a long-lived array of ', ' inexact reals')]
GC_SCHEMA = """(define-data classNode
  (Nil)
  (make-node-cells (left (Ref classNode) node.left-cell)
                   (right (Ref classNode) node.right-cell)
                   (i I64 node.i) (j I64 node.j)))
(define (empty-node? node)
  (match node ((Nil) #t) ((make-node-cells left right i j) #f)))
(define (classNode? node) (not (empty-node? node)))
"""
GC_COMMON = """(define (make-node-raw left right i j) (make-node-cells (ref left) (ref right) i j))
(define (node.left node) (ref-get (node.left-cell node)))
(define (node.right node) (ref-get (node.right-cell node)))
(define (node.left-set! node value) (ref-set! (node.left-cell node) value))
(define (node.right-set! node value) (ref-set! (node.right-cell node) value))
(define (power-of-two n)
  (let loop ((n n) (value 1)) (if (= n 0) value (loop (- n 1) (* value 2)))))
"""
GCBENCH_PRELUDE = GC_SCHEMA + GC_COMMON + """(define (min a b) (if (< a b) a b))
(define (inexact n) (i64->f64 n))
(define-extern print-text "benchmark" "print_text" (-> I64 Unit))
(define-extern print-size "benchmark" "print_size" (-> I64 I64 Unit))
(define-extern print-construction "benchmark" "print_construction" (-> I64 I64 Unit))
"""
GC_CHEZ_RECORDS = """(r6rs:define-record-type (classNil Nil empty-node?) (fields))
(r6rs:define-record-type (classNode make-node-cells classNode?)
  (fields (immutable left node.left-cell) (immutable right node.right-cell)
          (immutable i node.i) (immutable j node.j)))
(define (unit) (if #f #f))
"""


def gc_print_kernel(source):
    source = replace(source, '(display name)', '(print-text name)')
    source = replace(source, '(newline)', '(print-text 0)', 8)
    source = replace(source, form(source, '(display (string-append "Creating '),
                     '(print-construction iNumIters depth)')
    for index, variable in enumerate(('kStretchTreeDepth', 'kLongLivedTreeDepth', 'kArraySize')):
        prefix = '(display (string-append' + ('\n                  ' if index == 0 else '\n                     ' if index == 1 else '\n                       ')
        source = replace(source, form(source, prefix + '"' + GC_SIZES[index][0]), f'(print-size {index} {variable})')
    for index, text in enumerate(GC_TEXT[1:], 1):
        literal = '"' + text + '"'
        source = replace(source, '(display ' + literal + ')', f'(print-text {index})') if '(display ' + literal + ')' in source else replace(source, literal, str(index))
    return source


def gcbench_kernel(source):
    source = replace(source, form(source, '(define-record-type classNode'), '(define nil (Nil))')
    source = replace(source, '(make-node-raw 0 0 0 0)', '(make-node-raw nil nil 0 0)')
    source = replace(source, '(expt 2 (+ i 1))', '(power-of-two (+ i 1))')
    source = replace(source, "(eq? longLivedTree '())", '(empty-node? longLivedTree)')
    source = replace(source, '            #f\n', '            (unit)\n')
    for old, new, count in (('((>= i iNumIters))', '((>= i iNumIters) (unit))', 2),
                            ('((>= i (quotient kArraySize 2)))', '((>= i (quotient kArraySize 2)) (unit))', 1),
                            ('((> d kMaxTreeDepth))', '((> d kMaxTreeDepth) (unit))', 1)):
        source = replace(source, old, new, count)
    return gc_print_kernel(source)


def gc_chez_helpers():
    texts = '#(' + ' '.join('"' + text.replace('\n', '\\n') + '"' for text in GC_TEXT) + ')'
    sizes = '#(' + ' '.join('( "' + start + '" . "' + end + '")' for start, end in GC_SIZES) + ')'
    return GC_CHEZ_RECORDS + GC_COMMON + f"""(define diagnostic-text '{texts})
(define diagnostic-sizes '{sizes})
(define (print-text code) (display (vector-ref diagnostic-text code)))
(define (print-size code value)
  (let ((parts (vector-ref diagnostic-sizes code)))
    (display (string-append (car parts) (number->string value) (cdr parts)))))
(define (print-construction iters depth)
  (display (string-append "Creating " (number->string iters) " trees of depth " (number->string depth))))
"""


# ---- Supplemental gcbench traversal, outside the measured program ----

GC_OBSERVERS = '''(define (valid-tree? depth node)
  (and (classNode? node) (= (node.i node) 0) (= (node.j node) 0)
       (if (= depth 0)
           (and (empty-node? (node.left node)) (empty-node? (node.right node)))
           (and (valid-tree? (- depth 1) (node.left node))
                (valid-tree? (- depth 1) (node.right node))))))
(define (observe-tree phase depth node)
  (emit-event phase depth (valid-tree? depth node)))
(define (observe-array array)
  (emit-event 4 (vector-length array)
    (and (= (vector-length array) (vector-length expected-array))
         (let loop ((i 0))
           (or (= i (vector-length array))
               (and (= (vector-ref array i) (vector-ref expected-array i)) (loop (+ i 1))))))))
'''
GC_EDGE_PROBES = '''(let ((leaf (make-empty-node)))
  (emit-event 5 0 (and (valid-tree? 0 leaf) (not (valid-tree? 1 leaf))))
  (node.left-set! leaf (make-empty-node))
  (emit-event 6 0 (and (not (valid-tree? 0 leaf)) (empty-node? (node.right leaf))))
  (node.right-set! leaf (make-empty-node))
  (emit-event 7 1 (valid-tree? 1 leaf))
  (emit-event 8 0 (not (valid-tree? 0 (make-node-raw nil nil 1 0)))))
'''
GC_EVENT_HELPERS = '''(define (emit-event phase depth valid)
  (ref-set! events (cons (if valid 1 0) (cons depth (cons phase (ref-get events))))))
(define (event-list)
  (let loop ((xs (ref-get events)) (result '()))
    (if (null? xs) result (loop (cdr xs) (cons (car xs) result)))))
'''
GC_PROBE_END = '''(: bench (-> I64 I64))
(define (bench count)
  (gcbench input0)
  (if (same-i64-list? (event-list) (expected-list)) 1 0))
(unit)
'''


def gc_probe_kernel(source, adapted):
    declaration = '(define nil (Nil))' if adapted else form(source, '(define-record-type classNode')
    extra = '' if adapted else '(define nil 0)\n(define (empty-node? node) (eq? node 0))\n'
    source = replace(source, declaration, declaration + '\n' + extra + GC_OBSERVERS)
    source = replace(source, '(MakeTree kStretchTreeDepth)', '(observe-tree 0 kStretchTreeDepth (MakeTree kStretchTreeDepth))')
    source = replace(source, '(Populate depth (make-empty-node))',
                     '(let ((tree (make-empty-node))) (Populate depth tree) (observe-tree 1 depth tree))')
    source = replace(source, '(MakeTree depth)', '(observe-tree 2 depth (MakeTree depth))')
    source = replace(source, '(TimeConstruction d))',
                     '(TimeConstruction d))\n               (observe-tree 3 kLongLivedTreeDepth longLivedTree)\n               (observe-array array)')
    return replace(source, '(run-benchmark-x))))', GC_EDGE_PROBES + '\n      (run-benchmark-x))))')


def gc_probe_specification(spec, depth):
    size = 4 * (2 ** (depth - 1) - 1)
    array = [1.0 / (i + 1) if i < size // 2 else 0.0 for i in range(size)]
    events = [5, 0, 1, 6, 0, 1, 7, 1, 1, 8, 0, 1, 0, depth, 1]
    for tree_depth in range(4, depth - 1, 2):
        iterations = (2 * (2 ** (depth + 1) - 1)) // (2 ** (tree_depth + 1) - 1)
        events += [1, tree_depth, 1] * iterations + [2, tree_depth, 1] * iterations
    events += [3, depth - 2, 1, 4, size, 1]
    return dict(spec, count=1, inputs=[depth, array], expected=events,
                result_kind='i64-list-values', barriers_per_iteration=0)


def gc_negative_probes(spec):
    array = spec['inputs'][1]
    probes = []
    for label, index in [('first', 0), ('middle', len(array) // 2), ('last', len(array) - 1)]:
        changed = list(array)
        changed[index] += 1.0
        probes.append((label, dict(spec, inputs=[spec['inputs'][0], changed])))
    probes += [('short', dict(spec, inputs=[spec['inputs'][0], array[:-1]])),
               ('long', dict(spec, inputs=[spec['inputs'][0], array + [0.0]]))]
    return probes


def gc_diagnostics(depth):
    size, diagnostics = 4 * (2 ** (depth - 1) - 1), GC_TEXT[1] + GC_TEXT[2] + '\n'
    output = (GC_TEXT[3] + '\n' + GC_SIZES[0][0] + str(depth) + '\n' + diagnostics
              + GC_TEXT[6] + '\n' + GC_SIZES[1][0] + str(depth - 2) + '\n'
              + GC_SIZES[2][0] + str(size) + GC_SIZES[2][1] + '\n' + diagnostics)
    for tree_depth in range(4, depth - 1, 2):
        iterations = (2 * (2 ** (depth + 1) - 1)) // (2 ** (tree_depth + 1) - 1)
        output += f'Creating {iterations} trees of depth {tree_depth}\n' + GC_TEXT[4] + '\n' + GC_TEXT[5] + '\n'
    return output + diagnostics


def check_gc_diagnostics(stdout, depth, count):
    start = stdout.find('Garbage Collector Test\n')
    expected = gc_diagnostics(depth) * count
    if start < 0 or stdout[start:start + len(expected)] != expected or stdout.count('Garbage Collector Test\n') != count:
        raise ValueError('gcbench must preserve every diagnostic and construction count')
