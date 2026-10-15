"""Preserve destructive row splices, mutable node identity, and full equality."""

import re

from data_ports import form, replace
from lattice_port import replace_tokens
from puzzle_port import control_prelude
from string_port import exact_json_integer, i64


# ---- Two concrete list levels and explicit mutable pair fields ----

STRICT_TYPES = '''(define-data (MutableList T)
  (ml-empty)
  (ml-node (head (Ref T) ml-head-cell)
           (tail (Ref (MutableList T)) ml-tail-cell)))
(define-data Item (empty-item) (integer-item (value I64 item-value)))
(define empty-value (empty-item))
(: ml-cons (All (T) (-> T (MutableList T) (MutableList T))))
(define (ml-cons head tail) (ml-node (ref head) (ref tail)))
(: ml-null? (All (T) (-> (MutableList T) Bool)))
(define (ml-null? values)
  (match values ((ml-empty) #t) ((ml-node head tail) #f)))
(: ml-car (All (T) (-> (MutableList T) T)))
(define (ml-car values) (ref-get (ml-head-cell values)))
(: ml-cdr (All (T) (-> (MutableList T) (MutableList T))))
(define (ml-cdr values) (ref-get (ml-tail-cell values)))
(: ml-set-car! (All (T) (-> (MutableList T) T Unit)))
(define (ml-set-car! values head) (ref-set! (ml-head-cell values) head))
(: ml-set-cdr! (All (T) (-> (MutableList T) (MutableList T) Unit)))
(define (ml-set-cdr! values tail) (ref-set! (ml-tail-cell values) tail))
(define (item-empty? value)
  (match value ((empty-item) #t) ((integer-item number) #f)))
(define (zero? value) (= value 0))
'''
CHEZ_TYPES = '''(define-syntax : (syntax-rules () ((_ . signature) (begin))))
(define-syntax ann (syntax-rules () ((_ value type) value)))
(define (ml-empty) '())
(define (ml-cons head tail) (cons (vector head) (vector tail)))
(define ml-null? null?)
(define (ml-car values) (vector-ref (car values) 0))
(define (ml-cdr values) (vector-ref (cdr values) 0))
(define (ml-set-car! values head) (vector-set! (car values) 0 head))
(define (ml-set-cdr! values tail) (vector-set! (cdr values) 0 tail))
(define empty-value (vector 0))
(define (integer-item value) (vector 1 value))
(define (item-empty? value) (= (vector-ref value 0) 0))
(define (item-value value) (vector-ref value 1))
'''
COMMON = '''(: ml-length (All (T) (-> (MutableList T) I64)))
(define (ml-length values)
  (let loop ((values values) (size 0))
    (if (ml-null? values) size (loop (ml-cdr values) (+ size 1)))))
(define (same-item? left right)
  (if (item-empty? left) (item-empty? right)
      (and (not (item-empty? right)) (= (item-value left) (item-value right)))))
(: same-row? (-> (MutableList Item) (List Item) Bool))
(define (same-row? actual expected)
  (if (ml-null? actual) (null? expected)
      (and (not (null? expected)) (same-item? (ml-car actual) (car expected))
           (same-row? (ml-cdr actual) (cdr expected)))))
(: same-rows? (-> (MutableList (MutableList Item)) (List (List Item)) Bool))
(define (same-rows? actual expected)
  (if (ml-null? actual) (null? expected)
      (and (not (null? expected)) (same-row? (ml-car actual) (car expected))
           (same-rows? (ml-cdr actual) (cdr expected)))))
'''
CONTRACTS = '''(: append-to-tail! (All (T)
  (-> (MutableList T) (MutableList T) (MutableList T))))
(: destructive (-> I64 I64 (MutableList (MutableList Item))))
'''
INPUTS = '''(define-extern native-expected-i64 "benchmark" "expected_i64" (-> I64 I64))
(define expected-cursor (ref 0))
(define (read-expected-i64)
  (let ((value (native-expected-i64 (ref-get expected-cursor))))
    (ref-set! expected-cursor (+ (ref-get expected-cursor) 1)) value))
(define (read-expected-item)
  (if (= (read-expected-i64) 0) empty-value (integer-item (read-expected-i64))))
(define (read-expected-row size)
  (if (= size 0) '()
      (let ((head (read-expected-item)))
        (cons head (read-expected-row (- size 1))))))
(define (read-expected-rows size)
  (if (= size 0) '()
      (let ((head (read-expected-row (read-expected-i64))))
        (cons head (read-expected-rows (- size 1))))))
(define input0 (native-input-i64 (ann 0 I32)))
(define input1 (native-input-i64 (ann 1 I32)))
(define expected-false? (= (native-input-i64 (ann 2 I32)) 1))
(define expected-rows (read-expected-rows (read-expected-i64)))
'''
WORKER = '''(if (<= count 0) (if expected-false? 1 0)
  (let loop ((i 1) (result (destructive (hide count input0) (hide count input1))))
    (if (< i count)
        (loop (+ i 1) (destructive (hide count input0) (hide count input1)))
        (if (and (not expected-false?) (same-rows? result expected-rows)) 1 0))))'''
