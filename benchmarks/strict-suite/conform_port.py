"""Preserve Conform's functional lists, cyclic graph mutations, and memo tables."""

import difflib
import json
import re
import shutil
import signal

from data_ports import form, replace
from lattice_port import replace_tokens
import matrix_port
import reader_ports


# ---- Concrete roles keep each mutable source field visible ----

TYPES = '''(define-data (Optional T) (absent) (present (value T optional-value)))
(: present? (All (T) (-> (Optional T) Bool)))
(define (present? value) (match value ((absent) #f) ((present item) #t)))
(define-data Name
  (symbol-name (value Symbol name-symbol))
  (text-name (value String name-text)))
(define-data BlueState
  (blue-unresolved) (blue-none)
  (blue-ready (edges (List BlueEdge) blue-state-edges)))
(define-data Node
  (node-record (name (Ref String) node-name-cell)
               (green (Ref (List Node)) node-green-cell)
               (red (Ref (List Node)) node-red-cell)
               (blue (Ref BlueState) node-blue-cell)))
(define-data BlueEdge
  (edge-record (operation (Ref Symbol) edge-operation-cell)
               (argument (Ref Node) edge-argument-cell)
               (result (Ref Node) edge-result-cell)))
(define-data Signature
  (signature (argument Node signature-argument) (result Node signature-result)))
(define-data Entry (table-entry (key Node entry-key) (value Node entry-value)))
(define-data Row
  (row-record (key Node row-key) (entries (Ref (List Entry)) row-entry-cell)))
(define-data Table (table-record (rows (Ref (List Row)) table-row-cell)))
(define-data Graph
  (graph-record (nodes (Ref (List Node)) graph-node-cell)
                (met Table graph-met) (joined Table graph-joined)))
'''
IDENTITY = '''(define-class (ConformIdentity T) (: conform-eq? (-> T T Bool)))
(define-instance (ConformIdentity Node)
  (conform-eq? (lambda (left right) (ref-eq? (node-name-cell left) (node-name-cell right)))))
(define-instance (ConformIdentity Symbol) (conform-eq? conform-symbol=?))
'''
CHEZ_IDENTITY = '''(define (conform-eq? left right)
  (if (eq? (vector-ref left 0) 'node-record)
      (ref-eq? (node-name-cell left) (node-name-cell right))
      (conform-symbol=? left right)))
'''
COMMON = ''';; A node's independently allocated name Ref supplies its identity.
;; Its mutable fields and edge fields retain all aliases across graph copies.
(define phi-operation (conform-string->symbol "phi"))
(define theta-operation (conform-string->symbol "theta"))
(define (name-string value)
  (match value ((symbol-name name) (conform-symbol->string name)) ((text-name text) text)))
(define (table-rows table) (ref-get (table-row-cell table)))
(define (set-table-rows! table rows) (ref-set! (table-row-cell table) rows))
(define (row-entries row) (ref-get (row-entry-cell row)))
(define (set-row-entries! row entries) (ref-set! (row-entry-cell row) entries))
(define (find-row key rows)
  (if (null? rows) (absent)
      (if (conform-eq? key (row-key (car rows))) (present (car rows))
          (find-row key (cdr rows)))))
(define (find-entry key entries)
  (if (null? entries) (absent)
      (if (conform-eq? key (entry-key (car entries))) (present (car entries))
          (find-entry key (cdr entries)))))
(: conform-member? (All (T) (=> ((ConformIdentity T)) (-> T (List T) Bool))))
(define (conform-member? value values)
  (and (not (null? values))
       (or (conform-eq? value (car values)) (conform-member? value (cdr values)))))
(: conform-list (All (T) (-> (Rest T) (List T))))
(define (conform-list . values) values)
(: conform-map (All (A B) (-> (-> A B) (List A) (List B))))
(define (conform-map procedure values)
  (if (null? values) '()
      (let ((head (procedure (car values))))
        (cons head (conform-map procedure (cdr values))))))
(: conform-for-each (All (A B) (-> (-> A B) (List A) Unit)))
(define (conform-for-each procedure values)
  (unless (null? values) (procedure (car values)) (conform-for-each procedure (cdr values))))
(: conform-append (All (T) (-> (List T) (List T) (List T))))
(define (conform-append first last)
  (if (null? first) last (cons (car first) (conform-append (cdr first) last))))
(: conform-length (All (T) (-> (List T) I64)))
(define (conform-length values)
  (let loop ((values values) (count 0))
    (if (null? values) count (loop (cdr values) (+ count 1)))))
(: conform-pair? (All (T) (-> (List T) Bool)))
(define (conform-pair? value) (not (null? value)))
(define (conform-caar values) (car (car values)))
;; Dynamic apply to the source rest-argument constructor builds a fresh spine.
(define (copy-graph-arguments nodes)
  (if (null? nodes) '() (cons (car nodes) (copy-graph-arguments (cdr nodes)))))
(define (make-graph-list nodes)
  (make-internal-graph (copy-graph-arguments nodes) (make-empty-table) (make-empty-table)))
(define (display-text text)
  (let loop ((index 0))
    (unless (= index (string-length text))
      (print-character (string-ref text index)) (loop (+ index 1)))))
(define (display-number number) (display-text (i64->string number)))
(define (conform-newline) (print-character #\\newline))
'''
CONTROL = '''(define-syntax conform-cond
  (syntax-rules (else =>)
    ((_ (else body ...)) (begin body ...))
    ((_ (value => procedure) rest ...)
     (let ((result value))
       (if (present? result) (procedure result) (conform-cond rest ...))))
    ((_ (test body ...) rest ...)
     (if test (begin body ...) (conform-cond rest ...)))))
'''
CONTRACTS = '''(: sort-list (All (T) (-> (List T) (-> T T Bool) (List T))))
(: adjoin (All (T) (=> ((ConformIdentity T)) (-> T (List T) (List T)))))
(: eliminate (All (T) (=> ((ConformIdentity T)) (-> T (List T) (List T)))))
(: intersect (All (T) (=> ((ConformIdentity T)) (-> (List T) (List T) (List T)))))
(: union (All (T) (=> ((ConformIdentity T)) (-> (List T) (List T) (List T)))))
(: make-node (-> Name (Rest BlueState) Node))
(: make-internal-node (-> String (List Node) (List Node) BlueState Node))
(: make-edge-getter (All (T) (-> (-> Node T) (-> Node T))))
(: make-edge-setter (All (T) (-> (-> Node T Unit) (-> Node T Unit))))
(: lookup-op (-> Symbol Node (Optional BlueEdge)))
(: make-graph (-> (Rest Node) Graph))
(: make-graph-list (-> (List Node) Graph))
(: add-graph-nodes! (-> Graph Node Unit))
(: copy-node (-> Node Node))
(: copy-graph (-> Graph Graph))
(: canonicalize-graph (-> Graph (List (List Node)) Graph))
(: lookup (-> Table Node Node (Optional Node)))
(: insert! (-> Table Node Node Node Unit))
(: conforms? (-> Node Node Bool))
(: classify (-> (List Node) (List (List Node))))
(: find-canonical-representative (-> Node (List (List Node)) Node))
(: blue-edge-operate (-> (-> Graph Node Node Node) (-> Graph Node Node Node)
                        Graph Symbol Signature Signature BlueEdge))
(: meet (-> Graph Node Node Node))
(: join (-> Graph Node Node Node))
(: setup (-> Name Name Name Name Unit))
(: test (-> Name Name Name Name (List String)))
'''


