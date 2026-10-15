"""Preserve the puzzle search, local early return, and both setup regions."""

import re

from data_ports import form, replace
from string_port import exact_json_integer, expected_value, i64


# ---- Scalar inputs and the original false-or-count result ----

STRICT_TYPES = '''(define-data PuzzleResult (puzzle-failed) (puzzle-count (value I64)))
(define puzzle-failure (puzzle-failed))
(define (zero? value) (= value 0))
(define-extern puzzle-print "benchmark" "print_text" (-> I64 Unit))
(define (puzzle-error) (puzzle-print 0) (puzzle-print 1))
'''
COMMON = '''(define (puzzle-for-each procedure values)
  (unless (null? values)
    (procedure (car values)) (puzzle-for-each procedure (cdr values))))
'''
CHEZ_RESULTS = '''(define (puzzle-failed) (vector 0))
(define (puzzle-count value) (vector 1 value))
(define puzzle-failure (puzzle-failed))
(define (puzzle-original-value result)
  (if (= (vector-ref result 0) 0) #f (vector-ref result 1)))
(define (puzzle-error) (newline) (display "Error."))
'''
WORKER = '''(let loop ((i 0) (result puzzle-failure))
  (if (< i count)
      (loop (+ i 1) (start (hide count input0)))
      (if (match result
            ((puzzle-failed) (= input1 0))
            ((puzzle-count value) (and (= input1 2) (= value input2))))
          1 0)))'''


def specification(data):
    tokens = re.sub(r';[^\n]*', '', data.decode()).split()
    if len(tokens) != 3:
        raise ValueError('puzzle requires count, size and expected result')
    count, size = map(i64, tokens[:2])
    expected, kind, value = expected_value(tokens[2])
    return dict(name='puzzle', count=exact_json_integer(count),
                inputs=list(map(exact_json_integer, (size, kind, value))),
                original_expected=expected, expected=1, barriers_per_iteration=1,
                setup_barriers=0, diagnostic_text=['\n', 'Error.'])


# ---- Counted source edits keep the inclusive mask scans and all stores ----

TRIAL = '''(define (trial j)
  (let candidates ((i 0))
    (if (> i typemax)
        (begin (set! *kount* (+ *kount* 1)) #f)
        (if (and (not (zero? (vector-ref *piececount* (vector-ref *class* i))))
                 (fit i j))
            (let ((k (place i j)))
              (if (or (trial k) (zero? k))
                  (begin (set! *kount* (+ *kount* 1)) #t)
                  (begin (puzzle-remove i j) (candidates (+ i 1)))))
            (candidates (+ i 1))))))'''


def parts(source):
    source = re.sub(r'^\(import [^\n]*\)\s*$', '', source, flags=re.M)
    harness = form(source, '(define (run-benchmark)')
    before, after = source.split(harness)
    return before, harness, after


def explicit_ref(source, name, initial, stores, global_binding=False):
    # The local index and n are adapted only inside their own function forms.
    source = re.sub(r'"(?:[^"\\]|\\.)*"|;[^\n]*|[^\s()]+',
                    lambda token: '(ref-get ' + name + ')' if token[0] == name else token[0], source)
    prefix = '(define ' if global_binding else '('
    source = replace(source, prefix + '(ref-get ' + name + ') ' + initial + ')',
                     prefix + name + ' (ref ' + initial + '))')
    return replace(source, '(set! (ref-get ' + name + ')', '(ref-set! ' + name, stores)


def placement_guards(source):
    for value in ('#t', '#f'):
        old = '''(cond ((vector-ref (vector-ref *p* i) k)
             (vector-set! *puzzle* (+ j k) VALUE)
             VALUE))'''.replace('VALUE', value)
        new = '''(when (vector-ref (vector-ref *p* i) k)
        (vector-set! *puzzle* (+ j k) VALUE))'''.replace('VALUE', value)
        source = replace(source, old, new)
    return source