CHEZ_BOUNDARY = '''(define (read-expected-item value)
  (if (null? value) empty-value (integer-item value)))
(define (read-expected-rows value)
  (and value (map (lambda (row) (map read-expected-item row)) value)))
(define (original-item value) (if (item-empty? value) '() (item-value value)))
(define (original-row row)
  (if (ml-null? row) '()
      (cons (original-item (ml-car row)) (original-row (ml-cdr row)))))
(define (original-rows rows)
  (if (ml-null? rows) '()
      (cons (original-row (ml-car rows)) (original-rows (ml-cdr rows)))))
'''


# ---- Counted role substitutions preserve every original loop and splice ----

def sequence_splice(source):
    if 'destruc-suffix' in source or 'destruc-target' in source:
        raise ValueError('splice sequencing requires fresh local binding names')
    splice = form(source, '(set-cdr! (do ')
    target, suffix = form(splice, '(do ((j (quotient '), form(splice, '(let ((n ')
    # Scheme leaves operand order unspecified. Compiled Chez's observed order
    # evaluates the suffix first. Keep both searches exact and make that choice
    # explicit; neither search touches the other row's disjoint nodes.
    ordered = f'(let* ((destruc-suffix {suffix})\n                         (destruc-target {target}))\n                 (set-cdr! destruc-target destruc-suffix))'
    return replace(source, splice, ordered)


def kernel(source):
    source = sequence_splice(source)
    source = replace(source, "(i 10 (- i 1)) (a '() (cons '() a))",
                     '(i 10 (- i 1)) (a (ml-empty) (ml-cons (ml-empty) a))')
    source = replace(source, "(j m (- j 1)) (a '() (cons '() a))",
                     '(j m (- j 1)) (a (ml-empty) (ml-cons empty-value a))')
    source = replace(source, "(cons '() '())", '(ml-cons empty-value (ml-empty))')
    source = replace(source, '(set-car! a i)', '(set-car! a (integer-item i))', 2)
    source = replace(source, "'()", '(ml-empty)', 2)
    names = ('cons', 'car', 'cdr', 'null?', 'set-car!', 'set-cdr!', 'length')
    return CONTRACTS + replace_tokens(source, {name: 'ml-' + name for name in names})


def adapt_harness(source, reverse=False):
    edits = (('(output (read))', '(output (read-expected-rows (read)))'),
             ('(equal? result output)',
              '(if result (and output (same-rows? result output)) (not output))'),
             ('(write result)', '(write (and result (original-rows result)))'))
    for before, after in edits:
        source = replace(source, after if reverse else before, before if reverse else after)
    return source


# ---- Runtime expected values include empty-list items and the initial false ----

def read_datum(token, tokens):
    if token == '(':
        values = []
        for item in tokens:
            if item == ')':
                return values
            values.append(read_datum(item, tokens))
        raise ValueError('unclosed destruc input list')
    if token == '#f':
        return False
    return i64(token)


def encode_item(value):
    if value == []:
        return [0]
    if type(value) is not int:
        raise ValueError('destruc items must be integers or the empty list')
    return [1, exact_json_integer(value)]


def encode_rows(rows):
    if rows is False:
        return [0]
    if not isinstance(rows, list) or any(not isinstance(row, list) for row in rows):
        raise ValueError('destruc expected result must be false or a proper list of rows')
    result = [len(rows)]
    for row in rows:
        result.append(len(row))
        for item in row:
            result.extend(encode_item(item))
    return result


