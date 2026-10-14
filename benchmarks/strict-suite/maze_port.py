"""Preserve Shivers's complete hexagonal maze, mutable identities, and output."""

import difflib
import hashlib
import json
import re
import shutil
import signal

from data_ports import form, replace
from lattice_port import replace_tokens
import matrix_port
import reader_ports


# ---- Concrete fields preserve the source's mutable objects and aliases ----

TYPES = '''(define-data (Optional T) (absent) (present (value T optional-value)))
(define-data Reachable
  (reachable-record (size (Ref I64) reachable-size)
                    (next (Ref (Optional Reachable)) reachable-next)))
(define-data Coordinate (coordinate (x I64 coordinate-x) (y I64 coordinate-y)))
(define-data Cell
  (uninitialized-cell)
  (cell-record (reachable (Ref Reachable) cell-reachable-field)
               (id (Ref Coordinate) cell-id-field)
               (walls (Ref I64) cell-walls-field)
               (parent (Ref (Optional Cell)) cell-parent-field)
               (mark (Ref Bool) cell-mark-field)))
(define-data Wall
  (wall-record (owner (Ref Cell) wall-owner-field)
               (neighbor (Ref Cell) wall-neighbor-field)
               (bit (Ref I64) wall-bit-field)))
(define-data HexArray
  (harr-record (rows (Ref I64) harr-rows-field)
               (columns (Ref I64) harr-columns-field)
               (elements (Ref (Vector Cell)) harr-elements-field)))
(define-data Entrances
  (entrances (top (Optional I64) entrance-top) (bottom (Optional I64) entrance-bottom)))
(define-data LongestPath
  (longest-path (length I64 longest-length)
                (top (Optional I64) longest-top) (bottom (Optional I64) longest-bottom)))
(define-data Maze
  (maze-result (cells HexArray maze-cells) (entrance I64 maze-entrance) (exit I64 maze-exit)))
(define-data Output
  (initial-output) (character-output (characters (List Char) output-characters)) (other-output))
'''
COMMON = '''(: present? (All (T) (-> (Optional T) Bool)))
(define (present? value) (match value ((absent) #f) ((present item) #t)))
(define (same-set? left right) (ref-eq? (reachable-size left) (reachable-size right)))
(define (same-set-next? left next)
  (and (present? next) (same-set? left (optional-value next))))
;; A fresh field Ref supplies stable identity even if that field is mutated.
(define (same-cell? left right) (ref-eq? (cell-walls-field left) (cell-walls-field right)))
(define (same-cell-parent? cell parent)
  (and (present? parent) (same-cell? cell (optional-value parent))))
(define (maze-zero? value) (= value 0))
(define (maze-odd? value) (not (= (remainder value 2) 0)))
(: maze-exact-integer? (-> I64 Bool))
(define (maze-exact-integer? value) #t)
(: maze-reverse (All (T) (-> (List T) (List T))))
(define (maze-reverse values)
  (let loop ((values values) (result '()))
    (if (null? values) result (loop (cdr values) (cons (car values) result)))))
;; This is only the source's immediate lexical escape: stop before the next
;; vector lookup or index update. No continuation escapes or can be resumed.
(: vector-until-rev (All (T) (-> (-> T Bool) (Vector T) Unit)))
(define (vector-until-rev procedure values)
  (let loop ((index (- (vector-length values) 1)))
    (when (>= index 0)
      (unless (procedure (vector-ref values index)) (loop (- index 1))))))
(define (same-characters? actual expected)
  (if (null? actual) (null? expected)
      (and (not (null? expected)) (char=? (car actual) (car expected))
           (same-characters? (cdr actual) (cdr expected)))))
(define (same-output? actual expected)
  (match actual
    ((initial-output) (match expected ((initial-output) #t)
      ((character-output chars) #f) ((other-output) #f)))
    ((character-output chars) (match expected ((initial-output) #f)
      ((character-output wanted) (same-characters? chars wanted)) ((other-output) #f)))
    ((other-output) #f)))
'''
CONTROL = '''(define-syntax maze-cond
  (syntax-rules (else =>)
    ((_) (unit))
    ((_ (else body ...)) (begin body ...))
    ((_ (test => procedure) rest ...)
     (let ((value test))
       (if (present? value) (procedure (optional-value value)) (maze-cond rest ...))))
    ((_ (test body ...) rest ...) (if test (begin body ...) (maze-cond rest ...)))))
(define-syntax maze-step
  (syntax-rules () ((_ variable) variable) ((_ variable step) step)))
(define-syntax maze-do
  (syntax-rules ()
    ((_ ((variable initial step ...) ...) (test result ...) body ...)
     (let loop ((variable initial) ...)
       (if test (begin (unit) result ...)
           (begin body ... (loop (maze-step variable step ...) ...)))))))
'''
CONTRACTS = '''(: bitwise-not (-> I64 I64))
(: bitwise-and (-> I64 I64 I64))
(: div (-> I64 I64 I64))
(: mod (-> I64 I64 I64))
(: random-state (-> I64 (Ref I64)))
(: rand (-> (Ref I64) I64))
(: random-int (-> I64 (Ref I64) I64))
(: base-set (-> I64 Reachable))
(: get-set-root (-> Reachable Reachable))
(: union! (-> Reachable Reachable Unit))
(: vector-for-each-rev (All (T) (-> (-> T Unit) (Vector T) Unit)))
(: permute-vec! (All (T) (-> (Vector T) (Ref I64) (Vector T))))
(: dig-maze (-> (Vector Wall) I64 Unit))
(: dfs-maze (-> HexArray Cell (-> (-> Cell Unit) HexArray Cell Unit) Unit))
(: reroot-maze (-> Cell Unit))
(: path-length (-> Cell I64))
(: mark-path (-> Cell Unit))
(: harr-tabulate (-> I64 I64 (-> I64 I64 Cell) HexArray))
(: harr-for-each (-> (-> Cell Unit) HexArray Unit))
(: for-each-hex-child (-> (-> Cell Unit) HexArray Cell Unit))
(: make-wall-vec (-> HexArray (Vector Wall)))
(: pick-entrances (-> HexArray Entrances))
(: make-maze (-> I64 I64 Maze))
(: pmaze (-> I64 I64 Unit))
(: print-hexmaze (-> HexArray I64 Unit))
(: run (-> I64 I64 (List Char)))
'''


