"""Keep lattice enumeration, destructive reversal, and ordered list collectors."""

import itertools
import re

from data_ports import form, replace


# ---- Typed pairs and mutable proper-list spines ----

STRICT_TYPES = '''(define-data (MutableList T)
  (ml-empty)
  (ml-node (head T ml-car) (tail (Ref (MutableList T)) ml-tail-cell)))
(define-data (Lattice T)
  (make-lattice (elements (MutableList T) lattice->elements)
                (compare (-> T T I64) lattice->cmp)))
(define-data (Binding S T)
  (make-binding (source S binding-source) (target T binding-target)))
(: ml-cons (All (T) (-> T (MutableList T) (MutableList T))))
(define (ml-cons head tail) (ml-node head (ref tail)))
(: ml-null? (All (T) (-> (MutableList T) Bool)))
(define (ml-null? values)
  (match values ((ml-empty) #t) ((ml-node head tail) #f)))
(: ml-cdr (All (T) (-> (MutableList T) (MutableList T))))
(define (ml-cdr values) (ref-get (ml-tail-cell values)))
(: ml-set-cdr! (All (T) (-> (MutableList T) (MutableList T) Unit)))
(define (ml-set-cdr! values tail) (ref-set! (ml-tail-cell values) tail))
(define-syntax case
  (syntax-rules (else)
    ((_ key) (unreachable))
    ((_ key (else body ...)) (begin body ...))
    ((_ key ((datum ...) body ...) rest ...)
     (let ((value key))
       (if (or (= value datum) ...) (begin body ...) (case value rest ...))))))
'''
CHEZ_TYPES = '''(define-syntax : (syntax-rules () ((_ . signature) (begin))))
(define-syntax ann (syntax-rules () ((_ value type) value)))
(define (ml-empty) '())
(define (ml-cons head tail) (cons head (vector tail)))
(define ml-null? null?)
(define ml-car car)
(define (ml-cdr values) (vector-ref (cdr values) 0))
(define (ml-set-cdr! values tail) (vector-set! (cdr values) 0 tail))
(define (make-lattice elements compare) (cons elements compare))
(define lattice->elements car)
(define lattice->cmp cdr)
(define (make-binding source target) (cons source target))
(define binding-source car)
(define binding-target cdr)
(define (unreachable) (error 'lattice "invalid lattice element or workload"))
'''
COMMON = ''';; Each proper-list node has an explicit mutable tail. Selection
;; reverses only its fresh accumulator spine; element identities stay shared.
(: ml-map (All (A B) (-> (-> A B) (MutableList A) (MutableList B))))
(define (ml-map procedure values)
  (if (ml-null? values) (ml-empty)
      (let ((head (procedure (ml-car values))))
        (ml-cons head (ml-map procedure (ml-cdr values))))))
(: ml-append (All (T) (-> (MutableList T) (MutableList T) (MutableList T))))
(define (ml-append first last)
  (if (ml-null? first) last
      (ml-cons (ml-car first) (ml-append (ml-cdr first) last))))
(: ml-concatenate (All (T) (-> (MutableList (MutableList T)) (MutableList T))))
(define (ml-concatenate lists)
  (if (ml-null? lists) (ml-empty)
      (if (ml-null? (ml-cdr lists)) (ml-car lists)
          (ml-append (ml-car lists) (ml-concatenate (ml-cdr lists))))))
(: code-member? (-> I64 (MutableList I64) Bool))
(define (code-member? value codes)
  (and (not (ml-null? codes))
       (or (= value (ml-car codes)) (code-member? value (ml-cdr codes)))))
;; The original quoted lists have constant lifetime and precede timing.
;; Point codes: low=0, high=1. Order codes: less=0, equal=1, more=2, uncomparable=3.
(define lattice-base-elements (ml-cons 0 (ml-cons 1 (ml-empty))))
(define lattice-less-equal (ml-cons 0 (ml-cons 1 (ml-empty))))
(define lattice-more-equal (ml-cons 2 (ml-cons 1 (ml-empty))))
'''
CONTRACTS = '''(: lexico (All (T)
  (-> (-> T T I64) (-> (MutableList T) (MutableList T) I64))))
(: zulu-select (All (T)
  (-> (-> T Bool) (MutableList T) (MutableList T))))
(: xreverse! (All (T) (-> (MutableList T) (MutableList T))))
(: select-map (All (A B)
  (-> (-> A Bool) (-> A B) (MutableList A) (MutableList B))))
(: map-and (All (T) (-> (-> T Bool) (MutableList T) Bool)))
(: maps-1 (All (S T)
  (-> (Lattice S) (Lattice T) (MutableList (Binding S T)) S (MutableList T))))
(: maps-rest (All (S T R)
  (-> (Lattice S) (Lattice T) (MutableList (Binding S T)) (MutableList S)
      (-> (MutableList (Binding S T)) R) (-> (MutableList R) R) R)))
(: maps (All (S T) (-> (Lattice S) (Lattice T) (Lattice (MutableList T)))))
(: count-maps (All (S T) (-> (Lattice S) (Lattice T) I64)))
(: sum (-> (MutableList I64) I64))
(: run (-> I64 I64))
'''
WORKER = '''(if (<= count 0) (unreachable)
  (let loop ((i 1) (result (run (hide count input0))))
    (if (< i count) (loop (+ i 1) (run (hide count input0))) result)))'''