def specification(data):
    tokens = iter(re.findall(r'\(|\)|[^\s()]+', re.sub(r';[^\n]*', '', data.decode())))
    count, n, m, expected = [read_datum(token, tokens) for token in tokens]
    if any(type(value) is not int for value in (count, n, m)) or n < 0 or m < 0:
        raise ValueError('destruc requires an integer count and nonnegative integer n,m')
    return dict(name='destruc', count=exact_json_integer(count),
                inputs=[exact_json_integer(n), exact_json_integer(m), int(expected is False)],
                original_expected=expected, expected=encode_rows(expected),
                result_kind='i64-list-values', barriers_per_iteration=2, setup_barriers=0)


# ---- Separate identity registries observe the unmodified node representation ----

PROBE_COMMON = '''(define tracing (ref #f))
(define outer-nodes (ref (ann '() (List (MutableList (MutableList Item))))))
(define inner-nodes (ref (ann '() (List (MutableList Item)))))
(: node-id (All (T) (-> (MutableList T) (List (MutableList T)) I64)))
(define (node-id value nodes)
  (if (ml-null? value) 0
      (let find ((nodes nodes) (id (length nodes)))
        (if (null? nodes) (unreachable)
            (if (ml-same? value (car nodes)) id (find (cdr nodes) (- id 1)))))))
(define (outer-id value) (node-id value (ref-get outer-nodes)))
(define (inner-id value) (node-id value (ref-get inner-nodes)))
(define (emit-item value)
  (if (item-empty? value) (emit-i64 0)
      (begin (emit-i64 1) (emit-i64 (item-value value)))))
(define (emit-outer node)
  (emit-i64 (outer-id node)) (emit-i64 (inner-id (ml-car node)))
  (emit-i64 (outer-id (ml-cdr node))))
(define (emit-inner node)
  (emit-i64 (inner-id node)) (emit-item (ml-car node))
  (emit-i64 (inner-id (ml-cdr node))))
(define (probe-row-cons head tail)
  (let ((node (ml-cons head tail)))
    (when (ref-get tracing)
      (ref-set! outer-nodes (cons node (ref-get outer-nodes)))
      (emit-i64 0) (emit-outer node))
    node))
(define (probe-cell-cons head tail)
  (let ((node (ml-cons head tail)))
    (when (ref-get tracing)
      (ref-set! inner-nodes (cons node (ref-get inner-nodes)))
      (emit-i64 1) (emit-inner node))
    node))
(define (probe-set-row! node head)
  (when (ref-get tracing)
    (emit-i64 2) (emit-i64 (outer-id node)) (emit-i64 (inner-id head)))
  (ml-set-car! node head))
(define (probe-set-item! node head)
  (when (ref-get tracing)
    (emit-i64 3) (emit-i64 (inner-id node)) (emit-item head))
  (ml-set-car! node head))
(define (probe-set-tail! node tail)
  (when (ref-get tracing)
    (emit-i64 4) (emit-i64 (inner-id node)) (emit-i64 (inner-id tail)))
  (ml-set-cdr! node tail))
(define (emit-row row)
  (emit-i64 (ml-length row))
  (let loop ((row row))
    (unless (ml-null? row) (emit-item (ml-car row)) (loop (ml-cdr row)))))
(define (emit-rows rows)
  (emit-i64 9) (emit-i64 (ml-length rows))
  (let loop ((rows rows))
    (unless (ml-null? rows) (emit-row (ml-car rows)) (loop (ml-cdr rows)))))
(define (emit-registry emit-node nodes)
  (emit-i64 (length nodes))
  (let loop ((nodes nodes))
    (unless (null? nodes) (emit-node (car nodes)) (loop (cdr nodes)))))
(define (emit-graph)
  (emit-i64 10)
  (emit-registry emit-outer (ref-get outer-nodes))
  (emit-registry emit-inner (ref-get inner-nodes)))
(: probe (-> I64 I64 I64 I64))
(define (probe n m trace)
  (ref-set! tracing (= trace 1))
  (emit-rows (destructive n m))
  (when (ref-get tracing) (emit-graph))
  1)
'''
STRICT_PROBE = '''(define-extern emit-i64 "probe" "emit" (-> I64 Unit))
(: ml-same? (All (T) (-> (MutableList T) (MutableList T) Bool)))
(define (ml-same? left right)
  (if (ml-null? left) (ml-null? right)
      (and (not (ml-null? right)) (ref-eq? (ml-head-cell left) (ml-head-cell right)))))
'''
CHEZ_PROBE = '''(define (ref value) (vector value))
(define (ref-get cell) (vector-ref cell 0))
(define (ref-set! cell value) (vector-set! cell 0 value))
(define ml-same? eq?)
(define (emit-i64 value) (write value) (newline))
(define (unreachable) (error 'destruc-probe "unregistered node"))
'''
ORIGINAL_TYPES = '''(define-syntax : (syntax-rules () ((_ . signature) (begin))))
(define-syntax ann (syntax-rules () ((_ value type) value)))
(define (ml-empty) '())
(define ml-cons cons)
(define ml-null? null?)
(define ml-car car)
(define ml-cdr cdr)
(define ml-set-car! set-car!)
(define ml-set-cdr! set-cdr!)
(define item-empty? null?)
(define (item-value value) value)
'''