# ---- Each exact edit is recorded and reversed against the pinned source ----

def edit(source, ledger, before, after, reason, count=1):
    result = replace(source, before, after, count)
    offsets = [match.start() + index * (len(after) - len(before))
               for index, match in enumerate(re.finditer(re.escape(before), source))]
    ledger.append(dict(before=before, after=after, count=count, offsets=offsets, reason=reason))
    return result


def node_forms(source, ledger):
    reason = 'Heterogeneous vector slots become concrete fields with one Ref per mutable slot.'
    source = edit(source, ledger, '(define make-internal-node vector)',
                  '(define (make-internal-node name green red blue)\n'
                  '  (node-record (ref name) (ref green) (ref red) (ref blue)))', reason)
    fields = [('name', 'name'), ('green-edges', 'green'), ('red-edges', 'red'), ('blue-edges', 'blue')]
    for index, (public, field) in enumerate(fields):
        source = edit(source, ledger, f'(vector-ref node {index})', f'(ref-get (node-{field}-cell node))', reason)
        value = 'name' if index == 0 else 'edges'
        source = edit(source, ledger, f'(vector-set! node {index} {value})',
                      f'(ref-set! (node-{field}-cell node) {value})', reason)
    source = edit(source, ledger, '(if (symbol? name) (symbol->string name) name)', '(name-string name)',
                  'Only names cross the symbol/string input boundary; every original symbol->string call remains.')
    source = edit(source, ledger, "'NOT-A-NODE-YET", '(blue-unresolved)', 'Unfinished blue edges are distinct from NONE and empty lists.')
    source = edit(source, ledger, "(make-internal-node (internal-node-name node) '() '() (blue-edges node))",
                  "(make-internal-node (internal-node-name node) '() '() (blue-ready (blue-edges node)))",
                  'A copied node shares the blue list and its edge objects, with fresh red/green fields.')
    source = edit(source, ledger, '(make-edge-getter internal-node-blue-edges)',
                  '(make-edge-getter (lambda (node) (blue-state-edges (internal-node-blue-edges node))))',
                  'Only a completed ordinary node exposes a blue-edge list.')
    return edit(source, ledger, '(make-edge-setter set-internal-node-blue-edges!)',
                '(make-edge-setter (lambda (node edges) (set-internal-node-blue-edges! node (blue-ready edges))))',
                'The ordinary blue setter resolves the unfinished node.')


def edge_graph_forms(source, ledger):
    reason = 'Concrete records preserve every mutable vector slot and shared table identity.'
    source = edit(source, ledger, '(define make-blue-edge vector)',
                  '(define (make-blue-edge operation argument result)\n'
                  '  (edge-record (ref operation) (ref argument) (ref result)))', reason)
    for index, field in enumerate(('operation', 'argument', 'result')):
        source = edit(source, ledger, f'(vector-ref edge {index})', f'(ref-get (edge-{field}-cell edge))', reason)
        source = edit(source, ledger, f'(vector-set! edge {index} value)',
                      f'(ref-set! (edge-{field}-cell edge) value)', reason)
    source = edit(source, ledger, '(define make-internal-graph vector)',
                  '(define (make-internal-graph nodes met joined) (graph-record (ref nodes) met joined))', reason)
    for index, after in enumerate(('(ref-get (graph-node-cell graph))', '(graph-met graph)', '(graph-joined graph)')):
        source = edit(source, ledger, f'(vector-ref graph {index})', after, reason)
    source = edit(source, ledger, '(vector-set! graph 0 nodes)', '(ref-set! (graph-node-cell graph) nodes)', reason)
    for original, after in [("(make-node 'none #t)", '(make-node (symbol-name (conform-string->symbol "none")) (blue-none))'),
                            ("(make-node 'any '())", "(make-node (symbol-name (conform-string->symbol \"any\")) (blue-ready '()))")]:
        source = edit(source, ledger, original, after, 'NONE retains its special blue marker; ANY retains a completed empty blue list.')
    lookup = form(source, '(define (lookup-op ')
    adapted = replace(lookup, "((null? edges) '())", '((null? edges) (absent))')
    adapted = replace(adapted, '(operation (car edges))) (car edges))', '(operation (car edges))) (present (car edges)))')
    source = edit(source, ledger, lookup, adapted, 'Operation lookup returns Optional BlueEdge instead of edge-or-empty-list.')
    source = edit(source, ledger, '(not (null? (lookup-op op node)))', '(present? (lookup-op op node))', 'Test lookup presence explicitly.')
    source = edit(source, ledger, '(not (null? the-edge))', '(present? the-edge)', 'Test lookup presence explicitly.')
    source = edit(source, ledger, '(cons (arg-node the-edge) (res-node the-edge))',
                  '(signature (arg-node (optional-value the-edge)) (res-node (optional-value the-edge)))', 'Typed signatures preserve the source pair fields.')
    source = edit(source, ledger, '(cons none-node any-node)', '(signature none-node any-node)', 'The missing-operation signature remains shared.')
    source = edit(source, ledger, '(define (arg pair) (car pair))', '(define (arg pair) (signature-argument pair))', 'Typed signature accessor.')
    return edit(source, ledger, '(define (res pair) (cdr pair))', '(define (res pair) (signature-result pair))', 'Typed signature accessor.')