# ---- Counted substitutions leave the enumeration and reversal bodies visible ----

def replace_tokens(source, names):
    return re.sub(r'"(?:[^"\\]|\\.)*"|;[^\n]*|[^\s()]+',
                  lambda token: names.get(token[0], token[0]), source)


def pair_roles(source):
    source = replace(source, form(source, '(define (make-lattice '), '')
    source = replace(source, '(define lattice->elements car)', '')
    source = replace(source, '(define lattice->cmp cdr)', '')
    source = replace(source, '(cons next x)', '(make-binding next x)')
    source = replace(source, '(car p)', '(binding-source p)', 2)
    source = replace(source, '\n            cdr', '\n            binding-target', 2)
    return replace(source, '(map cdr x)', '(map binding-target x)')


def finite_atoms(source):
    for literal, value in (("'(low high)", 'lattice-base-elements'),
                           ("'(less equal)", 'lattice-less-equal'),
                           ("'(more equal)", 'lattice-more-equal')):
        source = replace(source, literal, value)
    source = replace(source, '((less more)', '((0 2)')
    for atom, code in (('low', 0), ('high', 1), ('less', 0), ('equal', 1), ('more', 2), ('uncomparable', 3)):
        source = source.replace("'" + atom, str(code)).replace('((' + atom + ')', '((' + str(code) + ')')
    return source


def generic_reverse(source):
    # The original outer letrec is an application, so ML's value restriction
    # cannot generalize it. Eta expansion exposes a function value; rotate's
    # read/store/recurse order and exact returned nodes remain unchanged.
    original = form(source, '(define xreverse!')
    rotated = replace(original, '(define xreverse!\n  (letrec', '(define (xreverse! lst)\n  (letrec')
    rotated = replace(rotated, '    (lambda (lst)\n      (if', '    (if')
    rotated = replace(rotated, "(rotate lst '())))))", "(rotate lst '()))))")
    return replace(source, original, rotated)


def kernel(source):
    source = finite_atoms(pair_roles(generic_reverse(source)))
    source = replace(source, '(list (map binding-target x))', '(cons (map binding-target x) (ml-empty))')
    source = replace(source, '(apply append x)', '(ml-concatenate x)')
    source = replace(source, "'()", '(ml-empty)', 6)
    source, errors = re.subn(r"\(error (?:'make-lattice \"base\" (?:lhs|rhs)|\"run: unanticipated problem size\" k)\)",
                             '(unreachable)', source)
    if errors != 4:
        raise ValueError('expected all four original lattice error sites')
    names = {name: 'ml-' + name for name in ('cons', 'car', 'cdr', 'null?', 'set-cdr!', 'map')}
    return CONTRACTS + replace_tokens(source, dict(names, **{'eq?': '=', 'memq': 'code-member?'}))