def adapt_piece(source):
    source = explicit_ref(source, 'index', '0', 1)
    return replace(source, '(cond ((not (= *iii* typemax))\n           (set! *iii* (+ *iii* 1))))',
                   '(when (not (= *iii* typemax))\n      (set! *iii* (+ *iii* 1)))')


def adapt_start(source):
    adapted = explicit_ref(source, 'n', '0', 1)
    adapted = replace(adapted, '(begin (newline) (display "Error."))', '(puzzle-error)')
    return replace(adapted, '        *kount*\n        #f)',
                   '        (puzzle-count *kount*)\n        puzzle-failure)')


def kernel_body(source):
    source = placement_guards(replace(source, form(source, '(define (trial j)'), TRIAL))
    for prefix, adapt in (('(define (definePiece ', adapt_piece), ('(define (start size)', adapt_start)):
        original = form(source, prefix)
        source = replace(source, original, adapt(original))
    return source


def adapt_region(source):
    source = replace(source, '(make-vector (+ *size* 1))', '(make-vector (+ *size* 1) #t)')
    if '(define (trial j)' not in source:
        return replace(source, '(for-each ', '(puzzle-for-each ')
    source = replace(source, '(make-vector (+ typemax 1))', '(make-vector (+ typemax 1) (make-vector 0 #t))')
    source = kernel_body(source)
    source = explicit_ref(source, '*iii*', '0', 2, True)
    return explicit_ref(source, '*kount*', '0', 3, True)


def kernel(source):
    before, _, after = parts(source)
    return adapt_region(before) + adapt_region(after)


def control_prelude(source):
    return replace(source, '(define-syntax do\n  (syntax-rules ()\n',
                   '(define-syntax do\n  (syntax-rules ()\n'
                   '    ((_ bindings (test) body ...) (do bindings (test (unit)) body ...))\n')


def adapt_harness(source, reverse=False):
    edits = (('(result #f)', '(result puzzle-failure)'),
             ('(ok? result)', '(ok? (puzzle-original-value result))'),
             ('(write result)', '(write (puzzle-original-value result))'))
    for before, after in edits:
        source = replace(source, after if reverse else before, before if reverse else after)
    return source


def matched_source(upstream, original, strict, helpers):
    before, harness, after = parts(upstream)
    first, last = adapt_region(before), adapt_region(after)
    if strict.count(first + last) != 1:
        raise ValueError('strict puzzle must contain both adapted setup regions')
    adapted = replace(original, before + harness + after, helpers + first + harness + last)
    adapted = adapt_harness(adapted)
    restored = replace(adapt_harness(adapted, True), helpers + first + harness + last,
                       before + harness + after)
    if restored != original:
        raise ValueError('puzzle full-source reversal failed')
    return adapted, before + after, first + last


# ---- Independent board model and ordered effects ----

PIECES = [(0, 3, 1, 0), (0, 1, 0, 3), (0, 0, 3, 1), (0, 1, 3, 0),
          (0, 3, 0, 1), (0, 0, 1, 3), (1, 2, 0, 0), (1, 0, 2, 0),
          (1, 0, 0, 2), (2, 1, 1, 0), (2, 1, 0, 1), (2, 0, 1, 1), (3, 1, 1, 1)]


def get(values, index):
    if not 0 <= index < len(values):
        raise IndexError(index)
    return values[index]