def table_forms(source, ledger):
    source = edit(source, ledger, "(define (make-empty-table) (list 'TABLE))",
                  "(define (make-empty-table) (table-record (ref '())))",
                  'The table record is the source header pair; its rows Ref is the mutable header cdr.')
    original = form(source, '(define (lookup table ')
    adapted = replace(original, '(assq x (cdr table))', '(find-row x (table-rows table))')
    adapted = replace(adapted, '(if one', '(if (present? one)')
    adapted = replace(adapted, '(assq y (cdr one))', '(find-entry y (row-entries (optional-value one)))')
    adapted = replace(adapted, '(if two (cdr two) #f)', '(if (present? two) (present (entry-value (optional-value two))) (absent))')
    adapted = replace(adapted, '#f', '(absent)')
    source = edit(source, ledger, original, adapted, 'Two linear identity searches preserve first matching row/entry and false becomes Optional.')
    original = form(source, '(define (insert! table ')
    adapted = replace(original, '(list (cons x y))', '(list (table-entry x y))')
    adapted = replace(adapted, '(assq x (cdr table))', '(find-row x (table-rows table))')
    adapted = replace(adapted, '(if one', '(if (present? one)')
    adapted = replace(adapted, '(set-cdr! one (cons (cons y value) (cdr one)))',
                      '(set-row-entries! (optional-value one)\n'
                      '          (cons (table-entry y value) (row-entries (optional-value one))))')
    adapted = replace(adapted, '(set-cdr! table (cons (cons x (make-singleton-table y value))\n                              (cdr table)))',
                      '(set-table-rows! table\n'
                      '          (cons (row-record x (ref (make-singleton-table y value))) (table-rows table)))')
    source = edit(source, ledger, original, adapted, 'Row entries Ref is the source association cdr; insertion prepends and keeps existing aliases.')
    original = form(source, '(define (fix-table table)')
    line = form(original, '(define (fix-line line)')
    new_line = replace(line, '(car entry)', '(entry-key entry)', 2)
    new_line = replace(new_line, '(cdr entry)', '(entry-value entry)')
    new_line = replace(new_line, '(cons (entry-key entry)', '(table-entry (entry-key entry)')
    adapted = replace(original, line, new_line)
    conditional = form(adapted, '(if (null? table)')
    rows = form(conditional, '(filter-and-fix\n               ')
    rows = replace(rows, '(car entry)', '(row-key entry)', 2)
    rows = replace(rows, '(cdr entry)', '(row-entries entry)')
    rows = replace(rows, '(cons (row-key entry) (fix-line (row-entries entry)))',
                   '(row-record (row-key entry) (ref (fix-line (row-entries entry))))')
    rows = replace(rows, '(cdr table)', '(table-rows table)')
    adapted = replace(adapted, conditional, '(table-record (ref\n              ' + rows + '))')
    adapted = replace(adapted, '(define (filter-and-fix ',
                      '(: filter-and-fix (All (A B) (-> (-> A Bool) (-> A B) (List A) (List B))))\n'
                      '    (define (filter-and-fix ')
    return edit(source, ledger, original, adapted,
                'Canonicalization copies headers/rows/entries in order. Every source table has a TABLE header, so its null-table arm is unreachable.')


def mutation_forms(source, ledger):
    source = edit(source, ledger, "(define nodes-with-red-edges-out '())",
                  "(define nodes-with-red-edges-out (ref (ann '() (List Node))))", 'Local mutation becomes an explicit Ref.')
    source = edit(source, ledger, '(set! nodes-with-red-edges-out\n          (adjoin from-node nodes-with-red-edges-out))',
                  '(ref-set! nodes-with-red-edges-out\n          (adjoin from-node (ref-get nodes-with-red-edges-out)))', 'Track precisely the nodes with temporary red assumptions.')
    source = edit(source, ledger, '              nodes-with-red-edges-out)', '              (ref-get nodes-with-red-edges-out))',
                  'Success greenifies and failure clears every touched node, preserving iteration order.')
    for name in ('a', 'b', 'c', 'd'):
        source = edit(source, ledger, f"(define {name} '())", f"(define node-{name} (ref (ann (absent) (Optional Node))))",
                      'Globals are absent until setup assigns fresh nodes.')
    original = form(source, '(define (setup ')
    adapted = original
    for name in ('a', 'b', 'c', 'd'):
        adapted = replace(adapted, f'(set! {name} (make-node {name}0))', f'(ref-set! node-{name} (present (make-node {name}0)))')
    adapted = replace(adapted, "'(made a b c d)", '(unit)')
    names = {name: f'(optional-value (ref-get node-{name}))' for name in ('a', 'b', 'c', 'd')}
    source = edit(source, ledger, original, replace_tokens(adapted, names), 'Setup preserves assignment/edge order; its ignored status list becomes Unit.')
    original = form(source, '(define (test ')
    return edit(source, ledger, original, replace_tokens(original, names), 'Read the four initialized global nodes.')


def adaptation(source):
    original, ledger = source, []
    for adapt in (node_forms, edge_graph_forms, table_forms, mutation_forms):
        source = adapt(source, ledger)
    for marker in ('^', 'v'):
        before = f'(make-node (string-append "(" (internal-node-name node1) " {marker} " (internal-node-name node2) ")"))'
        source = edit(source, ledger, before, replace(before, '(make-node ', '(make-node (text-name ') + ')', 'Generated names enter the text arm without symbol conversion.')
    for table in ('met', 'joined'):
        before = f'((lookup (already-{table} graph) node1 node2))'
        source = edit(source, ledger, before, before[:-1] + ' => optional-value)', 'A cache hit unwraps Optional before recursive construction.')
    source = edit(source, ledger, '(apply make-graph', '(make-graph-list',
                  'Build the rest-argument spine explicitly and preserve element order for the dynamic apply.')
    for atom in ('phi', 'theta'):
        source = edit(source, ledger, "'" + atom, atom + '-operation',
                      'Operation literals use ordinary interned Symbol values created before timing.', 3)
    source = edit(source, ledger, "'OK", '(unit)', 'The ignored NONE-setter status becomes Unit.')
    source = edit(source, ledger, '(error #f "Can\'t classify" element)', '(datum-fail "Can\'t classify")', 'The impossible missing-class path remains fatal; no generic node printer is added.')
    source = edit(source, ledger, '(error #f ', '(datum-fail ', 'Keep the special-node accessor and setter failures.', 2)
    for expression in ('count', '(length (graph-nodes lattice))', 'new-count'):
        source = edit(source, ledger, '(display ' + expression + ')', '(display-number ' + expression + ')', 'Diagnostic numbers use the existing scalar formatter.')
    source = edit(source, ledger, '(display " -> ")', '(display-text " -> ")', 'Diagnostic strings use scalar character output.', 2)
    renames = {'eq?': 'conform-eq?', 'memq': 'conform-member?', 'list': 'conform-list', 'map': 'conform-map',
               'for-each': 'conform-for-each', 'append': 'conform-append', 'length': 'conform-length',
               'pair?': 'conform-pair?', 'caar': 'conform-caar', 'cond': 'conform-cond', 'newline': 'conform-newline'}
    renamed = replace_tokens(source, renames)
    source = edit(source, ledger, source, renamed, 'Typed list/control/identity bindings retain the original recursive list algorithms.')
    ledger.append(dict(before='', after=CONTRACTS, count=1, offsets=[0],
                       reason='Prepend explicit type contracts without changing the source definitions.'))
    source = CONTRACTS + source
    restored = source
    for entry in reversed(ledger):
        for offset in reversed(entry['offsets']):
            if restored[offset:offset + len(entry['after'])] != entry['after']:
                raise ValueError('Conform reverse edit differs at its recorded location')
            restored = restored[:offset] + entry['before'] + restored[offset + len(entry['after']):]
    if restored != original:
        raise ValueError('Conform adaptation did not reverse to the pinned kernel')
    return source, ledger


