"""Keep the original string copies and global replacements over native String."""

import re

from data_ports import replace


# ---- Scalar inputs preserve the initial false result and final equal? ----


def i64(token):
    if not re.fullmatch(r'[+-]?\d+', token):
        raise ValueError('string benchmark input must be an I64 integer')
    value = int(token)
    if not -(2 ** 63) <= value < 2 ** 63:
        raise ValueError('string benchmark integer is outside I64')
    return value


def expected_value(token):
    if token in ('#f', '#t'):
        return token == '#t', int(token == '#t'), 0
    value = i64(token)
    return value, 2, value


def exact_json_integer(value):
    # JSON numbers pass through JavaScript Number before the host's BigInt call.
    return value if abs(value) <= 2 ** 53 - 1 else str(value)


def specification(data):
    tokens = re.sub(r';[^\n]*', '', data.decode()).split()
    if len(tokens) != 3:
        raise ValueError('string benchmark requires count, threshold and expected result')
    count, threshold = map(i64, tokens[:2])
    expected, kind, value = expected_value(tokens[2])
    return dict(name='string', count=exact_json_integer(count),
                inputs=list(map(exact_json_integer, (threshold, kind, value))),
                original_expected=expected, expected=1, barriers_per_iteration=1,
                predicate='equal? over the original Boolean-or-I64 result', setup_barriers=0)


WORKER = '''(let loop ((i 0) (result 0))
  (if (< i count)
      (loop (+ i 1) (my-try (hide count input0)))
      (if (if (= i 0) (= input1 0)
              (and (= input1 2) (= result input2)))
          1 0)))'''


# ---- Counted Ref edits leave every string operation and loop intact ----


def kernel(source):
    edits = (
        ('(define s "abcdef")', '(define s (ref "abcdef"))', 1),
        ('(set! s ', '(ref-set! s ', 3),
        ('(string-append "123" s "456" s "789")',
         '(string-append "123" (ref-get s) "456" (ref-get s) "789")', 1),
        ('(substring s ', '(substring (ref-get s) ', 2),
        ('(string-length s)', '(string-length (ref-get s))', 6),
        ('\n  s)', '\n  (ref-get s))', 1),
    )
    for before, after, count in edits:
        source = replace(source, before, after, count)
    return source


def adapt_chez_harness(source, reverse=False):
    # The loop counter already distinguishes the original #f initializer from
    # an integer result. Reconstruct false for both the predicate and diagnostics.
    edits = (('(result #f)', '(result 0)'),
             ('(ok? result)', '(ok? (if (= i 0) #f result))'),
             ('(write result)', '(write (if (= i 0) #f result))'))
    for before, after in edits:
        source = replace(source, after if reverse else before, before if reverse else after)
    return source


# ---- Independent complete-character and ordered-store oracles ----


def grown_text(value):
    # The original odd-length midpoint lands on the 5 in the middle literal.
    # This is an oracle only; the timed source keeps append and both substrings.
    return '123' + value + '456' + value + '789', '56' + value + '789123' + value + '45'


def trial_text(threshold):
    value, stores = 'abcdef', ['abcdef']
    while len(value) <= threshold:
        first, value = grown_text(value)
        stores.extend((first, value))
    return value, stores


def expected_output(case):
    if case['operation'] == 'grow':
        first, value = grown_text(case['seed'])
        stores = [first, value]
    else:
        value, stores = trial_text(case['threshold'])
        stores *= 10
    return dict(result=len(value), text=value, stores=stores if case['trace'] else [])


def fixtures():
    cases = [dict(label=label, operation='grow', seed=seed, threshold=0, trace=True)
             for label, seed in [('empty-seed', ''), ('first-grow', 'abcdef'),
                                 ('unicode-seed', 'A\0é😀'), ('scalar-seed', 'e\u0301𝄞\U0010ffff')]]
    cases += [dict(label='threshold-' + str(n), operation='trial', seed='', threshold=n, trace=n < 100)
              for n in (-1, 0, 5, 6, 21, 22, 53, 54, 500000)]
    return [dict(case, expected=expected_output(case)) for case in cases]


