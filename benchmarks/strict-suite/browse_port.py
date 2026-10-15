"""Preserve Browse's complete mutable database and backtracking matcher."""

import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal

from data_ports import form, replace
import matrix_port
import reader_ports


# ---- Concrete datum boundaries and all three matcher results ----

CONTROL = '''(define-syntax browse-cond
  (syntax-rules (else)
    ((_ (else body ...)) (begin body ...))
    ((_ (test body ...) rest ...) (if test (begin body ...) (browse-cond rest ...)))))
(define-syntax do-step
  (syntax-rules () ((_ variable) variable) ((_ variable step) step)))
(define-syntax browse-do
  (syntax-rules ()
    ((_ ((variable initial step ...) ...) (test result ...) body ...)
     (let loop ((variable initial) ...)
       (if test (begin (unit) result ...)
           (begin body ... (loop (do-step variable step ...) ...)))))))
'''
COMMON = '''(define-data MatchResult (match-false) (match-true) (match-empty))
(define failed-match (match-false))
(define successful-match (match-true))
(define empty-match (match-empty))
(: match-boolean (-> Bool MatchResult))
(define (match-boolean value) (if value successful-match failed-match))
(: match-truth? (-> MatchResult Bool))
(define (match-truth? value)
  (match value ((match-false) #f) ((match-true) #t) ((match-empty) #t)))
(define-syntax match-or
  (syntax-rules ()
    ((_ value) value)
    ((_ first rest ...) (let ((value first)) (if (match-truth? value) value (match-or rest ...))))))
(define-syntax match-and
  (syntax-rules ()
    ((_ value) value)
    ((_ first rest ...) (if (match-truth? first) (match-and rest ...) failed-match))))
(define (browse-zero? value) (= value 0))
(define (datum-cadr value) (datum-car (datum-cdr value)))
(define (datum-cddr value) (datum-cdr (datum-cdr value)))
(define symbol-pattern (datum-symbol (typed-string->symbol "pattern")))
(define symbol-question (datum-symbol (typed-string->symbol "?")))
(define symbol-star (datum-symbol (typed-string->symbol "*")))
(define symbol-a (datum-symbol (typed-string->symbol "a")))
(define symbol-b (datum-symbol (typed-string->symbol "b")))
(: generate-symbol-value (-> String Datum))
(define (generate-symbol-value text) (datum-symbol (typed-string->symbol text)))
(: symbol-datum->string (-> Datum String))
(define (symbol-datum->string value) (typed-symbol->string (datum-symbol-value value)))
(: symbol-datum->string-datum (-> Datum Datum))
(define (symbol-datum->string-datum value) (datum-string (symbol-datum->string value)))
(: string-datum->number-datum (-> Datum Datum))
(define (string-datum->number-datum value)
  (match (typed-string->number (datum-string-value value))
    ((not-a-number) (datum-boolean #f))
    ((parsed-number value) (datum-number value))
    ((number-error message) (datum-fail message))))
'''
CONTRACTS = '''(: lookup (-> Datum Datum Datum))
(: get (-> Datum Datum Datum))
(: put (-> Datum Datum Datum Unit))
(: generate-symbol (-> Datum))
(: append-to-tail! (-> Datum Datum Datum))
(: tree-copy (-> Datum Datum))
(: init (-> I64 I64 I64 Datum Datum))
(: browse-random (-> I64))
(: randomize (-> Datum Datum))
(: my-match (-> Datum Datum Datum MatchResult))
(: browse (-> Datum Datum))
(: investigate (-> Datum Datum Unit))
'''
INPUTS = '''(define-data Specification
  (specification (count I64 specification-count) (patterns Datum specification-patterns)
                 (expected Datum specification-expected)))
(: exact-count (-> Datum I64))
(define (exact-count datum)
  (match (datum-number-value datum)
    ((exact-number value) value)
    ((inexact-number value) (datum-fail "browse: count must be exact"))
    ((complex-number real imaginary) (datum-fail "browse: count must be exact"))))
(: read-specification (-> InputPort Specification))
(define (read-specification port)
  (let* ((count (exact-count (read-value! (read port))))
         (patterns (read-value! (read port))) (expected (read-value! (read port))))
    (specification count patterns expected)))
(define configured (call-with-input-file "input.txt" read-specification))
(define input0 (specification-patterns configured))
(define expected (specification-expected configured))
(: configured-count (-> I64))
(define (configured-count) (specification-count configured))
(define-extern barrier "benchmark" "barrier" (-> Bool))
(: hide (-> I64 Datum Datum))
(define (hide count value) (if (barrier) value (unreachable)))
'''
WORKER = '''(let loop ((index 0) (result (datum-boolean #f)))
  (if (< index count) (loop (+ index 1) (browse (hide count input0)))
      (if (datum=? result expected) 1 0)))'''


# ---- Counted reversible edits retain every canonical expression and loop ----


def edit(source, ledger, before, after, count=1):
    ledger.append(dict(before=before, after=after, count=count))
    return replace(source, before, after, count)


def tokens(source, replacements):
    return re.sub(r'"(?:[^"\\]|\\.)*"|;[^\n]*|[^\s()]+',
                  lambda token: replacements.get(token[0], token[0]), source)


def mutable_global(source, name, initial):
    source = tokens(source, {name: '(ref-get ' + name + ')'})
    source = replace(source, '(define (ref-get ' + name + ') ' + initial + ')',
                     '(define ' + name + ' (ref ' + initial + '))')
    return replace(source, '(set! (ref-get ' + name + ')', '(ref-set! ' + name)


