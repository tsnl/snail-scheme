"""Preserve both complete Boyer provers, including rewrite counts and sharing."""

import difflib
import hashlib
import json
import re
import shutil
import signal
from pathlib import Path

from data_ports import form, replace
import browse_port
import reader_ports


# ---- Typed datum boundaries keep source pairs and constructor identity ----

NAMES = ('nboyer', 'sboyer')
NATIVE_HEAP_BYTES = dict(nboyer=2 * 1024**3, sboyer=1024**3)
CONTROL = browse_port.CONTROL.replace('browse-cond', 'boyer-cond').replace('browse-do', 'boyer-do')
COMMON = '''(: boyer-zero? (-> I64 Bool))
(define (boyer-zero? value) (= value 0))
(: boyer-exact (-> Datum I64))
(define (boyer-exact value)
  (match (datum-number-value value)
    ((exact-number value) value)
    ((inexact-number value) (datum-fail "boyer: expected an exact integer"))
    ((complex-number real imaginary) (datum-fail "boyer: expected an exact integer"))))
(: boyer-symbol (-> String Datum))
(define (boyer-symbol text) (datum-symbol (typed-string->symbol text)))
(: boyer-integer (-> I64 Datum))
(define (boyer-integer value) (datum-number (exact-number value)))
(define (boyer-caar value) (datum-car (datum-car value)))
(define (boyer-cdar value) (datum-cdr (datum-car value)))
(define (boyer-cadr value) (datum-car (datum-cdr value)))
(define (boyer-caddr value) (datum-car (datum-cdr (datum-cdr value))))
(define (boyer-cadddr value) (datum-car (datum-cdr (datum-cdr (datum-cdr value)))))
(: boyer-vector (-> Datum Datum Datum))
(define (boyer-vector first second) (datum-vector (vector first second)))
(define (boyer-vector-ref value index) (vector-ref (datum-vector-values value) index))
(define (boyer-vector-set! value index item) (vector-set! (datum-vector-values value) index item))
'''
CONTRACTS = '''  (: setup (-> Bool))
  (: add-lemma-lst (-> Datum Bool))
  (: add-lemma (-> Datum Unit))
  (: translate-term (-> Datum Datum))
  (: translate-args (-> Datum Datum))
  (: untranslate-term (-> Datum Datum))
  (: put (-> Datum Datum Datum Unit))
  (: get (-> Datum Datum Datum))
  (: symbol->symbol-record (-> Datum Datum))
  (: make-symbol-record (-> Datum Datum))
  (: put-lemmas! (-> Datum Datum Unit))
  (: get-lemmas (-> Datum Datum))
  (: get-name (-> Datum Datum))
  (: symbol-record-equal? (-> Datum Datum Bool))
  (: test (-> Datum Datum I64 Bool))
  (: translate-alist (-> Datum Datum))
  (: apply-subst (-> Datum Datum Datum))
  (: apply-subst-lst (-> Datum Datum Datum))
  (: tautp (-> Datum Bool))
  (: tautologyp (-> Datum Datum Datum Bool))
  (: rewrite (-> Datum Datum))
  (: rewrite-args (-> Datum Datum))
  (: rewrite-with-lemmas (-> Datum Datum Datum))
  (: one-way-unify (-> Datum Datum Bool))
  (: one-way-unify1 (-> Datum Datum Bool))
  (: one-way-unify1-lst (-> Datum Datum Bool))
  (: falsep (-> Datum Datum Bool))
  (: truep (-> Datum Datum Bool))
  (: trans-of-implies (-> I64 Datum))
  (: trans-of-implies1 (-> I64 Datum))
  (: term-equal? (-> Datum Datum Bool))
  (: term-args-equal? (-> Datum Datum Bool))
  (: term-member? (-> Datum Datum Bool))
'''
INPUTS = '''(define-data Specification
  (specification (count I64 specification-count) (size I64 specification-size)
                 (expected Datum specification-expected)))
(: read-specification (-> InputPort Specification))
(define (read-specification port)
  (let* ((count (boyer-exact (read-value! (read port))))
         (size (boyer-exact (read-value! (read port))))
         (expected (read-value! (read port))))
    (specification count size expected)))
(define configured (call-with-input-file "input.txt" read-specification))
(: configured-count (-> I64))
(define (configured-count) (specification-count configured))
(define-extern barrier "benchmark" "barrier" (-> Bool))
(: hide (-> I64 I64 I64))
(define (hide count value) (if (barrier) value (unreachable)))
(: boyer-accepted? (-> Datum Datum Bool))
(define (boyer-accepted? result expected)
  (and (datum-number? result) (= (boyer-exact result) (boyer-exact expected))))
(: bench (-> I64 I64))
(define (bench count)
  (let loop ((index 0) (result (datum-boolean #f)))
    (if (< index count)
        (begin ((ref-get setup-boyer))
               (loop (+ index 1) ((ref-get test-boyer) alist term
                                 (hide count (specification-size configured)))))
        (if (boyer-accepted? result (specification-expected configured)) 1 0))))
'''


# ---- Exact reversible edits include the definitions after the harness ----


def kernel(source):
    source = re.sub(r'^\(import [^\n]*\)\s*$', '', source, flags=re.M)
    return replace(source, form(source, '(define (run-benchmark)'), '')


def tokens(source):
    return list(re.finditer(r';[^\n]*|"(?:[^"\\]|\\.)*"|[()\']|[^\s()\']+', source))


def read_tree(items, index):
    token = items[index][0]
    if token != '(':
        if token in (')', "'") or token.startswith(('"', ';')):
            raise ValueError('unsupported Boyer quoted atom: ' + token)
        return token, index + 1
    values, index = [], index + 1
    while items[index][0] != ')':
        value, index = read_tree(items, index)
        values.append(value)
    return values, index + 1