def harness_fixtures():
    return [('zero-false', 0, 500000, '#f', True),
            ('negative-false', -1, 500000, '#f', True),
            ('minimum-count', -(2 ** 63), 500000, '#f', True),
            ('zero-integer', 0, 500000, '0', False),
            ('zero-true', 0, 500000, '#t', False),
            ('positive-false', 1, 5, '#f', False),
            ('positive-true', 1, 5, '#t', False),
            ('minimum-threshold', 1, -(2 ** 63), '6', True),
            ('negative-threshold', 2, -1, '6', True),
            ('zero-threshold', 3, 0, '6', True),
            ('threshold-six', 2, 6, '22', True),
            ('threshold-twenty-two', 1, 22, '54', True),
            ('maximum-expected', 1, 5, str(2 ** 63 - 1), False),
            ('wrong-low', 1, 500000, '524277', False),
            ('wrong-high', 1, 500000, '524279', False)]


def scheme_string(value):
    return '"' + ''.join(f'\\x{ord(character):x};' for character in value) + '"'


def probe_input(case):
    return f'{int(case["operation"] != "grow")}\n{case["threshold"]}\n{scheme_string(case["seed"])}\n' + ('#t\n' if case['trace'] else '#f\n')


def chez_output(value):
    result, characters, stores = value
    return dict(result=result, text=''.join(map(chr, characters)),
                stores=[''.join(map(chr, characters)) for characters in stores])


# ---- Separate probe modules expose payloads without a String host ABI ----

STRICT_PROBE = '''(define-extern trace? "probe" "trace" (-> Bool))
(define-extern record-length "probe" "length" (-> I64 Unit))
(define-extern record-character "probe" "character" (-> Char Unit))
(define (record-replacement! cell value)
  (ref-set! cell value)
  (when (trace?)
    (record-length (string-length value))
    (let loop ((i 0))
      (unless (= i (string-length value))
        (record-character (string-ref value i)) (loop (+ i 1))))))
(: probe-run (-> I64 I64))
(define (probe-run threshold) (my-try threshold))
(: probe-grow (-> I64))
(define (probe-grow) (string-length (grow)))
(: probe-seed (-> I64 Unit))
(define (probe-seed count) (ref-set! s (make-string count)))
(: probe-set-character (-> I64 Char Unit))
(define (probe-set-character index value) (string-set! (ref-get s) index value))
(: probe-character (-> I64 Char))
(define (probe-character index) (string-ref (ref-get s) index))
(: probe-length (-> I64))
(define (probe-length) (string-length (ref-get s)))
(unit)
'''


def strict_probe(source, prelude):
    return prelude + replace(source, '(ref-set! s ', '(record-replacement! s ', 3) + STRICT_PROBE


# Every alias remains in a native local/list/Ref across allocations. Mutating
# each retained object must leave all four others unchanged. These extra roots
# and observations exist only in the diagnostic module, never in timed source.
ALIAS_PROBE = '''(define retained-first (ref ""))
(define retained-right (ref ""))
(define retained-left (ref ""))
(define (retain-string cell value) (ref-set! cell value) value)
(define (different-from-all? value xs)
  (or (null? xs) (and (not (string-eq? value (car xs)))
                     (different-from-all? value (cdr xs)))))
(define (distinct-strings? xs)
  (or (null? xs) (and (different-from-all? (car xs) (cdr xs))
                     (distinct-strings? (cdr xs)))))
(define (other-strings-unchanged? values saved target)
  (or (null? values)
      (and (or (string-eq? (car values) target) (string=? (car values) (car saved)))
           (other-strings-unchanged? (cdr values) (cdr saved) target))))
(define (indexed-string values index)
  (if (= index 0) (car values) (indexed-string (cdr values) (- index 1))))
(define (copy-strings values)
  (if (null? values) '() (cons (string-copy (car values)) (copy-strings (cdr values)))))
(define (check-independent-strings values index)
  (let* ((saved (copy-strings values)) (target (indexed-string values index)))
    (string-set! target 0 #\\Q)
    (if (and (distinct-strings? values) (char=? (string-ref target 0) #\\Q)
             (other-strings-unchanged? values saved target)) 1 0)))
(define (probe-alias index)
  (let ((old (string-copy "A\\x0;\\xe9;\\x1f600;")))
    (INSTALL-SEED old)
    (let ((final (grow)))
      (check-independent-strings
       (cons old (cons (ref-get retained-first) (cons (ref-get retained-right)
             (cons (ref-get retained-left) (cons final '()))))) index))))
'''