# ---- Counted edits reverse to the complete pinned kernel byte for byte ----

def edit(source, ledger, before, after, reason, count=1):
    result = replace(source, before, after, count)
    offsets = [match.start() + index * (len(after) - len(before))
               for index, match in enumerate(re.finditer(re.escape(before), source))]
    ledger.append(dict(before=before, after=after, count=count, offsets=offsets, reason=reason))
    return result


def numeric_and_random(source, ledger):
    reason = 'Keep the recursive integer helpers; express unary/variadic arithmetic with binary operations.'
    source = edit(source, ledger, '(- (- x) 1)', '(- (- 0 x) 1)', reason)
    source = edit(source, ledger, '(+ z z 1)', '(+ (+ z z) 1)', reason)
    reason = 'The random state car is the sole mutable seed; its unused false cdr is omitted.'
    for before, after in [('(cons n #f)', '(ref n)'), ('(car state)', '(ref-get state)'),
                          ('(set-car! state val)', '(ref-set! state val)')]:
        source = edit(source, ledger, before, after, reason)
    return source


def union_find(source, ledger):
    reason = 'Typed size and optional parent Refs preserve set identity and both compression walks.'
    replacements = [("(cons nelts '())", '(reachable-record (ref nelts) (ref (absent)))'),
                    ('(cdr r)', '(ref-get (reachable-next r))'), ('(cdr x)', '(ref-get (reachable-next x))'),
                    ('(pair? next)', '(present? next)'), ('(eq? r s)', '(same-set? r s)'),
                    ('(eq? r next)', '(same-set-next? r next)'),
                    ('(set-cdr! x r)', '(ref-set! (reachable-next x) (present r))'),
                    ('(eq? (get-set-root s1) (get-set-root s2))', '(same-set? (get-set-root s1) (get-set-root s2))'),
                    ('(car (get-set-root s))', '(ref-get (reachable-size (get-set-root s)))')]
    for before, after in replacements:
        source = edit(source, ledger, before, after, reason)
    source = edit(source, ledger, '(lp next)', '(lp (optional-value next))', reason, 2)
    for child, parent in [('r2', 'r1'), ('r1', 'r2')]:
        source = edit(source, ledger, f'(set-cdr! {child} {parent})',
                      f'(ref-set! (reachable-next {child}) (present {parent}))', reason)
        source = edit(source, ledger, f'(set-car! {parent} n)', f'(ref-set! (reachable-size {parent}) n)', reason)
    return source


def record_fields(source, ledger):
    reason = 'Each mutable heterogeneous vector field becomes a named typed Ref; aliases remain shared.'
    constructors = [("(vector 'wall owner neighbor bit)", '(wall-record (ref owner) (ref neighbor) (ref bit))'),
                    ("(vector 'cell reachable id -1 #f #f)",
                     '(cell-record (ref reachable) (ref id) (ref -1) (ref (absent)) (ref #f))'),
                    ("(vector 'harr nrows ncols elts)", '(harr-record (ref nrows) (ref ncols) (ref elts))')]
    for before, after in constructors:
        source = edit(source, ledger, before, after, reason)
    schemas = [('wall', ['owner', 'neighbor', 'bit'], ['owner', 'neighbor', 'bit']),
               ('cell', ['reachable', 'id', 'walls', 'parent', 'mark'], ['reachable', 'id', 'walls', 'parent', 'mark']),
               ('harr', ['nrows', 'ncols', 'elts'], ['rows', 'columns', 'elements'])]
    for record, public, fields in schemas:
        for index, (name, field) in enumerate(zip(public, fields), 1):
            for prefix, before, after in [(f'(define ({record}:{name} ', f'(vector-ref o {index})',
                                           f'(ref-get ({record}-{field}-field o))'),
                                          (f'(define (set-{record}:{name} ', f'(vector-set! o {index} v)',
                                           f'(ref-set! ({record}-{field}-field o) v)')]:
                original = form(source, prefix)
                source = edit(source, ledger, original, replace(original, before, after), reason)
    return source


def parent_links(source, ledger):
    reason = 'False parent links become Optional Cell without changing DFS or reroot order.'
    replacements = [('(let search ((node root) (parent #f))', '(let search ((node root) (parent (absent)))'),
                    ('(new-parent #f)', '(new-parent (absent))'),
                    ('(eq? child parent)', '(same-cell-parent? child parent)'),
                    ('(search child node)', '(search child (present node))'),
                    ('(if old-parent (lp old-parent node))',
                     '(if (present? old-parent) (lp (optional-value old-parent) (present node)))'),
                    ('(cell:parent node)))\n      ((not node)', '(cell:parent (optional-value node))))\n      ((not (present? node))')]
    for before, after in replacements:
        source = edit(source, ledger, before, after, reason)
    return source


def lexical_escape(source, ledger):
    original = form(source, '(define (dig-maze ')
    adapted = replace(original, '  (call-with-current-continuation\n   (lambda (quit)\n     (vector-for-each-rev',
                      '  (vector-until-rev')
    adapted = replace(adapted, '(if (not (set-equal? set1 set2))', '(and (not (set-equal? set1 set2))')
    adapted = replace(adapted, '(if (= (set-size set1) ncells) (quit #f))', '(= (set-size set1) ncells)')
    adapted = replace(adapted, '      walls))))', '      walls))')
    return edit(source, ledger, original, adapted,
                'The immediate, unstored quit skips the remaining walls after union/write/size check. '
                'Its ignored result becomes Unit; this does not implement general continuations.')