def datum_literal(value):
    if isinstance(value, str):
        return f'(boyer-integer {value})' if re.fullmatch(r'-?\d+', value) else f'(boyer-symbol {json.dumps(value)})'
    result = '(datum-null)'
    for child in reversed(value):
        result = f'(datum-cons {datum_literal(child)} {result})'
    return result


def quote_extent(items, index):
    abbreviated = items[index][0] == "'"
    spelled = items[index][0] == '(' and index + 1 < len(items) and items[index + 1][0] == 'quote'
    if not abbreviated and not spelled:
        return None
    value, end = read_tree(items, index + (1 if abbreviated else 2))
    if spelled and items[end][0] != ')':
        raise ValueError('Boyer quote requires exactly one datum')
    return end + int(spelled), value


def quoted_forms(source):
    items = [item for item in tokens(source) if not item[0].startswith(';')]
    index = 0
    while index < len(items):
        extent = quote_extent(items, index)
        if extent is None:
            index += 1
        else:
            end, value = extent
            yield items[index].start(), items[end - 1].end(), value
            index = end


def quoted_constants(source):
    edits, constants = [], []
    for start, end, value in quoted_forms(source):
        name = f'boyer-constant-{len(constants)}'
        edits.append((start, end, name))
        constants.append(f'(define {name} {datum_literal(value)})\n')
    for start, end, name in reversed(edits):
        source = source[:start] + name + source[end:]
    return source, ''.join(constants)


def mutable_bindings(source):
    for name in ('setup-boyer', 'test-boyer', '*symbol-records-alist*', 'if-constructor',
                 'rewrite-count', 'unify-subst', 'false-term', 'true-term'):
        source = browse_port.tokens(source, {name: f'(ref-get {name})'})
        source = source.replace(f'(set! (ref-get {name})', f'(ref-set! {name}')
        prefix = f'(define (ref-get {name}) '
        original = form(source, prefix)
        initial = original[len(prefix):-1]
        source = replace(source, original, f'(define {name} (ref {initial}))')
    return source


def stubs(source):
    for name, args, signature in [('setup-boyer', '', '(-> Bool)'),
                                   ('test-boyer', 'alist term n', '(-> Datum Datum I64 Datum)')]:
        original = form(source, f'(define ({name}')
        source = replace(source, original,
                         f'(define {name} (ann (lambda ({args}) (unreachable)) {signature}))')
    return source


def typed_results(source):
    source = replace(source, '(if answer\n                rewrite-count\n                #f)',
                     '(if answer\n                (boyer-integer rewrite-count)\n                (datum-boolean #f))')
    source = replace(source, '(equal? n 1)', '(= n 1)')
    for before, after, count in [('0 n)', '(boyer-integer 0) (boyer-integer n))', 1),
                                 ('0 1)', '(boyer-integer 0) (boyer-integer 1))', 1),
                                 ('(- n 1)\n                            n)',
                                  '(boyer-integer (- n 1))\n                            (boyer-integer n))', 1)]:
        source = replace(source, before, after, count)
    return replace(source, '(error #f "ADD-LEMMA did not like term:  " term)',
                   '(datum-fail "ADD-LEMMA did not like term")')


def datum_operations(source):
    names = 'cons car cdr list null? pair? assq map eq? number?'.split()
    replacements = {name: 'datum-' + name for name in names}
    replacements.update({name: 'boyer-' + name for name in 'caar cdar cadr caddr cadddr vector vector-ref vector-set!'.split()})
    replacements.update({'equal?': 'datum=?', 'zero?': 'boyer-zero?', 'cond': 'boyer-cond', 'do': 'boyer-do'})
    return browse_port.tokens(source, replacements)


# Chez's original primitive cons evaluates these operands from left to right.
# The wrapped Datum constructor needs explicit sequencing to retain that observed
# setup order; general Scheme leaves operand evaluation order unspecified.
LEMMA_CONS = '(cons\n                 (translate-term term)\n                 (get (car (cadr term)) (quote lemmas)))'
ORDERED_LEMMA_CONS = '''(let* ((translated-lemma (translate-term term))
                        (prior-lemmas (get (car (cadr term)) (quote lemmas))))
                  (cons translated-lemma prior-lemmas))'''
TERM_CONS = '''(cons (symbol->symbol-record (car term))
                      (translate-args (cdr term)))'''
ORDERED_TERM_CONS = '''(let* ((constructor (symbol->symbol-record (car term)))
                       (arguments (translate-args (cdr term))))
                  (cons constructor arguments))'''
ARGUMENT_CONS = '''(cons (translate-term (car lst))
                      (translate-args (cdr lst)))'''
ORDERED_ARGUMENT_CONS = '''(let* ((first (translate-term (car lst)))
                       (rest (translate-args (cdr lst))))
                  (cons first rest))'''


def typed_truth_tests(source):
    for variable in ('x', 'temp-temp'):
        source = replace(source, f'(if {variable}\n', f'(if (datum-truth? {variable})\n')
    return replace(source, '(boyer-cond (temp-temp\n', '(boyer-cond ((datum-truth? temp-temp)\n')


def function_contracts(source):
    contracts = CONTRACTS + ('  (: scons (-> Datum Datum Datum Datum))\n' if '(define (scons ' in source else '')
    return replace(source, '(let ()\n', '(let ()\n' + contracts)


def verify_reverse(source, adapted, ledger):
    for edit in reversed(ledger):
        adapted = replace(adapted, edit['after'], edit['before'], edit['count'])
    if adapted != source:
        raise ValueError('Boyer edits did not restore the complete kernel')