class Puzzle:
    def __init__(self, fail_initial=False):
        self.cursor, self.counter = 0, 0
        self.board, self.pieces = [1] * 512, [[1] * 512 for _ in range(13)]
        self.counts, self.classes, self.maximum = [0] * 4, [0] * 13, [0] * 13
        self.events, self.output, self.tracing, self.fail_initial = [], [], False, fail_initial

    def record(self, tag, a, b=0, c=0):
        if self.tracing:
            self.events.append([tag, a, b, c])

    def store(self, tag, values, index, value, row=None):
        get(values, index)
        values[index] = value
        self.record(tag, index if row is None else row, value if row is None else index,
                    0 if row is None else value)

    def scalar(self, name, value):
        setattr(self, name, value)
        self.record(6 if name == 'cursor' else 7, value)

    def fit(self, piece, position):
        self.record(10, piece, position)
        for offset in range(get(self.maximum, piece) + 1):
            if get(get(self.pieces, piece), offset) and get(self.board, position + offset):
                self.record(11, piece, position, 0)
                return 0
        self.record(11, piece, position, 1)
        return 1

    def place(self, piece, position):
        self.record(12, piece, position)
        for offset in range(get(self.maximum, piece) + 1):
            if get(get(self.pieces, piece), offset):
                self.store(1, self.board, position + offset, 1)
        kind = get(self.classes, piece)
        self.store(3, self.counts, kind, get(self.counts, kind) - 1)
        next_hole = next((i for i in range(position, 512) if not get(self.board, i)), 0)
        self.record(13, piece, position, next_hole)
        return next_hole

    def remove(self, piece, position):
        self.record(14, piece, position)
        for offset in range(get(self.maximum, piece) + 1):
            if get(get(self.pieces, piece), offset):
                self.store(1, self.board, position + offset, 0)
        kind = get(self.classes, piece)
        self.store(3, self.counts, kind, get(self.counts, kind) + 1)
        self.record(15, piece, position)
        return 0

    def trial(self, position):
        self.record(16, position)
        result = self.search(position)
        self.scalar('counter', self.counter + 1)
        self.record(17, position, result)
        return result

    def search(self, position):
        for piece in range(13):
            if get(self.counts, get(self.classes, piece)) != 0 and self.fit(piece, position):
                next_hole = self.place(piece, position)
                if self.trial(next_hole) or next_hole == 0:
                    return 1
                self.remove(piece, position)
        return 0

    def define_piece(self, kind, width, height, depth):
        last = 0
        for x in range(width + 1):
            for y in range(height + 1):
                for z in range(depth + 1):
                    last = x + 8 * (y + 8 * z)
                    self.store(2, self.pieces[self.cursor], last, 1, self.cursor)
        self.store(4, self.classes, self.cursor, kind)
        self.store(5, self.maximum, self.cursor, last)
        if self.cursor != 12:
            self.scalar('cursor', self.cursor + 1)

    def reset(self, size):
        self.scalar('counter', 0)
        for index in range(size + 1):
            self.store(1, self.board, index, 1)
        for x in range(1, 6):
            for y in range(1, 6):
                for z in range(1, 6):
                    self.store(1, self.board, x + 8 * (y + 8 * z), 0)
        for row in range(13):
            for index in range(size + 1):
                self.store(2, self.pieces[row], index, 0, row)
        self.scalar('cursor', 0)
        for dimensions in PIECES:
            self.define_piece(*dimensions)
        for index, value in enumerate((13, 3, 1, 1)):
            self.store(3, self.counts, index, value)

    def start(self, size):
        self.record(18, size)
        self.reset(size)
        if self.fail_initial:
            self.store(1, self.board, 73, 1)
        next_hole = 0
        if self.fit(0, 73):
            next_hole = self.place(0, 73)
        else:
            self.output.extend(map(ord, '\nError.'))
        result = self.counter if self.trial(next_hole) else -1
        self.record(19, size, result)
        return result

    def command(self, operation, a, b, c, _):
        if operation == 0:
            return self.start(a)
        if operation in (1, 2, 3):
            return (self.fit, self.place, self.remove)[operation - 1](a, b)
        if operation == 4:
            return self.trial(a)
        if operation == 5:
            self.store(3, self.counts, a, b)
        elif operation == 6:
            self.store(1, self.board, a, int(b != 0))
        elif operation == 7:
            self.store(2, get(self.pieces, a), b, int(c != 0), a)
        elif operation == 8:
            self.store(5, self.maximum, a, b)
        return 0

    def state(self):
        return [self.cursor, self.counter, *self.board, *(v for row in self.pieces for v in row),
                *self.counts, *self.classes, *self.maximum, 1, 1]

    def step(self, command, trace):
        self.events, self.output, self.tracing = [], [], trace
        try:
            trapped, result = 0, self.command(*command)
        except IndexError:
            trapped, result = 1, 0
        return [trapped, result, self.output, self.state(), self.events]