def observed_kernel(source, adapted):
    if adapted:
        # Observing inner-node IDs gives this diagnostic helper a concrete domain.
        # The canonical append keeps its rigid, fully polymorphic contract.
        source = replace(source, CONTRACTS, '''(: append-to-tail!
  (-> (MutableList Item) (MutableList Item) (MutableList Item)))
(: destructive (-> I64 I64 (MutableList (MutableList Item))))
''')
    prefix, empty, item = ('ml-', '(ml-empty)', 'empty-value') if adapted else ('', "'()", "'()")
    source = replace(source, f'(i 10 (- i 1)) (a {empty} ({prefix}cons {empty} a))',
                     f'(i 10 (- i 1)) (a {empty} (probe-row-cons {empty} a))')
    source = replace(source, f'(j m (- j 1)) (a {empty} ({prefix}cons {item} a))',
                     f'(j m (- j 1)) (a {empty} (probe-cell-cons {item} a))')
    source = replace(source, f'({prefix}cons {item} {empty})', f'(probe-cell-cons {item} {empty})')
    source = replace(source, f'({prefix}set-car! l ', '(probe-set-row! l ')
    source = replace(source, f'({prefix}set-car! l1 ', '(probe-set-row! l1 ')
    source = replace(source, f'({prefix}set-car! a ', '(probe-set-item! a ', 2)
    return replace(source, f'({prefix}set-cdr! ', '(probe-set-tail! ', 3)


def strict_probe(kernel, prelude):
    return (control_prelude(prelude) + STRICT_TYPES + COMMON + STRICT_PROBE
            + observed_kernel(kernel, True) + PROBE_COMMON + '\n(unit)\n')


def chez_probe(kernel, adapted):
    return ('(import (chezscheme))\n' + (CHEZ_TYPES if adapted else ORIGINAL_TYPES)
            + COMMON + CHEZ_PROBE + observed_kernel(kernel, adapted) + PROBE_COMMON
            + '''(let* ((n (read)) (m (read)) (trace (read)) (calls (read)))
  (do ((i 0 (+ i 1))) ((= i calls)) (probe n m trace)))\n''')


PROBE_HOST = '''import fs from 'node:fs';
import assert from 'node:assert/strict';
const [artifact, n, m, trace, calls] = process.argv.slice(2);
const values = [];
const {instance} = await WebAssembly.instantiate(fs.readFileSync(artifact),
  {probe: {emit: value => values.push(Number(value))}});
instance.exports.main();
for (let i = 0; i < Number(calls); i++)
  assert.equal(instance.exports.probe(BigInt(n), BigInt(m), BigInt(trace)), 1n);
console.log(JSON.stringify(values));
'''


# ---- Independent mutable graph model, including abandoned nodes ----

class Node:
    def __init__(self, identity, head, tail):
        self.identity, self.head, self.tail = identity, head, tail


def identity(node):
    return node.identity if node is not None else 0


def nodes(node):
    while node is not None:
        yield node
        node = node.tail


def item_encoding(item):
    return [0] if item is None else [1, item]