def adaptation(source):
    ledger, adapted = [], source
    for before, after in [(LEMMA_CONS, ORDERED_LEMMA_CONS), (TERM_CONS, ORDERED_TERM_CONS),
                          (ARGUMENT_CONS, ORDERED_ARGUMENT_CONS)]:
        adapted = browse_port.edit(adapted, ledger, before, after)
    unquoted, constants = quoted_constants(adapted)
    adapted = browse_port.edit(adapted, ledger, adapted, unquoted)
    for transform in (stubs, typed_results, mutable_bindings, datum_operations, typed_truth_tests, function_contracts):
        adapted = browse_port.edit(adapted, ledger, adapted, transform(adapted))
    verify_reverse(source, adapted, ledger)
    return constants + adapted, ledger


def specification(name, data):
    count, size, expected, *_ = map(int, re.sub(r';[^\n]*', '', data.decode()).split())
    return dict(name=name, count=count, size=size, original_expected=expected, inputs=[], expected=1,
                setup_barriers=0, barriers_per_iteration=1, additional_exports=['configured-count'],
                runtime='scalar-datum-reader', native_heap_bytes=NATIVE_HEAP_BYTES[name], predicate='number? rewrites and exact rewrite-count equality')


def program(source):
    adapted, _ = adaptation(kernel(source))
    return ('(import (snail strict) (rename (snail datum) (string->symbol typed-string->symbol)) (snail io) (snail read))\n'
            + CONTROL + COMMON + adapted + INPUTS + '(unit)\n')


# ---- Original Chez and exact adapted datum/prover bodies ----

EXPORTS = '''datum-fail datum-null datum-boolean datum-symbol datum-number datum-vector datum-cons
  datum-car datum-cdr datum-null? datum-pair? datum-truth? datum-eq? datum=?
  datum-list datum-length datum-assq datum-map datum-vector-values datum-number? datum-number-value datum-symbol-value exact-number'''.split()


def chez_prelude(root):
    return reader_ports.chez_reader(root, [*EXPORTS, ('typed-string->symbol', 'string->symbol'), ('typed-symbol->string', 'symbol->string')]) + CONTROL + COMMON


def adapted_chez(source, root):
    upstream = kernel(source)
    adapted, ledger = adaptation(upstream)
    harness = form(source, '(define (run-benchmark)')
    changed = harness.replace('(setup-boyer)', '((ref-get setup-boyer))').replace('(test-boyer ', '((ref-get test-boyer) ')
    changed = replace(changed, '(and (number? rewrites) (= rewrites output))',
                      '(and (datum-number? rewrites) (= (boyer-exact rewrites) output))')
    # The harness originally precedes all kernel definitions. Chez permits this
    # ordering because no benchmark call occurs until the complete program loads.
    return chez_prelude(root) + adapted + changed, ledger


def complete_chez_sources(name, files, original, runner, driver):
    original_program = runner.source_text(files, name, 'chez')
    body = re.sub(r'^\(import [^\n]*\)\s*$', '', original, flags=re.M)
    control, _ = adapted_chez(original, driver.ROOT)
    adjusted = replace(original_program, body, control)
    adjusted = replace(adjusted, '(result #f)', '(result (datum-boolean #f))')
    restored = replace(adjusted, '(result (datum-boolean #f))', '(result #f)')
    if replace(restored, control, body) != original_program:
        raise ValueError('complete Boyer Chez program failed to reverse')
    return original_program, adjusted


def retain_adaptation(directory, ledger, original, adapted, driver):
    driver.save(directory / 'adaptation-ledger.json', dict(edits=ledger, complete_reverse_verified=True))
    (directory / 'chez-adaptation.patch').write_text(''.join(difflib.unified_diff(
        original.splitlines(True), adapted.splitlines(True), fromfile='original-chez', tofile='adapted-chez')))


def write_sources(name, files, directory, runner, driver):
    original = files[f'src/{name}.scm'].decode()
    upstream = kernel(original)
    adapted, ledger = adaptation(upstream)
    chez, control = complete_chez_sources(name, files, original, runner, driver)
    for label, text in [('upstream.scm', original), ('upstream-kernel.scm', upstream),
                        ('adapted-kernel.scm', adapted), ('strict.scm', program(original)),
                        ('chez-prelude.scm', files['src/Petite-Chez-prelude.scm'].decode()),
                        ('chez/program.scm', chez), ('chez-adapted/program.scm', control)]:
        target = directory / label
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
    retain_adaptation(directory, ledger, chez, control, driver)


# ---- Full original inputs and wrong predicates execute on every target ----


def fixtures(data):
    return [('canonical', data, 1), ('small', b'1\n0\n95024\n', 1),
            ('repeat-reset', b'2\n0\n95024\n', 1), ('wrong-rewrites', b'1\n0\n95025\n', 0),
            ('zero-repetitions', b'0\n0\n95024\n', 0)]


def native_environment(name, environment):
    active = dict(environment, SNAIL_GC_HEAP_BYTES=str(NATIVE_HEAP_BYTES[name]))
    active.pop('SNAIL_GC_STATS', None)
    return active


def compiled_result(run, spec):
    value = json.loads(run['stdout'])
    required = dict(result=spec['expected'], barriers=spec['barriers_per_iteration'] * spec['count'],
                    setup_closed=1, worker_closed=0)
    if run['stderr'] or any(value.get(key) != amount for key, amount in required.items()):
        raise ValueError('Boyer result, opacity or file lifetime differs')
    return value


def compiled_commands(directory, target, tools, driver):
    host = [tools['NODE'], '--disable-warning=ExperimentalWarning', driver.HERE / 'reader-host.mjs']
    return [('raw', [*host, directory / 'raw.wasm', target / 'spec.json']),
            ('optimized', [*host, directory / 'optimized.wasm', target / 'spec.json']),
            ('native', [directory / 'native'])]