def mutable_accumulators(source, count):
    source = tokens(source, {'a': '(ref-get a)'})
    source = replace(source, "((ref-get a) '())", "(a (ref '()))", count)
    return replace(source, '(set! (ref-get a)', '(ref-set! a', 2)


def randomize_refs(source):
    source = mutable_accumulators(source, 1)
    source = tokens(source, {'l': '(ref-get l)'})
    source = replace(source, '(define (randomize (ref-get l))',
                     '(define (randomize original-list)\n  (let ((l (ref original-list)))')
    source = replace(source, '(set! (ref-get l)', '(ref-set! l')
    return source + ')'


def matcher_results(source):
    source = replace(source, '((null? pat)\n         (null? dat))',
                     '((null? pat)\n         (match-boolean (null? dat)))')
    source = replace(source, "((null? dat) '())", '((null? dat) empty-match)')
    source = replace(source, '(or (my-match ', '(match-or (my-match ')
    source = replace(source, '(else (and\n', '(else (match-and\n')
    source = replace(source, '(pair? (car dat))', '(match-boolean (pair? (car dat)))')
    source = replace(source, '(if (null? e) #f #t)', '(match-boolean (not (null? e)))')
    source = replace(source, '(else #f)', '(else failed-match)')
    result = form(source, '(my-match (cdr pat)\n                                                        d')
    source = replace(source, result, '(match-truth? ' + result + ')')
    return replace(source, '(cond (val ', '(cond ((datum-truth? val) ', 2)


def literal_tree(text):
    items = iter(re.findall(r'\(|\)|[^\s()]+', text))
    def datum(token):
        if token != '(':
            return 'symbol-' + token
        values = []
        for token in items:
            if token == ')':
                result = '(datum-null)'
                for value in reversed(values):
                    result = f'(datum-cons {value} {result})'
                return result
            values.append(datum(token))
        raise ValueError('unclosed browse literal')
    return datum(next(items))


def adaptation(source):
    adapted, ledger = source, []
    for name, initial in [('*properties*', "'()"), ('*current-gensym*', '0'), ('*rand*', '21')]:
        adapted = edit(adapted, ledger, adapted, mutable_global(adapted, name, initial))
    for prefix, transform in [('(define (init ', lambda s: mutable_accumulators(s, 2)),
                              ('(define (randomize ', randomize_refs),
                              ('(define (my-match ', matcher_results)]:
        region = form(adapted, prefix)
        adapted = edit(adapted, ledger, region, transform(region))
    for before, after, count in [('(if x', '(if (datum-truth? x)', 2),
                                  ('(if y', '(if (datum-truth? y)', 2),
                                  ('(eq? (string-ref ', '(char=? (string-ref ', 2)]:
        adapted = edit(adapted, ledger, before, after, count)
    literal = form(adapted, "((a a a b b b b a a a a a b b a a a)")
    for before, after, count in [("'()", '(datum-null)', 10), ("'pattern", 'symbol-pattern', 2),
                                 ("'?", 'symbol-question', 1), ("'*", 'symbol-star', 1),
                                 ('#f', '(datum-boolean #f)', 5)]:
        adapted = edit(adapted, ledger, before, after, count)
    adapted = edit(adapted, ledger, "'" + literal, literal_tree(literal))
    names = 'cons car cdr cadr cddr list length null? pair? set-cdr! assq append map eq?'.split()
    replacements = {name: 'datum-' + name for name in names}
    replacements.update({'number->string': 'i64->string', 'string->symbol': 'generate-symbol-value',
                         'symbol->string': 'symbol-datum->string', 'zero?': 'browse-zero?',
                         'do': 'browse-do', 'cond': 'browse-cond'})
    adapted = edit(adapted, ledger, adapted, tokens(adapted, replacements))
    adapted = edit(adapted, ledger,
                   '(datum-map string->number (datum-map symbol-datum->string database))',
                   '(datum-map string-datum->number-datum (datum-map symbol-datum->string-datum database))')
    restored = adapted
    for change in reversed(ledger):
        restored = replace(restored, change['after'], change['before'], change['count'])
    if restored != source:
        raise ValueError('browse edits did not reverse exactly')
    return CONTRACTS + adapted, ledger


def program(source, driver):
    adapted, _ = adaptation(driver.upstream_kernel(source))
    return ('(import (snail strict) (rename (snail datum) (string->symbol typed-string->symbol) (symbol->string typed-symbol->string) (string->number typed-string->number)) (snail io) (snail read))\n'
            + CONTROL + COMMON + adapted + INPUTS
            + '(: bench (-> I64 I64))\n(define (bench count) ' + WORKER + ')\n(unit)\n')


def specification(data):
    count = int(data.decode().splitlines()[0])
    return dict(name='browse', count=count, expected=1, inputs=[], setup_barriers=0,
                barriers_per_iteration=1, additional_exports=['configured-count'],
                runtime='scalar-datum-reader', result_kind='complete-datum-list')


# ---- Chez evaluates the exact adapted datum and workload bodies ----

DATUM_EXPORTS = '''datum-fail i64->string
  datum-null datum-boolean datum-string datum-symbol datum-number datum-cons
  datum-car datum-cdr datum-set-car! datum-set-cdr! datum-null? datum-pair?
  datum-truth? datum-eq? datum=? datum-list datum-length datum-append datum-assq datum-map
  datum-symbol-value datum-string-value datum-number-value exact-number read-value!'''.split()


