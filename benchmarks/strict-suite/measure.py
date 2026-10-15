#!/usr/bin/env python3
"""Measure original-sized R7RS kernels expressed in the strict Scheme subset."""

import argparse
from datetime import datetime, timezone
import difflib
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
NAMES = ('ack', 'tak', 'cpstak', 'fib', 'fibfp', 'sum', 'sumfp',
         'takl', 'ntakl', 'diviter', 'divrec', 'array1',
         'primes', 'nqueens', 'triangl', 'mbrot', 'pnpoly', 'fft', 'quicksort')
NEXT_PORTS = ('primes', 'nqueens', 'triangl', 'mbrot', 'pnpoly')
MATCHED_PORTS = NEXT_PORTS + ('fft', 'quicksort')
FLOATS = ('fibfp', 'sumfp')
FLOAT_RESULTS = FLOATS + ('fft',)
LISTS = ('takl', 'ntakl', 'diviter', 'divrec')
FULL_LISTS = ('primes', 'triangl')
KERNELS = dict(ack='ack', tak='tak', cpstak='cpstak', fib='fib', fibfp='fibfp',
               sum='run', sumfp='run', takl='mas', ntakl='mas',
               diviter='iterative-div2', divrec='recursive-div2', array1='go',
               primes='primes<=', nqueens='nqueens', triangl='test',
               mbrot='test', pnpoly='run', fft='run', quicksort='quick-1')


# ---- Fixed inputs and mechanical source adaptation ----


def load(path):
    return json.loads(Path(path).read_text())


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def upstream_runner():
    spec = importlib.util.spec_from_file_location('r7rs', ROOT / 'benchmarks/r7rs.py')
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    return runner


def input_values(text):
    tokens = iter(re.findall(r'#\(|\(|\)|[^\s()]+', re.sub(r';[^\n]*', '', text)))

    def datum(token):
        if token in ('(', '#('):
            values = []
            for item in tokens:
                if item == ')':
                    return values
                values.append(datum(item))
            raise ValueError('unclosed input list')
        return float(token) if re.search(r'[.eE]', token) else int(token)

    return [datum(token) for token in tokens]


def case_specification(name, data):
    if name == 'quicksort':
        # The fourth datum is a symbol read but never used by the upstream
        # predicate. Preserve it in input.txt instead of coercing it to a number.
        count, size, limit, unused = re.sub(r';[^\n]*', '', data.decode()).split()
        if unused != 'ignored':
            raise ValueError('unexpected canonical quicksort output datum')
        return dict(name=name, count=int(count), inputs=[int(size), int(limit)],
                    expected=1, unused_output_datum=unused,
                    barriers_per_iteration=0, setup_barriers=3)
    values = input_values(data.decode())
    if name == 'array1':
        repeats, size, expected = values
        return dict(name=name, count=1, inputs=[repeats, size], expected=expected,
                    barriers_per_iteration=2)
    arity = 3 if name in ('tak', 'cpstak', 'takl', 'ntakl') else 2 if name in ('ack', 'triangl', 'pnpoly', 'fft') else 1
    count, *rest = values
    inputs, expected = rest[:arity], rest[arity]
    if name in ('takl', 'ntakl'):
        assert all(xs == list(range(len(xs), 0, -1)) for xs in inputs)
        inputs = list(map(len, inputs))
    barriers = 0 if name in ('diviter', 'divrec') else 1 if name == 'fft' else arity
    spec = dict(name=name, count=count, inputs=inputs, expected=expected,
                barriers_per_iteration=barriers)
    if name in FULL_LISTS:
        spec['result_kind'] = 'i64-list-values'
    if name == 'fft':
        spec['math_provider'] = 'math-provider.wasm'
    return spec


PRELUDE = '''(import (snail strict))
(define-syntax cond
  (syntax-rules (else)
    ((_ (else body ...)) (begin body ...))
    ((_ (test body ...) rest ...) (if test (begin body ...) (cond rest ...)))))
(define-syntax do
  (syntax-rules ()
    ((_ ((var init step) ...) (test result) body ...)
     (let loop ((var init) ...)
       (if test result (begin body ... (loop step ...)))))))
(define (cddr xs) (cdr (cdr xs)))
(define (length xs)
  (let loop ((xs xs) (n 0)) (if (null? xs) n (loop (cdr xs) (+ n 1)))))
(define-extern native-input-i64 "benchmark" "input_i64" (-> I32 I64))
(define-extern native-input-f64 "benchmark" "input_f64" (-> I32 F64))
(define-extern barrier "benchmark" "barrier" (-> Bool))
(define-extern hide-i64 "benchmark" "hide_i64" (-> I64 I64))
(define-extern hide-f64 "benchmark" "hide_f64" (-> F64 F64))
'''


def upstream_kernel(source):
    source = source[:source.index('(define (run-benchmark)')]
    return re.sub(r'^\(import [^\n]*\)\s*$', '', source, flags=re.M)


def kernel_source(name, source):
    source = upstream_kernel(source)
    if name in FLOATS:
        for operation, native in (('+', 'f64-add'), ('-', 'f64-sub'), ('<', 'f64-lt')):
            source = source.replace('(' + operation + ' ', '(' + native + ' ')
    if name in ('diviter', 'divrec'):
        source = '(: create-n (-> I64 (List (List Never))))\n' + source
    if name == 'array1':
        source = array1_kernel(source)
    elif name == 'quicksort':
        source = quicksort_kernel(source)
    elif name in NEXT_PORTS:
        source = next_kernel(name, source)
    return source


def array1_kernel(source):
    # Both fill loops overwrite every element before reading it. The original
    # empty-list initial result is unreachable at its positive repeat count.
    assert source.count('(make-vector n)') == 2
    assert source.count("(result '())") == 1
    return source.replace('(make-vector n)', '(make-vector n 0)').replace("(result '())", '(result 0)')


def replace_exact(source, old, new, count=1):
    if source.count(old) != count:
        raise ValueError(f'expected {count} source occurrences of {old!r}')
    return source.replace(old, new)


def next_kernel(name, source):
    if name == 'nqueens':
        return replace_exact(source, '(when trace? (begin (write z) (newline)))', '')
    if name == 'triangl':
        return triangl_kernel(source)
    if name == 'mbrot':
        source = replace_exact(source, '(inexact ', '(i64->f64 ', 2)
        source = replace_exact(source, '((matrix (make-vector n)))', '((matrix (make-vector n (empty-vector))))')
        return replace_exact(source, 'i (make-vector n))', 'i (make-vector n 0))')
    if name == 'pnpoly':
        source = replace_exact(source, '(count 0)', '(count (ref 0))')
        source = replace_exact(source, '(set! count (+ count 1))', '(ref-set! count (+ (ref-get count) 1))', 12)
        return replace_exact(source, '    count))', '    (ref-get count)))')
    return source