def check_compiled(directory, target, spec, tools, environment, driver):
    results = {}
    for system, command in compiled_commands(directory, target, tools, driver):
        active = native_environment(spec['name'], environment) if system == 'native' else environment
        run = reader_ports.record(target, system, command, active, target)
        results[system] = compiled_result(run, spec)
    return results


def chez_result(run, spec):
    name = f"{spec['name']}:{spec['size']}:{spec['count']}"
    prefix, frame = f'Running {name}\n', f'+!CSVLINE!+chez,{name},'
    if spec['expected']:
        number = r'[0-9.eE+\-]+'
        pattern = re.escape(prefix) + rf'Elapsed time: ({number}) seconds \(({number})\) for '
        valid = re.fullmatch(pattern + re.escape(name + '\n' + frame) + rf'({number})\n', run['stdout'])
        valid = valid and float(valid[1]) == float(valid[3])
    else:
        valid = re.fullmatch(re.escape(prefix) + r'ERROR: returned incorrect result: [^\n]+\n'
                             + re.escape(frame + 'INCORRECT\n'), run['stdout'])
    if run['stderr'] or not valid:
        raise ValueError('Boyer complete Chez predicate or output frame differs')
    return dict(accepted=bool(spec['expected']))


def check_chez(target, data, spec, commands, environment):
    results = {}
    for system, command in commands.items():
        run = reader_ports.record(target, system, command, environment, target, data.decode())
        results[system] = chez_result(run, spec)
    return results


def validate_input(directory, label, data, accepted, commands, tools, environment, driver):
    target = directory / 'checks' / label
    target.mkdir(parents=True)
    spec = dict(specification(directory.name, data), expected=accepted)
    (target / 'input.txt').write_bytes(data)
    driver.save(target / 'spec.json', spec)
    results = check_compiled(directory, target, spec, tools, environment, driver)
    results.update(check_chez(target, data, spec, commands, environment))
    driver.save(target / 'validation.json', results)
    return dict(label=label, accepted=bool(accepted), size=spec['size'], count=spec['count'], systems=list(results))


def prepare_programs(name, files, directory, runner, tools, environment, driver):
    write_sources(name, files, directory, runner, driver)
    reader_ports.build(directory, tools, environment, driver)
    return reader_ports.build_chez(directory, runner, tools, environment)


def validate_workload(directory, data, commands, tools, environment, driver):
    checks = []
    for fixture in fixtures(data):
        checks.append(validate_input(directory, *fixture, commands, tools, environment, driver))
        driver.save(directory / 'canonical-validation.json', checks)
    validate_observations(directory, tools, environment, driver)
    validate_native_module(directory, tools, environment, driver)
    prepare_rust_control(directory, tools, environment, driver)


def prepare_workload(name, files, output, runner, tools, environment, driver):
    directory, data = output / name, files[f'inputs/{name}.input']
    directory.mkdir()
    (directory / 'input.txt').write_bytes(data)
    spec = specification(name, data)
    driver.save(directory / 'spec.json', spec)
    commands = prepare_programs(name, files, directory, runner, tools, environment, driver)
    validate_workload(directory, data, commands, tools, environment, driver)
    return dict(name=name, status='ready', spec=spec, chez_commands=commands,
                systems=['strict', 'native', 'chez', 'chez-adapted'],
                hashes={str(path.relative_to(directory)): driver.digest(path)
                        for path in directory.rglob('*')
                        if path.is_file() and 'target' not in path.relative_to(directory).parts})


def prepare_case(name, files, output, runner, tools, environment, driver):
    previous = signal.signal(signal.SIGTERM, reader_ports.interrupted)
    try:
        return prepare_workload(name, files, output, runner, tools, environment, driver)
    finally:
        signal.signal(signal.SIGTERM, previous)


# ---- Separate observers retain complete terms and meaningful source work ----

COUNTER_NAMES = ['rewrite', 'rewrite-args', 'rewrite-with-lemmas', 'apply-subst', 'apply-subst-lst',
                 'one-way-unify', 'one-way-unify1', 'one-way-unify1-lst', 'term-equal?',
                 'tautologyp', 'translate-term', 'add-lemma', 'source-cons', 'sharing-cons', 'sharing-reuse']