# ---- Runtime input parsing ends at concrete names and expected strings ----

INPUTS = '''(define-data Specification
  (specification (count I64 specification-count) (names (List Name) specification-names)
                 (expected (List String) specification-expected)))
(define (input-name value)
  (if (= (datum-kind value) 3) (text-name (datum-string-value value))
      (symbol-name (datum-symbol-value value))))
(define (input-names value)
  (if (datum-null? value) '()
      (cons (input-name (datum-car value)) (input-names (datum-cdr value)))))
(define (input-strings value)
  (if (datum-null? value) '()
      (cons (datum-string-value (datum-car value)) (input-strings (datum-cdr value)))))
(define (input-count value)
  (match (datum-number-value value)
    ((exact-number count) count)
    ((rational-number number) (datum-fail "Conform count must be exact"))
    ((inexact-number number) (datum-fail "Conform count must be exact"))
    ((complex-number real imaginary) (datum-fail "Conform count must be exact"))))
(define (read-specification port)
  (let* ((count (input-count (read-value! (read port))))
         (names (input-names (read-value! (read port))))
         (expected (input-strings (read-value! (read port)))))
    (if (= (conform-length names) 4) (specification count names expected)
        (datum-fail "Conform requires exactly four names"))))
(define configured (call-with-input-file "input.txt" read-specification))
(: configured-count (-> I64))
(define (configured-count) (specification-count configured))
(define (run-test names) (test (car names) (car (cdr names))
                              (car (cdr (cdr names))) (car (cdr (cdr (cdr names))))))
(define (same-strings? actual expected)
  (if (null? actual) (null? expected)
      (and (not (null? expected)) (string=? (car actual) (car expected))
           (same-strings? (cdr actual) (cdr expected)))))
'''
WORKER = '''(if (<= count 0) 0
  (let loop ((index 1) (result (run-test (specification-names configured))))
    (if (< index count) (loop (+ index 1) (run-test (specification-names configured)))
        (if (same-strings? result (specification-expected configured)) 1 0))))'''
IMPORTS = '''(import (snail strict)
  (rename (snail datum) (string->symbol conform-string->symbol)
                        (symbol->string conform-symbol->string) (symbol=? conform-symbol=?))
  (snail read) (snail io))
(define-extern print-character "benchmark" "write_char" (-> Char Unit))
'''


def program(source, driver):
    adapted, _ = adaptation(driver.upstream_kernel(source))
    return (IMPORTS + TYPES + IDENTITY + CONTROL + COMMON + adapted + INPUTS
            + '(: bench (-> I64 I64))\n(define (bench count) ' + WORKER + ')\n(unit)\n')


def chez_prelude(root):
    exports = [('conform-string->symbol', 'string->symbol'), ('conform-symbol->string', 'symbol->string'),
               ('conform-symbol=?', 'symbol=?'), 'datum-fail', 'i64->string']
    types = replace(TYPES, '(define-data (Optional T)', '(define-data Optional')
    return (reader_ports.chez_reader(root, exports) + types + CHEZ_IDENTITY + CONTROL + COMMON
            + '(define (print-character character) (display character))\n'
            + '(define (chez-name value)\n'
            + '  (if (symbol? value) (symbol-name (conform-string->symbol (symbol->string value))) (text-name value)))\n')


def specification(data):
    tokens = re.findall(r'"(?:[^"\\]|\\.)*"|\(|\)|[^\s()]+', re.sub(r';[^\n]*', '', data.decode()))
    count = int(tokens[0])
    if tokens[1] != '(' or tokens[6:8] != [')', '('] or tokens[-1] != ')':
        raise ValueError('Conform requires a count, four symbol/string names and a string result list')
    expected = [json.loads(value) for value in tokens[8:-1]]
    return dict(name='conform', count=count, inputs=[], names=tokens[2:6], expected=1,
                expected_names=expected, barriers_per_iteration=0, setup_barriers=0,
                additional_exports=['configured-count'], runtime='scalar-datum-reader')


def write_sources(files, directory, runner, driver):
    original = files['src/conform.scm'].decode()
    upstream = driver.upstream_kernel(original)
    adapted, ledger = adaptation(upstream)
    source = runner.source_text(files, 'conform', 'chez')
    replacement = chez_prelude(driver.ROOT) + adapted
    control = replace(source, upstream, replacement)
    control = replace(control, '(input1 (read))', '(input1 (map chez-name (read)))')
    restored = replace(control, '(input1 (map chez-name (read)))', '(input1 (read))')
    if replace(restored, replacement, upstream) != source:
        raise ValueError('Complete Conform Chez control did not reverse exactly')
    for system in ('chez', 'chez-adapted'):
        (directory / system).mkdir()
    for name, text in [('upstream.scm', original), ('upstream-kernel.scm', upstream), ('adapted-kernel.scm', adapted),
                       ('strict.scm', program(original, driver)), ('chez/program.scm', source), ('chez-adapted/program.scm', control)]:
        (directory / name).write_text(text)
    driver.save(directory / 'adaptation-ledger.json', dict(edits=ledger, complete_reverse_verified=True))
    for name, before, after in [('kernel-adaptation.patch', upstream, adapted), ('chez-adaptation.patch', source, control)]:
        (directory / name).write_text(''.join(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
                                                                 fromfile='original', tofile='adapted')))
    strict = (directory / 'strict.scm').read_text()
    if strict.count(adapted) != 1 or control.count(adapted) != 1:
        raise ValueError('Strict and adapted Chez must contain the exact shared Conform kernel once')
    driver.save(directory / 'source-proof.json', dict(shared_kernel_verified=True, reverse_verified=True,
        count=500, input_names=['symbol a', 'symbol b', 'string c', 'string d'], expected_names=31,
        files={name: driver.digest(directory / name) for name in
               ('upstream.scm', 'upstream-kernel.scm', 'adapted-kernel.scm', 'strict.scm',
                'chez/program.scm', 'chez-adapted/program.scm', 'input.txt', 'adaptation-ledger.json')},
        differences=['Concrete Node/BlueEdge/Graph records have explicit mutable Ref fields.',
                     'Optional memo/operation hits and Name/BlueState are closed variants.',
                     'Typed symbol->string returns a fresh string; original Chez may reuse its string.',
                     'Ignored setup and NONE-setter status values become Unit.',
                     'The impossible missing-class error omits its generic node rendering.',
                     'List membership is Boolean because source uses every memq result only as a condition.']))


# ---- Production artifacts share the same Binaryen optimized Scheme Wasm ----

NATIVE_PRINT = '''
#include <stdio.h>
#include <stdlib.h>
void write_char(uint32_t character) {
    // Conform's optional progress display consists only of ASCII digits/arrows.
    if (character > 127) abort();
    putchar((int)character);
}
'''