def arrays_and_walls(source, ledger):
    reason = 'Every vector slot starts as an explicit unfinished Cell; original row/column fill order remains.'
    for dimensions in ('(* r c)', '(* nrows ncols)'):
        before = '(make-vector ' + dimensions + ')'
        source = edit(source, ledger, before, before[:-1] + ' (uninitialized-cell))', reason)
    source = edit(source, ledger, '(cons x y)', '(coordinate x y)', 'Coordinate fields keep the immutable source pair.')
    for before, after in [('(car id)', '(coordinate-x id)'), ('(cdr id)', '(coordinate-y id)')]:
        source = edit(source, ledger, before, after, 'Read the two coordinate fields.')
    reason = 'The local wall-list binding becomes a Ref; every prepend and final list->vector remains.'
    for before, after in [("(walls '())", "(walls (ref (ann '() (List Wall))))"),
                          ('(set! walls (cons (make-wall o n b) walls))',
                           '(ref-set! walls (cons (make-wall o n b) (ref-get walls)))'),
                          ('(list->vector walls)', '(list->vector (ref-get walls))')]:
        source = edit(source, ledger, before, after, reason)
    return source


def entrance_results(source, ledger):
    original = form(source, '(define (pick-entrances ')
    adapted = original
    replacements = [('(entrance #f)', '(entrance (absent))'), ('(exit #f)', '(exit (absent))'),
                    ('(vector entrance exit)', '(entrances entrance exit)'),
                    ('(vector max-len entrance exit)', '(longest-path max-len entrance exit)'),
                    ('(bt-lp this-len tcol bcol ', '(bt-lp this-len (present tcol) (present bcol) ')]
    replacements += [(f'(vector-ref result {index})', '(' + getter + ' result)')
                     for index, getter in enumerate(('longest-length', 'longest-top', 'longest-bottom'))]
    for before, after in replacements:
        adapted = replace(adapted, before, after)
    source = edit(source, ledger, original, adapted,
                  'Typed result fields retain false initial choices and the original strict-greater tie rule.')
    original = form(source, '(define (make-maze ')
    adapted = replace(original, '(vector-ref result 0)', '(optional-value (entrance-top result))')
    adapted = replace(adapted, '(vector-ref result 1)', '(optional-value (entrance-bottom result))')
    adapted = replace(adapted, '(vector cells entrance exit)', '(maze-result cells entrance exit)')
    source = edit(source, ledger, original, adapted, 'Unwrap choices only after the nonempty candidate search completes.')
    original = form(source, '(define (pmaze ')
    adapted = original
    for index, getter in enumerate(('maze-cells', 'maze-entrance', 'maze-exit')):
        adapted = replace(adapted, f'(vector-ref result {index})', '(' + getter + ' result)')
    return edit(source, ledger, original, adapted, 'Read the complete maze result record.')


def output_mutation(source, ledger):
    reason = ('The output binding becomes an explicit list Ref. Its unobserved initial false becomes empty; '
              'run still resets it before any rendering, then reverses the complete list.')
    replacements = [('(define output #f)', "(define output (ref (ann '() (List Char))))"),
                    ('(set! output (cons c output))', '(ref-set! output (cons c (ref-get output)))'),
                    ("(set! output '())", "(ref-set! output '())"),
                    ('(reverse output)', '(maze-reverse (ref-get output))')]
    for before, after in replacements:
        source = edit(source, ledger, before, after, reason)
    return source


def adaptation(source):
    original, ledger = source, []
    for operation in (numeric_and_random, union_find, record_fields, parent_links, lexical_escape,
                      arrays_and_walls, entrance_results, output_mutation):
        source = operation(source, ledger)
    renamed = replace_tokens(source, dict(cond='maze-cond', do='maze-do', **{
        'zero?': 'maze-zero?', 'odd?': 'maze-odd?', 'exact-integer?': 'maze-exact-integer?'}))
    source = edit(source, ledger, source, renamed, 'Typed control syntax and exact integer predicates preserve the source operations.')
    ledger.append(dict(before='', after=CONTRACTS, count=1, offsets=[0], reason='Explicit signatures.'))
    source = CONTRACTS + source
    restored = source
    for entry in reversed(ledger):
        for offset in reversed(entry['offsets']):
            if restored[offset:offset + len(entry['after'])] != entry['after']:
                raise ValueError('Maze edit no longer reverses at its recorded offset')
            restored = restored[:offset] + entry['before'] + restored[offset + len(entry['after']):]
    if restored != original:
        raise ValueError('Maze kernel did not restore the pinned source exactly')
    return source, ledger


# ---- Runtime reader setup and the complete final character-list predicate ----

INPUTS = '''(define-data Specification
  (specification (count I64 specification-count) (rows I64 specification-rows)
                 (columns I64 specification-columns) (expected Output specification-expected)))
(define (maze-input-integer value)
  (match (datum-number-value value)
    ((exact-number number) number)
    ((inexact-number number) (datum-fail "Maze requires exact integers"))
    ((complex-number real imaginary) (datum-fail "Maze requires exact integers"))))
(define (maze-input-output value)
  (if (and (= (datum-kind value) 1) (not (datum-boolean-value value))) (initial-output)
      (let loop ((tail value) (result (ann '() (List Char))))
        (if (datum-null? tail) (character-output (maze-reverse result))
            (if (and (datum-pair? tail) (= (datum-kind (datum-car tail)) 2))
                (loop (datum-cdr tail) (cons (datum-character-value (datum-car tail)) result))
                (other-output))))))
(define (read-specification port)
  (let* ((count (maze-input-integer (read-value! (read port))))
         (rows (maze-input-integer (read-value! (read port))))
         (columns (maze-input-integer (read-value! (read port))))
         (expected (maze-input-output (read-value! (read port)))))
    (specification count rows columns expected)))
(define configured (call-with-input-file "input.txt" read-specification))
(: configured-count (-> I64))
(define (configured-count) (specification-count configured))
(define-extern barrier "benchmark" "barrier" (-> Bool))
(: hide (All (T) (-> I64 T T)))
(define (hide count value) (if (barrier) value (unreachable)))
'''
WORKER = '''(let loop ((index 0) (result (initial-output)))
  (if (< index count)
      (loop (+ index 1) (character-output
        (run (hide count (specification-rows configured)) (hide count (specification-columns configured)))))
      (if (same-output? result (specification-expected configured)) 1 0)))'''