COUNTERS = '''(define observer-counts (make-vector 15 0))
(define observer-order (ref (ann (lambda () (unreachable)) (-> I64))))
(define observer-rewritten (ref (datum-null)))
(define observer-run (ref (ann (lambda (size details?) (unreachable)) (-> I64 Bool I64))))
(define observer-check (ref (ann (lambda () (unreachable)) (-> I64))))
(define observer-setup (ref (ann (lambda () (unreachable)) (-> I64))))
(: observer-tick! (-> I64 Unit))
(define (observer-tick! index)
  (vector-set! observer-counts index (+ (vector-ref observer-counts index) 1)))
(define-syntax observer-cons
  (syntax-rules ()
    ((observer-cons first rest)
     (begin (observer-tick! 12) (datum-cons first rest)))))
(: observer-save (-> Datum Datum))
(define (observer-save value) (ref-set! observer-rewritten value) value)
(: observer-reset! (-> Unit))
(define (observer-reset!)
  (let loop ((index 0))
    (when (< index 15) (vector-set! observer-counts index 0) (loop (+ index 1)))))
(: observer-counters (-> Unit))
(define (observer-counters)
  (let loop ((index 0))
    (when (< index 15) (emit-i64 (vector-ref observer-counts index)) (loop (+ index 1)))))
(: observer-assert (-> Bool String Unit))
(define (observer-assert test message) (if test (unit) (datum-fail message)))
(: observer-symbol (-> Datum Unit))
(define (observer-symbol symbol)
  (let ((text (boyer-symbol-text symbol)))
    (emit-i64 (string-length text))
    (let loop ((index 0))
      (when (< index (string-length text))
        (emit-i64 (char->integer (string-ref text index))) (loop (+ index 1))))))
'''
ORIGINAL_ALIASES = '''(define datum-cons cons)
(define datum-car car)
(define datum-cdr cdr)
(define datum-list list)
(define datum-assq assq)
(define datum-length length)
(define datum-null? null?)
(define datum-pair? pair?)
(define datum-number? number?)
(define datum-eq? eq?)
(define (datum-null) '())
(define boyer-symbol string->symbol)
(define boyer-symbol-text symbol->string)
(define boyer-integer values)
(define boyer-exact values)
(define (datum-fail text) (error 'boyer text))
'''
INTERNAL_OBSERVERS = '''
  (: observer-term (-> Datum Unit))
  (define (observer-term value)
    (if (datum-pair? value)
        (begin (emit-i64 -1) (observer-symbol (get-name (datum-car value)))
               (observer-arguments (datum-cdr value)))
        (if (datum-null? value) (emit-i64 -5)
            (if (datum-number? value) (begin (emit-i64 -3) (emit-i64 (boyer-exact value)))
                (begin (emit-i64 -4) (observer-symbol value))))))
  (: observer-arguments (-> Datum Unit))
  (define (observer-arguments values)
    (if (datum-null? values) (emit-i64 -2)
        (begin (observer-term (datum-car values)) (observer-arguments (datum-cdr values)))))
  (: observer-records (-> Datum Unit))
  (define (observer-records records)
    (unless (datum-null? records)
      (let* ((entry (datum-car records)) (record (datum-cdr entry)))
        (observer-symbol (datum-car entry))
        (observer-assert (datum-eq? (get-name record) (datum-car entry)) "symbol table name")
        (observer-arguments (get-lemmas record))
        (observer-records (datum-cdr records)))))
  (: observer-unification (-> Unit))
  (define (observer-unification)
    (let ((seven (boyer-integer 7)) (eight (boyer-integer 8)) (variable (boyer-symbol "probe-variable")))
      (observer-assert (one-way-unify seven seven) "numeric match")
      (observer-assert (not (one-way-unify eight seven)) "numeric mismatch")
      (observer-assert (one-way-unify seven variable) "bind variable")
      (observer-assert (one-way-unify1 seven variable) "repeat variable match")
      (observer-assert (not (one-way-unify1 eight variable)) "repeat variable mismatch")
      (observer-assert (one-way-unify1-lst (datum-null) (datum-null)) "empty argument lists")
      (observer-assert (not (one-way-unify1-lst (datum-list seven) (datum-null))) "missing pattern argument")
      (observer-assert (not (one-way-unify1-lst (datum-null) (datum-list variable))) "extra pattern argument")))
  (: observer-repeated-arguments (-> Unit))
  (define (observer-repeated-arguments)
    (let* ((symbol (boyer-symbol "probe-call")) (x (boyer-symbol "probe-x"))
           (seven (boyer-integer 7)) (eight (boyer-integer 8))
           (pattern (translate-term (datum-list symbol x x)))
           (equal (translate-term (datum-list symbol seven seven)))
           (unequal (translate-term (datum-list symbol seven eight))))
      (observer-assert (one-way-unify equal pattern) "repeated argument match")
      (observer-assert (not (one-way-unify unequal pattern)) "repeated argument mismatch")
      (observer-assert (not (one-way-unify equal (translate-term (datum-list symbol x)))) "argument count")
      (observer-assert (not (one-way-unify equal (translate-term (datum-list x x x)))) "constructor identity")))
  (: observer-unification-reset (-> Unit))
  (define (observer-unification-reset)
    (let* ((call (boyer-symbol "probe-call")) (x (boyer-symbol "probe-x"))
           (seven (boyer-integer 7)) (eight (boyer-integer 8))
           (pattern (translate-term (datum-list call x seven)))
           (value (translate-term (datum-list call eight eight))))
      (observer-assert (not (one-way-unify value pattern)) "failure after first binding")
      (observer-assert (one-way-unify1 eight x) "failed unify retains partial source binding")
      (observer-assert (not (one-way-unify1 seven x)) "partial binding must agree")
      (observer-assert (one-way-unify seven x) "new top-level unify resets bindings")))
  (: observer-sharing (-> Unit))
  (define (observer-sharing)
    (let* ((quoted (datum-list (boyer-symbol "probe-no-lemmas") (boyer-symbol "probe-x")))
           (original (translate-term quoted)) (copy (translate-term quoted))
           (substituted (apply-subst (datum-null) original)) (rewritten (rewrite original)))
      (observer-assert (and (term-equal? original copy) (not (datum-eq? original copy))) "fresh translated pair")
      (observer-assert (and (term-equal? original substituted) (not (datum-eq? original substituted))) "fresh substitution pair")
      (observer-assert (not (datum-eq? (datum-cdr original) (datum-cdr substituted))) "fresh substituted arguments")
      (observer-assert (term-equal? original rewritten) "unchanged rewrite contents")
      (observer-assert (= (if (datum-eq? original rewritten) 1 0) SHARING) "rewrite call identity")
      (observer-assert (= (if (datum-eq? (datum-cdr original) (datum-cdr rewritten)) 1 0) SHARING) "rewrite argument identity")))
  (: observer-symbol-reset (-> Unit))
  (define (observer-symbol-reset)
    (let* ((name (boyer-symbol "equal")) (record (symbol->symbol-record name))
           (lemmas (get-lemmas record)))
      (observer-assert (datum-pair? lemmas) "installed equal lemmas")
      (observer-assert (datum-eq? record (datum-car (datum-car lemmas))) "recursive constructor/lemma edge")
      (SETUP)
      (observer-assert (not (datum-eq? record (symbol->symbol-record name))) "setup resets constructor identity")
      (observer-assert (datum-eq? lemmas (get-lemmas record)) "reset preserves old record")))
  (ref-set! observer-order
    (lambda ()
      (SETUP)
      (let* ((variable (boyer-symbol "probe-variable"))
             (left (datum-list (boyer-symbol "probe-left") variable))
             (right (datum-list (boyer-symbol "probe-right") variable)))
        (add-lemma (datum-list (boyer-symbol "equal") left right)))
      (observer-symbol (datum-car (datum-car RECORDS)))
      (observer-symbol (datum-car (datum-car (datum-cdr RECORDS)))) 42))
  (ref-set! observer-setup
    (lambda () (SETUP) (observer-records RECORDS) 42))
  (ref-set! observer-check
    (lambda () (SETUP) (observer-unification) (observer-repeated-arguments)
      (observer-unification-reset) (observer-sharing) SHARING-CHECK (observer-symbol-reset) 42))
  (ref-set! observer-run
    (lambda (size details?)
      (observer-reset!) (SETUP)
      (let ((result (TEST alist term size)))
        (emit-i64 (boyer-exact result)) (observer-counters)
        (when details? (observer-term (ref-get observer-rewritten))) 1)))
'''
SHARING_CHECK = '''(let* ((x (translate-term (datum-list (boyer-symbol "probe-call"))))
                         (copy (translate-term (datum-list (boyer-symbol "probe-call"))))
                         (tail (datum-list x)) (tail-copy (datum-list x))
                         (original (datum-cons x tail)))
                    (observer-assert (datum-eq? original (scons x tail original)) "sharing preserves original")
                    (observer-assert (not (datum-eq? original (scons copy tail original))) "equal new car allocates")
                    (observer-assert (not (datum-eq? original (scons x tail-copy original))) "equal new cdr allocates"))'''