def triangl_kernel(source):
    source, count = re.subn(r"'\(([\d\s]+)\)", r'(list \1)', source)
    if count != 5:
        raise ValueError('expected five flat integer table literals')
    source = replace_exact(source, "(define *answer* '())", "(define *answer* (ref (ann '() (List (List I64)))))")
    source = replace_exact(source, '(set! *answer*', '(ref-set! *answer*', 2)
    source = replace_exact(source, '*sequence*)) *answer*))', '*sequence*)) (ref-get *answer*)))')
    source = replace_exact(source, '(car *answer*)', '(car (ref-get *answer*))')
    return replace_exact(source, '(depth (+ depth 1))', '(depth (+ depth 1) depth)')


def quicksort_kernel(source):
    # The false procedure values are never read: initialization installs all
    # three closures before vector generation. Concrete cells use typed traps
    # for that uninitialized interval, without a Bool-to-procedure conversion.
    for name in ('seed-set!', 'seed-ref', 'random-flonum'):
        stub = {'seed-set!': 'uninitialized-seed-set', 'seed-ref': 'uninitialized-seed-ref',
                'random-flonum': 'uninitialized-random-flonum'}[name]
        source = replace_exact(source, f'(define {name} #f)', f'(define {name} (ref {stub}))')
        source = replace_exact(source, f'(set! {name}', f'(ref-set! {name}')
    source = replace_exact(source, '(seed (vector 1.0 0.0 0.0 1.0 0.0 0.0))',
                           '(seed (ref (vector 1.0 0.0 0.0 1.0 0.0 0.0)))')
    source = replace_exact(source, '(let ((seed seed))', '(let ((seed (ref-get seed)))')
    source = replace_exact(source, '(vector->list seed)', '(vector->list (ref-get seed))')
    source = replace_exact(source, '(set! seed (list->vector l))', '(ref-set! seed (list->vector l))')
    return replace_exact(source, '(random-flonum)', '((ref-get random-flonum))')


NEXT_PRELUDE = '''(define (list . elements) elements)
(define (append xs ys)
  (if (null? xs) ys (cons (car xs) (append (cdr xs) ys))))
'''
EXPECTED_PRELUDE = '''(define-extern native-expected-length "benchmark" "expected_length" (-> I64))
(define-extern native-expected-i64 "benchmark" "expected_i64" (-> I64 I64))
(define (expected-list)
  (let loop ((n (native-expected-length)) (xs '()))
    (if (= n 0) xs
        (loop (- n 1) (cons (native-expected-i64 (- n 1)) xs)))))
(: same-i64-list? (-> (List I64) (List I64) Bool))
(define (same-i64-list? xs ys)
  (if (null? xs) (null? ys)
      (and (not (null? ys)) (= (car xs) (car ys))
           (same-i64-list? (cdr xs) (cdr ys)))))
'''
VECTOR_PRELUDE = '''(define-extern native-vector-length "benchmark" "vector_length" (-> I32 I64))
(define-extern native-vector-f64 "benchmark" "vector_f64" (-> I32 I64 F64))
(define (input-vector index)
  (let ((n (native-vector-length index)))
    (let ((result (make-vector n 0.0)))
      (let loop ((i 0))
        (when (< i n)
          (vector-set! result i (native-vector-f64 index i))
          (loop (+ i 1))))
      result)))
'''
FFT_PRELUDE = '''(define (inexact value) (i64->f64 value))
(define-extern sin "math" "snail_sin" (-> F64 F64))
(define-extern native-expected-length "benchmark" "expected_length" (-> I64))
(define-extern native-expected-f64 "benchmark" "expected_f64" (-> I64 F64))
(define-extern native-tolerance "benchmark" "tolerance" (-> F64))
(: close-f64? (-> F64 F64 Bool))
(define (close-f64? actual expected)
  (let ((difference (- actual expected))
        (scale (if (< expected 0.0) (- 0.0 expected) expected)))
    (let ((error (if (< difference 0.0) (- 0.0 difference) difference)))
      (<= error (* (native-tolerance) (if (< scale 1.0) 1.0 scale))))))
(: fft-probe (-> I64 I64))
(define (fft-probe count)
  (let ((data (input-vector (ann 2 I32))))
    (four1 data)
    (if (and (= (vector-length data) (native-expected-length))
             (let loop ((i 0))
               (or (= i (vector-length data))
                   (and (close-f64? (vector-ref data i) (native-expected-f64 i))
                        (loop (+ i 1))))))
        1 0)))
'''