def chez_prelude(root):
    return reader_ports.chez_reader(root, [*DATUM_EXPORTS, ('strict-read', 'read'),
        ('typed-string->symbol', 'string->symbol'), ('typed-symbol->string', 'symbol->string'),
        ('typed-string->number', 'string->number')]) + CONTROL + COMMON


def adapted_chez(source, root, driver):
    upstream = driver.upstream_kernel(source)
    adapted, ledger = adaptation(upstream)
    body = re.sub(r'^\(import [^\n]*\)\s*$', '', source, flags=re.M)
    body = replace(body, upstream, adapted)
    harness = []
    for before, after in [('(input1 (read))', '(input1 (read-value! (strict-read (current-input-port))))'),
                          ('(output (read))', '(output (read-value! (strict-read (current-input-port))))'),
                          ('(equal? result output)', '(datum=? result output)')]:
        body = edit(body, harness, before, after)
    restored = body
    for change in reversed(harness):
        restored = replace(restored, change['after'], change['before'])
    if replace(restored, adapted, upstream) != re.sub(r'^\(import [^\n]*\)\s*$', '', source, flags=re.M):
        raise ValueError('adapted complete Chez body did not reverse')
    return chez_prelude(root) + body, dict(kernel=ledger, harness=harness, complete_reverse_verified=True)


def write_sources(files, directory, runner, driver):
    original = files['src/browse.scm'].decode()
    upstream = driver.upstream_kernel(original)
    adapted, edits = adaptation(upstream)
    control, complete = adapted_chez(original, driver.ROOT, driver)
    original_program = runner.source_text(files, 'browse', 'chez')
    import_line = re.search(r'^\(import [^\n]*\)\s*$', original, re.M).group()
    body = original.replace(import_line, '')
    adjusted = replace(original_program, body, control)
    adjusted = replace(adjusted, '(result #f)', '(result (datum-boolean #f))')
    if replace(replace(adjusted, '(result (datum-boolean #f))', '(result #f)'), control, body) != original_program:
        raise ValueError('Chez harness did not reverse exactly')
    for label in ('chez', 'chez-adapted'):
        (directory / label).mkdir(exist_ok=True)
    for name, text in [('upstream.scm', original), ('upstream-kernel.scm', upstream),
                       ('adapted-kernel.scm', adapted), ('strict.scm', program(original, driver)),
                       ('chez/program.scm', original_program), ('chez-adapted/program.scm', adjusted)]:
        (directory / name).write_text(text)
    driver.save(directory / 'adaptation-ledger.json', edits)
    driver.save(directory / 'complete-chez-edit-ledger.json', complete)
    (directory / 'chez-adaptation.patch').write_text(''.join(difflib.unified_diff(
        original_program.splitlines(True), adjusted.splitlines(True), fromfile='original-chez', tofile='adapted-chez')))


def configured_input(data, count):
    return str(count).encode() + b'\n' + data.split(b'\n', 1)[1]


def runtime_commands(directory, tools, host):
    node = [tools['NODE'], '--disable-warning=ExperimentalWarning', host]
    return [('raw', [*node, directory / 'raw.wasm', directory / 'check-spec.json']),
            ('optimized', [*node, directory / 'optimized.wasm', directory / 'check-spec.json']),
            ('native', [directory / 'native'])]


def validate_count(directory, spec, count, data, commands, tools, environment, driver):
    configured = configured_input(data, count)
    driver.save(directory / 'check-spec.json', dict(spec, count=count))
    (directory / 'input.txt').write_bytes(configured)
    observations = {}
    host = directory.parent / 'reader-host.mjs'
    for system, command in runtime_commands(directory, tools, host):
        run = reader_ports.record(directory, f'count-{count}-{system}', command, environment)
        value = json.loads(run['stdout'])
        if value['result'] != 1 or value['barriers'] != count or value['setup_closed'] != 1 or value['worker_closed'] != 0:
            raise ValueError('incorrect full browse result or workload boundary: ' + system)
        observations[system] = value
    for system, command in commands.items():
        run = reader_ports.record(directory, f'count-{count}-{system}', command, environment,
                                  directory / system, configured.decode())
        if ',INCORRECT' in run['stdout'] or '+!CSVLINE!+' not in run['stdout']:
            raise ValueError('Chez full browse failed: ' + system)
        observations[system] = dict(correct=True)
    return dict(count=count, observations=observations)


# ---- Separate observations expose every recursive argument and return class ----