IMPORTS = '(import (snail strict) (snail datum) (snail read) (snail io))\n'
CHEZ_INPUTS = '''(define (chez-output value)
  (cond ((eq? value #f) (initial-output))
        ((and (list? value) (for-all char? value)) (character-output value))
        (else (other-output))))
(define (original-output value)
  (match value ((initial-output) #f) ((character-output chars) chars) ((other-output) #t)))
'''
CHEZ_EXACT_INTEGER = '''(define (exact-integer? z) (and (exact? z) (integer? z)))
'''


def program(source, driver):
    kernel, _ = adaptation(driver.upstream_kernel(source))
    return (IMPORTS + TYPES + COMMON + CONTROL + kernel + INPUTS
            + '(: bench (-> I64 I64))\n(define (bench count) ' + WORKER + ')\n(unit)\n')


def chez_prelude():
    return (reader_ports.CHEZ_TYPES + replace(TYPES, '(define-data (Optional T)', '(define-data Optional')
            + COMMON + CONTROL + CHEZ_INPUTS)


def specification(data):
    count, rows, columns, expected = data.decode().split('\n', 3)
    return dict(name='maze', count=int(count), rows=int(rows), columns=int(columns), inputs=[],
                expected=1, expected_datum=expected.strip(), barriers_per_iteration=2, setup_barriers=0,
                additional_exports=['configured-count'], runtime='scalar-datum-reader')


def write_sources(files, directory, runner, driver):
    original = files['src/maze.scm'].decode()
    upstream = driver.upstream_kernel(original)
    adapted, ledger = adaptation(upstream)
    source = runner.source_text(files, 'maze', 'chez')
    replacements = [(upstream, chez_prelude() + adapted), ('(output (read))', '(output (chez-output (read)))'),
                    ('(lambda () (run (hide count input1) (hide count input2)))',
                     '(lambda () (character-output (run (hide count input1) (hide count input2))))'),
                    ('(equal? result output)', '(same-output? result output)'),
                    ('(result #f)', '(result (initial-output))'), ('(write result)', '(write (original-output result))')]
    control = source
    for before, after in replacements:
        control = replace(control, before, after)
    restored = control
    for before, after in reversed(replacements):
        restored = replace(restored, after, before)
    if restored != source:
        raise ValueError('Maze complete adapted Chez source did not reverse')
    for system in ('chez', 'chez-adapted'):
        (directory / system).mkdir()
    for name, text in [('upstream.scm', original), ('upstream-kernel.scm', upstream), ('adapted-kernel.scm', adapted),
                       ('strict.scm', program(original, driver)), ('chez/program.scm', source), ('chez-adapted/program.scm', control)]:
        (directory / name).write_text(text)
    driver.save(directory / 'adaptation-ledger.json', dict(edits=ledger, complete_reverse_verified=True,
        full_chez_edits=[dict(before=before, after=after, count=1) for before, after in replacements]))
    for name, before, after in [('kernel-adaptation.patch', upstream, adapted), ('chez-adaptation.patch', source, control)]:
        (directory / name).write_text(''.join(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
                                                                 fromfile='original', tofile='adapted')))
    if program(original, driver).count(adapted) != 1 or control.count(adapted) != 1:
        raise ValueError('Maze strict and Chez bodies must share the exact adapted kernel once')


# ---- Complete outputs and rejected expectations execute on all runtimes ----

def write_input(target, data, driver, accepted=True, observing=False):
    target.mkdir(parents=True, exist_ok=True)
    spec = dict(specification(data), expected=int(accepted), observe=observing)
    (target / 'input.txt').write_bytes(data)
    driver.save(target / 'spec.json', spec)
    return spec


def character_tokens(expected):
    tokens = re.findall(r'#\\(?:newline|space|.)', expected)
    rest = re.sub(r'#\\(?:newline|space|.)', '', expected)
    if re.sub(r'[\s()]', '', rest) or not rest.strip().startswith('(') or not rest.strip().endswith(')'):
        raise ValueError('Expected a complete character-list fixture')
    return tokens


def fixture_input(count, rows, columns, expected):
    return f'{count}\n{rows}\n{columns}\n{expected}\n'.encode()


def fixtures(data):
    spec = specification(data)
    rows, columns, expected = spec['rows'], spec['columns'], spec['expected_datum']
    values = character_tokens(expected)
    yield 'once', fixture_input(1, rows, columns, expected), True
    yield 'twice', fixture_input(2, rows, columns, expected), True
    yield 'canonical', data, True
    for label, changed in [('wrong-character', [r'#\λ', *values[1:]]), ('missing-character', values[:-1]),
                           ('extra-character', [*values, r'#\space']), ('wrong-order', list(reversed(values))),
                           ('non-character', ['7', *values[1:]])]:
        yield label, fixture_input(1, rows, columns, '(' + ' '.join(changed) + ')'), False
    yield 'zero-false', fixture_input(0, rows, columns, '#f'), True
    yield 'zero-list', fixture_input(0, rows, columns, expected), False
    yield 'negative-false', fixture_input(-1, rows, columns, '#f'), True


def compiled_result(run, spec):
    value = json.loads(run['stdout'])
    fields = dict(result=spec['expected'], barriers=spec['barriers_per_iteration'] * max(0, spec['count']),
                  setup_closed=1, worker_closed=0)
    if run['stderr'] or any(value.get(key) != expected for key, expected in fields.items()):
        raise ValueError('Maze complete result, opacity calls, or input lifetime differs')
    return value


def compiled_commands(directory, target, tools, driver):
    node = [tools['NODE'], '--disable-warning=ExperimentalWarning', driver.HERE / 'reader-host.mjs']
    return [('raw', [*node, directory / 'raw.wasm', target / 'spec.json']),
            ('optimized', [*node, directory / 'optimized.wasm', target / 'spec.json']),
            ('native', [directory / 'native'])]


def check_chez(run, spec):
    name = f'maze:{spec["rows"]}:{spec["columns"]}:{spec["count"]}'
    suffix = f'+!CSVLINE!+chez,{name},'
    accepted = not run['stdout'].endswith(suffix + 'INCORRECT\n')
    prefix = f'Running {name}\n' + ('Elapsed time: ' if accepted else 'ERROR: returned incorrect result: ')
    if (run['stderr'] or accepted != bool(spec['expected']) or not run['stdout'].startswith(prefix)
            or suffix not in run['stdout']):
        raise ValueError('Maze complete Chez predicate or output frame differs')
    return dict(accepted=accepted)