def build(directory, tools, environment, driver, runtime=None, observing=False):
    command = [driver.ROOT / 'scripts/build-strict', '--export', 'bench', '--export', 'configured-count']
    if observing:
        command += ['--export', 'observe-once']
    reader_ports.record(directory, 'strict-build', [*command, directory / 'strict.scm', directory / 'strict-native.wasm'], environment, driver.ROOT)
    if runtime is None:
        reader_ports.record(directory, 'rust-runtime', [tools['CARGO'], 'rustc', '--crate-type=cdylib', '--quiet', '--offline',
            '--release', '--target', 'wasm32-wasip1', '--target-dir', driver.ROOT / 'build/wasm-runtime'], environment, driver.ROOT)
        runtime = driver.ROOT / 'build/wasm-runtime/wasm32-wasip1/release/snail_runtime.wasm'
    shutil.copyfile(runtime, directory / 'runtime.wasm')
    link_artifacts(directory, environment, driver)
    build_native(directory, environment, driver, observing)
    host = (driver.HERE / 'reader-host.mjs').read_text()
    host = replace(host, 'benchmark: {barrier: () => {barriers++; return 1;}}',
                   'benchmark: {barrier: () => {barriers++; return 1;}, write_char: value => process.stdout.write(String.fromCodePoint(value))}')
    (directory / 'host.mjs').write_text(host)


def link_artifacts(directory, environment, driver):
    for label, suffix, flags in [('raw', '.raw.wasm', ['--diagnostic-prune-only']), ('optimized', '', [])]:
        reader_ports.record(directory, label + '-link', [driver.ROOT / 'scripts/link-strict-runtime', '--runtime', directory / 'runtime.wasm',
            *flags, directory / ('strict-native.wasm' + suffix), directory / (label + '.wasm')], environment, driver.ROOT)


def build_native(directory, environment, driver, observing):
    header = reader_ports.NATIVE_HEADER + '\nvoid write_char(uint32_t character);\n'
    provider = reader_ports.NATIVE_PROVIDER + NATIVE_PRINT
    entry = reader_ports.NATIVE_ENTRY
    if observing:
        entry = replace(entry, 'int64_t result = bench(count);', 'puts("call:0");\n    int64_t result = bench(count);')
    for name, text in [('native-provider.h', header), ('native-provider.c', provider), ('native-entry.c', entry)]:
        (directory / name).write_text(text)
    command = [driver.ROOT / 'scripts/build-native', '--wasm', '--c-provider', 'benchmark',
               directory / 'native-provider.h', directory / 'native-provider.c']
    if observing:
        fixtures = driver.ROOT / 'tests/strict-reader'
        command += ['--c-provider', 'reader.test', fixtures / 'observer.h', fixtures / 'observer.c']
    reader_ports.record(directory, 'native-build', [*command, '--entry-c', directory / 'native-entry.c',
        directory / 'strict-native.wasm', directory / 'native'], environment, driver.ROOT)


# ---- Full result values, ordering, and ending are checked on every system ----

def write_input(target, data, driver, accepted=True, observing=False):
    target.mkdir(parents=True, exist_ok=True)
    spec = dict(specification(data), expected=int(accepted), observe=observing)
    (target / 'input.txt').write_bytes(data)
    driver.save(target / 'spec.json', spec)
    return spec


def fixtures(data):
    text = data.decode()
    body = text.split('\n', 1)[1]
    spec = specification(data)
    yield 'once', ('1\n' + body).encode(), True
    yield 'twice', ('2\n' + body).encode(), True
    yield 'canonical', data, True
    renamed = [re.sub(r'(?<!\w)[abcd](?!\w)', lambda match: dict(zip('abcd', 'αβγδ'))[match[0]], name)
               for name in spec['expected_names']]
    yield 'unicode-names', ('1\n(α β "γ" "δ")\n(' + ' '.join(json.dumps(name, ensure_ascii=False) for name in renamed) + ')\n').encode(), True
    for label, values in [('wrong-name', ['wrong', *spec['expected_names'][1:]]),
                          ('wrong-order', list(reversed(spec['expected_names']))),
                          ('missing-name', spec['expected_names'][:-1]),
                          ('extra-name', [*spec['expected_names'], 'extra'])]:
        yield label, ('1\n(a b "c" "d")\n(' + ' '.join(map(json.dumps, values)) + ')\n').encode(), False


def check_compiled(directory, target, spec, tools, environment):
    observations = {}
    for system in ('raw', 'optimized', 'native'):
        command = ([directory / 'native'] if system == 'native' else
                   [tools['NODE'], '--disable-warning=ExperimentalWarning', directory / 'host.mjs',
                    directory / (system + '.wasm'), target / 'spec.json'])
        run = reader_ports.record(target, system, command, environment, target)
        observations[system] = compiled_result(run, spec['expected'])
    return observations


def compiled_result(run, expected):
    value = json.loads(run['stdout'])
    fields = dict(result=expected, barriers=0, setup_closed=1, worker_closed=0)
    if run['stderr'] or any(value.get(key) != amount for key, amount in fields.items()):
        raise ValueError('Conform complete output or resource lifetime differs')
    return value


def check_chez(target, data, spec, commands, environment):
    observations = {}
    for system, command in commands.items():
        run = reader_ports.record(target, system, command, environment, target, stdin=data.decode())
        name = f'conform:{spec["count"]}'
        correct = f'+!CSVLINE!+chez,{name},INCORRECT\n' not in run['stdout']
        prefix = f'Running {name}\n' + ('Elapsed time: ' if correct else 'ERROR: returned incorrect result: ')
        if (run['stderr'] or correct != bool(spec['expected']) or not run['stdout'].startswith(prefix)
                or f'+!CSVLINE!+chez,{name},' not in run['stdout']):
            raise ValueError('Conform Chez full predicate differs: ' + system)
        observations[system] = dict(correct=correct)
    return observations


def validate_workload(directory, data, commands, tools, environment, driver):
    checks = []
    for label, source, accepted in fixtures(data):
        target = directory / 'validation' / label
        spec = write_input(target, source, driver, accepted)
        observations = check_compiled(directory, target, spec, tools, environment)
        observations.update(check_chez(target, source, spec, commands, environment))
        checks.append(dict(label=label, count=spec['count'], accepted=accepted, observations=observations))
    driver.save(directory / 'canonical-validation.json', checks)


# ---- Independent original and adapted observations share concrete assertions ----