def fixtures():
    start, remove = (0, 511), (3, 0, 73)
    cases = [
        ('full-search', [start], 0, False),
        ('roundtrip', [start, (1, 0, 73), remove, (1, 0, 73), (2, 0, 73), (1, 0, 73)], 1, False),
        ('terminal-recursion', [start, remove, (4, 73)], 1, False),
        ('failed-branch', [start, remove, (5, 0, 0), (5, 1, 1), (4, 73)], 1, False),
        ('exhausted-search', [start, (4, 0)], 1, False),
        ('class-gates-fit', [(4, 512), (5, 0, -1), (4, 512)], 0, False),
        ('mask-gates-board', [(7, 0, 0, 0), (1, 0, 512), (7, 0, 0, 1), (1, 0, 512)], 0, False),
        ('fit-bounds', [start, (1, 0, 512), (1, 0, -1), (1, 0, 511)], 1, False),
        ('partial-write-bounds', [start, (2, 0, 510), (3, 0, 510)], 1, False),
        ('oversize-reset', [(0, 512)], 0, False),
        ('repeated-reset', [start, remove, start, (0, 500)], 1, False),
        ('partial-first-reset', [(0, 500)], 0, False),
        ('negative-reset', [(0, -1)], 0, False),
        ('initial-placement-failure', [start], 0, True),
        ('initial-storage', [(9,)], 0, False),
    ]
    result = []
    for label, commands, trace_from, fail_initial in cases:
        commands = [list(command) + [0] * (5 - len(command)) for command in commands]
        puzzle = Puzzle(fail_initial)
        expected = [puzzle.step(command, i >= trace_from) for i, command in enumerate(commands)]
        result.append(dict(label=label, commands=commands, trace_from=trace_from,
                           fail_initial=fail_initial, expected=expected))
    return result


def harness_fixtures():
    return [('zero-false', 0, 511, '#f', True),
            ('negative-false', -1, 511, '#f', True),
            ('minimum-count', -(2 ** 63), 511, '#f', True),
            ('zero-invalid-size', 0, 512, '#f', True),
            ('zero-integer', 0, 511, '0', False),
            ('zero-true', 0, 511, '#t', False),
            ('positive-false', 1, 511, '#f', False),
            ('positive-true', 1, 511, '#t', False),
            ('partial-size', 2, 500, '2005', True),
            ('negative-size', 1, -1, '#f', True),
            ('minimum-size', 1, -(2 ** 63), '#f', True),
            ('wrong-low', 1, 511, '2004', False),
            ('wrong-high', 1, 511, '2006', False),
            ('maximum-expected', 1, 511, str(2 ** 63 - 1), False)]


def probe_input(case):
    commands = '(' + ' '.join('(' + ' '.join(map(str, command)) + ')' for command in case['commands']) + ')'
    return f'{commands}\n{case["trace_from"]}\n{int(case["fail_initial"])}\n'


# ---- Separate modules observe every cell, row identity, and ordered effects ----