MATCH_WRAPPER = '''(: my-match (-> Datum Datum Datum MatchResult))
(define (my-match pat dat alist)
  (emit-i64 100) (observe pat) (observe dat) (observe alist)
  (let ((result (my-match-body pat dat alist)))
    (emit-i64 101) (emit-i64 (probe-match-code result)) result))
'''
RING_OBSERVER = '''(define (observe-pattern-ring values)
  (emit-i64 110)
  (observe (datum-car values))
  (observe (datum-car (datum-cdr values)))
  (observe (datum-car (datum-cdr (datum-cdr values))))
  (emit-i64 (if (datum-eq? values (datum-cdr (datum-cdr (datum-cdr values)))) 1 0)))
'''
PROBE_ENTRIES = '''(: observe-once (-> I64))
(define (observe-once)
  (let loop ((index 0))
    (unless (= index (configured-count))
      (emit-i64 102) (emit-i64 index)
      (let ((result (browse (hide (configured-count) input0))))
        (emit-i64 103) (observe result))
      (loop (+ index 1)))) 1)
(: match-probe (-> I64))
(define (match-probe)
  (let loop ((cases input0) (index 0))
    (unless (datum-null? cases)
      (let ((case (datum-car cases)))
        (emit-i64 104) (emit-i64 index)
        (my-match (datum-car case) (datum-cadr case) (datum-car (datum-cddr case))))
      (loop (datum-cdr cases) (+ index 1)))) 1)
'''
STRICT_MATCH_CODE = '''(define (probe-match-code value)
  (match value ((match-false) 0) ((match-true) 1) ((match-empty) 2)))
'''
ORIGINAL_MATCH_CODE = '''(define (probe-match-code value)
  (cond ((not value) 0) ((null? value) 2) (else 1)))
'''
ORIGINAL_DATUM_ALIASES = '''(define-syntax : (syntax-rules () ((_ . signature) (begin))))
(define datum-car car)
(define datum-cdr cdr)
(define datum-cadr cadr)
(define datum-cddr cddr)
(define datum-cons cons)
(define datum-list list)
(define datum-null? null?)
(define datum-eq? eq?)
(define datum=? equal?)
(define datum-length length)
(define datum-set-car! set-car!)
(define datum-set-cdr! set-cdr!)
(define datum-append append)
(define (datum-null) '())
(define symbol-a 'a)
(define symbol-b 'b)
(define symbol-pattern 'pattern)
(define (probe-symbol text) (string->symbol text))
(define (properties-value) *properties*)
(define (gensym-value) *current-gensym*)
(define (reset-random!) (set! *rand* 21))
'''
STRICT_STATE_ACCESS = '''(define probe-symbol generate-symbol-value)
(define (properties-value) (ref-get *properties*))
(define (gensym-value) (ref-get *current-gensym*))
(define (reset-random!) (ref-set! *rand* 21))
'''
SETUP_PROBES = '''(define (probe-check value)
  (emit-i64 (if value 1 0))
  (unless value (unreachable)))
(define (probe-tree-copy)
  (let* ((leaf (datum-list symbol-a)) (source (datum-list leaf leaf)) (copied (tree-copy source)))
    (probe-check (not (datum-eq? source copied)))
    (probe-check (not (datum-eq? leaf (datum-car copied))))
    (probe-check (not (datum-eq? (datum-car copied) (datum-cadr copied))))
    (probe-check (datum-eq? symbol-a (datum-car (datum-car copied))))
    (probe-check (datum-eq? (tree-copy symbol-a) symbol-a))
    (datum-set-car! (datum-car copied) symbol-b)
    (observe source) (observe copied)))
(define (probe-append)
  (let* ((suffix (datum-list symbol-b)) (head (datum-list symbol-a))
         (copied (datum-append head suffix)) (joined (append-to-tail! head suffix)))
    (probe-check (datum-eq? joined head))
    (probe-check (datum-eq? (datum-cdr copied) suffix))
    (probe-check (datum-eq? (datum-cdr joined) suffix))
    (probe-check (not (datum-eq? copied joined)))
    (probe-check (datum-eq? (append-to-tail! (datum-null) suffix) suffix))
    (datum-set-car! suffix symbol-a)
    (observe copied) (observe joined)))
(define (probe-properties)
  (let ((name (probe-symbol "probe-unit")) (key (probe-symbol "probe-key")))
    (put name key symbol-a)
    (let* ((unit (lookup name (properties-value))) (entry (lookup key (datum-cdr unit))))
      (put name key symbol-b)
      (probe-check (datum-eq? entry (lookup key (datum-cdr unit))))
      (probe-check (datum-eq? (get name key) symbol-b))
      (put name symbol-pattern (datum-list symbol-a))
      (probe-check (datum-eq? unit (lookup name (properties-value))))
      (observe (datum-cdr unit)))))
(define (probe-ring-sharing)
  (let* ((seed (datum-list (datum-list symbol-a) (datum-list symbol-b) (datum-list symbol-a symbol-b)))
         (before (gensym-value)) (names (init 2 2 4 seed))
         (first (get (datum-car names) symbol-pattern)) (second (get (datum-cadr names) symbol-pattern)))
    (probe-check (= (- (gensym-value) before) 7))
    (probe-check (datum-eq? (datum-car first) (datum-car (datum-cdr (datum-cddr first)))))
    (probe-check (datum-eq? (datum-car first) (datum-car second)))
    (probe-check (not (datum-eq? (datum-car first) (datum-car seed))))
    (datum-set-car! (datum-car first) symbol-b)
    (observe seed) (observe first) (observe second)))
(define (probe-shuffle)
  (reset-random!)
  (let* ((third (datum-list (probe-symbol "c"))) (second (datum-cons symbol-b third))
         (first (datum-cons symbol-a second)) (result (randomize first)))
    (probe-check (= (datum-length result) 3))
    (observe result) (observe first) (observe second) (observe third)))
(: setup-probe (-> I64))
(define (setup-probe)
  (emit-i64 120) (probe-tree-copy) (emit-i64 121) (probe-append)
  (emit-i64 122) (probe-properties) (emit-i64 123) (probe-ring-sharing)
  (emit-i64 124) (probe-shuffle) 42)
'''


def observed_kernel(kernel, adapted):
    edited, ledger = kernel, []
    edited = edit(edited, ledger, '(define (my-match pat dat alist)', '(define (my-match-body pat dat alist)')
    if adapted:
        edited = edit(edited, ledger, '(: my-match ', '(: my-match-body ')
    store = '(datum-set-cdr! p ipats)' if adapted else '(set-cdr! p ipats)'
    edited = edit(edited, ledger, store, '(begin ' + store + ' (observe-pattern-ring ipats))')
    restored = edited
    for change in reversed(ledger):
        restored = replace(restored, change['after'], change['before'], change['count'])
    if restored != kernel:
        raise ValueError('observation edits did not reverse')
    return edited