PROBE_ADAPTED = '''(define (probe-blue-state node)
  (match (internal-node-blue-edges node)
    ((blue-unresolved) 0) ((blue-none) 1) ((blue-ready edges) 2)))
(define (probe-blue-list node) (blue-state-edges (internal-node-blue-edges node)))
(define probe-rows table-rows)
(define probe-row-key row-key)
(define probe-row-values row-entries)
(define probe-entry-key entry-key)
(define probe-entry-value entry-value)
(define probe-hit? present?)
(define probe-hit-value optional-value)
(define probe-op-hit? present?)
(define probe-op-value optional-value)
(define (probe-table-same? first second) (ref-eq? (table-row-cell first) (table-row-cell second)))
(define (probe-row-same? first second) (ref-eq? (row-entry-cell first) (row-entry-cell second)))
(define (probe-edge-same? first second) (ref-eq? (edge-operation-cell first) (edge-operation-cell second)))
'''
PROBE_ORIGINAL = '''(define conform-eq? eq?)
(define conform-string->symbol string->symbol)
(define conform-symbol->string symbol->string)
(define conform-list list)
(define conform-length length)
(define conform-for-each for-each)
(define symbol-name values)
(define text-name values)
(define phi-operation 'phi)
(define theta-operation 'theta)
(define (probe-blue-state node)
  (cond ((eq? (internal-node-blue-edges node) 'NOT-A-NODE-YET) 0)
        ((eq? (internal-node-blue-edges node) #t) 1) (else 2)))
(define probe-blue-list internal-node-blue-edges)
(define probe-rows cdr)
(define probe-row-key car)
(define probe-row-values cdr)
(define probe-entry-key car)
(define probe-entry-value cdr)
(define (probe-hit? value) (if value #t #f))
(define probe-hit-value values)
(define (probe-op-hit? value) (not (null? value)))
(define probe-op-value values)
(define probe-table-same? eq?)
(define probe-row-same? eq?)
(define probe-edge-same? eq?)
'''
PROBE_SCALARS = '''(define-extern emit-i64 "reader.test" "emit_i64" (-> I64 Unit))
(define-extern emit-char "reader.test" "emit_char" (-> Char Unit))
'''
PROBE_CHEZ_SCALARS = '''(define (emit-i64 value) (display "i:") (display value) (newline))
(define (emit-char value) (display "c:") (display (char->integer value)) (newline))
'''
WORK_COUNTERS = ['meet', 'join', 'conforms', 'does-conform', 'nodes', 'blue-edges', 'lookup', 'insert',
                 'unfinished-cache-hits', 'copy-graph', 'clean-graph', 'reduce', 'classify', 'sort',
                 'split', 'merge', 'adjoin', 'intersect', 'union', 'red-assumptions', 'greenifications',
                 'red-clears', 'operation-lookup', 'successful-conforms', 'failed-conforms',
                 'clean-node', 'lattice-step', 'make-node', 'copied-node-list-lengths', 'unfinished-inserts']


def instrument_kernel(source, adapted):
    counted = [('meet graph node1 node2', 0), ('join graph node1 node2', 1), ('does-conform t1 t2', 3),
               ('lookup table x y', 6), ('xreduce graph', 11), ('classify nodes', 12), ('split-list l one two', 14),
               ('merge one two', 15), ('adjoin element set', 16), ('intersect list1 list2', 17), ('union list1 list2', 18),
               ('add-red-edge! from-node to-node', 19), ('greenify-red-edges! from-node', 20),
               ('delete-red-edges! from-node', 21), ('lookup-op op node', 22), ('clean-node node', 25),
               ('step g', 26), ('make-node name . blue-edges', 27)]
    for signature, index in counted:
        prefix = '(define (' + signature + ')'
        source = replace(source, prefix, prefix + f'\n    (probe-tick {index})')
    source = instrument_constructors(source, adapted)
    return instrument_transitions(source, adapted)


def instrument_constructors(source, adapted):
    if not adapted:
        source = replace(source, '(define make-internal-node vector)',
                         '(define (make-internal-node name green red blue) (vector name green red blue))')
        source = replace(source, '(define make-blue-edge vector)',
                         '(define (make-blue-edge operation argument result) (vector operation argument result))')
    for signature, index in [('make-internal-node name green red blue', 4), ('make-blue-edge operation argument result', 5)]:
        prefix = '(define (' + signature + ')'
        source = replace(source, prefix, prefix + f'\n    (probe-tick {index})')
    marker = '(let ((one (' + ('find-row x (table-rows table)' if adapted else 'assq x (cdr table)') + ')))'
    insertion = form(source, '(define (insert! ')
    source = replace(source, insertion, replace(insertion, marker, '(probe-insert value)\n  ' + marker))
    result = '(entry-value (optional-value two))' if adapted else '(cdr two)'
    lookup = form(source, '(define (lookup table ')
    return replace(source, lookup, replace(lookup, result, '(probe-cache-result ' + result + ')'))


def instrument_transitions(source, adapted):
    each, length = ('conform-for-each', 'conform-length') if adapted else ('for-each', 'length')
    source = replace(source, '(loop obj))', '(probe-tick 13)\n  (loop obj))')
    source = replace(source, '(make-internal-graph\n   (copy-list (graph-nodes g))',
                     '(probe-tick 9)\n  (vector-set! probe-counts 28 (+ (vector-ref probe-counts 28) (' + length + ' (graph-nodes g))))\n'
                     '  (make-internal-graph\n   (copy-list (graph-nodes g))')
    source = replace(source, '(' + each + ' clean-node (graph-nodes g))',
                     '(probe-tick 10)\n  (' + each + ' clean-node (graph-nodes g))')
    source = replace(source, '(let ((result (does-conform t1 t2)))',
                     '(probe-tick 2)\n  (let ((result (does-conform t1 t2)))\n    (probe-tick (if result 23 24))')
    source = replace(source, '      copy))', '      (probe-graph 100 copy)\n      copy))')
    source = replace(source, '(if (= new-count count)', '(probe-graph 101 new-g)\n        (if (= new-count count)')
    return source


def probe_aliases(adapted):
    result = PROBE_ADAPTED if adapted else PROBE_ORIGINAL
    for name in ('a', 'b', 'c', 'd'):
        value = f'(optional-value (ref-get node-{name}))' if adapted else name
        result += f'(define (probe-{name}) {value})\n'
    return result


def strict_probe(source, driver):
    kernel = adaptation(driver.upstream_kernel(source))[0]
    observed = instrument_kernel(kernel, True)
    probes = (driver.ROOT / 'tests/strict-conform/probe.scm').read_text()
    prefix = IMPORTS + TYPES + IDENTITY + CONTROL + COMMON + PROBE_SCALARS + probes
    return (prefix + observed + probe_aliases(True) + INPUTS
            + '(: bench (-> I64 I64))\n(define (bench count)\n'
            + '  (probe-run count (specification-names configured) (specification-expected configured)))\n'
            + '(: observe-once (-> I64))\n(define (observe-once) (bench (configured-count)))\n(unit)\n')