class Graph:
    def __init__(self, tracing):
        self.outer, self.inner, self.events, self.tracing = [], [], [], tracing

    def record(self, *event):
        if self.tracing:
            self.events.extend(event)

    def cons(self, outer, head, tail):
        registry = self.outer if outer else self.inner
        node = Node(len(registry) + 1, head, tail)
        registry.append(node)
        data = [identity(head)] if outer else item_encoding(head)
        self.record(0 if outer else 1, node.identity, *data, identity(tail))
        return node

    def set_row(self, node, head):
        self.record(2, node.identity, identity(head))
        node.head = head

    def set_item(self, node, item):
        self.record(3, node.identity, *item_encoding(item))
        node.head = item

    def set_tail(self, node, tail):
        self.record(4, node.identity, identity(tail))
        node.tail = tail

    def refill(self, rows, m):
        for row in nodes(rows):
            if row.head is None:
                self.set_row(row, self.cons(False, None, None))
            added = None
            for _ in range(m):
                added = self.cons(False, None, added)
            last = row.head
            while last.tail is not None:
                last = last.tail
            self.set_tail(last, added)

    def right_target(self, row, value):
        node = row.head
        for _ in range(len(list(nodes(node))) // 2):
            self.set_item(node, value)
            node = node.tail
        return node

    def split_left(self, row, value):
        half, node = len(list(nodes(row.head))) // 2, row.head
        if half == 0:
            self.set_row(row, None)
            return None
        for _ in range(half - 1):
            self.set_item(node, value)
            node = node.tail
        suffix = node.tail
        self.set_tail(node, None)
        return suffix

    def destructive(self, n, m):
        rows = None
        for _ in range(10):
            rows = self.cons(True, None, rows)
        for value in range(n, 0, -1):
            if rows.head is None:
                self.refill(rows, m)
            else:
                for left in list(nodes(rows))[:-1]:
                    suffix = self.split_left(left, value)
                    target = self.right_target(left.tail, value)
                    self.set_tail(target, suffix)
        return rows

    def snapshot(self):
        result = [10, len(self.outer)]
        for node in reversed(self.outer):
            result += [node.identity, identity(node.head), identity(node.tail)]
        result += [len(self.inner)]
        for node in reversed(self.inner):
            result += [node.identity, *item_encoding(node.head), identity(node.tail)]
        return result


def oracle(n, m, tracing=False, calls=1):
    graph = Graph(tracing)
    result = []
    for _ in range(calls):
        start = len(graph.events)
        rows = [[[] if cell.head is None else cell.head for cell in nodes(row.head)]
                for row in nodes(graph.destructive(n, m))]
        result += graph.events[start:] + [9] + encode_rows(rows) + (graph.snapshot() if tracing else [])
    return rows, result


def fixtures():
    return [(n, m, 1, 1) for n, m in ((0, 0), (1, 0), (2, 0), (3, 0),
                                     (1, 1), (2, 1), (3, 2), (4, 4), (13, 5))] + [(600, 50, 0, 1), (2, 1, 1, 2)]


def scheme_datum(value):
    if value is False:
        return '#f'
    if isinstance(value, list):
        return '(' + ' '.join(map(scheme_datum, value)) + ')'
    return str(value)


def harness_fixtures():
    rows = oracle(4, 4)[0]
    variants = [('complete', rows, True), ('short-outer', rows[:-1], False),
                ('long-outer', rows + [[]], False), ('short-last-row', rows[:-1] + [rows[-1][:-1]], False),
                ('long-last-row', rows[:-1] + [rows[-1] + [1]], False),
                ('late-item', rows[:-1] + [rows[-1][:-1] + [99]], False),
                ('item-tag', rows[:-1] + [rows[-1][:-1] + [[]]], False), ('false', False, False)]
    cases = [(label, 1, 4, 4, expected, accepted) for label, expected, accepted in variants]
    cases += [(f'{count}-{label}', count, 0, 0, expected, accepted)
              for count in (0, -1) for label, expected, accepted in
              [('false', False, True), ('empty-outer', [], False), ('ten-empty-rows', [[]] * 10, False)]]
    return [(label, f'{count}\n{n}\n{m}\n{scheme_datum(expected)}\n', accepted)
            for label, count, n, m, expected, accepted in cases]