QUICKSORT_STUBS = ''';; ---- Typed placeholders for staged initialization ----

(: uninitialized-seed-set (-> (Rest F64) Unit))
(define (uninitialized-seed-set . state) (unreachable))
(: uninitialized-seed-ref (-> (List F64)))
(define (uninitialized-seed-ref) (unreachable))
(: uninitialized-random-flonum (-> F64))
(define (uninitialized-random-flonum) (unreachable))
'''
QUICKSORT_COMMON = ''';; ---- Per-element mapping and adjacent-pair validation ----

(define (map-vector-elements function source)
  ;; The first mapped value initializes slots; visit every remaining element
  ;; once in increasing order. No bulk-copy operation implements this map.
  (let ((n (vector-length source)))
    (if (= n 0) (empty-vector)
        (let ((result (make-vector n (function (vector-ref source 0)))))
          (let loop ((i 1))
            (if (= i n) result
                (begin (vector-set! result i (function (vector-ref source i)))
                       (loop (+ i 1)))))))))
(define (sorted-i64-vector? source)
  (let loop ((i 1))
    (or (>= i (vector-length source))
        (and (<= (vector-ref source (- i 1)) (vector-ref source i))
             (loop (+ i 1))))))
'''
QUICKSORT_PRELUDE = ''';; ---- Quicksort host inputs and numeric bindings ----

(define-extern native-count "benchmark" "count" (-> I64))
(define-extern native-vector-length "benchmark" "vector_length" (-> I32 I64))
(define-extern native-vector-i64 "benchmark" "vector_i64" (-> I32 I64 I64))
(define-extern native-expected-length "benchmark" "expected_length" (-> I64))
(define-extern native-expected-i64 "benchmark" "expected_i64" (-> I64 I64))
(define (inexact value) (i64->f64 value))
(define (exact value) (f64->i64 value))
(define (values value) value)
(define (input-i64-vector index)
  (let ((n (native-vector-length index)))
    (let ((result (make-vector n 0)))
      (let loop ((i 0))
        (if (= i n) result
            (begin (vector-set! result i (native-vector-i64 index i))
                   (loop (+ i 1))))))))
(define (same-expected-i64-vector? source)
  (and (= (vector-length source) (native-expected-length))
       (let loop ((i 0))
         (or (= i (vector-length source))
             (and (= (vector-ref source i) (native-expected-i64 i))
                  (loop (+ i 1)))))))
(define (same-input-i64-vector? source index)
  (and (= (vector-length source) (native-vector-length index))
       (let loop ((i 0))
         (or (= i (vector-length source))
             (and (= (vector-ref source i) (native-vector-i64 index i))
                  (loop (+ i 1)))))))
(define (same-f64-list? xs ys)
  (if (null? xs) (null? ys)
      (and (not (null? ys)) (= (car xs) (car ys))
           (same-f64-list? (cdr xs) (cdr ys)))))
'''
QUICKSORT_PROBES = ''';; ---- Supplemental full-output and initialization probes ----

(: quicksort-probe (-> I64 I64))
(define (quicksort-probe count)
  (let* ((source (input-i64-vector (ann 2 I32)))
         (result (quick-1 (map-vector-elements values source) less?)))
    (if (and (same-expected-i64-vector? result)
             (sorted-i64-vector? result)
             (same-input-i64-vector? source (ann 2 I32))
             (or (= (vector-length source) 0)
                 (not (vector-eq? result source)))) 1 0)))
(: quicksort-rng-probe (-> I64 I64))
(define (quicksort-rng-probe count)
  (if (same-expected-i64-vector? quicksort-input) 1 0))
(: quicksort-seed-probe (-> I64 I64))
(define (quicksort-seed-probe count)
  ((ref-get seed-set!) 1.0 0.0 0.0 1.0 0.0 0.0)
  (if (and (same-f64-list? ((ref-get seed-ref))
                          (vector->list (vector 1.0 0.0 0.0 1.0 0.0 0.0)))
           (= (random input1) (native-expected-i64 0))) 1 0))
(: quicksort-sorted-probe (-> I64 I64))
(define (quicksort-sorted-probe count)
  (if (sorted-i64-vector? (input-i64-vector (ann 2 I32))) 1 0))
'''


def quicksort_input_bindings():
    return ''';; ---- Original vector generation before timing ----

(define setup-count (native-count))
(define input0 (hide setup-count (native-input-i64 (ann 0 I32))))
(define input1 (hide setup-count (native-input-i64 (ann 1 I32))))
(define less? (hide setup-count (ann (lambda (x y) (< x y)) (-> I64 I64 Bool))))
(define quicksort-input
  (let ((v (ann (make-vector input0) (Vector I64))))
    (let loop ((i 0))
      (if (= i input0) v
          (begin (vector-set! v i (random input1)) (loop (+ i 1)))))))
'''


def input_bindings(name, spec):
    if name == 'quicksort':
        return quicksort_input_bindings()
    bindings = [f'(define input{index} {input_expression(name, index)})'
                for index in range(len(spec['inputs']))]
    if name in FULL_LISTS:
        bindings.append('(define expected (expected-list))')
    return '\n'.join(bindings)


def input_expression(name, index):
    if name == 'pnpoly':
        return f'(input-vector (ann {index} I32))'
    floating = name in FLOATS or (name == 'fft' and index == 1)
    value = f'(native-input-{"f64" if floating else "i64"} (ann {index} I32))'
    if name in ('takl', 'ntakl'):
        return f'(listn {value})'
    if name in ('diviter', 'divrec'):
        return f'(create-n {value})'
    return value


def kernel_call(name, spec):
    if name == 'fft':
        return '(run (hide count (make-vector input0 input1)))'
    if name == 'quicksort':
        return '(quick-1 (map-vector-elements values quicksort-input) less?)'
    arguments = [f'input{i}' for i in range(len(spec['inputs']))]
    if spec['barriers_per_iteration']:
        opacity_count = 'input0' if name == 'array1' else 'count'
        arguments = [f'(hide {opacity_count} {value})' for value in arguments]
    return f'({KERNELS[name]} {" ".join(arguments)})'


def worker_body(name, spec):
    initial = 'quicksort-input' if name == 'quicksort' else "'()" if name in LISTS + FULL_LISTS else '0.0' if name in FLOAT_RESULTS else '0'
    loop = f'''(let loop ((i 0) (result {initial}))
    (if (< i count) (loop (+ i 1) {kernel_call(name, spec)}) result))'''
    if name in LISTS:
        return f'(length {loop})'
    if name in FULL_LISTS:
        return f'(if (same-i64-list? {loop} expected) 1 0)'
    if name == 'quicksort':
        return f'(if (sorted-i64-vector? {loop}) 1 0)'
    return loop


def strict_program(name, spec, upstream):
    result = 'F64' if name in FLOAT_RESULTS else 'I64'
    worker = f'(: bench (-> I64 {result}))\n(define (bench count) {worker_body(name, spec)})\n(unit)\n'
    hide = '(if (barrier) x (unreachable))' if name in LISTS or name in ('pnpoly', 'fft', 'quicksort') else f'(hide-{"f64" if name in FLOATS else "i64"} x)'
    prelude = PRELUDE + (NEXT_PRELUDE if name in NEXT_PORTS else '')
    prelude += EXPECTED_PRELUDE if name in FULL_LISTS else VECTOR_PRELUDE if name == 'pnpoly' else ''
    if name == 'fft':
        prelude += VECTOR_PRELUDE + FFT_PRELUDE
    if name == 'quicksort':
        prelude += QUICKSORT_PRELUDE + QUICKSORT_STUBS + QUICKSORT_COMMON
        worker = QUICKSORT_PROBES + '\n;; ---- Canonical timed workload ----\n\n' + worker
    return (prelude + f'(define (hide count x) {hide})\n' + kernel_source(name, upstream)
            + input_bindings(name, spec) + '\n' + worker)


# ---- Preparation: freeze sources, build and validate before timing ----