def chez_probe(source, adapted, driver):
    kernel = driver.upstream_kernel(source)
    kernel = adaptation(kernel)[0] if adapted else kernel
    prefix = chez_prelude(driver.ROOT) if adapted else reader_ports.CHEZ_TYPES
    probes = (driver.ROOT / 'tests/strict-conform/probe.scm').read_text()
    names = '(map chez-name (read))' if adapted else '(read)'
    return ('(import (chezscheme))\n' + prefix + PROBE_CHEZ_SCALARS + probes
            + instrument_kernel(kernel, adapted) + probe_aliases(adapted)
            + '(define probe-count (read))\n(define probe-names ' + names + ')\n'
            + '(define probe-expected (read))\n(display "call:0\\n")\n'
            + '(probe-run probe-count probe-names probe-expected)\n')


def validate_observations(directory, data, tools, environment, driver):
    target = directory / 'observations'
    once = ('1\n' + data.decode().split('\n', 1)[1]).encode()
    write_input(target, once, driver, observing=True)
    source = (directory / 'upstream.scm').read_text()
    (target / 'strict.scm').write_text(strict_probe(source, driver))
    for adapted, system in [(False, 'chez'), (True, 'chez-adapted')]:
        (target / (system + '.scm')).write_text(chez_probe(source, adapted, driver))
    build(target, tools, environment, driver, directory / 'runtime.wasm', observing=True)
    observations = collect_observations(target, tools, environment)
    original = observations['chez']
    if any(trace != original for trace in observations.values()):
        raise ValueError('Conform graph structure, work counts, alias checks or ordering differs')
    for system, trace in observations.items():
        (target / (system + '-trace.txt')).write_text(trace)
    counts = work_counts(original)
    driver.save(target / 'validation.json', dict(assertions=38, snapshots=[99, 100, 101, 102],
        work_counts=dict(zip(WORK_COUNTERS, counts)),
        systems=list(observations), identical_complete_stream=True,
        copied_spines='original vector->list(list->vector(nodes)) is retained verbatim; all node identities/order '
                      'and graph mutations are checked, but strict List exposes no pair-identity predicate'))
    validate_full_work(target, data, counts, tools, environment, driver)
    validate_fatal_probes(target, data, tools, environment, driver)


def observation_command(directory, target, system, tools):
    if system.startswith('chez'):
        return [tools['CHEZ'], '--script', directory / (system + '.scm')]
    if system == 'native':
        return [directory / 'native']
    return [tools['NODE'], '--disable-warning=ExperimentalWarning', directory / 'host.mjs',
            directory / (system + '.wasm'), target / 'spec.json']


def collect_observations(directory, tools, environment, target=None):
    target = target or directory
    observations = {}
    for system in ('chez', 'chez-adapted', 'raw', 'optimized', 'native'):
        command = observation_command(directory, target, system, tools)
        data = (target / 'input.txt').read_text() if system.startswith('chez') else None
        run = reader_ports.record(target, system, command, environment, stdin=data)
        observations[system] = observation_trace(run, system)
    return observations


def observation_trace(run, system):
    if run['stderr']:
        raise ValueError('Conform observation wrote unexpected diagnostics')
    if system.startswith('chez'):
        return run['stdout']
    if system == 'native':
        lines = run['stdout'].splitlines()
        value, trace = json.loads(lines[-1]), '\n'.join(lines[:-1]) + '\n'
    else:
        value = json.loads(run['stdout'])
        trace = '\n'.join(value['trace']) + '\n'
    if any(value.get(key) != count for key, count in dict(result=1, barriers=0, setup_closed=1, worker_closed=0).items()):
        raise ValueError('Conform observation changed the invocation or input lifetime')
    return trace


def work_counts(trace):
    tail = trace.split('i:200\ni:30\n')[-1].splitlines()[:30]
    if len(tail) != 30 or any(not re.fullmatch(r'i:\d+', value) for value in tail):
        raise ValueError('Conform observation omitted its complete work counters')
    return [int(value[2:]) for value in tail]


def validate_full_work(directory, data, counts, tools, environment, driver):
    target = directory / 'full-work'
    spec = write_input(target, data, driver, observing=True)
    observations = collect_observations(directory, tools, environment, target)
    expected = [spec['count'] * value for value in counts]
    prefix = 'call:0\n' + ''.join(f'i:202\ni:{index}\n' + ''.join(f'i:{value}\n' for value in counts)
                                 for index in range(1, spec['count'] + 1))
    expected_trace = prefix + f'i:201\ni:{spec["count"]}\ni:200\ni:30\n' + ''.join(f'i:{value}\n' for value in expected)
    for system, trace in observations.items():
        if trace != expected_trace:
            raise ValueError('Full Conform work or per-iteration result validation differs: ' + system)
        (target / (system + '-trace.txt')).write_text(trace)
    if len(set(observations.values())) != 1:
        raise ValueError('Full Conform ordered counter streams differ')
    validate_collections(directory, target, observations['native'], environment, driver)
    driver.save(target / 'validation.json', dict(iterations=spec['count'], every_result_checked=True, every_counter_delta_checked=True,
        work_counts=dict(zip(WORK_COUNTERS, expected)), systems=list(observations)))


def validate_collections(directory, target, expected, environment, driver):
    configured = dict(environment, SNAIL_GC_STATS='1', SNAIL_GC_MIN_BYTES=str(64 * 1024),
                      SNAIL_GC_HEAP_BYTES=str(64 * 1024 * 1024))
    run = reader_ports.record(target, 'native-frequent-collection', [directory / 'native'], configured)
    stats = {name: int(value) for name, value in re.findall(r'(\w+)=(\d+)(?: |$)', run['stderr'])}
    if stats.get('collections', 0) == 0 or observation_trace(dict(run, stderr=''), 'native') != expected:
        raise ValueError('Frequent exact native collections changed Conform work or per-iteration results')
    driver.save(target / 'collection-validation.json', dict(gc=stats,
        condition='all 500 results and every iteration’s 30 work counter deltas survive a 64 KiB minimum collection threshold'))


def validate_fatal_probes(directory, data, tools, environment, driver):
    cases = [(9001, 'ANY-getter'), (9002, 'NONE-getter'), (9003, 'unfinished-list-use'), (9004, 'ANY-setter')]
    checks = []
    for command, label in cases:
        target = directory / 'fatal' / label
        configured = (str(command) + '\n' + data.decode().split('\n', 1)[1]).encode()
        write_input(target, configured, driver, observing=True)
        for system in ('chez', 'chez-adapted', 'raw', 'optimized', 'native'):
            args = observation_command(directory, target, system, tools)
            run = reader_ports.record(target, system, args, environment,
                                      stdin=configured.decode() if system.startswith('chez') else None, failure=True)
            if not run['stderr']:
                raise ValueError('Conform fatal probe omitted its diagnostic or trap: ' + label)
            checks.append(dict(case=label, system=system, failed_as_required=True))
    driver.save(directory / 'fatal-validation.json', checks)


# ---- Frozen native, identical-Wasm V8, and unchanged Rust controls ----