def validate_input(directory, label, data, accepted, commands, tools, environment, driver):
    target = directory / 'validation' / label
    spec = write_input(target, data, driver, accepted)
    results = {}
    for system, command in compiled_commands(directory, target, tools, driver):
        results[system] = compiled_result(reader_ports.record(target, system, command, environment, target), spec)
    for system, command in commands.items():
        results[system] = check_chez(reader_ports.record(target, system, command, environment, target, stdin=data.decode()), spec)
    driver.save(target / 'validation.json', results)
    return dict(label=label, count=spec['count'], accepted=accepted, systems=list(results))


def dimension_fixtures(directory, tools, environment, driver):
    source = (directory / 'upstream-kernel.scm').read_text()
    target = directory / 'dimension-oracles'
    target.mkdir()
    for rows, columns in [(1, 1), (1, 2), (2, 1), (2, 2), (3, 3), (4, 4)]:
        label = f'{rows}x{columns}'
        script = target / (label + '.scm')
        script.write_text('(import (chezscheme))\n' + CHEZ_EXACT_INTEGER + source
                          + f'\n(write (run {rows} {columns})) (newline)\n')
        result = reader_ports.record(target, label, [tools['CHEZ'], '--script', script], environment)
        if result['stderr']:
            raise ValueError('Original Chez dimension oracle emitted a diagnostic')
        character_tokens(result['stdout'])
        yield label, fixture_input(1, rows, columns, result['stdout'].strip()), True


def validate_workload(directory, data, commands, tools, environment, driver):
    cases = list(fixtures(data)) + list(dimension_fixtures(directory, tools, environment, driver))
    results = [validate_input(directory, *case, commands, tools, environment, driver) for case in cases]
    driver.save(directory / 'validation.json', results)


# ---- Production builds always retain raw and Binaryen optimized artifacts ----

def build(directory, tools, environment, driver, runtime=None, observing=False):
    exports = ['bench', 'configured-count'] + (['observe-once'] if observing else [])
    reader_ports.record(directory, 'strict-build', [driver.ROOT / 'scripts/build-strict',
        *[part for name in exports for part in ('--export', name)], directory / 'strict.scm',
        directory / 'strict-native.wasm'], environment, driver.ROOT)
    if runtime is None:
        reader_ports.record(directory, 'rust-runtime', [tools['CARGO'], 'rustc', '--crate-type=cdylib',
            '--quiet', '--offline', '--release', '--target', 'wasm32-wasip1', '--target-dir',
            driver.ROOT / 'build/wasm-runtime'], environment, driver.ROOT)
        runtime = driver.ROOT / 'build/wasm-runtime/wasm32-wasip1/release/snail_runtime.wasm'
    shutil.copy2(runtime, directory / 'runtime.wasm')
    for label, suffix, flags in [('raw', '.raw.wasm', ['--diagnostic-prune-only']), ('optimized', '', [])]:
        reader_ports.record(directory, label + '-link', [driver.ROOT / 'scripts/link-strict-runtime',
            '--runtime', directory / 'runtime.wasm', *flags, directory / ('strict-native.wasm' + suffix),
            directory / (label + '.wasm')], environment, driver.ROOT)
    build_native(directory, environment, driver, observing)


def build_native(directory, environment, driver, observing=False, timing=False):
    provider = reader_ports.NATIVE_PROVIDER
    if timing:
        provider = replace(provider, 'count++; return 1;', 'return 1;')
    for name, text in [('native-provider.h', reader_ports.NATIVE_HEADER),
                       ('native-provider.c', provider),
                       ('native-entry.c', reader_ports.TIMING_ENTRY if timing else reader_ports.NATIVE_ENTRY)]:
        (directory / name).write_text(text)
    observer = (['--c-provider', 'reader.test', driver.ROOT / 'tests/strict-reader/observer.h',
                 driver.ROOT / 'tests/strict-reader/observer.c'] if observing else [])
    reader_ports.record(directory, 'native-build', [driver.ROOT / 'scripts/build-native', '--wasm',
        '--c-provider', 'benchmark', directory / 'native-provider.h', directory / 'native-provider.c',
        *observer, '--entry-c', directory / 'native-entry.c', directory / 'strict-native.wasm',
        directory / 'native'], environment, driver.ROOT)


# ---- Diagnostics observe each ordered mutation without changing clean runs ----

COUNTER_NAMES = ['run', 'cell', 'wall', 'rand', 'bitwise-and', 'div', 'mod', 'get-set-root',
                 'union', 'visited-wall', 'reroot', 'path-length', 'write-character',
                 'parent-write', 'mark-write', 'compression-write']
PROBE_ADAPTED = '''(define (probe-x cell) (coordinate-x (cell:id cell)))
(define (probe-y cell) (coordinate-y (cell:id cell)))
(define probe-set-same? same-set?)
(define probe-cell-same? same-cell?)
(define (probe-set-linked? set) (present? (ref-get (reachable-next set))))
(define (probe-set-next set) (optional-value (ref-get (reachable-next set))))
(define (probe-set-size-field set) (ref-get (reachable-size set)))
(define (probe-parent-present? cell) (present? (cell:parent cell)))
(define (probe-parent-cell cell) (optional-value (cell:parent cell)))
'''
PROBE_ORIGINAL = '''(define (probe-x cell) (car (cell:id cell)))
(define (probe-y cell) (cdr (cell:id cell)))
(define probe-set-same? eq?)
(define probe-cell-same? eq?)
(define (probe-set-linked? set) (pair? (cdr set)))
(define probe-set-next cdr)
(define probe-set-size-field car)
(define (probe-parent-present? cell) (if (cell:parent cell) #t #f))
(define probe-parent-cell cell:parent)
'''
PROBE_SCALARS = '''(define-extern emit-i64 "reader.test" "emit_i64" (-> I64 Unit))
(define-extern emit-char "reader.test" "emit_char" (-> Char Unit))
'''
PROBE_CHEZ_SCALARS = '''(define (emit-i64 value) (display "i:") (display value) (newline))
(define (emit-char value) (display "c:") (display (char->integer value)) (newline))
'''