def strict_probe(source, root, driver):
    adapted = adaptation(driver.upstream_kernel(source))[0]
    observer = reader_ports.strict_observer(root).replace('(symbol->string value)', '(typed-symbol->string value)')
    declarations = program(source, driver).split(CONTROL, 1)[0].replace('(snail io)', '(snail io) (snail bytes)') + CONTROL + COMMON
    return (declarations + observer + STRICT_MATCH_CODE + RING_OBSERVER + MATCH_WRAPPER
            + observed_kernel(adapted, True) + INPUTS + STRICT_STATE_ACCESS + SETUP_PROBES + PROBE_ENTRIES + '(unit)\n')


def chez_probe(source, root, driver, adapted):
    kernel = driver.upstream_kernel(source)
    if adapted:
        prefix = chez_prelude(root)
        observer = reader_ports.original_observer(root).split('(define (observe-string', 1)[0]
        observer += '(: observe-string' + reader_ports.strict_observer(root).split('(: observe-string', 1)[1]
        observer = observer.replace('(symbol->string value)', '(typed-symbol->string value)')
        kernel, code, state = adaptation(kernel)[0], STRICT_MATCH_CODE, STRICT_STATE_ACCESS
        inputs = '''(define configured-port (open-input-file "input.txt"))
(define count (read configured-port))
(define input0 (read-value! (strict-read configured-port)))
(define expected (read-value! (strict-read configured-port)))
(close-input-port configured-port)
'''
    else:
        prefix, observer, code, state = ORIGINAL_DATUM_ALIASES, reader_ports.original_observer(root), ORIGINAL_MATCH_CODE, ''
        inputs = '''(define configured-port (open-input-file "input.txt"))
(define count (read configured-port)) (define input0 (read configured-port))
(define expected (read configured-port)) (close-input-port configured-port)
'''
    inputs += '(define (configured-count) count)\n(define (hide count value) value)\n'
    return ('(import (chezscheme))\n' + prefix + observer + code + RING_OBSERVER + MATCH_WRAPPER
            + observed_kernel(kernel, adapted) + inputs + state + SETUP_PROBES + PROBE_ENTRIES
            + ('' if adapted else '(define (unreachable) (error \'browse "probe assertion failed"))\n')
            + '(let ((mode (car (command-line-arguments))))\n'
            + '  (let ((result (cond ((string=? mode "match-probe") (match-probe))\n'
            + '    ((string=? mode "setup-probe") (setup-probe)) (else (observe-once)))))\n'
            + '    (display "result:") (write result) (newline)))\n')


PROBE_ENTRY = r'''#include <inttypes.h>
#include <stdio.h>
#include <string.h>
extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void guest_main(void) __asm__("wasm.main");
extern int64_t observe_once(void) __asm__("wasm.observe-once");
extern int64_t match_probe(void) __asm__("wasm.match-probe");
extern int64_t setup_probe(void) __asm__("wasm.setup-probe");
int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    guest_main();
    const char *mode = argc > 1 ? argv[1] : "observe-once";
    int64_t result = !strcmp(mode, "match-probe") ? match_probe() :
                     !strcmp(mode, "setup-probe") ? setup_probe() : observe_once();
    int status = native_finish(0);
    printf("result:%" PRId64 "\n", result);
    return status;
}
'''


def build_probe(directory, tools, environment, driver):
    target = directory / 'observation'
    target.mkdir()
    source = (directory / 'upstream.scm').read_text()
    (target / 'strict.scm').write_text(strict_probe(source, driver.ROOT, driver))
    for adapted, name in [(False, 'chez'), (True, 'chez-adapted')]:
        (target / (name + '.scm')).write_text(chez_probe(source, driver.ROOT, driver, adapted))
    exports = [part for name in ('observe-once', 'match-probe', 'setup-probe') for part in ('--export', name)]
    reader_ports.record(target, 'compile', [driver.ROOT / 'scripts/build-strict', *exports,
                        target / 'strict.scm', target / 'strict.wasm'], environment, driver.ROOT)
    for name, suffix, flags in [('raw', '.raw.wasm', ['--diagnostic-prune-only']), ('optimized', '', [])]:
        reader_ports.record(target, name + '-link', [driver.ROOT / 'scripts/link-strict-runtime', '--runtime',
                            directory / 'runtime.wasm', *flags, target / ('strict.wasm' + suffix),
                            target / (name + '.wasm')], environment, driver.ROOT)
    (target / 'entry.c').write_text(PROBE_ENTRY)
    reader_ports.record(target, 'native-build', [driver.ROOT / 'scripts/build-native', '--wasm',
        '--c-provider', 'benchmark', directory / 'native-provider.h', directory / 'native-provider.c',
        '--c-provider', 'reader.test', driver.ROOT / 'tests/strict-reader/observer.h',
        driver.ROOT / 'tests/strict-reader/observer.c', '--entry-c', target / 'entry.c',
        target / 'strict.wasm', target / 'native'], environment, driver.ROOT)
    return target


def probe_commands(probe, target, mode, tools, driver):
    node = [tools['NODE'], '--disable-warning=ExperimentalWarning', driver.HERE / 'browse-observe.mjs']
    return [('chez', [tools['CHEZ'], '--script', probe / 'chez.scm', mode]),
            ('chez-adapted', [tools['CHEZ'], '--script', probe / 'chez-adapted.scm', mode]),
            ('raw', [*node, probe / 'raw.wasm', target / 'spec.json']),
            ('optimized', [*node, probe / 'optimized.wasm', target / 'spec.json']),
            ('native', [probe / 'native', mode])]