def timing_host(driver):
    return replace((driver.HERE / 'reader-timing.mjs').read_text(), 'benchmark: {barrier: () => 1}',
                   'benchmark: {barrier: () => 1, write_char: value => process.stdout.write(String.fromCodePoint(value))}')


def prepare_native_control(original, target, tools, environment, driver):
    target.mkdir()
    for name in ('strict-native.wasm', 'spec.json', 'input.txt', 'native-provider.h', 'native-provider.c'):
        shutil.copy2(original / name, target / name)
    (target / 'native-entry.c').write_text(reader_ports.TIMING_ENTRY)
    reader_ports.record(target, 'build', [driver.ROOT / 'scripts/build-native', '--wasm', '--c-provider', 'benchmark',
        target / 'native-provider.h', target / 'native-provider.c', '--entry-c', target / 'native-entry.c',
        target / 'strict-native.wasm', target / 'native'], environment, driver.ROOT)
    run = reader_ports.record(target, 'full-count-validation', [target / 'native'], environment)
    compiled_result(run, 1)
    prepare_identical_wasm(original, target, tools, environment, driver)


def prepare_identical_wasm(original, target, tools, environment, driver):
    modules = list(target.glob('native.native-*/optimized.wasm'))
    if len(modules) != 1:
        raise ValueError('Expected one exact final Wasm for Conform native lowering')
    shutil.copy2(modules[0], target / 'native-final.wasm')
    reader_ports.prepare_scalar_provider(target / 'native-final.wasm', original / 'runtime.wasm', target, tools, environment, driver)
    run = reader_ports.record(target, 'identical-wasm-v8-validation', [tools['NODE'], '--disable-warning=ExperimentalWarning',
        original / 'host.mjs', target / 'native-final.wasm', target / 'spec.json', target / 'provider.wasm'], environment)
    compiled_result(run, 1)
    driver.save(target / 'final-module.json', dict(path=str(modules[0]), sha256=driver.digest(target / 'native-final.wasm'),
        input_sha256=driver.digest(target / 'strict-native.wasm'), executable_sha256=driver.digest(target / 'native'),
        lowering='mechanical WasmGC-to-LLVM, native64 reference slots, in-house exact tracing GC'))


def prepare_rust_control(original, target, tools, environment, driver):
    source = driver.ROOT / 'benchmarks/wasm-reference'
    shutil.copytree(source / 'src', target / 'src')
    for name in ('Cargo.toml', 'Cargo.lock', 'run-wasi.mjs'):
        shutil.copy2(source / name, target / name)
    reader_ports.record(target, 'unit-tests', [tools['CARGO'], 'test', '--offline', '--bin', 'conform'],
                        dict(environment, CARGO_TARGET_DIR=str(target / 'target')), target)
    reader_ports.build_rust_bin(target, 'conform', tools, environment)
    checks = []
    for label, data, accepted in fixtures((original / 'input.txt').read_bytes()):
        expected = specification(data)['expected_names']
        for system, command in reader_ports.rust_commands(target, 'conform', tools):
            run = reader_ports.record(target, label + '-' + system, command, environment, stdin=data.decode(), failure=not accepted)
            check_rust_result(run, expected, accepted)
            checks.append(dict(label=label, system=system, accepted=accepted))
    driver.save(target / 'validation.json', dict(checks=checks,
        source_sha256=driver.digest(target / 'src/bin/conform.rs'),
        representation='unchanged Rust arena indices, Vec graph/edge/table storage and VecDeque unstable sort; '
                       'the arena retains removed noncanonical nodes until each invocation ends; '
                       'distinct allocation, list implementations, name storage and reclamation from Scheme'))


def check_rust_result(run, expected, accepted):
    if not accepted:
        if run['stdout'] or 'assertion' not in run['stderr']:
            raise ValueError('Rust Conform failed to reject a changed complete expected result')
        return
    result = 'Result: (' + ' '.join(json.dumps(name, ensure_ascii=False) for name in expected) + ')\n'
    if run['stderr'] or not run['stdout'].startswith(result) or '+!CSVLINE!+rust-wasm,conform:' not in run['stdout']:
        raise ValueError('Rust Conform complete ordered result differs')


def prepare_controls(original, target, commands, tools, environment, driver):
    target.mkdir()
    (target / 'timing-host.mjs').write_text(timing_host(driver))
    prepare_native_control(original, target / 'native', tools, environment, driver)
    prepare_rust_control(original, target / 'rust', tools, environment, driver)
    matrix_port.retain_toolchain(target, tools, environment, driver)
    driver.save(target / 'commands.json', comparison_commands(original, target, commands, tools))
    driver.save(target / 'prepared.json', dict(status='ready', timing='not measured; root coordinates the clean timing window',
        hashes={str(path.relative_to(target)): driver.digest(path) for path in target.rglob('*') if path.is_file()}))


def comparison_commands(original, target, commands, tools):
    node = [tools['NODE'], '--disable-warning=ExperimentalWarning', str(target / 'timing-host.mjs')]
    wasm = str(target / 'native/native-final.wasm')
    result = [dict(system='snail-production-v8', command=node + [str(original / 'optimized.wasm'), str(original / 'spec.json')], cwd=str(original)),
              dict(system='snail-native64', command=[str(target / 'native/native')], cwd=str(target / 'native')),
              dict(system='snail-identical-wasm-v8', command=node + [wasm, str(original / 'spec.json'), str(target / 'native/provider.wasm')], cwd=str(original))]
    for system, command in commands.items():
        result.append(dict(system=system, command=list(map(str, command)), cwd=str(original), stdin_file=str(original / 'input.txt')))
    for system, command in reader_ports.rust_commands(target / 'rust', 'conform', tools):
        if system != 'raw-wasm':
            result.append(dict(system='rust-' + system, command=list(map(str, command)), cwd=str(original), stdin_file=str(original / 'input.txt')))
    return result


# ---- Preparation is complete before any separately coordinated timing ----

def prepare_case(files, output, runner, tools, environment, driver):
    previous = signal.signal(signal.SIGTERM, reader_ports.interrupted)
    try:
        return prepare_workload(files, output, runner, tools, environment, driver)
    finally:
        signal.signal(signal.SIGTERM, previous)


def prepare_workload(files, output, runner, tools, environment, driver):
    directory, data = output / 'conform', files['inputs/conform.input']
    spec = write_input(directory, data, driver)
    write_sources(files, directory, runner, driver)
    build(directory, tools, environment, driver)
    commands = reader_ports.build_chez(directory, runner, tools, environment)
    validate_workload(directory, data, commands, tools, environment, driver)
    validate_observations(directory, data, tools, environment, driver)
    prepare_controls(directory, directory / 'controls', commands, tools, environment, driver)
    return dict(name='conform', status='ready', spec=spec, chez_commands=commands,
                systems=['strict', 'native', 'chez', 'chez-adapted'],
                hashes={str(path.relative_to(directory)): driver.digest(path)
                        for path in directory.rglob('*') if path.is_file()})