PROBE_STORES = '''(define (probe-board! index value)
  (vector-set! *puzzle* index value) (probe-record 1 index (if value 1 0) 0))
(define (probe-piece! row number index value)
  (vector-set! row index value) (probe-record 2 number index (if value 1 0)))
(define (probe-count! index value)
  (vector-set! *piececount* index value) (probe-record 3 index value 0))
(define (probe-class! index value)
  (vector-set! *class* index value) (probe-record 4 index value 0))
(define (probe-maximum! index value)
  (vector-set! *piecemax* index value) (probe-record 5 index value 0))
(define (probe-before-initial-place)
  (when (probe-fail-initial?) (probe-board! 73 #t)))
'''
PROBE_STATE = '''(define saved-rows
  (let copy ((i 0))
    (if (> i typemax) '() (cons (vector-ref *p* i) (copy (+ i 1))))))
(define (rows-retained? rows i)
  (or (null? rows)
      (and (vector-eq? (car rows) (vector-ref *p* i)) (rows-retained? (cdr rows) (+ i 1)))))
(define (rows-distinct?)
  (let row ((i 0))
    (or (> i typemax)
        (and (let other ((j (+ i 1)))
               (or (> j typemax)
                   (and (not (vector-eq? (vector-ref *p* i) (vector-ref *p* j)))
                        (other (+ j 1)))))
             (row (+ i 1))))))
(define (probe-state index)
  (cond ((= index 0) CURSOR)
        ((= index 1) COUNTER)
        ((< index 514) (if (vector-ref *puzzle* (- index 2)) 1 0))
        ((< index 7170)
         (let ((i (- index 514)))
           (if (vector-ref (vector-ref *p* (quotient i 512)) (remainder i 512)) 1 0)))
        ((< index 7174) (vector-ref *piececount* (- index 7170)))
        ((< index 7187) (vector-ref *class* (- index 7174)))
        ((< index 7200) (vector-ref *piecemax* (- index 7187)))
        ((= index 7200) (if (rows-retained? saved-rows 0) 1 0))
        (else (if (rows-distinct?) 1 0))))
(define (probe-command operation a b c unused)
  (cond ((= operation 0) (probe-result (start a)))
        ((= operation 1) (if (fit a b) 1 0))
        ((= operation 2) (place a b))
        ((= operation 3) (puzzle-remove a b) 0)
        ((= operation 4) (if (trial a) 1 0))
        ((= operation 5) (probe-count! a b) 0)
        ((= operation 6) (probe-board! a (not (= b 0))) 0)
        ((= operation 7) (probe-piece! (vector-ref *p* a) a b (not (= c 0))) 0)
        ((= operation 8) (probe-maximum! a b) 0)
        (else 0)))
'''


def probe_mutations(source, adapted):
    for variable, helper, count in (('*puzzle*', 'board', 4), ('*piececount*', 'count', 6),
                                    ('*class*', 'class', 1), ('*piecemax*', 'maximum', 1)):
        source = replace(source, '(vector-set! ' + variable, '(probe-' + helper + '!', count)
    cursor = '(ref-get *iii*)' if adapted else '*iii*'
    for row in ('i', cursor):
        before = '(vector-set! (vector-ref *p* ' + row + ')'
        source = replace(source, before, '(probe-piece! (vector-ref *p* ' + row + ') ' + row)
    for variable, helper, count in (('*iii*', 'cursor', 2), ('*kount*', 'counter', 3)):
        source = replace(source, ('(ref-set! ' if adapted else '(set! ') + variable, '(probe-' + helper + '!', count)
    return replace(source, '  (let ((m (+ (* *d* (+ *d* 1)) 1))',
                   '  (probe-before-initial-place)\n  (let ((m (+ (* *d* (+ *d* 1)) 1))')


def probe_wrappers(source):
    wrappers = []
    for name, arguments, before, after, encoded in (
            ('fit', 'i j', '10 i j 0', '11 i j', '(if result 1 0)'),
            ('place', 'i j', '12 i j 0', '13 i j', 'result'),
            ('puzzle-remove', 'i j', '14 i j 0', '15 i j', '0'),
            ('trial', 'j', '16 j 0 0', '17 j', '(if result 1 0)'),
            ('start', 'size', '18 size 0 0', '19 size', '(probe-result result)')):
        source = replace(source, '(define (' + name + ' ', '(define (work-' + name + ' ')
        padding = ' 0' if name in ('trial', 'start') else ''
        wrappers.append(f'''(define ({name} {arguments})
  (probe-record {before})
  (let ((result (work-{name} {arguments})))
    (probe-record {after} {encoded}{padding}) result))\n''')
    return source + ''.join(wrappers)