def instrument_kernel(source, adapted):
    if adapted:
        source = replace(source, '(: permute-vec! (All (T) (-> (Vector T) (Ref I64) (Vector T))))',
                         '(: permute-vec! (-> (Vector Wall) (Ref I64) (Vector Wall)))')
    signatures = ['run nrows ncols', 'make-cell reachable id', 'make-wall owner neighbor bit',
                  'rand state', 'bitwise-and x y', 'div x y', 'mod x y', 'get-set-root s',
                  'union! s1 s2', None, 'reroot-maze new-root', 'path-length cell',
                  'write-ch c', 'set-cell:parent o v', 'set-cell:mark o v']
    for index, signature in enumerate(signatures):
        if signature:
            prefix = '(define (' + signature + ')'
            source = replace(source, prefix, prefix + f'\n  (probe-tick {index})')
    source = replace(source, '(lambda (wall)', '(lambda (wall)\n        (probe-visit wall)')
    compression = '(ref-set! (reachable-next x) (present r))' if adapted else '(set-cdr! x r)'
    source = replace(source, compression, '(begin (probe-tick 15) ' + compression + ')')
    return instrument_snapshots(source, adapted)


def instrument_snapshots(source, adapted):
    vector = '(list->vector (ref-get walls))' if adapted else '(list->vector walls)'
    source = replace(source, vector, '(probe-wall-vector 100 ' + vector + ')')
    original = form(source, '(define (permute-vec! ')
    source = replace(source, original, replace(original, '  v)', '  (probe-wall-vector 101 v)\n  v)'))
    source = replace(source, '(dig-maze walls (* nrows ncols))',
                     '(dig-maze walls (* nrows ncols))\n    (probe-after-dig cells walls)')
    result = '(maze-result cells entrance exit)' if adapted else '(vector cells entrance exit)'
    return replace(source, result, '(begin (probe-finished-maze cells entrance exit) ' + result + ')')


def strict_probe(source, driver):
    kernel = adaptation(driver.upstream_kernel(source))[0]
    probes = (driver.ROOT / 'tests/strict-maze/probe.scm').read_text()
    return (IMPORTS + TYPES + COMMON + CONTROL + PROBE_SCALARS + probes
            + instrument_kernel(kernel, True) + PROBE_ADAPTED + INPUTS
            + '(: bench (-> I64 I64))\n(define (bench count)\n'
            + '  (probe-run count (specification-rows configured) (specification-columns configured)\n'
            + '    (specification-expected configured)))\n'
            + '(: observe-once (-> I64))\n(define (observe-once) (bench (configured-count)))\n(unit)\n')


def chez_probe(source, adapted, driver):
    kernel = driver.upstream_kernel(source)
    prefix = chez_prelude() if adapted else (reader_ports.CHEZ_TYPES
        + replace(TYPES, '(define-data (Optional T)', '(define-data Optional') + COMMON + CHEZ_INPUTS)
    probes = (driver.ROOT / 'tests/strict-maze/probe.scm').read_text()
    kernel = adaptation(kernel)[0] if adapted else kernel
    prelude = (driver.ROOT / 'benchmarks/r7rs-benchmarks/src/Petite-Chez-prelude.scm').read_text()
    return (prelude + prefix + PROBE_CHEZ_SCALARS + probes
            + instrument_kernel(kernel, adapted) + (PROBE_ADAPTED if adapted else PROBE_ORIGINAL)
            + '(let* ((count (read)) (rows (read)) (columns (read)) (expected (chez-output (read))))\n'
            + '  (let ((result (probe-run count rows columns expected)))\n'
            + '    (display "result:") (write result) (newline)))\n')


def observation_trace(run, system):
    if run['stderr']:
        raise ValueError('Maze observation emitted diagnostics: ' + system)
    if system in ('raw', 'optimized'):
        value = json.loads(run['stdout'])
        lines = value['trace']
        if (lines.pop(0) != 'call:0' or value['result'] != 1 or value['barriers'] != 0
                or value['setup_closed'] != 1 or value['worker_closed'] != 0):
            raise ValueError('Maze observation result or input lifetime differs')
    else:
        lines = run['stdout'].splitlines()
        result = lines.pop()
        if (system == 'native' and json.loads(result)['result'] != 1) or (system != 'native' and result != 'result:1'):
            raise ValueError('Maze observation result differs')
    if any(not re.fullmatch(r'[ic]:-?\d+', line) for line in lines):
        raise ValueError('Maze observation frame differs')
    return '\n'.join(lines) + '\n'


def validate_observations(directory, data, tools, environment, driver):
    target = directory / 'observations'
    target.mkdir()
    source = (directory / 'upstream.scm').read_text()
    (target / 'strict.scm').write_text(strict_probe(source, driver))
    build(target, tools, environment, driver, directory / 'runtime.wasm', True)
    commands = build_chez_observers(target, source, tools, environment, driver)
    for label, source_data in [('once', fixture_input(1, 20, 7, specification(data)['expected_datum'])), ('full-count', data)]:
        compare_observations(target, label, source_data, commands, tools, environment, driver)


def build_chez_observers(target, source, tools, environment, driver):
    commands = {}
    for adapted, system in [(False, 'chez'), (True, 'chez-adapted')]:
        script = target / (system + '.scm')
        script.write_text(chez_probe(source, adapted, driver))
        artifact = target / (system + '.so')
        compiler = target / (system + '-compile.scm')
        compiler.write_text('(import (chezscheme))\n(parameterize ((optimize-level 2))\n'
                            f'  (compile-program {json.dumps(str(script))} {json.dumps(str(artifact))}))\n')
        reader_ports.record(target, system + '-compile', [tools['CHEZ'], '--script', compiler], environment)
        commands[system] = [tools['CHEZ'], '--program', artifact]
    return commands