def alias_kernel(source, adapted):
    read = '(ref-get s)' if adapted else 's'
    values = [(f'(string-append "123" {read} "456" {read} "789")', 'first'),
              (f'(substring {read} (quotient (string-length {read}) 2) (string-length {read}))', 'right'),
              (f'(substring {read} 0 (+ 1 (quotient (string-length {read}) 2)))', 'left')]
    for value, name in values:
        source = replace(source, value, f'(retain-string retained-{name} {value})')
    return source


def alias_source(source, adapted):
    setter = '(ref-set! s old)' if adapted else '(set! s old)'
    return alias_kernel(source, adapted) + ALIAS_PROBE.replace('(INSTALL-SEED old)', setter)


def chez_probe(source, adapted, ref_helpers):
    source = replace(source, '(ref-set! s ' if adapted else '(set! s ', '(record-replacement! ', 3)
    read = '(ref-get s)' if adapted else 's'
    write = '(ref-set! s value)' if adapted else '(set! s value)'
    setup = '(ref-set! s seed)' if adapted else '(set! s seed)'
    return ('(import (chezscheme))\n' + (ref_helpers if adapted else '') + source + f'''
(define stores '())
(define tracing? #f)
(define (record-replacement! value)
  {write}
  (when tracing? (set! stores (cons (map char->integer (string->list value)) stores))))
(let* ((operation (read)) (threshold (read)) (seed (read)) (trace (read)))
  {setup}
  (set! tracing? trace)
  (let ((result (if (= operation 0) (string-length (grow)) (my-try threshold))))
    (write (list result (map char->integer (string->list {read})) (reverse stores)))
    (newline)))
''')


PROBE_HOST = '''import fs from 'node:fs';
import assert from 'node:assert/strict';
const [artifact, specification] = process.argv.slice(2);
const config = JSON.parse(fs.readFileSync(specification, 'utf8'));
const stores = [];
const imports = {probe: {
  trace: () => Number(config.trace),
  length: value => stores.push({length: Number(value), characters: []}),
  character: value => stores.at(-1).characters.push(String.fromCodePoint(value)),
}};
const {instance: {exports}} = await WebAssembly.instantiate(fs.readFileSync(artifact), imports);
exports.main();
if (config.operation === 'grow') {
  const characters = [...config.seed];
  exports['probe-seed'](BigInt(characters.length));
  for (let i = 0; i < characters.length; i++)
    exports['probe-set-character'](BigInt(i), characters[i].codePointAt(0));
}
const result = config.operation === 'grow' ? exports['probe-grow']() : exports['probe-run'](BigInt(config.threshold));
const characters = [];
for (let i = 0; i < Number(exports['probe-length']()); i++)
  characters.push(String.fromCodePoint(exports['probe-character'](BigInt(i))));
console.log(JSON.stringify({result: Number(result), text: characters.join(''), stores: stores.map(value => {
  assert.equal(value.characters.length, value.length);
  return value.characters.join('');
})}));
'''