def execute(command, cwd, environment, timeout=300, stdin=None):
    started = time.perf_counter()
    try:
        run = subprocess.run(list(map(str, command)), cwd=cwd, env=environment,
                             input=stdin, capture_output=True, text=True, timeout=timeout)
        return dict(command=list(map(str, command)), returncode=run.returncode,
                    stdout=run.stdout, stderr=run.stderr, process_seconds=time.perf_counter() - started)
    except (subprocess.TimeoutExpired, OSError, UnicodeError) as error:
        return dict(command=list(map(str, command)), error=str(error),
                    process_seconds=time.perf_counter() - started)


def require_success(record):
    if record.get('returncode') != 0:
        raise RuntimeError(str(record))


def tool_paths(benchmarks=()):
    names = dict(CHIBI='chibi-scheme', NODE='node', WASM_AS='wasm-as', WASM_OPT='wasm-opt',
                 WASM_DIS='wasm-dis', CHEZ='scheme', TASKSET='taskset')
    if 'fft' in benchmarks:
        names['RUSTC'] = 'rustc'
    paths = {key: shutil.which(os.environ.get(key, value)) for key, value in names.items()}
    paths['PYTHON'] = sys.executable
    if not all(paths.values()):
        raise ValueError(f'missing tools: {paths}')
    return paths


def build_strict(directory, tools, environment):
    command = [ROOT / 'scripts/build-strict', '--export', 'bench',
               directory / 'strict.scm', directory / 'strict.wasm']
    if load(directory / 'spec.json')['name'] == 'fft':
        command[3:3] = ['--export', 'fft-probe']
    if load(directory / 'spec.json')['name'] == 'quicksort':
        command[3:3] = [part for name in ('quicksort-probe', 'quicksort-rng-probe',
                                        'quicksort-seed-probe', 'quicksort-sorted-probe')
                       for part in ('--export', name)]
    record = execute(command, ROOT, environment)
    save(directory / 'strict-build.json', record)
    require_success(record)
    record = execute([tools['WASM_DIS'], directory / 'strict.wasm', '-o',
                      directory / 'strict.optimized.wat'], ROOT, environment)
    require_success(record)


def build_fft_provider(directory, tools, environment):
    shutil.copyfile(HERE / 'fft-math.rs', directory / 'math-provider.rs')
    compiler = freeze_fft_toolchain(directory, tools['RUSTC'], environment)
    command = [compiler, '--edition=2024', '--crate-name=snail_fft_math', '--crate-type=cdylib', '--target=wasm32-wasip1',
               '-C', 'opt-level=3', '-C', 'lto=yes', '-C', 'codegen-units=1', '-C', 'panic=abort',
               directory / 'math-provider.rs', '-o', directory / 'math-provider.wasm']
    record = execute(command, ROOT, environment)
    save(directory / 'math-provider-build.json', record)
    require_success(record)
    record = execute([tools['WASM_DIS'], directory / 'math-provider.wasm', '-o',
                      directory / 'math-provider.wat'], ROOT, environment)
    save(directory / 'math-provider-disassemble.json', record)
    require_success(record)


def freeze_fft_toolchain(directory, launcher, environment):
    queries = dict(version=['--version', '--verbose'], sysroot=['--print', 'sysroot'],
                   target_libdir=['--print', 'target-libdir', '--target=wasm32-wasip1'])
    report = {}
    for name, arguments in queries.items():
        report[name] = execute([launcher, *arguments], ROOT, environment)
        save(directory / 'math-provider-toolchain.json', report)
        require_success(report[name])
    sysroot = Path(report['sysroot']['stdout'].strip())
    library = Path(report['target_libdir']['stdout'].strip())
    host = next(line.removeprefix('host: ') for line in report['version']['stdout'].splitlines() if line.startswith('host: '))
    compiler, linker = sysroot / 'bin/rustc', sysroot / 'lib/rustlib' / host / 'bin/rust-lld'
    files = [compiler, linker, *sysroot.glob('lib/librustc_driver*'), *(p for p in library.rglob('*') if p.is_file())]
    report['toolchain_files'] = {str(path): digest(path) for path in files}
    report['actual_compiler'] = str(compiler)
    save(directory / 'math-provider-toolchain.json', report)
    return compiler


def validate_strict(directory, tools, environment):
    spec = load(directory / 'spec.json')
    checks = []
    for label, probe in validation_specifications(spec):
        save(directory / f'validation-spec-{label}.json', probe)
        for suffix in ('.raw.wasm', ''):
            command = [tools['NODE'], directory.parent / 'host.mjs', directory / ('strict.wasm' + suffix),
                       directory / f'validation-spec-{label}.json', '--validate']
            record = execute(command, directory, environment)
            checks.append(dict(record, specification=probe, module_suffix=suffix))
            save(directory / 'validation.json', checks)
            require_success(record)
    if spec['name'] in FULL_LISTS:
        validate_sequence_failures(directory, tools, environment, spec)
    if spec['name'] == 'fft':
        validate_sequence_failures(directory, tools, environment, fft_probe_specification(spec, FFT_NONZERO))
    if spec['name'] == 'quicksort':
        validate_sequence_failures(directory, tools, environment,
                                   quicksort_probe_specification(spec, QUICKSORT_VALUES))
        validate_sequence_failures(directory, tools, environment,
                                   quicksort_rng_specification(spec), prefix='rng-')


FFT_NONZERO = [1.0, 0.0, 2.0, 0.5, -1.0, 1.0, 0.0, -2.0,
               0.75, -0.25, -0.5, 0.5, 1.5, -1.0, -2.0, 0.75]


def direct_dft(values):
    size, result = len(values) // 2, []
    for k in range(size):
        total = 0j
        for n in range(size):
            phase = math.tau * k * n / size
            total += complex(values[2 * n], values[2 * n + 1]) * complex(math.cos(phase), math.sin(phase))
        result.extend([total.real, total.imag])
    return result


def fft_probe_specification(spec, values):
    return dict(spec, count=1, inputs=[*spec['inputs'], values], expected=direct_dft(values),
                result_kind='f64-vector-values', export='fft-probe', tolerance=1e-12, barriers_per_iteration=0)


QUICKSORT_VALUES = [3, 1, 2, 3, 0, 2, 1, -4]