def compare_probe(probe, label, data, mode, tools, environment, driver):
    target = probe / label
    target.mkdir()
    (target / 'input.txt').write_bytes(data)
    driver.save(target / 'spec.json', dict(export=mode))
    expected, results = None, {}
    for system, command in probe_commands(probe, target, mode, tools, driver):
        run = reader_ports.record(target, system, command, environment, target)
        trace = run['stdout']
        if run['stderr'] or not trace.endswith('result:' + ('42' if mode == 'setup-probe' else '1') + '\n'):
            raise ValueError('probe failed: ' + system)
        if expected is None:
            expected = trace
        if trace != expected:
            raise ValueError('complete ordered probe differs: ' + label + ' ' + system)
        (target / (system + '.trace')).write_text(trace)
        results[system] = dict(sha256=hashlib.sha256(trace.encode()).hexdigest(), bytes=len(trace),
                               fields=len(trace.splitlines()))
        # Keep one full trace file per executor; the small command record names
        # that file instead of storing a duplicate multi-megabyte JSON string.
        run['stdout'] = dict(path=system + '.trace', sha256=results[system]['sha256'])
        driver.save(target / 'commands' / system / 'record.json', run)
    driver.save(target / 'comparison.json', results)
    return results


MATCH_CASES = '''1
((() () ())
 (() (a) ())
 ((a) () ())
 ((a) (a) ())
 ((a) (b) ())
 ((?) (b) ())
 ((*) (a b) ())
 ((?x ?x) (a a) ())
 ((?x ?x) (a b) ())
 ((*x b *x) (a b a) ())
 ((*x b *x) (a b c) ())
 (((a) ?) ((a) b) ())
 (((a)) (a) ())
 ((?x) (a) ((?x . a)))
 ((*x b) (a b) ((*x a)))
 ((* a) (b) ())
 ((*x a) (b) ()))
()
'''.encode()


# ---- The complete original predicate rejects every shape and ordering error ----


def input_datums(data):
    remaining = iter(re.findall(r'\(|\)|[^\s()]+', re.sub(r';[^\n]*', '', data.decode())))
    def read(token):
        if token != '(':
            return int(token) if re.fullmatch(r'[+-]?\d+', token) else token
        values = []
        for token in remaining:
            if token == ')':
                return values
            values.append(read(token))
        raise ValueError('unclosed browse input')
    return [read(token) for token in remaining]


def datum_text(value):
    return '(' + ' '.join(map(datum_text, value)) + ')' if isinstance(value, list) else str(value)


def fixture_data(count, patterns, expected):
    return ('\n'.join(map(datum_text, (count, patterns, expected))) + '\n').encode()


def fixtures(data):
    _, patterns, expected = input_datums(data)
    wrong, reordered = list(expected), list(expected)
    wrong[0] += 1
    reordered[0], reordered[1] = reordered[1], reordered[0]
    return [('wrong-value', fixture_data(1, patterns, wrong), 0),
            ('short-result', fixture_data(1, patterns, expected[:-1]), 0),
            ('extra-result', fixture_data(1, patterns, expected + [expected[0]]), 0),
            ('reordered-result', fixture_data(1, patterns, reordered), 0),
            ('empty-patterns', fixture_data(2, [], expected), 1),
            ('changed-patterns', fixture_data(2, [['*x', 'b', '*x'], [['a'], '?'], ['?', '*', '?']], expected), 1),
            ('zero-count', fixture_data(0, patterns, '#f'), 1),
            ('negative-count', fixture_data(-1, patterns, '#f'), 1)]


def validate_fixture(directory, case, commands, tools, environment, driver):
    label, data, accepted = case
    target = directory / 'predicates' / label
    target.mkdir(parents=True)
    spec = dict(specification(data), expected=accepted)
    (target / 'input.txt').write_bytes(data)
    driver.save(target / 'spec.json', spec)
    node = [tools['NODE'], '--disable-warning=ExperimentalWarning', directory.parent / 'reader-host.mjs']
    checks = [('raw', [*node, directory / 'raw.wasm', target / 'spec.json']),
              ('optimized', [*node, directory / 'optimized.wasm', target / 'spec.json']),
              ('native', [directory / 'native'])]
    results = {}
    for system, command in checks:
        run = reader_ports.record(target, system, command, environment, target)
        value = json.loads(run['stdout'])
        if value['result'] != accepted or value['barriers'] != max(0, spec['count']):
            raise ValueError('complete predicate or worker count changed: ' + label + ' ' + system)
        results[system] = value
    for system, command in commands.items():
        run = reader_ports.record(target, system, command, environment, target, data.decode())
        correct = ',INCORRECT' not in run['stdout']
        if correct != bool(accepted) or '+!CSVLINE!+' not in run['stdout']:
            raise ValueError('original/adapted complete predicate changed: ' + label + ' ' + system)
        results[system] = dict(correct=correct)
    driver.save(target / 'validation.json', results)
    return dict(label=label, expected_acceptance=bool(accepted), systems=list(results))


# ---- Datum tests stay in their implementation module ----


def datum_unit_program(root):
    library = (root / 'src/snail/datum.sld').read_text()
    tests = form(library, '(begin\n      (define (test-pair-identity)')
    return ('(import (snail strict) (snail datum) (snail bytes))\n' + tests
            + '\n(: configured-count (-> I64))\n(define (configured-count) 1)\n(: bench (-> I64 I64))\n(define (bench count) (test-datum))\n(unit)\n')