# ---- Independent finite-poset enumeration and complete values ----

def compare_points(left, right):
    return 1 if left == right else 0 if left < right else 2


def compare_sequences(compare, left, right):
    directions = {compare(a, b) for a, b in zip(left, right)} - {1}
    return 1 if not directions else next(iter(directions)) if len(directions) == 1 else 3


def enumerate_maps(source, target, source_compare, target_compare):
    # Exhaustive independent oracle; output is lexicographic assignment order,
    # then reversed to match the source's prepended binding representation.
    return [list(reversed(values)) for values in itertools.product(target, repeat=len(source))
            if all(source_compare(a, b) != 0 or target_compare(x, y) in (0, 1)
                   for a, x in zip(source, values) for b, y in zip(source, values))]


def small_lattices():
    points = [0, 1]
    sequences = enumerate_maps(points, points, compare_points, compare_points)
    compare = lambda left, right: compare_sequences(compare_points, left, right)
    nested = enumerate_maps(sequences, sequences, compare, compare)
    return points, sequences, nested


# ---- Supplemental probes never enter the canonical artifact ----

PROBE_COMMON = '''(define (emit-bool value) (emit-i64 (if value 1 0)))
(define (probe-list-length values)
  (if (ml-null? values) 0 (+ 1 (probe-list-length (ml-cdr values)))))
(define (emit-sequence emit-element values)
  (emit-i64 (probe-list-length values))
  (let loop ((values values))
    (unless (ml-null? values)
      (emit-element (ml-car values)) (loop (ml-cdr values)))))
(define (emit-points values) (emit-sequence emit-point values))
(define (emit-assignments values) (emit-sequence emit-points values))
(define (emit-i64s values) (emit-sequence emit-i64 values))
(define (emit-comparisons lattice)
  (let ((compare (lattice->cmp lattice)) (elements (lattice->elements lattice)))
    (let rows ((left elements))
      (unless (ml-null? left)
        (let columns ((right elements))
          (unless (ml-null? right)
            (emit-order (compare (ml-car left) (ml-car right)))
            (columns (ml-cdr right))))
        (rows (ml-cdr left))))))
(define (probe-number-compare left right)
  (if (< left right) (probe-order 0)
      (if (= left right) (probe-order 1) (probe-order 2))))
(define (probe-diamond-compare left right)
  (cond ((= left right) (probe-order 1))
        ((or (= left 0) (= right 3)) (probe-order 0))
        ((or (= left 3) (= right 0)) (probe-order 2))
        (else (probe-order 3))))
(define (probe-complete-values)
  (let* ((l2 (probe-base)) (l3 (maps l2 l2)) (l4 (maps l3 l3)))
    (emit-points (lattice->elements l2))
    (emit-assignments (lattice->elements l3))
    (emit-sequence emit-assignments (lattice->elements l4))
    (emit-comparisons l3) (emit-comparisons l4)
    (emit-i64 (count-maps l2 l2)) (emit-i64 (count-maps l3 l3))
    (emit-i64 (count-maps l2 l3)) (emit-i64 (count-maps l3 l2))))
(define (probe-number-maps source target)
  (emit-sequence emit-i64s (lattice->elements (maps source target)))
  (emit-i64 (count-maps source target)))
(define (probe-boundaries)
  (let* ((none (make-lattice (ml-empty) probe-number-compare))
         (two (make-lattice (ml-cons 0 (ml-cons 1 (ml-empty))) probe-number-compare))
         (reverse (make-lattice (ml-cons 1 (ml-cons 0 (ml-empty))) probe-number-compare))
         (diamond (make-lattice (ml-cons 3 (ml-cons 2 (ml-cons 0 (ml-cons 1 (ml-empty)))))
                                probe-diamond-compare)))
    (probe-number-maps none none) (probe-number-maps none two)
    (probe-number-maps two none) (probe-number-maps reverse two)
    (probe-number-maps diamond two)))
(define (probe-source-compare left right)
  (emit-i64 20) (emit-i64 left) (emit-i64 right)
  (probe-number-compare left right))
(define (probe-target-compare left right)
  (emit-i64 21) (emit-i64 left) (emit-i64 right)
  (probe-number-compare left right))
(define (probe-enumeration-order)
  (let ((source (make-lattice (ml-cons 1 (ml-cons 0 (ml-empty))) probe-source-compare))
        (target (make-lattice (ml-cons 0 (ml-cons 1 (ml-empty))) probe-target-compare)))
    (probe-number-maps source target)))
(define (probe-select-order)
  (let* ((a (ml-cons 1 (ml-empty))) (b (ml-cons 2 (ml-empty))) (c (ml-cons 3 (ml-empty)))
         (source (ml-cons a (ml-cons b (ml-cons c (ml-empty)))))
         (selected (zulu-select
           (lambda (value) (emit-i64 10) (emit-i64 (ml-car value))
             (= (remainder (ml-car value) 2) 1)) source)))
    (emit-sequence emit-i64s selected) (emit-sequence emit-i64s source)
    (emit-bool (ml-same? (ml-car selected) a))
    (emit-bool (ml-same? (ml-car (ml-cdr selected)) c))
    (emit-bool (not (ml-same? selected source)))
    (emit-bool (not (ml-same? (ml-cdr selected) (ml-cdr (ml-cdr source)))))))
(define (probe-map-order)
  (let ((source (ml-cons 1 (ml-cons 2 (ml-cons 3 (ml-empty))))))
    (emit-i64s (select-map
      (lambda (value) (emit-i64 11) (emit-i64 value) (not (= value 2)))
      (lambda (value) (emit-i64 12) (emit-i64 value) (+ value 10)) source))
    (emit-bool (map-and
      (lambda (value) (emit-i64 13) (emit-i64 value) (< value 2)) source))
    (emit-bool (map-and (lambda (value) (unreachable)) (ann (ml-empty) (MutableList I64))))
    (emit-bool (map-and
      (lambda (value) (emit-i64 14) (emit-i64 value) #t) (ml-cons 3 (ml-empty))))))
(define (probe-reverse-identity)
  (let* ((first (ml-cons 1 (ml-cons 2 (ml-cons 3 (ml-empty)))))
         (second (ml-cdr first)) (third (ml-cdr second)) (result (xreverse! first)))
    (emit-i64s result)
    (emit-bool (ml-same? result third)) (emit-bool (ml-same? (ml-cdr third) second))
    (emit-bool (ml-same? (ml-cdr second) first)) (emit-bool (ml-null? (ml-cdr first))))
  (let ((single (ml-cons 4 (ml-empty)))) (emit-bool (ml-same? single (xreverse! single))))
  (emit-bool (ml-null? (xreverse! (ann (ml-empty) (MutableList I64))))))
(define (probe-append-identity)
  (let* ((prefix (ml-cons 1 (ml-empty))) (tail (ml-cons 2 (ml-empty)))
         (joined (ml-concatenate (ml-cons prefix (ml-cons tail (ml-empty)))))
         (copied (ml-concatenate (ml-cons prefix (ml-cons (ml-empty) (ml-empty))))))
    (emit-i64s joined) (emit-bool (ml-same? (ml-cdr joined) tail))
    (emit-bool (not (ml-same? joined prefix)))
    (emit-bool (not (ml-same? copied prefix)))
    (emit-bool (ml-same? tail (ml-concatenate (ml-cons tail (ml-empty)))))
    (emit-bool (ml-same? tail (ml-concatenate (ml-cons (ml-empty) (ml-cons tail (ml-empty))))))
    (emit-bool (ml-null? (ml-concatenate (ann (ml-empty) (MutableList (MutableList I64))))))))
(define (probe command)
  (cond ((= command 0) (probe-complete-values))
        ((= command 1) (probe-boundaries))
        ((= command 2) (probe-enumeration-order))
        (else (probe-select-order) (probe-map-order)
              (probe-reverse-identity) (probe-append-identity)))
  1)
'''
STRICT_PROBE = '''(define-extern emit-i64 "probe" "emit" (-> I64 Unit))
(define emit-point emit-i64)
(define emit-order emit-i64)
(define (probe-order value) value)
(define (ml-same? left right)
  (if (ml-null? left) (ml-null? right)
      (and (not (ml-null? right)) (ref-eq? (ml-tail-cell left) (ml-tail-cell right)))))
(: probe (-> I64 I64))
'''
ORIGINAL_PROBE = '''(define-syntax ann (syntax-rules () ((_ value type) value)))
(define ml-cons cons)
(define (ml-empty) '())
(define ml-null? null?)
(define ml-car car)
(define ml-cdr cdr)
(define ml-same? eq?)
(define (ml-concatenate values) (apply append values))
(define (emit-point value) (emit-i64 (case value ((low) 0) ((high) 1))))
(define (emit-order value)
  (emit-i64 (case value ((less) 0) ((equal) 1) ((more) 2) ((uncomparable) 3))))
(define (probe-order value) (list-ref '(less equal more uncomparable) value))
(define (unreachable) (error 'probe "unexpected evaluation"))
'''