def quicksort_random_values(size, limit):
    # Independent binary64 reference for the six-state canonical generator.
    # Keep the expression order visible; truncation returns an inexact integer
    # in Scheme, so convert its Python result back to float before multiplying.
    seed, result = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0], []
    norm, m1, m2 = 2.328306549295728e-10, 4294967087.0, 4294944443.0
    for _ in range(size):
        p1 = 1403580.0 * seed[1] - 810728.0 * seed[0]
        p2 = 527612.0 * seed[5] - 1370589.0 * seed[3]
        k1, k2 = float(math.trunc(p1 / m1)), float(math.trunc(p2 / m2))
        seed[0], seed[3] = seed[1], seed[4]
        p1, p2 = p1 - k1 * m1, p2 - k2 * m2
        seed[1], seed[4] = seed[2], seed[5]
        p1, p2 = p1 + m1 if p1 < 0.0 else p1, p2 + m2 if p2 < 0.0 else p2
        seed[2], seed[5] = p1, p2
        value = norm * ((p1 - p2) + m1) if p1 <= p2 else norm * (p1 - p2)
        result.append(math.trunc(float(limit) * value))
    return result


def quicksort_probe_specification(spec, values):
    return dict(spec, count=1, inputs=[*spec['inputs'], values], expected=sorted(values),
                result_kind='i64-vector-values', export='quicksort-probe')


def quicksort_rng_specification(spec):
    return dict(spec, count=1, expected=quicksort_random_values(*spec['inputs']),
                result_kind='i64-vector-values', export='quicksort-rng-probe')


def quicksort_validation_specifications(spec):
    probes = [(str(count), dict(spec, count=count)) for count in (1, 2)]
    probes.append(('canonical-count', spec))
    values = [('empty', []), ('singleton', [7]), ('duplicates', QUICKSORT_VALUES),
              ('ordered', list(range(8))), ('reversed', list(range(7, -1, -1))),
              ('all-equal', [2] * 8)]
    probes += [(label, quicksort_probe_specification(spec, data)) for label, data in values]
    rng = quicksort_rng_specification(spec)
    probes += [('rng', rng), ('seed-reset', dict(rng, export='quicksort-seed-probe'))]
    for label, data, expected in [('sorted-empty', [], 1), ('sorted-duplicates', [1, 1, 2], 1),
                                  ('inversion-first', [2, 1, 3, 4], 0), ('inversion-middle', [1, 3, 2, 4], 0),
                                  ('inversion-last', [1, 2, 4, 3], 0)]:
        probes.append((label, dict(spec, count=1, inputs=[*spec['inputs'], data], expected=expected,
                                  export='quicksort-sorted-probe')))
    return probes


def validation_specifications(spec):
    if spec['name'] == 'quicksort':
        return quicksort_validation_specifications(spec)
    if spec['name'] == 'fft':
        return [(str(count), dict(spec, count=count)) for count in (1, 2)] + [
            ('nonzero', fft_probe_specification(spec, FFT_NONZERO)),
            ('impulse', fft_probe_specification(spec, [1.0, 0.0] + [0.0] * 14))]
    if spec['name'] == 'primes':
        return [(str(count), dict(spec, count=count)) for count in (1, 2)] + [
            ('empty', dict(spec, count=1, inputs=[1], expected=[]))]
    if spec['name'] == 'pnpoly':
        return [(str(count), dict(spec, count=count)) for count in (1, 2)] + [
            ('zero-vectors', dict(spec, count=1, inputs=[[0.0] * 20, [0.0] * 20], expected=0))]
    if spec['name'] != 'array1':
        return [(str(count), dict(spec, count=count)) for count in (1, 2)]
    # These are behavior probes, not performance samples. The discarded full
    # pair later checks the unchanged original workload on both systems.
    return [(f'{count}-{repeats}-{size}',
             dict(spec, count=count, inputs=[repeats, size], expected=size if repeats else 0))
            for count, repeats, size in ((1, 1, 0), (1, 1, 1), (2, 3, 7), (1, 0, 7))]