def validate_datum_units(directory, tools, environment, driver):
    target = directory / 'datum-tests'
    target.mkdir()
    (target / 'strict.scm').write_text(datum_unit_program(driver.ROOT))
    driver.save(target / 'spec.json', dict(name='datum-tests', count=1, inputs=[], expected=42))
    reader_ports.build(target, tools, environment, driver)
    results = {}
    for system, command in [('raw', [tools['NODE'], '--disable-warning=ExperimentalWarning',
                           directory.parent / 'reader-host.mjs', target / 'raw.wasm', target / 'spec.json']),
                           ('optimized', [tools['NODE'], '--disable-warning=ExperimentalWarning',
                           directory.parent / 'reader-host.mjs', target / 'optimized.wasm', target / 'spec.json']),
                           ('native', [target / 'native'])]:
        run = reader_ports.record(target, system, command, environment, target)
        result = json.loads(run['stdout'])
        if result['result'] != 42:
            raise ValueError('datum operations failed on ' + system)
        results[system] = result
    driver.save(target / 'validation.json', results)


def validate_observations(directory, data, tools, environment, driver):
    probe = build_probe(directory, tools, environment, driver)
    observations = {}
    cases = [('matcher-cases', MATCH_CASES, 'match-probe'),
             ('setup-aliases', configured_input(data, 1), 'setup-probe'),
             ('canonical-1', configured_input(data, 1), 'observe-once'),
             ('canonical-2', configured_input(data, 2), 'observe-once')]
    cases += [(label, configured, 'observe-once') for label, configured, accepted in fixtures(data)
              if label in ('empty-patterns', 'changed-patterns')]
    for label, configured, mode in cases:
        observations[label] = compare_probe(probe, label, configured, mode, tools, environment, driver)
    driver.save(probe / 'validation.json', observations)


# ---- Preparation completes correctness before any scheduled clean timing ----


def prepare_case(files, output, runner, tools, environment, driver):
    previous = signal.signal(signal.SIGTERM, reader_ports.interrupted)
    try:
        return prepare_workload(files, output, runner, tools, environment, driver)
    finally:
        signal.signal(signal.SIGTERM, previous)


def prepare_workload(files, output, runner, tools, environment, driver):
    directory = output / 'browse'
    directory.mkdir()
    data = files['inputs/browse.input']
    spec = specification(data)
    driver.save(directory / 'spec.json', spec)
    write_sources(files, directory, runner, driver)
    reader_ports.build(directory, tools, environment, driver)
    commands = reader_ports.build_chez(directory, runner, tools, environment)
    checks = [validate_count(directory, spec, count, data, commands, tools, environment, driver)
              for count in (1, 2, spec['count'])]
    driver.save(directory / 'canonical-validation.json', checks)
    negatives = [validate_fixture(directory, case, commands, tools, environment, driver) for case in fixtures(data)]
    driver.save(directory / 'predicate-validation.json', negatives)
    validate_observations(directory, data, tools, environment, driver)
    validate_trace_counts(directory, driver)
    validate_datum_units(directory, tools, environment, driver)
    (directory / 'input.txt').write_bytes(data)
    prepare_controls(directory, directory / 'controls', tools, environment, driver)
    return dict(name='browse', status='ready', spec=spec, chez_commands=commands,
                systems=['strict', 'native', 'chez', 'chez-adapted'],
                hashes={str(path.relative_to(directory)): driver.digest(path)
                        for path in directory.rglob('*') if path.is_file()})


# ---- A native timing entry has no observational barrier counter ----


def prepare_native_control(original, target, tools, environment, driver):
    target.mkdir()
    for name in ('strict-native.wasm', 'spec.json', 'input.txt'):
        shutil.copy2(original / name, target / name)
    provider = replace(reader_ports.NATIVE_PROVIDER, 'count++; return 1;', 'return 1;')
    for name, text in [('native-provider.h', reader_ports.NATIVE_HEADER), ('native-provider.c', provider),
                       ('native-entry.c', reader_ports.TIMING_ENTRY)]:
        (target / name).write_text(text)
    reader_ports.record(target, 'build', [driver.ROOT / 'scripts/build-native', '--wasm', '--c-provider', 'benchmark',
        target / 'native-provider.h', target / 'native-provider.c', '--entry-c', target / 'native-entry.c',
        target / 'strict-native.wasm', target / 'native'], environment, driver.ROOT)
    check = reader_ports.record(target, 'full-count-validation', [target / 'native'], environment, target)
    value = json.loads(check['stdout'])
    if value['result'] != 1 or value['barriers'] != 0 or value['setup_closed'] != 1 or value['worker_closed'] != 0:
        raise ValueError('native timing entry changed browse or its boundaries')
    modules = list(target.glob('native.native-*/optimized.wasm'))
    if len(modules) != 1:
        raise ValueError('expected one exact native final Wasm')
    shutil.copy2(modules[0], target / 'native-final.wasm')
    reader_ports.prepare_scalar_provider(target / 'native-final.wasm', original / 'runtime.wasm',
                                         target, tools, environment, driver)
    check = reader_ports.record(target, 'shared-module-validation', [tools['NODE'], '--disable-warning=ExperimentalWarning',
        driver.HERE / 'reader-host.mjs', target / 'native-final.wasm', target / 'spec.json', target / 'provider.wasm'], environment, target)
    value = json.loads(check['stdout'])
    if value['result'] != 1 or value['barriers'] != specification((target / 'input.txt').read_bytes())['count']:
        raise ValueError('same native final module lost full browse work on V8')