def compare_observations(directory, label, data, commands, tools, environment, driver):
    target = directory / label
    write_input(target, data, driver, observing=True)
    traces, expected = {}, None
    systems = list(commands.items()) + compiled_commands(directory, target, tools, driver)
    for system, command in systems:
        run = reader_ports.record(target, system, command, environment, target,
                                  stdin=data.decode() if system.startswith('chez') else None)
        trace = observation_trace(run, system)
        (target / (system + '.trace')).write_text(trace)
        if expected is not None and trace != expected:
            raise ValueError('Maze complete ordered observation differs: ' + label + ' ' + system)
        expected = trace
        traces[system] = dict(sha256=hashlib.sha256(trace.encode()).hexdigest(), fields=len(trace.splitlines()))
    validate_trace(target, expected, specification(data)['count'], driver)
    driver.save(target / 'validation.json', dict(systems=traces, counter_names=COUNTER_NAMES))


def validate_trace(target, trace, count, driver):
    lines = trace.splitlines()
    starts = [index for index, line in enumerate(lines) if line == 'i:200']
    # Counter sections follow the character snapshot and terminate the stream.
    full = list(map(lambda line: int(line[2:]), lines[-16:]))
    first = list(map(lambda line: int(line[2:]), lines[-33:-17]))
    if lines[-17] != 'i:200' or len(starts) < 2 or full != [value * count for value in first]:
        raise ValueError('Full Maze work is not the exact count multiple of one complete maze')
    if first[0:4] != [1, 140, 367, 365] or first[8] != 139 or first[12] != 668 or not 139 <= first[9] < 367:
        raise ValueError('Canonical Maze construction, early stop, or rendering work differs')
    structure = validate_ordered_snapshot(trace, first[9], (target / 'input.txt').read_bytes())
    driver.save(target / 'work-counts.json', dict(one=dict(zip(COUNTER_NAMES, first)),
        full=dict(zip(COUNTER_NAMES, full)), iterations=count, skipped_walls=367 - first[9], structure=structure))


def trace_integers(lines, count):
    values = [next(lines) for _ in range(count)]
    if any(not re.fullmatch(r'i:-?\d+', value) for value in values):
        raise ValueError('Maze trace lost an integer field')
    return [int(value[2:]) for value in values]


def trace_header(lines, expected):
    if trace_integers(lines, len(expected)) != expected:
        raise ValueError('Maze trace stage or dimensions differ')