def validate_sequence_failures(directory, tools, environment, spec, prefix=''):
    changed = list(spec['expected'])
    changed[len(changed) // 2] += 1
    probes = [('wrong-value', changed), ('short', spec['expected'][:-1]),
              ('long', spec['expected'] + [0])]
    checks = []
    for label, expected in probes:
        path = directory / f'validation-spec-{prefix}{label}.json'
        save(path, dict(spec, count=1, expected=expected))
        for suffix in ('.raw.wasm', ''):
            record = execute([tools['NODE'], directory.parent / 'host.mjs',
                              directory / ('strict.wasm' + suffix), path, '--validate'], directory, environment)
            rejected = record.get('returncode') != 0 and "actual: '0'" in record.get('stderr', '')
            checks.append(dict(record, label=label, rejected=rejected, checked_flag=0 if rejected else None))
            save(directory / f'validation-negative{ "-" + prefix.rstrip("-") if prefix else ""}.json', checks)
            if not rejected or 'AssertionError' not in record.get('stderr', ''):
                raise ValueError('full result predicate must reject the changed expected result')


CHEZ_REF_HELPERS = '''(define (ref value) (vector value))
(define (ref-get cell) (vector-ref cell 0))
(define (ref-set! cell value) (vector-set! cell 0 value))
'''
CHEZ_HELPERS = dict(primes='', nqueens='', fft='', pnpoly=CHEZ_REF_HELPERS,
                   triangl='''(define-syntax ann
  (syntax-rules () ((_ expression type) expression)))
''' + CHEZ_REF_HELPERS,
                   quicksort='''(define-syntax :
  (syntax-rules () ((_ . signature) (begin))))
(define (unreachable) (error 'quicksort "uninitialized procedure called"))
(define (empty-vector) (vector))
''' + CHEZ_REF_HELPERS + QUICKSORT_STUBS + QUICKSORT_COMMON,
                   mbrot='''(define (empty-vector) (vector))
(define (i64->f64 value) (inexact value))
''')


def quicksort_original_predicate(upstream):
    start = upstream.index('(lambda (v)\n')
    depth = 0
    for index, char in enumerate(upstream[start:]):
        depth += (char == '(') - (char == ')')
        if depth == 0:
            return upstream[start:start + index + 1]
    raise ValueError('unclosed canonical quicksort result predicate')


def matched_chez_source(name, directory):
    upstream = (directory / 'upstream.scm').read_text()
    original_kernel = upstream_kernel(upstream)
    adapted_kernel = kernel_source(name, upstream)
    original = (directory / 'program.scm').read_text()
    strict = (directory / 'strict.scm').read_text()
    if original.count(original_kernel) != 1 or strict.count(adapted_kernel) != 1:
        raise ValueError('kernel text must occur exactly once in each complete program')
    adapted = replace_exact(original, original_kernel, CHEZ_HELPERS[name] + adapted_kernel)
    if name == 'quicksort':
        predicate = quicksort_original_predicate(upstream)
        adapted = replace_exact(adapted, predicate, '(lambda (v) (sorted-i64-vector? v))')
        adapted = replace_exact(adapted, '(vector-map values v)', '(map-vector-elements values v)')
    restored = replace_exact(adapted, CHEZ_HELPERS[name] + adapted_kernel, original_kernel)
    if name == 'quicksort':
        restored = replace_exact(restored, '(lambda (v) (sorted-i64-vector? v))', predicate)
        restored = replace_exact(restored, '(map-vector-elements values v)', '(vector-map values v)')
    if restored != original:
        raise ValueError('adapted Chez source changed outside the kernel and compatibility helpers')
    if name in ('primes', 'fft') and adapted != original:
        raise ValueError('this kernel must have identical complete original/adapted Chez source')
    return adapted, original_kernel, adapted_kernel


def quicksort_source_proof(original, adapted):
    sort = lambda source: source[:source.index(";;; Hansen's original code")]
    def rng(source):
        start = source.index('            (let ((p1 ')
        return source[start:source.index('\n  (', start)]
    if sort(original) != sort(adapted) or rng(original) != rng(adapted):
        raise ValueError('quicksort partition/sort text and RNG arithmetic/seed transitions must be unchanged')
    return dict(sorting_kernel_exact_match=True, rng_arithmetic_and_seed_transitions_exact_match=True,
                sorting_kernel_sha256=hashlib.sha256(sort(original).encode()).hexdigest(),
                rng_arithmetic_and_seed_transitions_sha256=hashlib.sha256(rng(original).encode()).hexdigest())


def build_chez(directory, runner, environment, record_name):
    build, run = runner.chez_commands(directory, str(directory / 'program.scm'))
    record = execute(build, directory, environment)
    save(directory / record_name, record)
    require_success(record)
    return run


def prepare_adapted_chez(name, directory, runner, environment):
    adapted, original_kernel, adapted_kernel = matched_chez_source(name, directory)
    control = directory / 'same-source-chez'
    control.mkdir()
    (control / 'program.scm').write_text(adapted)
    (directory / 'original-kernel.scm').write_text(original_kernel)
    (directory / 'adapted-kernel.scm').write_text(adapted_kernel)
    patch = difflib.unified_diff(original_kernel.splitlines(True), adapted_kernel.splitlines(True),
                                 fromfile='original-kernel', tofile='adapted-kernel')
    (directory / 'kernel-adaptation.patch').write_text(''.join(patch))
    if name == 'quicksort':
        patch = difflib.unified_diff((directory / 'program.scm').read_text().splitlines(True), adapted.splitlines(True),
                                     fromfile='original-program', tofile='adapted-program')
        (directory / 'complete-source-adaptation.patch').write_text(''.join(patch))
        save(directory / 'quicksort-source-proof.json', quicksort_source_proof(original_kernel, adapted_kernel))
    if name == 'fft':
        shutil.copyfile(directory / 'program.so', control / 'program.so')
        shutil.copyfile(directory / 'compile.scm', control / 'compile.scm')
        save(control / 'build.json', dict(reused_original_artifact=True, original_sha256=digest(directory / 'program.so')))
    else:
        build_chez(control, runner, environment, 'build.json')
    save(directory / 'source-proof.json', dict(kernel_exact_match=True,
         complete_source_only_kernel_edits_and_helpers=name != 'quicksort',
         result_predicate_early_exit_adaptation=name == 'quicksort',
         per_element_map_compatibility_adapter=name == 'quicksort',
         complete_original_adapted_source_equal=adapted == (directory / 'program.scm').read_text(),
         original_kernel_sha256=hashlib.sha256(original_kernel.encode()).hexdigest(),
         adapted_kernel_sha256=hashlib.sha256(adapted_kernel.encode()).hexdigest(),
         helper_sha256=hashlib.sha256(CHEZ_HELPERS[name].encode()).hexdigest()))


def chez_validation_inputs(directory, runner, spec):
    original = (directory / 'input.txt').read_bytes()
    probes = [(str(count), runner.input_data(original, count).decode()) for count in (1, 2)]
    if spec['name'] == 'primes':
        probes.append(('empty', '1\n1\n()\n'))
    if spec['name'] == 'pnpoly':
        vector = '#(' + ' '.join(['0.0'] * 20) + ')\n'
        probes.append(('zero-vectors', '1\n' + vector + vector + '0\n'))
    if spec['name'] == 'quicksort':
        probes.append(('canonical-count', original.decode()))
    return probes


def validate_chez(directory, runner, tools, environment, spec):
    checks = []
    for system in ('original', 'same-source-chez'):
        target = directory if system == 'original' else directory / system
        for label, data in chez_validation_inputs(directory, runner, spec):
            record = execute([tools['CHEZ'], '--program', target / 'program.so'], target, environment, stdin=data)
            checks.append(dict(record, system=system, label=label, stdin=data))
            save(directory / 'chez-validation.json', checks)
            require_success(record)
            if record['stderr'] or runner.parse_result(record['stdout'], 'chez', spec['name'])['status'] != 'ok':
                raise ValueError('Chez behavior validation failed')


CHEZ_FFT_PROBE = '''(let* ((data (read)) (expected (read)) (tolerance (read)))
  (four1 data)
  (display
   (and (= (vector-length data) (vector-length expected))
        (let loop ((i 0))
          (or (= i (vector-length data))
              (and (<= (abs (- (vector-ref data i) (vector-ref expected i)))
                       (* tolerance (max 1.0 (abs (vector-ref expected i)))))
                   (loop (+ i 1)))))))
  (newline))
'''

CHEZ_QUICKSORT_PROBE = ''';; ---- Supplemental complete-output probes ----

(define (validate-sort data expected)
  (let* ((original (vector->list data))
         (result (quick-1 (vector-map values data) (lambda (x y) (< x y)))))
    (and (equal? result expected)
         (equal? (vector->list data) original)
         (or (= (vector-length data) 0) (not (eq? result data))))))
(define (validate-rng size expected limit)
  (let ((v (make-vector size)))
    (do ((i 0 (+ i 1))) ((= i (vector-length v)))
      (vector-set! v i (random limit)))
    (equal? v expected)))
(define (validate-seed expected limit)
  (seed-set! 1.0 0.0 0.0 1.0 0.0 0.0)
  (and (equal? (seed-ref) '(1.0 0.0 0.0 1.0 0.0 0.0))
       (= (random limit) (vector-ref expected 0))))
(let* ((mode (read)) (limit (read)) (data (read)) (expected (read)))
  (display
   (case mode
     ((sort) (validate-sort data expected))
     ((rng) (validate-rng data expected limit))
     ((seed) (validate-seed expected limit))
     ((sorted) (= (if (sorted-i64-vector? data) 1 0) expected))))
  (newline))
'''


def quicksort_chez_probe_source(directory, system):
    kernel_file = 'original-kernel.scm' if system == 'original' else 'adapted-kernel.scm'
    helpers = '' if system == 'original' else CHEZ_HELPERS['quicksort']
    wrapper = CHEZ_QUICKSORT_PROBE
    if system == 'original':
        predicate = quicksort_original_predicate((directory / 'upstream.scm').read_text())
        helpers += '(define sorted-i64-vector? ' + predicate + ')\n'
    else:
        wrapper = replace_exact(wrapper, '(seed-set! ', '((ref-get seed-set!) ')
        wrapper = replace_exact(wrapper, '(seed-ref)', '((ref-get seed-ref))')
        wrapper = replace_exact(wrapper, '(vector-map values data)', '(map-vector-elements values data)')
    return '(import (except (chezscheme) partition random))\n' + helpers + (directory / kernel_file).read_text() + wrapper


def quicksort_chez_output_probes(spec):
    probes = [(label, probe, True) for label, probe in quicksort_validation_specifications(spec)
              if 'export' in probe and label != 'sorted-empty']
    for prefix, base in [('sort', quicksort_probe_specification(spec, QUICKSORT_VALUES)),
                         ('rng', quicksort_rng_specification(spec))]:
        changed = list(base['expected'])
        changed[len(changed) // 2] += 1
        probes += [(prefix + '-' + label, dict(base, expected=expected), False) for label, expected in
                   [('wrong-value', changed), ('short', base['expected'][:-1]), ('long', base['expected'] + [0])]]
    return probes


def quicksort_chez_probe_input(probe):
    modes = {'quicksort-probe': 'sort', 'quicksort-rng-probe': 'rng',
             'quicksort-seed-probe': 'seed', 'quicksort-sorted-probe': 'sorted'}
    vector = lambda values: '#(' + ' '.join(map(str, values)) + ')'
    data = vector(probe['inputs'][2]) if len(probe['inputs']) == 3 else str(probe['inputs'][0])
    expected = vector(probe['expected']) if isinstance(probe['expected'], list) else str(probe['expected'])
    return '\n'.join([modes[probe['export']], str(probe['inputs'][1]), data, expected]) + '\n'


def validate_quicksort_chez_outputs(directory, runner, tools, environment, spec):
    for system in ('original', 'same-source-chez'):
        target = directory / ('chez-output-probe-' + system)
        target.mkdir()
        (target / 'program.scm').write_text(quicksort_chez_probe_source(directory, system))
        command = build_chez(target, runner, environment, 'build.json')
        checks = []
        for label, probe, expected_flag in quicksort_chez_output_probes(spec):
            data = quicksort_chez_probe_input(probe)
            record = execute(command, target, environment, stdin=data)
            checks.append(dict(record, label=label, stdin=data, expected_flag=expected_flag))
            save(target / 'validation.json', checks)
            require_success(record)
            if record['stderr'] or record['stdout'].strip() != ('#t' if expected_flag else '#f'):
                raise ValueError('Chez quicksort must check complete outputs and reject changed expectations')


def validate_fft_chez_dft(directory, runner, tools, environment, spec):
    target = directory / 'chez-dft-probe'
    target.mkdir()
    kernel = (directory / 'original-kernel.scm').read_text()
    (target / 'program.scm').write_text('(import (chezscheme))\n' + kernel + CHEZ_FFT_PROBE)
    command = build_chez(target, runner, environment, 'build.json')
    nonzero = fft_probe_specification(spec, FFT_NONZERO)
    changed = list(nonzero['expected'])
    changed[len(changed) // 2] += 1
    probes = [('nonzero', nonzero, True), ('impulse', fft_probe_specification(spec, [1.0, 0.0] + [0.0] * 14), True)]
    probes += [(label, dict(nonzero, expected=expected), False) for label, expected in
               [('wrong-value', changed), ('short', nonzero['expected'][:-1]), ('long', nonzero['expected'] + [0.0])]]
    checks = []
    for label, probe, expected_flag in probes:
        vectors = [probe['inputs'][2], probe['expected']]
        data = '\n'.join('#(' + ' '.join(repr(float(value)) for value in values) + ')' for values in vectors)
        data += '\n' + repr(probe['tolerance']) + '\n'
        record = execute(command, target, environment, stdin=data)
        checks.append(dict(record, label=label, stdin=data, expected_flag=expected_flag))
        save(target / 'validation.json', checks)
        require_success(record)
        if record['stderr'] or record['stdout'].strip() != ('#t' if expected_flag else '#f'):
            raise ValueError('Chez must check every nonzero DFT component and reject changed expectations')


def prepare_case(name, files, output, runner, tools, environment):
    directory = output / name
    directory.mkdir()
    spec = case_specification(name, files[f'inputs/{name}.input'])
    write_case_sources(name, files, directory, spec, runner)
    if name == 'fft':
        build_fft_provider(directory, tools, environment)
    build_strict(directory, tools, environment)
    run = build_chez(directory, runner, environment, 'chez-build.json')
    validate_strict(directory, tools, environment)
    if name in MATCHED_PORTS:
        prepare_adapted_chez(name, directory, runner, environment)
        validate_chez(directory, runner, tools, environment, spec)
    if name == 'fft':
        validate_fft_chez_dft(directory, runner, tools, environment, spec)
    if name == 'quicksort':
        validate_quicksort_chez_outputs(directory, runner, tools, environment, spec)
    return dict(name=name, status='ready', spec=spec, chez_command=run,
                systems=['strict', 'chez', 'chez-adapted'] if name in NEXT_PORTS + ('quicksort',) else ['strict', 'chez-adapted'] if name == 'fft' else ['strict', 'chez'],
                hashes={str(p.relative_to(directory)): digest(p) for p in directory.rglob('*') if p.is_file()})


def write_case_sources(name, files, directory, spec, runner):
    save(directory / 'spec.json', spec)
    (directory / 'input.txt').write_bytes(files[f'inputs/{name}.input'])
    (directory / 'upstream.scm').write_bytes(files[f'src/{name}.scm'])
    (directory / 'strict.scm').write_text(strict_program(name, spec, files[f'src/{name}.scm'].decode()))
    (directory / 'program.scm').write_text(runner.source_text(files, name, 'chez'))


def prepare(options):
    runner, tools = upstream_runner(), tool_paths(options.benchmarks)
    environment = {**os.environ, **tools, 'BINARYEN_CORES': '1'}
    files = runner.suite_sources()
    options.output.mkdir(parents=True, exist_ok=False)
    shutil.copy2(HERE / 'host.mjs', options.output / 'host.mjs')
    shutil.copy2(__file__, options.output / 'measure.py')
    shutil.copy2(ROOT / 'benchmarks/r7rs.py', options.output / 'r7rs.py')
    sources = [*ROOT.glob('src/**/*.sld'), ROOT / 'scripts/build-strict', ROOT / 'tests/build-strict-program.scm']
    for source in sources:
        target = options.output / 'compiler-source' / source.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    report = dict(date=datetime.now(timezone.utc).isoformat(), cases=[],
                  tools={key: dict(path=value, sha256=digest(value)) for key, value in tools.items()},
                  compiler_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                  compiler_files={str(p.relative_to(ROOT)): digest(p) for p in sources},
                  upstream_commit=runner.REVISION, host_sha256=digest(options.output / 'host.mjs'),
                  runner_sha256=digest(ROOT / 'benchmarks/r7rs.py'),
                  driver_sha256=digest(__file__))
    for name in options.benchmarks:
        try:
            case = prepare_case(name, files, options.output, runner, tools, environment)
        except (RuntimeError, ValueError) as error:
            case = dict(name=name, status='prepare-failed', diagnostic=str(error))
        report['cases'].append(case)
        save(options.output / 'prepared.json', report)
        print(case['status'], name, flush=True)
    if report['compiler_files'] != {str(p.relative_to(ROOT)): digest(p) for p in sources}:
        raise ValueError('compiler changed during preparation')


# ---- Clean fresh-process measurements ----


def checked_case(case, output):
    directory = output / case['name']
    for name, expected in case['hashes'].items():
        if digest(directory / name) != expected:
            raise ValueError(f'changed artifact: {directory / name}')
    return directory


def run_case(case, system, output, cpu, tools):
    directory = checked_case(case, output)
    if system == 'strict':
        command = [tools['NODE']['path'], output / 'host.mjs', directory / 'strict.wasm', directory / 'spec.json']
        data = None
    else:
        target = directory / 'same-source-chez' if system == 'chez-adapted' else directory
        command = [tools['CHEZ']['path'], '--program', target / 'program.so']
        data = (directory / 'input.txt').read_text()
    taskset = tools.get('TASKSET', {}).get('path', 'taskset')
    result = execute([taskset, '-c', str(cpu), *command], directory, os.environ, stdin=data)
    if result.get('returncode') != 0 or result.get('stderr'):
        return dict(result, valid=False)
    try:
        parsed = json.loads(result['stdout']) if system == 'strict' else upstream_runner().parse_result(result['stdout'], 'chez', case['name'])
        seconds = parsed['seconds']
        assert math.isfinite(seconds) and seconds > 0
        if system != 'strict' and parsed['status'] != 'ok':
            raise ValueError('Chez predicate rejected the result')
        return dict(result, valid=True, workload_seconds=seconds, checked_result=parsed)
    except (KeyError, ValueError, AssertionError) as error:
        return dict(result, valid=False, validation_error=str(error))


def checked_preparation(output):
    if os.environ.get('NODE_OPTIONS'):
        raise ValueError('NODE_OPTIONS must be unset')
    prepared = load(output / 'prepared.json')
    if prepared.get('driver_sha256', digest(__file__)) != digest(__file__):
        raise ValueError('driver changed')
    for record in prepared['tools'].values():
        if digest(record['path']) != record['sha256']:
            raise ValueError('tool changed')
    if digest(output / 'host.mjs') != prepared['host_sha256']:
        raise ValueError('host changed')
    if 'runner_sha256' in prepared:
        if any(digest(path) != prepared['runner_sha256'] for path in
               (output / 'r7rs.py', ROOT / 'benchmarks/r7rs.py')):
            raise ValueError('upstream runner changed')
    return prepared


def round_systems(case, round_number, index):
    systems = case.get('systems', ['strict', 'chez'])
    if len(systems) == 3:
        offset = (round_number + 1 + index) % 3
        return systems[offset:] + systems[:offset]
    return systems if (round_number + index) % 2 else list(reversed(systems))


def record_round(report, options, round_number):
    cases = [case for case in report['prepared']['cases'] if case['status'] == 'ready']
    if not cases:
        raise ValueError('no ready cases')
    offset = max(round_number, 0) % len(cases)
    for case in cases[offset:] + cases[:offset]:
        for system in round_systems(case, round_number, cases.index(case)):
            sample = run_case(case, system, options.output, options.cpu, report['prepared']['tools'])
            report['samples'].append(dict(sample, name=case['name'], system=system,
                                          round=round_number, retained=round_number >= 0))
            save(options.output / 'results.json', report)
            if not sample['valid']:
                raise RuntimeError(str(sample))
            print(round_number, case['name'], system, sample['workload_seconds'], flush=True)


def summarize(report):
    report['medians'], report['ranges'] = {}, {}
    for case in report['prepared']['cases']:
        if case['status'] != 'ready':
            continue
        medians, ranges = {}, {}
        for system in case.get('systems', ['strict', 'chez']):
            times = [s['workload_seconds'] for s in report['samples']
                     if s['name'] == case['name'] and s['system'] == system and s['retained']]
            medians[system], ranges[system] = statistics.median(times), [min(times), max(times)]
        report['medians'][case['name']], report['ranges'][case['name']] = medians, ranges


def measure(options):
    prepared = checked_preparation(options.output)
    if options.rounds != 3 and any(len(case.get('systems', [])) == 3 for case in prepared['cases']):
        raise ValueError('the three-system controls require exactly three retained rounds')
    report = dict(prepared=prepared, cpu=options.cpu, rounds=options.rounds, samples=[], complete=False)
    for round_number in range(-1, options.rounds):
        record_round(report, options, round_number)
    summarize(report)
    report['complete'] = True
    save(options.output / 'results.json', report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('prepare', 'measure'))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--benchmarks', nargs='+', choices=NAMES, default=list(NAMES))
    parser.add_argument('--rounds', type=int, default=3)
    parser.add_argument('--cpu', type=int, default=5)
    options = parser.parse_args()
    options.output = options.output.resolve()
    if options.rounds < 1:
        parser.error('rounds must be positive')
    if options.action == 'prepare':
        prepare(options)
    else:
        measure(options)


if __name__ == '__main__':
    main()