# ---- Rust remains a distinct vector/property and Rc-pattern control ----


def prepare_rust_control(original, target, tools, environment, driver):
    source = driver.ROOT / 'benchmarks/wasm-reference'
    shutil.copytree(source / 'src', target / 'src')
    for name in ('Cargo.toml', 'Cargo.lock', 'run-wasi.mjs'):
        shutil.copy2(source / name, target / name)
    reader_ports.record(target, 'unit-tests', [tools['CARGO'], 'test', '--offline', '--bin', 'browse'],
                        dict(environment, CARGO_TARGET_DIR=str(target / 'target')), target)
    reader_ports.build_rust_bin(target, 'browse', tools, environment)
    data = (original / 'input.txt').read_bytes()
    count, patterns, expected = input_datums(data)
    checks = []
    for repetitions in (1, 2, count):
        for system, command in reader_ports.rust_commands(target, 'browse', tools):
            run = reader_ports.record(target, f'count-{repetitions}-{system}', command, environment, target,
                                      configured_input(data, repetitions).decode())
            line = run['stdout'].splitlines()[0]
            if not line.startswith('Result: ') or input_datums(line[8:].encode()) != [expected] or run['stderr']:
                raise ValueError('Rust browse result differs on ' + system)
            checks.append(dict(system=system, count=repetitions, complete_result=line[8:]))
    for label, configured, accepted in fixtures(data)[:4]:
        for system, command in reader_ports.rust_commands(target, 'browse', tools):
            run = reader_ports.record(target, label + '-' + system, command, environment, target,
                                      configured.decode(), failure=True)
            if 'assertion' not in run['stderr']:
                raise ValueError('Rust did not reject the complete negative result')
    driver.save(target / 'validation.json', dict(canonical=checks, negative_predicates=4,
        source_sha256=driver.digest(target / 'src/bin/browse.rs'),
        representation='Vec units/property tables, Rc immutable lists, copied star prefixes, string symbol equality; '
                       'empty truth collapsed into bool; black_box on each matcher result'))


def prepare_controls(original, target, tools, environment, driver):
    target.mkdir()
    prepare_native_control(original, target / 'native', tools, environment, driver)
    prepare_rust_control(original, target / 'rust', tools, environment, driver)
    matrix_port.retain_toolchain(target, tools, environment, driver)
    driver.save(target / 'prepared.json', dict(status='ready',
        hashes={str(path.relative_to(target)): driver.digest(path) for path in target.rglob('*') if path.is_file()}))


# ---- Decode event framing independently of the emitting Scheme functions ----


def trace_integer(fields):
    text = next(fields)
    if not text.startswith('i:'):
        raise ValueError('expected a complete integer trace field')
    return int(text[2:])


def skip_trace_datum(fields):
    pending = 1
    while pending:
        tag, pending = trace_integer(fields), pending - 1
        if tag == 6:
            pending += 2
        elif tag in (3, 4):
            for _ in range(trace_integer(fields)):
                if not next(fields).startswith('c:'):
                    raise ValueError('incomplete text snapshot')
        elif tag == 1:
            if trace_integer(fields) not in (0, 1):
                raise ValueError('invalid Boolean snapshot')
        elif tag == 5:
            if trace_integer(fields) != 0:
                raise ValueError('browse result must contain exact integers')
            trace_integer(fields)
        elif tag != 0:
            raise ValueError('datum outside the observed browse symbol/list/integer workload')


def audit_match_trace(path):
    fields, depth = iter(path.read_text().splitlines()), 0
    entries, returns, top, workers, outputs = 0, [0, 0, 0], [], [], 0
    for field in fields:
        if field == 'i:110':
            for _ in range(3): skip_trace_datum(fields)
            if trace_integer(fields) != 1: raise ValueError('copied pattern ring was not cyclic')
        elif field in ('i:102', 'i:104'):
            if depth: raise ValueError('worker began before the preceding matcher returned')
            index = trace_integer(fields)
            if field == 'i:102': workers.append(index)
        elif field == 'i:100':
            entries, depth = entries + 1, depth + 1
            for _ in range(3): skip_trace_datum(fields)
        elif field == 'i:101':
            code, depth = trace_integer(fields), depth - 1
            if code not in (0, 1, 2) or depth < 0: raise ValueError('unbalanced matcher return')
            returns[code] += 1
            if depth == 0: top.append(code)
        elif field == 'i:103':
            if depth: raise ValueError('result appeared before the matcher returned')
            skip_trace_datum(fields)
            outputs += 1
        elif field == 'result:1':
            if depth or list(fields): raise ValueError('incomplete or extra trace events')
            return dict(entries=entries, returns=returns, top_level_returns=top, workers=workers, complete_outputs=outputs)
        else:
            raise ValueError('unknown ordered matcher event: ' + field)
    raise ValueError('trace omitted its final result')


def validate_trace_counts(directory, driver):
    probe, reports = directory / 'observation', {}
    for count in (1, 2):
        report = audit_match_trace(probe / f'canonical-{count}/chez.trace')
        if report['workers'] != list(range(count)) or report['complete_outputs'] != count or len(report['top_level_returns']) != 1200 * count:
            raise ValueError('canonical trace omitted an original unit/pattern iteration')
        reports[str(count)] = report
    report = audit_match_trace(probe / 'matcher-cases/chez.trace')
    if report['top_level_returns'] != [1, 0, 2, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 2, 1]:
        raise ValueError('targeted matcher cases changed their source return classes')
    reports['matcher-cases'] = report
    driver.save(probe / 'event-counts.json', reports)