def trace_grid(lines, stage):
    trace_header(lines, [stage, 20, 7])
    cells = [trace_integers(lines, 7) for _ in range(140)]
    if any(cell[:2] != [3 * (index % 7), 2 * (index // 7) + (index % 7) % 2]
           for index, cell in enumerate(cells)):
        raise ValueError('Maze cell snapshot changed its complete row-major order')
    return cells


def validate_ordered_snapshot(trace, visited_count, data):
    # 19 signed x values × (8 nonzero divisors × div/mod + 9 ANDs),
    # ten RNG results, and eight two-field assertions precede the wall vectors.
    lines = iter(trace.splitlines())
    prefix = trace_integers(lines, 19 * 25 + 10 + 16)
    if prefix[-16:] != [part for label in range(1, 9) for part in (label, 1)]:
        raise ValueError('Maze identity or alias assertion failed')
    trace_header(lines, [100, 367])
    constructed = [trace_integers(lines, 5) for _ in range(367)]
    trace_header(lines, [101, 367])
    shuffled = [trace_integers(lines, 5) for _ in range(367)]
    visited = []
    for _ in range(visited_count):
        trace_header(lines, [102])
        visited.append(trace_integers(lines, 5))
    if sorted(constructed) != sorted(shuffled) or visited != list(reversed(shuffled))[:visited_count]:
        raise ValueError('Maze permutation or exact consumed reverse prefix differs')
    trace_header(lines, [103, 367, visited_count, 367 - visited_count])
    dug = trace_grid(lines, 104)
    trace_header(lines, [105])
    entrance, exit = trace_integers(lines, 2)
    finished = trace_grid(lines, 106)
    trace_header(lines, [107])
    expected = decode_characters(specification(data)['expected_datum'])
    if [next(lines) for _ in expected] != ['c:' + str(ord(char)) for char in expected]:
        raise ValueError('Maze trace differs from a complete original expected character')
    trace_header(lines, [200])
    trace_integers(lines, 16)
    trace_header(lines, [200])
    trace_integers(lines, 16)
    if next(lines, None) is not None:
        raise ValueError('Maze trace has trailing fields')
    return validate_maze_states(constructed, dug, finished, entrance, exit)


def validate_maze_states(walls, dug, finished, entrance, exit):
    removed = sum(not (dug[(y // 2) * 7 + x // 3][2] & bit) for x, y, nx, ny, bit in walls)
    if removed != 139 or any(cell[3] != 0 or cell[4] != -1 for cell in dug):
        raise ValueError('Maze dig did not finish exactly 139 unions before DFS and marking')
    root, node, marked = 19 * 7 + entrance, exit, set()
    while node != -1:
        if node in marked:
            raise ValueError('Maze parent snapshot contains a cycle')
        marked.add(node)
        previous, node = node, finished[node][4]
    if previous != root or {index for index, cell in enumerate(finished) if cell[3]} != marked:
        raise ValueError('Maze final marks differ from the complete exit-to-entrance path')
    if finished[exit][2] & 2:
        raise ValueError('Maze exit south wall remains closed')
    return dict(removed_internal_walls=removed, entrance=entrance, exit=exit, marked_cells=len(marked),
                complete_output_characters=668, exact_reverse_prefix=True)


# ---- Native64 and its exact final Wasm are separately retained controls ----

def prepare_native_control(original, target, tools, environment, driver):
    target.mkdir()
    for name in ('strict-native.wasm', 'spec.json', 'input.txt'):
        shutil.copy2(original / name, target / name)
    build_native(target, environment, driver, timing=True)
    run = reader_ports.record(target, 'full-count-validation', [target / 'native'], environment)
    compiled_result(run, dict(driver.load(target / 'spec.json'), barriers_per_iteration=0))
    modules = list(target.glob('native.native-*/optimized.wasm'))
    if len(modules) != 1:
        raise ValueError('Expected one final Maze module used by native64 lowering')
    shutil.copy2(modules[0], target / 'native-final.wasm')
    reader_ports.prepare_scalar_provider(target / 'native-final.wasm', original / 'runtime.wasm',
                                         target, tools, environment, driver)
    command = [tools['NODE'], '--disable-warning=ExperimentalWarning', driver.HERE / 'reader-host.mjs',
               target / 'native-final.wasm', target / 'spec.json', target / 'provider.wasm']
    compiled_result(reader_ports.record(target, 'identical-wasm-v8-validation', command, environment),
                    driver.load(target / 'spec.json'))
    driver.save(target / 'final-module.json', dict(path=str(modules[0]),
        sha256=driver.digest(target / 'native-final.wasm'), input_sha256=driver.digest(target / 'strict-native.wasm'),
        executable_sha256=driver.digest(target / 'native'), lowering='native64 WasmGC-to-LLVM with tracing GC'))


# ---- Rust keeps indexed cells, native bit operations, and owned output lists ----

def decode_characters(text):
    return [dict(newline='\n', space=' ').get(token[2:], token[2:]) for token in character_tokens(text)]


def check_rust_result(run, spec, accepted):
    if not accepted:
        if run['stdout'] or 'assertion' not in run['stderr']:
            raise ValueError('Rust Maze did not reject the altered complete character list')
        return
    lines = run['stdout'].splitlines()
    if (run['stderr'] or len(lines) != 2 or not lines[0].startswith('Result: ')
            or not re.fullmatch(r'\+!CSVLINE!\+rust-wasm,maze:' + str(spec['count']) + r',[0-9.eE+\-]+', lines[1])
            or decode_characters(lines[0][8:]) != decode_characters(spec['expected_datum'])):
        raise ValueError('Rust Maze complete output or result frame differs')


def prepare_rust_control(original, target, tools, environment, driver):
    source = driver.ROOT / 'benchmarks/wasm-reference'
    shutil.copytree(source / 'src', target / 'src')
    for name in ('Cargo.toml', 'Cargo.lock', 'run-wasi.mjs'):
        shutil.copy2(source / name, target / name)
    reader_ports.build_rust_bin(target, 'maze', tools, environment)
    for label, profile in [('native', 'release'), ('wasm', 'wasm32-wasip1/release')]:
        modules = list((target / 'target' / profile / 'deps').glob('maze-*.ll'))
        if len(modules) != 1:
            raise ValueError('Expected one Rust Maze LLVM module: ' + label)
        shutil.copy2(modules[0], target / ('maze-' + label + '.ll'))
    cases = [case for case in fixtures((original / 'input.txt').read_bytes())
             if case[0] not in ('non-character', 'zero-false', 'zero-list', 'negative-false')]
    checks = []
    for label, data, accepted in cases:
        for system, command in reader_ports.rust_commands(target, 'maze', tools):
            run = reader_ports.record(target, label + '-' + system, command, environment,
                                      stdin=data.decode(), failure=not accepted)
            check_rust_result(run, specification(data), accepted)
            checks.append(dict(label=label, system=system, accepted=accepted))
    driver.save(target / 'validation.json', dict(checks=checks, source_sha256=driver.digest(target / 'src/bin/maze.rs'),
        representation='unchanged indexed Vec cells and walls, native bit operations, Vec child snapshots, '
                       'owned Box character lists and iterative destruction; Scheme retains callbacks, recursive '
                       'bitwise helpers, Ref fields and traced lifetime; allocation costs are not equated',
        boundary='Rust requires a character-list expectation and an unsigned count; false and non-character '
                 'expected datums are validated on the original/adapted Scheme implementations only'))


def comparison_commands(original, target, commands, tools, driver):
    node = [tools['NODE'], '--disable-warning=ExperimentalWarning', str(driver.HERE / 'reader-timing.mjs')]
    result = [dict(system='snail-production-v8', command=node + [str(original / 'optimized.wasm'), str(original / 'spec.json')], cwd=str(original)),
              dict(system='snail-native64', command=[str(target / 'native/native')], cwd=str(target / 'native')),
              dict(system='snail-identical-wasm-v8', command=node + [str(target / 'native/native-final.wasm'),
                   str(original / 'spec.json'), str(target / 'native/provider.wasm')], cwd=str(original))]
    for system, command in commands.items():
        result.append(dict(system=system, command=list(map(str, command)), cwd=str(original), stdin_file=str(original / 'input.txt')))
    for system, command in reader_ports.rust_commands(target / 'rust', 'maze', tools):
        if system != 'raw-wasm':
            result.append(dict(system='rust-' + system, command=list(map(str, command)), cwd=str(original), stdin_file=str(original / 'input.txt')))
    return result


def prepare_controls(original, target, commands, tools, environment, driver):
    target.mkdir()
    prepare_native_control(original, target / 'native', tools, environment, driver)
    prepare_rust_control(original, target / 'rust', tools, environment, driver)
    matrix_port.retain_toolchain(target, tools, environment, driver)
    driver.save(target / 'commands.json', comparison_commands(original, target, commands, tools, driver))
    driver.save(target / 'prepared.json', dict(status='ready', timing='Not measured; root coordinates clean timing.',
        hashes={str(path.relative_to(target)): driver.digest(path) for path in target.rglob('*') if path.is_file()}))


# ---- Preparation completes before separately coordinated clean timing ----

def prepare_case(files, output, runner, tools, environment, driver):
    previous = signal.signal(signal.SIGTERM, reader_ports.interrupted)
    try:
        return prepare_workload(files, output, runner, tools, environment, driver)
    finally:
        signal.signal(signal.SIGTERM, previous)


def prepare_workload(files, output, runner, tools, environment, driver):
    directory, data = output / 'maze', files['inputs/maze.input']
    spec = write_input(directory, data, driver)
    write_sources(files, directory, runner, driver)
    build(directory, tools, environment, driver)
    commands = reader_ports.build_chez(directory, runner, tools, environment)
    validate_workload(directory, data, commands, tools, environment, driver)
    validate_observations(directory, data, tools, environment, driver)
    prepare_controls(directory, directory / 'controls', commands, tools, environment, driver)
    return dict(name='maze', status='ready', spec=spec, chez_commands=commands,
                systems=['strict', 'native', 'chez', 'chez-adapted'],
                hashes={str(path.relative_to(directory)): driver.digest(path)
                        for path in directory.rglob('*') if path.is_file()})