def observe_function_entry(source, name, index):
    original = form(source, f'(define ({name} ')
    header, rest = original.split('\n', 1)
    return replace(source, original, header + f'\n    (observer-tick! {index})\n' + rest)


def observe_sharing_cons(source):
    if '(define (scons ' not in source:
        return source
    original = form(source, '(define (scons ')
    observed = replace(original, '    (if ', '    (observer-tick! 13)\n    (if ')
    observed = replace(observed, '\n        original\n', '\n        (begin (observer-tick! 14) original)\n')
    return replace(source, original, observed)


def observed_kernel(source, adapted):
    # Skip all quoted trees and their generated constructors. Only actual source
    # cons expressions are counted; list construction is a distinct source call.
    prefix, body = source.split('(define (add-lemma-lst', 1)
    body = '(define (add-lemma-lst' + body
    constructor = 'datum-cons' if adapted else 'cons'
    body = re.sub(r'\(' + constructor + r'(?=\s)', '(observer-cons', body)
    for index, name in enumerate(COUNTER_NAMES[:12]):
        body = observe_function_entry(body, name, index)
    body = replace(body, '(rewrite x)', '(observer-save (rewrite x))')
    return prefix + observe_sharing_cons(body)


def observer_bindings(adapted, sharing):
    probes = INTERNAL_OBSERVERS.replace('SHARING-CHECK', SHARING_CHECK if sharing else '(unit)')
    probes = probes.replace('SHARING', '1' if sharing else '0')
    probes = probes.replace('(SETUP)', '((ref-get setup-boyer))' if adapted else '(setup-boyer)')
    probes = probes.replace('(TEST ', '((ref-get test-boyer) ' if adapted else '(test-boyer ')
    return probes.replace('RECORDS', '(ref-get *symbol-records-alist*)' if adapted else '*symbol-records-alist*')


def attach_observers(source, adapted, sharing):
    definitions, actions = observer_bindings(adapted, sharing).split('  (ref-set! observer-order', 1)
    anchor = '  (ref-set! setup-boyer' if adapted else '  (set! setup-boyer'
    source = replace(source, anchor, definitions + anchor)
    end = source.rfind(')')
    return source[:end] + '  (ref-set! observer-order' + actions + source[end:]


def strict_probe(source, count_work):
    adapted, _ = adaptation(kernel(source))
    body = observed_kernel(adapted, True) if count_work else adapted
    observed = attach_observers(body, True, '(define (scons ' in source)
    prefix = '(import (snail strict) (rename (snail datum) (string->symbol typed-string->symbol)) (snail io) (snail read))\n'
    symbol_text = '(define (boyer-symbol-text value) (symbol->string (datum-symbol-value value)))\n'
    exports = '''(: observe-once (-> I64))
(define (observe-once) ((ref-get observer-run) (specification-size configured) #t))
(: work-probe (-> I64))
(define (work-probe) ((ref-get observer-run) (specification-size configured) #f))
(: order-probe (-> I64))
(define (order-probe) ((ref-get observer-order)))
(: semantics-probe (-> I64))
(define (semantics-probe) ((ref-get observer-check)))
(: setup-probe (-> I64))
(define (setup-probe) ((ref-get observer-setup)))
'''
    return (prefix + '(define-extern emit-i64 "reader.test" "emit_i64" (-> I64 Unit))\n'
            + CONTROL + COMMON + symbol_text + COUNTERS + observed + INPUTS + exports + '(unit)\n')