def probe_base(kernel):
    binding = form(kernel, '(l2\n')
    return '(define (probe-base) ' + binding[3:].strip()[:-1] + ')\n'


def strict_probe(kernel, prelude):
    return prelude + STRICT_TYPES + COMMON + kernel + probe_base(kernel) + STRICT_PROBE + PROBE_COMMON


def chez_probe(kernel, adapted):
    helpers = CHEZ_TYPES + COMMON if adapted else ''
    interface = ('''(define emit-point emit-i64)
(define emit-order emit-i64)
(define (probe-order value) value)
(define ml-same? eq?)
''' if adapted else ORIGINAL_PROBE)
    return ('(import (chezscheme))\n' + helpers + kernel + probe_base(kernel)
            + '(define (emit-i64 value) (write value) (newline))\n' + interface + PROBE_COMMON
            + '(probe (read))\n')


PROBE_HOST = '''import fs from 'node:fs';
import assert from 'node:assert/strict';
const [artifact, command] = process.argv.slice(2);
const values = [];
const {instance} = await WebAssembly.instantiate(fs.readFileSync(artifact),
  {probe: {emit: value => values.push(Number(value))}});
instance.exports.main();
assert.equal(instance.exports.probe(BigInt(command)), 1n);
console.log(JSON.stringify(values));
'''