def probe_source(source, adapted):
    source = probe_wrappers(probe_mutations(source, adapted)) + PROBE_STORES
    for name, variable, tag in (('cursor', '*iii*', 6), ('counter', '*kount*', 7)):
        setter = ('ref-set!' if adapted else 'set!') + ' ' + variable
        source += f'(define (probe-{name}! value) ({setter} value) (probe-record {tag} value 0 0))\n'
    read = lambda name: '(ref-get ' + name + ')' if adapted else name
    return source + PROBE_STATE.replace('CURSOR', read('*iii*')).replace('COUNTER', read('*kount*'))


def strict_probe(source, prelude):
    return control_prelude(prelude) + STRICT_TYPES + COMMON + '''
(define-extern probe-record "probe" "record" (-> I64 I64 I64 I64 Unit))
(define-extern probe-fail-initial? "probe" "fail_initial" (-> Bool))
(define (probe-result value)
  (match value ((puzzle-failed) -1) ((puzzle-count count) count)))
(: probe-state (-> I64 I64))
(: probe-command (-> I64 I64 I64 I64 I64 I64))
''' + probe_source(source, True) + '(unit)\n'


CHEZ_PROBE = '''(define commands (read))
(define trace-from (read))
(define fail-initial (read))
(define tracing? #f)
(define events '())
(define (probe-fail-initial?) (= fail-initial 1))
(define (probe-record tag a b c)
  (when tracing? (set! events (cons (list tag a b c) events))))
(define (probe-snapshot)
  (let loop ((i 0)) (if (= i 7202) '() (cons (probe-state i) (loop (+ i 1))))))
(define (probe-step command i)
  (set! events '())
  (set! tracing? (>= i trace-from))
  (let* ((port (open-output-string))
         (result (parameterize ((current-output-port port))
                   (guard (error (else (list 1 0))) (list 0 (apply probe-command command))))))
    (append result (list (map char->integer (string->list (get-output-string port)))
                         (probe-snapshot) (reverse events)))))
(write (let loop ((commands commands) (i 0))
         (if (null? commands) '()
             (let ((value (probe-step (car commands) i)))
               (cons value (loop (cdr commands) (+ i 1)))))))
(newline)
'''


def chez_probe(source, adapted, helpers):
    result = '(if value value -1)' if not adapted else '(if (= (vector-ref value 0) 0) -1 (vector-ref value 1))'
    prefix = '(import (chezscheme))\n' + (helpers if adapted else '')
    prefix += '(define (vector-eq? a b) (eq? a b))\n(define (probe-result value) ' + result + ')\n'
    return prefix + probe_source(source, adapted) + CHEZ_PROBE


PROBE_HOST = '''import fs from 'node:fs';
import assert from 'node:assert/strict';
const [artifact, specification] = process.argv.slice(2);
const config = JSON.parse(fs.readFileSync(specification, 'utf8'));
let events = [], output = [], tracing = false;
const imports = {benchmark: {
  input_i64: () => 0n, input_f64: () => 0, barrier: () => 1,
  hide_i64: x => x, hide_f64: x => x,
  print_text: code => output.push(...[...['\\n', 'Error.'][Number(code)]].map(c => c.codePointAt(0))),
}, probe: {
  record: (...values) => { if (tracing) events.push(values.map(Number)); },
  fail_initial: () => Number(config.fail_initial),
}};
const {instance} = await WebAssembly.instantiate(fs.readFileSync(artifact), imports);
instance.exports.main();
const actual = config.commands.map((command, index) => {
  events = []; output = []; tracing = index >= config.trace_from;
  let trapped = 0, result = 0;
  try { result = Number(instance.exports['probe-command'](...command.map(BigInt))); }
  catch (error) { if (!(error instanceof WebAssembly.RuntimeError)) throw error; trapped = 1; }
  const state = Array.from({length: 7202}, (_, i) => Number(instance.exports['probe-state'](BigInt(i))));
  return [trapped, result, output, state, events];
});
fs.writeFileSync(specification + '.actual.json', JSON.stringify(actual) + '\\n');
assert.deepEqual(actual, config.expected);
console.log(JSON.stringify({valid: true, steps: actual.length, diagnostic_only: true}));
'''