def chez_probe(source, adapted, root, prelude, count_work):
    typed, _ = adaptation(kernel(source))
    original = typed if adapted else kernel(source)
    observed = observed_kernel(original, adapted) if count_work else original
    body = attach_observers(observed, adapted, '(define (scons ' in source)
    prefix = chez_prelude(root) if adapted else reader_ports.CHEZ_TYPES + ORIGINAL_ALIASES
    if adapted:
        prefix += '(define (boyer-symbol-text value) (typed-symbol->string (datum-symbol-value value)))\n'
    main = '''(define mode (cadr (command-line)))
(define size (call-with-input-file "input.txt" (lambda (port) (read port) (read port))))
'''
    invoke = '''(let ((result (cond ((string=? mode "setup-probe") ((ref-get observer-setup)))
                          ((string=? mode "semantics-probe") ((ref-get observer-check)))
                          ((string=? mode "order-probe") ((ref-get observer-order)))
                          (else ((ref-get observer-run) size (not (string=? mode "work-probe")))))))
  (display "result:") (write result) (newline))
'''
    return (prelude + prefix + '(define (emit-i64 value) (display "i:") (write value) (newline))\n'
            + COUNTERS + body + main + invoke)


# ---- Probe preparation uses the same captures and native scalar observer ----

PROBE_EXPORTS = ('observe-once', 'work-probe', 'semantics-probe', 'setup-probe', 'order-probe')
PROBE_ENTRY = r'''#include <inttypes.h>
#include <stdio.h>
#include <string.h>
extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void guest_main(void) __asm__("wasm.main");
extern int64_t observe_once(void) __asm__("wasm.observe-once");
extern int64_t work_probe(void) __asm__("wasm.work-probe");
extern int64_t semantics_probe(void) __asm__("wasm.semantics-probe");
extern int64_t setup_probe(void) __asm__("wasm.setup-probe");
extern int64_t order_probe(void) __asm__("wasm.order-probe");
int main(int argc, char **argv) {
    native_host_init(argc, argv); native_module_init(); guest_main();
    const char *mode = argc > 1 ? argv[1] : "observe-once";
    int64_t result = !strcmp(mode, "semantics-probe") ? semantics_probe() :
                     !strcmp(mode, "setup-probe") ? setup_probe() :
                     !strcmp(mode, "order-probe") ? order_probe() :
                     !strcmp(mode, "work-probe") ? work_probe() : observe_once();
    int status = native_finish(0);
    printf("result:%" PRId64 "\n", result);
    return status;
}
'''


def probe_sources(directory, target, driver, count_work):
    source = (directory / 'upstream.scm').read_text()
    prelude = (directory / 'chez-prelude.scm').read_text()
    (target / 'strict.scm').write_text(strict_probe(source, count_work))
    for adapted, system in [(False, 'chez'), (True, 'chez-adapted')]:
        (target / (system + '.scm')).write_text(chez_probe(source, adapted, driver.ROOT, prelude, count_work))


def compile_chez_probes(target, tools, environment):
    for system in ('chez', 'chez-adapted'):
        source, artifact = str(target / (system + '.scm')), str(target / (system + '.so'))
        script = target / (system + '-compile.scm')
        script.write_text('(import (chezscheme))\n(parameterize ((optimize-level 2))\n'
                          f'  (compile-program {json.dumps(source)} {json.dumps(artifact)}))\n')
        reader_ports.record(target, system + '-compile', [tools['CHEZ'], '--script', script], environment)


def build_probe(directory, target, count_work, tools, environment, driver):
    target.mkdir(parents=True)
    probe_sources(directory, target, driver, count_work)
    compile_chez_probes(target, tools, environment)
    exports = [part for name in PROBE_EXPORTS for part in ('--export', name)]
    reader_ports.record(target, 'compile', [driver.ROOT / 'scripts/build-strict', *exports,
                        target / 'strict.scm', target / 'strict.wasm'], environment, driver.ROOT)
    link_probe(directory, target, tools, environment, driver)
    return target


def link_probe(directory, target, tools, environment, driver):
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


def probe_commands(probe, target, mode, tools, driver):
    host = [tools['NODE'], '--disable-warning=ExperimentalWarning', driver.HERE / 'browse-observe.mjs']
    return [('chez', [tools['CHEZ'], '--program', probe / 'chez.so', mode]),
            ('chez-adapted', [tools['CHEZ'], '--program', probe / 'chez-adapted.so', mode]),
            ('raw', [*host, probe / 'raw.wasm', target / 'spec.json']),
            ('optimized', [*host, probe / 'optimized.wasm', target / 'spec.json']),
            ('native', [probe / 'native', mode])]


def checked_trace(run, mode):
    result = 42 if mode in ('setup-probe', 'semantics-probe', 'order-probe') else 1
    if run['stderr'] or not re.fullmatch(r'(?:i:-?\d+\n)*result:' + str(result) + r'\n', run['stdout']):
        raise ValueError('Boyer observation frame differs: ' + mode)
    return run['stdout']


def compare_probe(name, probe, label, data, mode, tools, environment, driver):
    target = probe / label
    target.mkdir()
    (target / 'input.txt').write_bytes(data)
    driver.save(target / 'spec.json', dict(export=mode, native_heap_bytes=NATIVE_HEAP_BYTES[name]))
    expected, results = None, {}
    for system, command in probe_commands(probe, target, mode, tools, driver):
        active = native_environment(name, environment) if system == 'native' else environment
        run = reader_ports.record(target, system, command, active, target)
        trace = checked_trace(run, mode)
        results[system] = retain_trace(target, system, run, driver)
        expected = trace if expected is None else expected
        if trace != expected:
            raise ValueError('Boyer complete ordered observation differs: ' + label + ' ' + system)
    driver.save(target / 'validation.json', results)
    return dict(label=label, mode=mode, systems=results)