def encode(values):
    if isinstance(values, int):
        return [values]
    return [len(values)] + [part for value in values for part in encode(value)]


def complete_oracle():
    points, sequences, nested = small_lattices()
    sequence_compare = lambda a, b: compare_sequences(compare_points, a, b)
    nested_compare = lambda a, b: compare_sequences(sequence_compare, a, b)
    matrices = [compare(a, b) for values, compare in ((sequences, sequence_compare), (nested, nested_compare))
                for a in values for b in values]
    return encode(points) + encode(sequences) + encode(nested) + matrices + [3, 10, 6, 4]


def boundary_oracle():
    def diamond(a, b):
        return 1 if a == b else 0 if a == 0 or b == 3 else 2 if a == 3 or b == 0 else 3
    cases = [([], [], compare_points), ([], [0, 1], compare_points), ([0, 1], [], compare_points),
             ([1, 0], [0, 1], compare_points), ([3, 2, 0, 1], [0, 1], diamond)]
    result = []
    for source, target, compare in cases:
        maps = enumerate_maps(source, target, compare, compare_points)
        result += encode(maps) + [len(maps)]
    return result


def list_operation_oracle():
    selected = [10, 1, 10, 2, 10, 3] + encode([[1], [3]]) + encode([[1], [2], [3]]) + [1] * 4
    mapped = [11, 1, 12, 1, 11, 2, 11, 3, 12, 3] + encode([11, 13])
    mapped += [13, 1, 13, 2, 0, 1, 14, 3, 1]
    reversed_nodes = encode([3, 2, 1]) + [1] * 6
    appended = encode([1, 2]) + [1] * 6
    return selected + mapped + reversed_nodes + appended