def retain_trace(target, system, run, driver):
    trace = run['stdout']
    (target / (system + '.trace')).write_text(trace)
    identity = dict(sha256=hashlib.sha256(trace.encode()).hexdigest(), bytes=len(trace), fields=len(trace.splitlines()))
    run['stdout'] = dict(path=system + '.trace', **identity)
    driver.save(target / 'commands' / system / 'record.json', run)
    return identity


def probe_cases(directory):
    small = b'1\n0\n95024\n'
    return [('all-lemmas', small, 'setup-probe'), ('identity-and-unification', small, 'semantics-probe'),
            ('lemma-evaluation-order', small, 'order-probe'), ('complete-small-term', small, 'observe-once'),
            ('full-original-work', (directory / 'input.txt').read_bytes(), 'work-probe')]


def validate_observations(directory, tools, environment, driver):
    cases = probe_cases(directory)
    results = []
    # Procedure-entry counters can change Chez inlining and unspecified operand
    # order. Observe constructor order and sharing in an uninstrumented kernel;
    # retain complete work counts in a separately compiled diagnostic program.
    for kind, count_work, selected in [('structure', False, cases[:3]), ('work', True, cases[3:])]:
        target = build_probe(directory, directory / 'observations' / kind, count_work, tools, environment, driver)
        for case in selected:
            results.append(compare_probe(directory.name, target, *case, tools, environment, driver))
            driver.save(directory / 'observations' / 'validation.json', dict(cases=results, counter_names=COUNTER_NAMES))


# ---- The native final module is also executed directly on V8 ----


def validate_native_module(directory, tools, environment, driver):
    target = directory / 'native-module'
    target.mkdir()
    modules = list(directory.glob('native.native-*/optimized.wasm'))
    if len(modules) != 1:
        raise ValueError('expected one final native Wasm input')
    shutil.copy2(modules[0], target / 'native-final.wasm')
    reader_ports.prepare_scalar_provider(target / 'native-final.wasm', directory / 'runtime.wasm',
                                         target, tools, environment, driver)
    validate_shared_module(directory, target, tools, environment, driver)


def validate_shared_module(directory, target, tools, environment, driver):
    command = [tools['NODE'], '--disable-warning=ExperimentalWarning', driver.HERE / 'reader-host.mjs',
               target / 'native-final.wasm', directory / 'spec.json', target / 'provider.wasm']
    run = reader_ports.record(target, 'full-canonical', command, environment, directory)
    checked = compiled_result(run, driver.load(directory / 'spec.json'))
    driver.save(target / 'validation.json', dict(result=checked,
        native_final_wasm_sha256=driver.digest(target / 'native-final.wasm'),
        provider_sha256=driver.digest(target / 'provider.wasm')))


# ---- Rust keeps its independent Rc layout and vector constructor table ----


def retain_rust_source(target, driver):
    source = driver.ROOT / 'benchmarks/wasm-reference'
    shutil.copytree(source / 'src', target / 'src')
    for name in ('Cargo.toml', 'Cargo.lock', 'run-wasi.mjs'):
        shutil.copy2(source / name, target / name)


def verify_rust_literals(source, target):
    expected = [value for start, end, value in quoted_forms(source)][:3]
    retained = (target / 'src/boyer-data.scm').read_text()
    items = [item for item in tokens(retained) if not item[0].startswith(';')]
    actual, end = read_tree(items, 0)
    if actual != expected or end != len(items):
        raise ValueError('Rust Boyer quoted constants differ from the complete pinned source')


def rust_result(run, accepted, expected, name, count):
    if accepted:
        pattern = rf'Result: {expected}\n\+!CSVLINE!\+rust-wasm,{name}:{count},[0-9.eE+\-]+\n'
        valid = re.fullmatch(pattern, run['stdout']) and not run['stderr']
    else:
        valid = not run['stdout'] and 'assertion' in run['stderr']
    if not valid:
        raise ValueError('independent Rust Boyer result or predicate differs')


def validate_rust_control(directory, target, tools, environment, driver):
    checks = []
    for label, data, accepted in fixtures((directory / 'input.txt').read_bytes()):
        spec = specification(directory.name, data)
        for system, command in reader_ports.rust_commands(target, directory.name, tools):
            run = reader_ports.record(target, label + '-' + system, command, environment,
                                      stdin=data.decode(), failure=not accepted)
            rust_result(run, accepted, spec['original_expected'], directory.name, spec['count'])
            checks.append(dict(label=label, system=system, accepted=bool(accepted)))
    driver.save(target / 'validation.json', dict(checks=checks, quoted_trees_match_pinned_source=True,
        representation='unchanged Rc immutable calls/argument cells and substitution-entry cells; '
        'Vec symbol records use integer constructor IDs to avoid Rc cycles; separate tail loops and destruction'))


def prepare_rust_control(directory, tools, environment, driver):
    target = directory / 'rust-control'
    retain_rust_source(target, driver)
    verify_rust_literals((directory / 'upstream.scm').read_text(), target)
    reader_ports.record(target, 'unit-tests', [tools['CARGO'], 'test', '--offline', '--lib', 'boyer::tests'],
                        dict(environment, CARGO_TARGET_DIR=str(target / 'target')), target)
    reader_ports.build_rust_bin(target, directory.name, tools, environment)
    retain_rust_ir(target, directory.name)
    validate_rust_control(directory, target, tools, environment, driver)


def retain_rust_ir(target, name):
    for system, directory in [('native', 'release'), ('wasm', 'wasm32-wasip1/release')]:
        paths = list((target / 'target' / directory / 'deps').glob(name + '-*.ll'))
        if len(paths) != 1:
            raise ValueError('expected one Rust Boyer LLVM module: ' + system)
        shutil.copy2(paths[0], target / (name + '-' + system + '.ll'))
