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

from data_ports import (GC_TEXT, GC_SIZES, PARAFFINS_PRELUDE, PARAFFINS_PROBE,
                        GCBENCH_PRELUDE, paraffins_kernel, gcbench_kernel)
import data_ports
import enumeration_ports
import simplex_port
import deriv_port
import mbrotz_port
import string_port
import puzzle_port
import lattice_port
import destruc_port
import ray_port
import mazefun_port
import tail_port
import nucleic_port
import bv2string_port
import earley_port
import matrix_port
import reader_ports
import browse_port
import equal_port
import boyer_port
import conform_port
import maze_port
import parsing_port

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
NAMES = ('ack', 'tak', 'cpstak', 'fib', 'fibfp', 'sum', 'sumfp',
         'takl', 'ntakl', 'diviter', 'divrec', 'array1',
         'primes', 'nqueens', 'triangl', 'mbrot', 'pnpoly', 'fft', 'quicksort', 'paraffins', 'gcbench', 'graphs', 'mperm', 'simplex', 'deriv', 'mbrotZ', 'string', 'puzzle', 'lattice', 'destruc', 'ray', 'mazefun', 'tail', 'nucleic', 'bv2string', 'matrix')
NEXT_PORTS = ('primes', 'nqueens', 'triangl', 'mbrot', 'pnpoly')
DATA_PORTS = ('paraffins', 'gcbench')
ENUMERATION_PORTS = ('graphs', 'mperm')
NAMES += ('earley', 'browse', 'equal', 'conform', 'maze', 'parsing') + reader_ports.NAMES + boyer_port.NAMES
MATCHED_PORTS = NEXT_PORTS + ('fft', 'quicksort', 'simplex', 'deriv', 'mbrotZ', 'string', 'puzzle', 'lattice', 'destruc', 'ray', 'mazefun', 'tail', 'nucleic', 'bv2string', 'earley', 'matrix') + DATA_PORTS + ENUMERATION_PORTS
FLOATS = ('fibfp', 'sumfp')
FLOAT_RESULTS = FLOATS + ('fft',)
LISTS = ('takl', 'ntakl', 'diviter', 'divrec')
FULL_LISTS = ('primes', 'triangl')
KERNELS = dict(ack='ack', tak='tak', cpstak='cpstak', fib='fib', fibfp='fibfp',
               sum='run', sumfp='run', takl='mas', ntakl='mas',
               diviter='iterative-div2', divrec='recursive-div2', array1='go',
               primes='primes<=', nqueens='nqueens', triangl='test',
               mbrot='test', mbrotZ='test', string='my-try', pnpoly='run', fft='run', quicksort='quick-1', paraffins='nb', gcbench='gcbench', graphs='run', lattice='run')


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
    if name == 'maze':
        return maze_port.specification(data)
    if name in boyer_port.NAMES:
        return boyer_port.specification(name, data)
    if name == 'conform':
        return conform_port.specification(data)
    if name == 'equal':
        return equal_port.specification(data)
    if name == 'browse':
        return browse_port.specification(data)
    if name in reader_ports.NAMES:
        return reader_ports.specification(name, data)
    if name == 'earley':
        return earley_port.specification(data)
    if name == 'matrix':
        return matrix_port.specification(data)
    if name == 'nucleic':
        return nucleic_port.specification(data)
    if name == 'bv2string':
        return bv2string_port.specification(data)
    if name == 'tail':
        return tail_port.specification(data)
    if name == 'mazefun':
        return mazefun_port.specification(data)
    if name == 'destruc':
        return destruc_port.specification(data)
    if name == 'ray':
        return ray_port.specification(data)
    if name == 'puzzle':
        return puzzle_port.specification(data)
    if name == 'string':
        return string_port.specification(data)
    if name == 'deriv':
        return deriv_port.specification(data)
    if name == 'quicksort':
        # The fourth datum is a symbol read but never used by the upstream
        # predicate. Preserve it in input.txt instead of coercing it to a number.
        count, size, limit, unused = re.sub(r';[^\n]*', '', data.decode()).split()
        if unused != 'ignored':
            raise ValueError('unexpected canonical quicksort output datum')
        return dict(name=name, count=int(count), inputs=[int(size), int(limit)],
                    expected=1, unused_output_datum=unused,
                    barriers_per_iteration=0, setup_barriers=3)
    if name == 'gcbench':
        count, depth, unused = input_values(data.decode())
        return dict(name=name, count=count, inputs=[depth], expected=1, unused_output_datum=unused,
                    barriers_per_iteration=1, diagnostic_text=GC_TEXT, diagnostic_sizes=GC_SIZES)
    if name == 'mperm':
        count, n, k, ell, unused = input_values(data.decode())
        return dict(name=name, count=count, inputs=[n, k, ell], expected=1,
                    unused_output_datum=unused, barriers_per_iteration=0, setup_barriers=4)
    if name == 'simplex':
        count, value, expected = input_values(data.decode())
        return dict(name=name, count=count, inputs=[value], original_expected=expected,
                    expected=simplex_port.encoded_expected(expected),
                    result_kind='i64-list-values', barriers_per_iteration=1)
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
    if name == 'puzzle':
        return puzzle_port.kernel(source)
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
    elif name == 'paraffins':
        source = paraffins_kernel(source)
    elif name == 'gcbench':
        source = gcbench_kernel(source)
    elif name == 'graphs':
        source = enumeration_ports.graphs_kernel(source)
    elif name == 'mperm':
        source = enumeration_ports.mperm_kernel(source)
    elif name == 'simplex':
        source = simplex_port.kernel(source)
    elif name == 'deriv':
        source = deriv_port.kernel(source)
    elif name == 'mbrotZ':
        source = mbrotz_port.kernel(source)
    elif name == 'string':
        source = string_port.kernel(source)
    elif name == 'destruc':
        source = destruc_port.kernel(source)
    elif name == 'lattice':
        source = lattice_port.kernel(source)
    elif name == 'ray':
        source = ray_port.kernel(source)
    elif name == 'mazefun':
        source = mazefun_port.kernel(source)
    elif name == 'tail':
        source = tail_port.kernel(source)
    elif name == 'nucleic':
        source = nucleic_port.kernel(source)
    elif name == 'bv2string':
        source = bv2string_port.kernel(source)
    elif name == 'earley':
        source = earley_port.kernel(source)
    elif name == 'matrix':
        source = matrix_port.kernel(source)
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
    if name == 'earley':
        return earley_port.INPUTS
    if name == 'matrix':
        return matrix_port.INPUTS
    if name == 'nucleic':
        return nucleic_port.INPUTS
    if name == 'tail':
        return tail_port.INPUTS
    if name == 'mazefun':
        return mazefun_port.INPUTS
    if name == 'destruc':
        return destruc_port.INPUTS
    if name == 'ray':
        return ray_port.INPUTS
    if name == 'deriv':
        return deriv_port.INPUT_BINDINGS
    if name == 'quicksort':
        return quicksort_input_bindings()
    if name == 'mperm':
        return enumeration_ports.MPERM_INPUTS
    bindings = [f'(define input{index} {input_expression(name, index)})'
                for index in range(len(spec['inputs']))]
    if name in FULL_LISTS:
        bindings.append('(define expected (expected-list))')
    if name == 'simplex':
        bindings.append('(define expected (expected-index-vectors))')
    return '\n'.join(bindings)


def input_expression(name, index):
    if name == 'pnpoly':
        return f'(input-vector (ann {index} I32))'
    floating = name in FLOATS + ('simplex',) or (name == 'fft' and index == 1)
    value = f'(native-input-{"f64" if floating else "i64"} (ann {index} I32))'
    if name in ('takl', 'ntakl'):
        return f'(listn {value})'
    if name in ('diviter', 'divrec'):
        return f'(create-n {value})'
    return value


def kernel_call(name, spec):
    if name == 'graphs':
        return '(length (run (hide count input0)))'
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
    if name == 'earley':
        return earley_port.WORKER
    if name == 'matrix':
        return matrix_port.WORKER
    if name == 'nucleic':
        return nucleic_port.WORKER
    if name == 'bv2string':
        return bv2string_port.WORKER
    if name == 'tail':
        return tail_port.WORKER
    if name == 'mazefun':
        return mazefun_port.WORKER
    if name == 'destruc':
        return destruc_port.WORKER
    if name == 'ray':
        return ray_port.WORKER
    if name == 'lattice':
        return lattice_port.WORKER
    if name == 'puzzle':
        return puzzle_port.WORKER
    if name == 'string':
        return string_port.WORKER
    if name == 'deriv':
        return deriv_port.WORKER
    if name == 'mbrotZ':
        return mbrotz_port.worker(kernel_call(name, spec))
    if name == 'simplex':
        return simplex_port.worker()
    if name == 'mperm':
        return enumeration_ports.MPERM_WORKER
    if name == 'gcbench':
        return f'(begin (let loop ((i 0)) (unless (= i count) {kernel_call(name, spec)} (loop (+ i 1)))) 1)'
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
    if name == 'maze':
        return maze_port.program(upstream, sys.modules[__name__])
    if name == 'equal':
        return equal_port.program(upstream, sys.modules[__name__])
    if name == 'browse':
        return browse_port.program(upstream, sys.modules[__name__])
    if name in reader_ports.NAMES:
        return reader_ports.program(name, upstream, sys.modules[__name__])
    result = 'F64' if name in FLOAT_RESULTS else 'I64'
    worker = f'(: bench (-> I64 {result}))\n(define (bench count) {worker_body(name, spec)})\n(unit)\n'
    hide = '(if (barrier) x (unreachable))' if name in LISTS or name in ('pnpoly', 'fft', 'quicksort', 'deriv') else f'(hide-{"f64" if name in FLOATS + ("simplex",) else "i64"} x)'
    prelude = PRELUDE + (NEXT_PRELUDE if name in NEXT_PORTS else '')
    prelude += EXPECTED_PRELUDE if name in FULL_LISTS else VECTOR_PRELUDE if name == 'pnpoly' else ''
    if name == 'paraffins':
        prelude += PARAFFINS_PRELUDE
    if name == 'gcbench':
        prelude += GCBENCH_PRELUDE
    if name == 'graphs':
        prelude += enumeration_ports.GRAPHS_COMMON
    if name == 'mperm':
        prelude += enumeration_ports.MPERM_COMMON + enumeration_ports.MPERM_PLAN
    if name == 'simplex':
        prelude = simplex_port.control_prelude(prelude) + simplex_port.STRICT_TYPES + simplex_port.EXPECTED_PRELUDE + simplex_port.PREDICATE
    if name == 'deriv':
        prelude += deriv_port.strict_types() + deriv_port.input_prelude()
    if name == 'mbrotZ':
        prelude += mbrotz_port.strict_prelude()
    if name == 'puzzle':
        prelude = puzzle_port.control_prelude(prelude) + puzzle_port.STRICT_TYPES + puzzle_port.COMMON
    if name == 'destruc':
        prelude = puzzle_port.control_prelude(prelude) + destruc_port.STRICT_TYPES + destruc_port.COMMON
    if name == 'lattice':
        prelude += lattice_port.STRICT_TYPES + lattice_port.COMMON
    if name == 'ray':
        prelude = ray_port.control_prelude(prelude) + ray_port.STRICT_TYPES + ray_port.COMMON
    if name == 'mazefun':
        prelude += mazefun_port.STRICT_TYPES + mazefun_port.COMMON
    if name == 'tail':
        prelude = replace_exact(prelude, '(import (snail strict))',
                                '(import (snail strict) (rename (snail io) (eof-object? line-eof?)))')
        prelude += tail_port.COMMON
    if name == 'nucleic':
        prelude = replace_exact(prelude, '(import (snail strict))', '(import (snail strict) (snail math))')
        prelude += nucleic_port.STRICT_TYPES + nucleic_port.COMMON
    if name == 'bv2string':
        prelude = replace_exact(prelude, '(import (snail strict))',
                                '(import (snail strict) (snail bytes))')
        prelude += bv2string_port.COMMON + bv2string_port.DIAGNOSTICS
    if name == 'earley':
        prelude += earley_port.STRICT_TYPES + earley_port.COMMON
    if name == 'matrix':
        prelude += matrix_port.STRICT_TYPES + matrix_port.CONTROL + matrix_port.COMMON + matrix_port.DIAGNOSTICS
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
    if any(name in benchmarks for name in ('ray', 'tail', 'nucleic')):
        names.update(RUSTC='rustc', CARGO='cargo', WASM_MERGE='wasm-merge')
    if any(name in benchmarks for name in ('bv2string', 'earley', 'matrix', 'browse', 'equal', 'conform', 'maze', 'parsing') + reader_ports.NAMES + boyer_port.NAMES):
        names.update(RUSTC='rustc', CARGO='cargo', CLANG='clang', LLD='ld.lld', WASM_MERGE='wasm-merge')
    paths = {key: shutil.which(os.environ.get(key, value)) for key, value in names.items()}
    paths['PYTHON'] = sys.executable
    if not all(paths.values()):
        raise ValueError(f'missing tools: {paths}')
    return paths


def build_strict(directory, tools, environment):
    spec = load(directory / 'spec.json')
    command = [ROOT / 'scripts/build-strict', '--export', spec.get('export', 'bench'),
               directory / 'strict.scm', directory / 'strict.wasm']
    command[3:3] = [part for name in spec.get('additional_exports', []) for part in ('--export', name)]
    if load(directory / 'spec.json')['name'] == 'fft':
        command[3:3] = ['--export', 'fft-probe']
    if load(directory / 'spec.json')['name'] == 'quicksort':
        command[3:3] = [part for name in ('quicksort-probe', 'quicksort-rng-probe',
                                        'quicksort-seed-probe', 'quicksort-sorted-probe')
                       for part in ('--export', name)]
    if spec['name'] == 'nucleic':
        record = nucleic_port.build_record(command, ROOT, environment)
    else:
        run = bv2string_port.execute if spec['name'].startswith('bv2string') else execute
        record = run(command, ROOT, environment)
    save(directory / 'strict-build.json', record)
    require_success(record)
    if spec['name'] == 'ray':
        ray_port.link_runtime(directory, tools, environment, sys.modules[__name__])
    if spec['name'] == 'tail':
        tail_port.link_runtime(directory, tools, environment, sys.modules[__name__])
    if spec['name'] == 'nucleic':
        nucleic_port.link_runtime(directory, tools, environment, sys.modules[__name__])
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


def freeze_fft_toolchain(directory, launcher, environment, prefix='math-provider'):
    queries = dict(version=['--version', '--verbose'], sysroot=['--print', 'sysroot'],
                   target_libdir=['--print', 'target-libdir', '--target=wasm32-wasip1'])
    report = {}
    for name, arguments in queries.items():
        report[name] = execute([launcher, *arguments], ROOT, environment)
        save(directory / (prefix + '-toolchain.json'), report)
        require_success(report[name])
    sysroot = Path(report['sysroot']['stdout'].strip())
    library = Path(report['target_libdir']['stdout'].strip())
    host = next(line.removeprefix('host: ') for line in report['version']['stdout'].splitlines() if line.startswith('host: '))
    compiler, linker = sysroot / 'bin/rustc', sysroot / 'lib/rustlib' / host / 'bin/rust-lld'
    files = [compiler, linker, *sysroot.glob('lib/librustc_driver*'), *(p for p in library.rglob('*') if p.is_file())]
    report['toolchain_files'] = {str(path): digest(path) for path in files}
    report['actual_compiler'] = str(compiler)
    save(directory / (prefix + '-toolchain.json'), report)
    return compiler


def validate_strict(directory, tools, environment):
    spec = load(directory / 'spec.json')
    checks = []
    for label, probe in validation_specifications(spec):
        save(directory / f'validation-spec-{label}.json', probe)
        for suffix in ('.raw.wasm', ''):
            if spec['name'] == 'ray':
                ray_port.reset_output(directory, probe)
            if spec['name'] == 'tail':
                tail_port.seed_files(directory, probe)
            host = spec['name'] + '-host.mjs' if spec['name'] in ('ray', 'tail', 'nucleic') else 'host.mjs'
            warning = ['--disable-warning=ExperimentalWarning'] if spec['name'] in ('ray', 'tail', 'nucleic') else []
            command = [tools['NODE'], *warning, directory.parent / host, directory / ('strict.wasm' + suffix),
                       directory / f'validation-spec-{label}.json', '--validate']
            record = execute(command, directory, environment)
            checks.append(dict(record, specification=probe, module_suffix=suffix))
            save(directory / 'validation.json', checks)
            require_success(record)
            if spec['name'] == 'ray':
                ray_port.check_image(directory, probe)
            if spec['name'] == 'tail':
                checks[-1]['file'] = tail_port.check_output(directory, probe)
                save(directory / 'validation.json', checks)
            if spec['name'] == 'gcbench':
                data_ports.check_gc_diagnostics(record['stdout'], probe['inputs'][0], probe['count'])
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
    if spec['name'] in ENUMERATION_PORTS:
        return [('canonical-count', spec)]
    if spec['name'] in ('simplex', 'deriv', 'mbrotZ', 'string', 'puzzle', 'lattice', 'destruc', 'ray', 'mazefun', 'tail', 'nucleic', 'bv2string'):
        return [(str(count), dict(spec, count=count)) for count in (1, 2, spec['count'])]
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
        counts = (1, 2, spec['count']) if spec['name'] == 'paraffins' else (1, 2)
        return [(str(count), dict(spec, count=count)) for count in dict.fromkeys(counts)]
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
CHEZ_HELPERS = dict(matrix=matrix_port.chez_helpers(),
                   bv2string=bv2string_port.CHEZ_BOUNDARY + bv2string_port.COMMON,
                   earley=earley_port.CHEZ_TYPES + earley_port.COMMON,
                   destruc=destruc_port.CHEZ_TYPES + destruc_port.COMMON + destruc_port.CHEZ_BOUNDARY,
                   nucleic=nucleic_port.CHEZ_TYPES + nucleic_port.COMMON,
                   tail=tail_port.chez_helpers(),
                   mazefun=mazefun_port.CHEZ_TYPES + mazefun_port.COMMON + mazefun_port.CHEZ_BOUNDARY,
                   puzzle=CHEZ_REF_HELPERS + puzzle_port.CHEZ_RESULTS + puzzle_port.COMMON,
                   ray=ray_port.CHEZ_TYPES + ray_port.CHEZ_FORMAT + ray_port.COMMON,
                   lattice=lattice_port.CHEZ_TYPES + lattice_port.COMMON,
                   string=CHEZ_REF_HELPERS, paraffins=data_ports.PARAFFINS_CHEZ,
                   simplex=CHEZ_REF_HELPERS + simplex_port.CHEZ_RESULTS,
                   deriv=deriv_port.chez_helpers(),
                   mbrotZ=mbrotz_port.chez_helpers(),
                   graphs='(define (unit) (if #f #f))\n(define (unreachable) (error \'graphs "unreachable comparison"))\n' + enumeration_ports.GRAPHS_COMMON,
                   mperm=CHEZ_REF_HELPERS + enumeration_ports.MPERM_COMMON + enumeration_ports.MPERM_CHEZ_HARNESS + '(define (unreachable) (error \'mperm "invalid arguments"))\n',
                   gcbench=CHEZ_REF_HELPERS + data_ports.gc_chez_helpers(), primes='', nqueens='', fft='', pnpoly=CHEZ_REF_HELPERS,
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
    if name == 'puzzle':
        return puzzle_port.matched_source(upstream, (directory / 'program.scm').read_text(),
                                          (directory / 'strict.scm').read_text(), CHEZ_HELPERS[name])
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
    if name == 'simplex':
        adapted = replace_exact(adapted, '(equal? result output)', '(equal? (simplex-original-value result) output)')
    if name == 'destruc':
        adapted = destruc_port.adapt_harness(adapted)
    if name == 'mazefun':
        adapted = mazefun_port.adapt_harness(adapted)
    if name == 'deriv':
        adapted = deriv_port.adapt_chez_harness(adapted)
    if name == 'string':
        adapted = string_port.adapt_chez_harness(adapted)
    if name == 'ray':
        adapted = ray_port.adapt_chez_harness(adapted)
    if name == 'tail':
        adapted = tail_port.adapt_chez_harness(adapted)
    if name == 'bv2string':
        adapted = bv2string_port.adapt_chez_harness(adapted)
    if name == 'matrix':
        adapted = matrix_port.adapt_chez_harness(adapted)
    restored = replace_exact(adapted, CHEZ_HELPERS[name] + adapted_kernel, original_kernel)
    if name == 'quicksort':
        restored = replace_exact(restored, '(lambda (v) (sorted-i64-vector? v))', predicate)
        restored = replace_exact(restored, '(map-vector-elements values v)', '(vector-map values v)')
    if name == 'simplex':
        restored = replace_exact(restored, '(equal? (simplex-original-value result) output)', '(equal? result output)')
    if name == 'destruc':
        restored = destruc_port.adapt_harness(restored, reverse=True)
    if name == 'mazefun':
        restored = mazefun_port.adapt_harness(restored, reverse=True)
    if name == 'deriv':
        restored = deriv_port.adapt_chez_harness(restored, reverse=True)
    if name == 'string':
        restored = string_port.adapt_chez_harness(restored, reverse=True)
    if name == 'ray':
        restored = ray_port.adapt_chez_harness(restored, reverse=True)
    if name == 'tail':
        restored = tail_port.adapt_chez_harness(restored, reverse=True)
    if name == 'bv2string':
        restored = bv2string_port.adapt_chez_harness(restored, reverse=True)
    if name == 'matrix':
        restored = matrix_port.adapt_chez_harness(restored, reverse=True)
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
    if name in ('quicksort', 'simplex', 'deriv', 'mbrotZ', 'string', 'puzzle', 'lattice', 'destruc', 'ray', 'mazefun', 'tail', 'nucleic', 'bv2string'):
        patch = difflib.unified_diff((directory / 'program.scm').read_text().splitlines(True), adapted.splitlines(True),
                                     fromfile='original-program', tofile='adapted-program')
        (directory / 'complete-source-adaptation.patch').write_text(''.join(patch))
    if name == 'quicksort':
        save(directory / 'quicksort-source-proof.json', quicksort_source_proof(original_kernel, adapted_kernel))
    if name == 'fft':
        shutil.copyfile(directory / 'program.so', control / 'program.so')
        shutil.copyfile(directory / 'compile.scm', control / 'compile.scm')
        save(control / 'build.json', dict(reused_original_artifact=True, original_sha256=digest(directory / 'program.so')))
    else:
        build_chez(control, runner, environment, 'build.json')
    if name == 'tail':
        spec = load(directory / 'spec.json')
        tail_port.seed_files(control, spec, (directory / spec['pathnames'][0]).read_bytes())
    save(directory / 'source-proof.json', dict(kernel_exact_match=True,
         complete_source_only_kernel_edits_and_helpers=name not in ('quicksort', 'simplex', 'deriv', 'string', 'puzzle', 'destruc', 'ray', 'mazefun', 'tail', 'bv2string'),
         result_representation_predicate_adapter=name in ('simplex', 'deriv', 'string', 'puzzle', 'destruc', 'ray', 'mazefun'),
         expected_datum_setup_adapter=name in ('destruc', 'mazefun'),
         typed_file_io_compatibility_adapter=name == 'tail',
         failure_list_ref_adapter=name == 'bv2string',
         explicit_splice_operand_order=name == 'destruc',
         input_datum_and_initial_false_adapters=name == 'deriv',
         scalar_initial_false_adapter=name == 'string',
         local_escape_boolean_adapter=name == 'puzzle',
         trailing_setup_region_preserved=name == 'puzzle',
         kernel_source_regions=2 if name == 'puzzle' else 1,
         result_predicate_early_exit_adaptation=name == 'quicksort',
         per_element_map_compatibility_adapter=name == 'quicksort',
         complete_original_adapted_source_equal=adapted == (directory / 'program.scm').read_text(),
         original_kernel_sha256=hashlib.sha256(original_kernel.encode()).hexdigest(),
         adapted_kernel_sha256=hashlib.sha256(adapted_kernel.encode()).hexdigest(),
         helper_sha256=hashlib.sha256(CHEZ_HELPERS[name].encode()).hexdigest()))


def chez_validation_inputs(directory, runner, spec):
    original = (directory / 'input.txt').read_bytes()
    if spec['name'] in ENUMERATION_PORTS:
        return [('canonical-count', original.decode())]
    probes = [(str(count), runner.input_data(original, count).decode()) for count in (1, 2)]
    if spec['name'] == 'primes':
        probes.append(('empty', '1\n1\n()\n'))
    if spec['name'] == 'pnpoly':
        vector = '#(' + ' '.join(['0.0'] * 20) + ')\n'
        probes.append(('zero-vectors', '1\n' + vector + vector + '0\n'))
    if spec['name'] in ('quicksort', 'paraffins', 'simplex', 'deriv', 'mbrotZ', 'string', 'puzzle', 'lattice', 'destruc', 'ray', 'mazefun', 'tail', 'nucleic', 'bv2string'):
        probes.append(('canonical-count', original.decode()))
    return probes


def validate_chez(directory, runner, tools, environment, spec):
    checks = []
    for system in ('original', 'same-source-chez'):
        target = directory if system == 'original' else directory / system
        for label, data in chez_validation_inputs(directory, runner, spec):
            if spec['name'] == 'ray':
                ray_port.reset_output(target, spec)
            if spec['name'] == 'tail':
                tail_port.seed_files(target, spec)
            record = execute([tools['CHEZ'], '--program', target / 'program.so'], target, environment, stdin=data)
            checks.append(dict(record, system=system, label=label, stdin=data))
            save(directory / 'chez-validation.json', checks)
            require_success(record)
            if record['stderr'] or runner.parse_result(record['stdout'], 'chez', spec['name'])['status'] != 'ok':
                raise ValueError('Chez behavior validation failed')
            if spec['name'] == 'ray':
                ray_port.check_image(target, spec)
            if spec['name'] == 'tail':
                checks[-1]['file'] = tail_port.check_output(target, spec)
                save(directory / 'chez-validation.json', checks)
            if spec['name'] == 'gcbench':
                data_ports.check_gc_diagnostics(record['stdout'], spec['inputs'][0], input_values(data)[0])


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


# ---- Complete structural checks for nominal data ports ----


def validate_data_wasm_probe(directory, tools, environment, spec, label, accepted=True):
    path = directory / f'validation-spec-{label}.json'
    save(path, spec)
    checks = []
    for suffix in ('.raw.wasm', ''):
        record = execute([tools['NODE'], directory.parent / 'host.mjs',
                          directory / ('strict.wasm' + suffix), path, '--validate'], directory, environment)
        checks.append(dict(record, label=label, accepted=accepted, module_suffix=suffix))
        save(directory / f'validation-{label}.json', checks)
        rejected = record.get('returncode') != 0 and "actual: '0'" in record.get('stderr', '')
        if (accepted and (record.get('returncode') != 0 or record.get('stderr'))) or (not accepted and not rejected):
            raise ValueError(f'data probe did not produce the expected flag: {checks[-1]}')


def validate_paraffins_outputs(directory, runner, tools, environment, spec):
    oracles = {}
    for system in ('original', 'same-source-chez'):
        target = directory / ('chez-output-probe-' + system)
        target.mkdir()
        kernel = (directory / ('original-kernel.scm' if system == 'original' else 'adapted-kernel.scm')).read_text()
        (target / 'program.scm').write_text(data_ports.paraffins_chez_probe(kernel, system != 'original'))
        command = build_chez(target, runner, environment, 'build.json')
        checks = []
        for n, count in ((1, 1), (2, 1), (4, 2), (6, 5), (8, 18), (10, 75)):
            record = execute(command, target, environment, stdin=str(n) + '\n#f\n')
            checks.append(dict(record, carbons=n, expected_count=count))
            save(target / 'validation.json', checks)
            require_success(record)
            values = input_values(record['stdout'])[0]
            data_ports.check_paraffins_encoding(values, n, count)
            if system == 'original':
                oracles[n] = values
            elif record['stderr'] or values != oracles[n]:
                raise ValueError('adapted paraffins must preserve every product and output order')
        validate_paraffins_chez_rejections(target, command, environment, oracles[10])
    save(directory / 'complete-output-oracles.json', oracles)
    target = build_paraffins_probe(directory, tools, environment, spec)
    for n, values in oracles.items():
        probe = dict(spec, count=1, inputs=[n], expected=values, result_kind='i64-list-values',
                     export='paraffins-probe', barriers_per_iteration=0)
        validate_data_wasm_probe(target, tools, environment, probe, f'products-{n}')
    validate_sequence_failures(target, tools, environment, probe, prefix='products-')


def validate_paraffins_chez_rejections(target, command, environment, expected):
    changed = list(expected)
    changed[len(changed) // 2] += 1
    probes = [('unchanged', expected, True), ('wrong-value', changed, False),
              ('short', expected[:-1], False), ('long', expected + [0], False)]
    checks = []
    for label, values, accepted in probes:
        data = '10\n(' + ' '.join(map(str, values)) + ')\n'
        record = execute(command, target, environment, stdin=data)
        checks.append(dict(record, label=label, accepted=accepted, stdin=data))
        save(target / 'expected-output-validation.json', checks)
        require_success(record)
        if record['stderr'] or record['stdout'].strip() != ('#t' if accepted else '#f'):
            raise ValueError('paraffins must reject every changed complete output')


def build_paraffins_probe(directory, tools, environment, spec):
    target = directory / 'strict-structure-probe'
    target.mkdir()
    shutil.copyfile(directory.parent / 'host.mjs', directory / 'host.mjs')
    save(target / 'spec.json', dict(spec, export='paraffins-probe'))
    source = PRELUDE + PARAFFINS_PRELUDE + EXPECTED_PRELUDE
    source += (directory / 'adapted-kernel.scm').read_text() + input_bindings('paraffins', spec)
    (target / 'strict.scm').write_text(source + PARAFFINS_PROBE + '(unit)\n')
    build_strict(target, tools, environment)
    return target


def gc_probe_source(directory, spec):
    source = PRELUDE + GCBENCH_PRELUDE + VECTOR_PRELUDE + EXPECTED_PRELUDE
    source += "(define events (ref (ann '() (List I64))))\n"
    source += data_ports.GC_EVENT_HELPERS + '(define input0 (native-input-i64 (ann 0 I32)))\n'
    source += '(define expected-array (input-vector (ann 1 I32)))\n'
    source += data_ports.gc_probe_kernel((directory / 'adapted-kernel.scm').read_text(), True)
    return source + data_ports.GC_PROBE_END


def gc_chez_probe_source(directory, adapted):
    kernel = (directory / ('adapted-kernel.scm' if adapted else 'original-kernel.scm')).read_text()
    original_kernel = (directory / 'original-kernel.scm').read_text()
    prefix = (directory / 'program.scm').read_text().split(original_kernel)[0]
    helpers = CHEZ_HELPERS['gcbench'] if adapted else CHEZ_REF_HELPERS
    return (prefix + helpers + "(define events (ref '()))\n" + data_ports.GC_EVENT_HELPERS
            + '(define depth (read)) (define expected-array (read))\n'
            + data_ports.gc_probe_kernel(kernel, adapted)
            + '(gcbench depth)\n(write (event-list)) (newline)\n')


def validate_gc_chez_probes(directory, runner, tools, environment, probes):
    for system in ('original', 'same-source-chez'):
        target = directory / ('chez-structure-probe-' + system)
        target.mkdir()
        (target / 'program.scm').write_text(gc_chez_probe_source(directory, system != 'original'))
        command = build_chez(target, runner, environment, 'build.json')
        checks = []
        for label, probe, accepted in probes:
            data = str(probe['inputs'][0]) + '\n#(' + ' '.join(map(repr, probe['inputs'][1])) + ')\n'
            record = execute(command, target, environment, stdin=data)
            checks.append(dict(record, label=label, expected_flag=accepted, stdin=data))
            save(target / 'validation.json', checks)
            require_success(record)
            actual = input_values(record['stdout'].splitlines()[-1])[0]
            if record['stderr'] or (actual == probe['expected']) != accepted:
                raise ValueError('gcbench structural probe must check every tree and array element')


def validate_gc_outputs(directory, runner, tools, environment, spec):
    target = directory / 'strict-structure-probe'
    target.mkdir()
    shutil.copyfile(directory.parent / 'host.mjs', directory / 'host.mjs')
    probes = [(f'depth-{n}', data_ports.gc_probe_specification(spec, n), True) for n in (6, 8)]
    probes += [(label, probe, False) for label, probe in data_ports.gc_negative_probes(probes[-1][1])]
    save(target / 'spec.json', probes[0][1])
    (target / 'strict.scm').write_text(gc_probe_source(directory, probes[0][1]))
    build_strict(target, tools, environment)
    for label, probe, accepted in probes:
        validate_data_wasm_probe(target, tools, environment, probe, label, accepted)
    validate_gc_chez_probes(directory, runner, tools, environment, probes)


# ---- Complete enumeration and queue snapshots in separate probes ----


def enumeration_probe_cases(name):
    cases = [(f'values-{n}', dict(action=0, count=1, inputs=[n, 2, 1]))
             for n in (range(1, 5) if name == 'graphs' else range(1, 7))]
    if name == 'mperm':
        cases += [(f'queue-{m}-{k}-{ell}', dict(action=1, count=m, inputs=[4, k, ell]))
                  for m, k, ell in ((1, 2, 1), (3, 4, 1), (2, 4, 2), (2, 2, 0), (2, 2, 2))]
        cases += [(f'predicate-{mode}', dict(action=2, count=mode, inputs=[4, 4, 1])) for mode in range(6)]
    return cases


def enumeration_probe_input(probe, expected=None):
    n, k, ell = probe['inputs']
    value = '#f' if expected is None else '(' + ' '.join(map(str, expected)) + ')'
    return '\n'.join(map(str, [probe['action'], probe['count'], n, k, ell])) + '\n' + value + '\n'


def build_enumeration_chez_probe(name, directory, adapted, runner, environment):
    target = directory / ('chez-output-probe-adapted' if adapted else 'chez-output-probe-original')
    target.mkdir()
    kernel = (directory / ('adapted-kernel.scm' if adapted else 'original-kernel.scm')).read_text()
    helpers = CHEZ_HELPERS[name] if adapted else '(define (unreachable) (error \'probe "invalid probe"))\n'
    if name == 'mperm':
        kernel = enumeration_ports.mperm_probe_kernel(kernel, adapted)
        helpers = helpers.replace(enumeration_ports.MPERM_CHEZ_HARNESS, '')
        helpers += '(define (unit) (if #f #f))\n'
        if not adapted:
            helpers += '(define (integer-max a b) (max a b))\n'
    (target / 'program.scm').write_text(enumeration_ports.chez_probe_source(name, kernel, helpers))
    return target, build_chez(target, runner, environment, 'build.json')


def enumeration_oracles(name, directory, command, target, environment):
    cases, checks = [], []
    for label, probe in enumeration_probe_cases(name):
        record = execute(command, target, environment, stdin=enumeration_probe_input(probe))
        checks.append(dict(record, label=label, specification=probe))
        save(target / 'oracle-runs.json', checks)
        require_success(record)
        values = input_values(record['stdout'])[0]
        proof = check_enumeration_oracle(name, probe, values)
        cases.append((label, dict(probe, expected=values, proof=proof)))
    save(directory / 'complete-output-oracles.json', dict(cases))
    return cases


def check_enumeration_oracle(name, probe, values):
    if name == 'graphs':
        return enumeration_ports.check_graphs(values, probe['inputs'][0])
    if probe['action'] == 0:
        return enumeration_ports.check_permutations(values, probe['inputs'][0])
    if probe['action'] == 2:
        if values != [int(probe['count'] == 0)]:
            raise ValueError('canonical predicate did not reject the malformed queue')
        return dict(canonical_predicate_accepts=values[0] == 1)
    if values != enumeration_ports.queue_values(probe['count'], *probe['inputs']):
        raise ValueError('incorrect complete queue lifetime schedule')
    return dict(all_snapshots_checked=True, snapshots=probe['count'] + 1)


def build_enumeration_wasm_probe(name, directory, spec, tools, environment):
    target = directory / 'strict-output-probe'
    target.mkdir()
    shutil.copyfile(directory.parent / 'host.mjs', directory / 'host.mjs')
    probe = dict(spec, export='enumeration-probe', additional_exports=['queue-probe', 'predicate-probe'] if name == 'mperm' else [])
    save(target / 'spec.json', probe)
    kernel = (directory / 'adapted-kernel.scm').read_text()
    common = enumeration_ports.GRAPHS_COMMON if name == 'graphs' else enumeration_ports.MPERM_COMMON + enumeration_ports.MPERM_PROBE_PLAN
    encoders = enumeration_ports.LIST_ENCODERS + (enumeration_ports.GRAPH_ENCODERS if name == 'graphs' else enumeration_ports.MPERM_QUEUE_ENCODER)
    if name == 'mperm':
        kernel = enumeration_ports.mperm_probe_kernel(kernel, True)
        encoders += enumeration_ports.MPERM_PREDICATE_PROBE
    inputs = '\n'.join(f'(define input{i} (native-input-i64 (ann {i} I32)))' for i in range(3))
    body = enumeration_ports.GRAPH_PROBE if name == 'graphs' else enumeration_ports.MPERM_PROBE
    (target / 'strict.scm').write_text(PRELUDE + EXPECTED_PRELUDE + common + kernel + encoders + inputs + body + '\n(unit)\n')
    build_strict(target, tools, environment)
    return target


def changed_enumeration_expectations(probe):
    values, probes = probe['expected'], []
    for label, index in (('first', 0), ('middle', len(values) // 2), ('last', len(values) - 1)):
        changed = list(values)
        changed[index] += 1
        probes.append((label, dict(probe, expected=changed), False))
    return probes + [('short', dict(probe, expected=values[:-1]), False),
                     ('long', dict(probe, expected=values + [0]), False)]


def validate_enumeration_cases(name, targets, strict, cases, spec, tools, environment):
    probes = [(label, probe, True) for label, probe in cases]
    negative_cases = [cases[3]] if name == 'graphs' else [cases[5], cases[7]]
    probes += [(label + '-' + failure, altered, accepted) for label, probe in negative_cases
               for failure, altered, accepted in changed_enumeration_expectations(probe)]
    for label, probe, accepted in probes:
        wasm = dict(spec, **{key: probe[key] for key in ('inputs', 'count', 'expected')},
                    result_kind='i64-list-values', setup_barriers=0, barriers_per_iteration=0,
                    export=('enumeration-probe', 'queue-probe', 'predicate-probe')[probe['action']])
        validate_data_wasm_probe(strict, tools, environment, wasm, label, accepted)
        for target, command in targets:
            record = execute(command, target, environment, stdin=enumeration_probe_input(probe, probe['expected']))
            save(target / f'validation-{label}.json', dict(record, accepted=accepted, specification=probe))
            require_success(record)
            if record['stderr'] or record['stdout'].strip() != ('#t' if accepted else '#f'):
                raise ValueError('enumeration predicate did not validate every expected value')


def validate_enumeration_outputs(name, directory, runner, tools, environment, spec):
    targets = [build_enumeration_chez_probe(name, directory, adapted, runner, environment) for adapted in (False, True)]
    cases = enumeration_oracles(name, directory, targets[0][1], targets[0][0], environment)
    strict = build_enumeration_wasm_probe(name, directory, spec, tools, environment)
    validate_enumeration_cases(name, targets, strict, cases, spec, tools, environment)


# ---- Complete simplex outputs, store order and result predicate ----


def build_simplex_chez_probe(directory, adapted, runner, environment):
    target = directory / ('chez-output-probe-adapted' if adapted else 'chez-output-probe-original')
    target.mkdir()
    kernel = (directory / ('adapted-kernel.scm' if adapted else 'original-kernel.scm')).read_text()
    (target / 'program.scm').write_text(simplex_port.chez_probe_source(kernel, adapted, CHEZ_REF_HELPERS))
    return target, build_chez(target, runner, environment, 'build.json')


def simplex_oracles(directory, original, environment):
    target, command = original
    cases, records = [], []
    for case in simplex_port.fixtures():
        data = simplex_port.probe_input(case)
        record = execute(command, target, environment, timeout=10, stdin=data)
        records.append(dict(record, label=case['label'], stdin=data))
        save(target / 'oracle-runs.json', records)
        require_success(record)
        values = input_values(record['stdout'])[0]
        cases.append(dict(case=case, expected=values, checked=simplex_port.check_oracle(case, values)))
        save(directory / 'complete-output-oracles.json', cases)
    return cases


def build_simplex_wasm_probe(directory, tools, environment, case):
    target = directory / 'strict-output-probe'
    target.mkdir()
    shutil.copy2(directory.parent / 'host.mjs', directory / 'host.mjs')
    spec = simplex_port.probe_specification(case['case'], case['expected'])
    save(target / 'spec.json', dict(spec, additional_exports=['simplex-predicate-probe']))
    source = simplex_port.control_prelude(PRELUDE) + simplex_port.STRICT_TYPES + simplex_port.PROBE_COMMON
    source += simplex_port.traced_kernel((directory / 'adapted-kernel.scm').read_text())
    source += simplex_port.STRICT_ENCODER + simplex_port.PROBE_RESULT + simplex_port.PROBE_INPUTS
    source += simplex_port.PREDICATE + '(: simplex-predicate-probe (-> I64 I64))\n' + simplex_port.PREDICATE_PROBE
    (target / 'strict.scm').write_text(source + '\n(unit)\n')
    build_strict(target, tools, environment)
    return target


def validate_simplex_case(targets, strict, case, values, label, accepted, tools, environment):
    validate_data_wasm_probe(strict, tools, environment, simplex_port.probe_specification(case, values), label, accepted)
    for target, command in targets:
        data = simplex_port.probe_input(case, values)
        record = execute(command, target, environment, timeout=10, stdin=data)
        save(target / f'validation-{label}.json', dict(record, stdin=data, accepted=accepted))
        require_success(record)
        if record['stderr'] or record['stdout'].strip() != ('#t' if accepted else '#f'):
            raise ValueError('simplex complete-output comparison returned the wrong flag')


def validate_simplex_predicates(targets, strict, tools, environment):
    for mode in range(11):
        spec = dict(name='simplex-predicate', count=mode, inputs=[], expected=int(mode == 0),
                    export='simplex-predicate-probe', barriers_per_iteration=0)
        validate_data_wasm_probe(strict, tools, environment, spec, 'predicate-' + str(mode))
        for target, command in targets:
            data = f'2\n#()\n{mode}\n0\n0\n#f\n'
            record = execute(command, target, environment, stdin=data)
            save(target / f'validation-predicate-{mode}.json', dict(record, stdin=data, expected=spec['expected']))
            require_success(record)
            if record['stderr'] or record['stdout'].strip() != str(spec['expected']):
                raise ValueError('simplex canonical predicate did not check the entire result')


def validate_simplex_invalid(targets, strict, tools, environment):
    for case in simplex_port.invalid_fixtures():
        path = strict / ('validation-spec-' + case['label'] + '.json')
        save(path, simplex_port.probe_specification(case, []))
        for suffix in ('.raw.wasm', ''):
            record = execute([tools['NODE'], strict.parent / 'host.mjs', strict / ('strict.wasm' + suffix), path, '--validate'], strict, environment)
            save(strict / (case['label'] + ('.raw' if suffix else '') + '-rejection.json'), record)
            if record.get('returncode') != 1 or 'RuntimeError: unreachable' not in record.get('stderr', ''):
                raise ValueError('invalid simplex input must reach the original complaint')
        for target, command in targets:
            data = simplex_port.probe_input(case)
            record = execute(command, target, environment, stdin=data)
            save(target / (case['label'] + '-rejection.json'), dict(record, stdin=data))
            if record.get('returncode') != 255 or "This shouldn't happen" not in record.get('stderr', ''):
                raise ValueError('invalid simplex input must raise the original Chez complaint')


def validate_simplex_outputs(directory, runner, tools, environment):
    targets = [build_simplex_chez_probe(directory, adapted, runner, environment) for adapted in (False, True)]
    cases = simplex_oracles(directory, targets[0], environment)
    strict = build_simplex_wasm_probe(directory, tools, environment, cases[0])
    for item in cases:
        validate_simplex_case(targets, strict, item['case'], item['expected'], item['case']['label'], True, tools, environment)
    last = cases[-1]
    for label, values in simplex_port.changed_expectations(last['expected']):
        validate_simplex_case(targets, strict, last['case'], values, label, False, tools, environment)
    validate_simplex_predicates(targets, strict, tools, environment)
    validate_simplex_invalid(targets, strict, tools, environment)


# ---- Complete derivative expressions and preserved pair sharing ----


def build_deriv_chez_probe(directory, adapted, runner, environment, sharing=False):
    kind = 'sharing' if sharing else 'output'
    target = directory / ('chez-' + kind + '-probe-' + ('adapted' if adapted else 'original'))
    target.mkdir()
    kernel = (directory / ('adapted-kernel.scm' if adapted else 'original-kernel.scm')).read_text()
    source = deriv_port.chez_sharing_source if sharing else deriv_port.chez_probe_source
    (target / 'program.scm').write_text(source(kernel, adapted))
    return target, build_chez(target, runner, environment, 'build.json')


def build_deriv_wasm_probe(directory, tools, environment):
    target = directory / 'strict-output-probe'
    target.mkdir()
    shutil.copy2(directory.parent / 'host.mjs', directory / 'host.mjs')
    save(target / 'spec.json', deriv_port.probe_specification('x', '1'))
    source = PRELUDE + deriv_port.strict_types() + deriv_port.input_prelude()
    source += (directory / 'adapted-kernel.scm').read_text() + deriv_port.INPUT_BINDINGS + deriv_port.PROBE
    (target / 'strict.scm').write_text(source)
    build_strict(target, tools, environment)
    return target


def validate_deriv_case(targets, strict, case, accepted, tools, environment):
    label, expression, expected = case
    validate_data_wasm_probe(strict, tools, environment,
                            deriv_port.probe_specification(expression, expected), label, accepted)
    for target, command in targets:
        data = deriv_port.probe_input(expression, expected)
        record = execute(command, target, environment, stdin=data)
        save(target / ('validation-' + label + '.json'), dict(record, stdin=data, accepted=accepted))
        require_success(record)
        if record['stderr'] or record['stdout'].strip() != ('#t' if accepted else '#f'):
            raise ValueError('deriv must compare every atom and ordered pair edge')


def validate_deriv_oracles(targets, environment):
    for target, command in targets:
        checks = []
        for label, expression, expected in deriv_port.fixtures():
            data = deriv_port.probe_input(expression, expected, extract=True)
            record = execute(command, target, environment, stdin=data)
            checks.append(dict(record, label=label, stdin=data, expected_expression=expected))
            save(target / 'complete-output-oracles.json', checks)
            require_success(record)
            if record['stderr'] or deriv_port.read_datums(record['stdout']) != deriv_port.read_datums(expected):
                raise ValueError('original/adapted derivative differs from the complete literal oracle')


def validate_deriv_invalid(targets, strict, tools, environment):
    for label, expression in deriv_port.invalid_fixtures():
        path = strict / ('validation-spec-' + label + '.json')
        save(path, deriv_port.probe_specification(expression, '0'))
        for suffix in ('.raw.wasm', ''):
            record = execute([tools['NODE'], strict.parent / 'host.mjs', strict / ('strict.wasm' + suffix), path, '--validate'], strict, environment)
            save(strict / (label + ('.raw' if suffix else '') + '-rejection.json'), record)
            if record.get('returncode') != 1 or 'RuntimeError: unreachable' not in record.get('stderr', ''):
                raise ValueError('malformed derivative input must trap')
        for target, command in targets:
            data = deriv_port.probe_input(expression, '0')
            record = execute(command, target, environment, stdin=data)
            save(target / (label + '-rejection.json'), dict(record, stdin=data))
            if record.get('returncode') != 255 or not record.get('stderr'):
                raise ValueError('malformed derivative input must fail in Chez')


def validate_deriv_sharing(directory, runner, environment):
    data = '(* (+ x a) (* b x))\n(/ (* a x) (+ x b))\n'
    expected = deriv_port.read_datums('(' + ' '.join(['#t'] * 9) + ')')
    for adapted in (False, True):
        target, command = build_deriv_chez_probe(directory, adapted, runner, environment, sharing=True)
        record = execute(command, target, environment, stdin=data)
        save(target / 'validation.json', dict(record, stdin=data, expected_checks=9))
        require_success(record)
        if record['stderr'] or deriv_port.read_datums(record['stdout']) != expected:
            raise ValueError('product/quotient must share original operands and allocate fresh result spines')


def validate_deriv_harness(directory, runner, tools, environment):
    for count, expression, expected, accepted in ((-1, '(a x)', '#f', True), (0, '(a x)', '#f', True),
                                                  (0, '(+ x)', '(+ 1)', False), (1, '(+ x)', '(+ 1)', True),
                                                  (3, '(+ x)', '(+ 1)', True)):
        label = f'harness-{count}-' + ('accept' if accepted else 'reject')
        spec = dict(deriv_port.probe_specification(expression, expected), count=count, export='bench',
                    barriers_per_iteration=int(count > 0), setup_barriers=0)
        validate_data_wasm_probe(directory, tools, environment, spec, label, accepted)
        for target in (directory, directory / 'same-source-chez'):
            data = f'{count}\n{expression}\n{expected}\n'
            record = execute([tools['CHEZ'], '--program', target / 'program.so'], target, environment, stdin=data)
            save(target / ('validation-' + label + '.json'), dict(record, stdin=data, accepted=accepted))
            require_success(record)
            if record['stderr'] or (runner.parse_result(record['stdout'], 'chez', 'deriv')['status'] == 'ok') != accepted:
                raise ValueError('deriv harness changed its false initial result or repetition boundary')


def validate_deriv_outputs(directory, runner, tools, environment):
    targets = [build_deriv_chez_probe(directory, adapted, runner, environment) for adapted in (False, True)]
    validate_deriv_oracles(targets, environment)
    strict = build_deriv_wasm_probe(directory, tools, environment)
    for case in deriv_port.fixtures():
        validate_deriv_case(targets, strict, case, True, tools, environment)
    for case in deriv_port.predicate_fixtures():
        validate_deriv_case(targets, strict, case, False, tools, environment)
    validate_deriv_invalid(targets, strict, tools, environment)
    validate_deriv_sharing(directory, runner, environment)
    validate_deriv_harness(directory, runner, tools, environment)


# ---- Complex components, complete grids and original store order ----


def build_mbrotz_chez_probe(directory, adapted, runner, environment):
    target = directory / ('chez-output-probe-adapted' if adapted else 'chez-output-probe-original')
    target.mkdir()
    kernel = (directory / ('adapted-kernel.scm' if adapted else 'original-kernel.scm')).read_text()
    (target / 'program.scm').write_text(mbrotz_port.chez_probe(kernel, adapted))
    return target, build_chez(target, runner, environment, 'build.json')


def build_mbrotz_wasm_probe(directory, tools, environment):
    target = directory / 'strict-output-probe'
    target.mkdir()
    save(target / 'spec.json', dict(name='mbrotZ-probe', export='probe-grid',
                                   additional_exports=['probe-real', 'probe-imag', 'probe-count']))
    (target / 'host.mjs').write_text(mbrotz_port.PROBE_HOST)
    (target / 'strict.scm').write_text(mbrotz_port.strict_probe((directory / 'adapted-kernel.scm').read_text()))
    build_strict(target, tools, environment)
    return target


def validate_mbrotz_case(targets, strict, case, tools, environment):
    path = strict / ('spec-' + case['label'] + '.json')
    save(path, case)
    for suffix in ('.raw.wasm', ''):
        record = execute([tools['NODE'], strict / 'host.mjs', strict / ('strict.wasm' + suffix), path], strict, environment)
        save(strict / (case['label'] + ('.raw' if suffix else '') + '.json'), record)
        require_success(record)
        if record['stderr'] or json.loads(record['stdout']) != case['expected']:
            raise ValueError('mbrotZ component/grid/store result differs from the complete oracle')
    for target, command in targets:
        data = mbrotz_port.probe_input(case)
        record = execute(command, target, environment, stdin=data)
        save(target / ('validation-' + case['label'] + '.json'), dict(record, stdin=data))
        require_success(record)
        actual = mbrotz_port.chez_output(case, input_values(record['stdout'])[0])
        if record['stderr'] or actual != case['expected']:
            raise ValueError('original/adapted complex result differs from the complete oracle')


def validate_mbrotz_harness(directory, runner, tools, environment):
    spec, checks = load(directory / 'spec.json'), []
    cases = [('small-grid', 3, 2, 5, True), ('wrong-low', 1, 75, 4, False),
             ('wrong-high', 1, 75, 6, False), ('empty-grid', 1, 0, 5, False),
             ('negative-grid', 1, -1, 5, False), ('zero-count', 0, 75, 5, False),
             ('negative-count', -1, 75, 5, False)]
    for label, count, size, expected, accepted in cases:
        path = directory / ('validation-spec-' + label + '.json')
        save(path, dict(spec, count=count, inputs=[size], expected=expected))
        for suffix in ('.raw.wasm', ''):
            record = execute([tools['NODE'], directory.parent / 'host.mjs', directory / ('strict.wasm' + suffix), path, '--validate'], directory, environment)
            checks.append(dict(record, label=label, accepted=accepted))
            save(directory / 'harness-boundaries.json', checks)
            if (record.get('returncode') == 0 and not record['stderr']) != accepted:
                raise ValueError('mbrotZ must preserve the scalar predicate and invalid loop/size failures')
            if not accepted and not any(text in record['stderr'] for text in ('RuntimeError:', 'AssertionError')):
                raise ValueError('mbrotZ rejection did not reach the Wasm program/result predicate')
        for target in (directory, directory / 'same-source-chez'):
            data = f'{count}\n{size}\n{expected}\n'
            record = execute([tools['CHEZ'], '--program', target / 'program.so'], target, environment, stdin=data)
            checks.append(dict(record, label=label, accepted=accepted, stdin=data))
            save(directory / 'harness-boundaries.json', checks)
            passed = record.get('returncode') == 0 and not record['stderr'] and runner.parse_result(record['stdout'], 'chez', 'mbrotZ')['status'] == 'ok'
            if passed != accepted:
                raise ValueError('original/adapted mbrotZ harness boundary differs')


def validate_mbrotz_outputs(directory, runner, tools, environment):
    targets = [build_mbrotz_chez_probe(directory, adapted, runner, environment) for adapted in (False, True)]
    strict = build_mbrotz_wasm_probe(directory, tools, environment)
    cases = mbrotz_port.fixtures()
    save(directory / 'complete-output-oracles.json', cases)
    for case in cases:
        validate_mbrotz_case(targets, strict, case, tools, environment)
    validate_mbrotz_harness(directory, runner, tools, environment)


# ---- Complete string payloads, ordered replacements and independent copies ----


def build_string_chez_probe(directory, adapted, runner, environment, aliases=False):
    target = directory / (('chez-alias-' if aliases else 'chez-output-') + ('adapted' if adapted else 'original'))
    target.mkdir()
    kernel = (directory / ('adapted-kernel.scm' if adapted else 'original-kernel.scm')).read_text()
    source = string_port.chez_probe(kernel, adapted, CHEZ_REF_HELPERS)
    if aliases:
        source = '(import (chezscheme))\n' + CHEZ_REF_HELPERS + '(define string-eq? eq?)\n'
        source += string_port.alias_source(kernel, adapted) + '(write (probe-alias (read))) (newline)\n'
    (target / 'program.scm').write_text(source)
    return target, build_chez(target, runner, environment, 'build.json')


def build_string_wasm_probe(directory, tools, environment, aliases=False):
    target = directory / ('strict-alias-probe' if aliases else 'strict-output-probe')
    target.mkdir()
    kernel = (directory / 'adapted-kernel.scm').read_text()
    exports = ['probe-grow', 'probe-seed', 'probe-set-character', 'probe-character', 'probe-length']
    source = PRELUDE + '(: probe-alias (-> I64 I64))\n' + string_port.alias_source(kernel, True) + '(unit)\n' if aliases else string_port.strict_probe(kernel, PRELUDE)
    save(target / 'spec.json', dict(name='string-probe', export='probe-alias' if aliases else 'probe-run', additional_exports=[] if aliases else exports))
    (target / 'host.mjs').write_text(string_port.PROBE_HOST)
    (target / 'strict.scm').write_text(source)
    build_strict(target, tools, environment)
    return target


def validate_string_case(targets, strict, case, tools, environment):
    path = strict / ('spec-' + case['label'] + '.json')
    save(path, case)
    for suffix in ('.raw.wasm', ''):
        record = execute([tools['NODE'], strict / 'host.mjs', strict / ('strict.wasm' + suffix), path], strict, environment)
        save(strict / (case['label'] + ('.raw' if suffix else '') + '.json'), record)
        require_success(record)
        if record['stderr'] or json.loads(record['stdout']) != case['expected']:
            raise ValueError('string payload or replacement sequence differs from the complete oracle')
    for target, command in targets:
        data = string_port.probe_input(case)
        record = execute(command, target, environment, stdin=data)
        save(target / ('validation-' + case['label'] + '.json'), dict(record, stdin=data))
        require_success(record)
        if record['stderr'] or string_port.chez_output(input_values(record['stdout'])[0]) != case['expected']:
            raise ValueError('original/adapted string payload or replacement sequence differs')


def validate_string_harness(directory, runner, tools, environment):
    for label, count, threshold, expected, accepted in string_port.harness_fixtures():
        data = f'{count}\n{threshold}\n{expected}\n'
        spec = string_port.specification(data.encode())
        validate_data_wasm_probe(directory, tools, environment, spec, label, accepted)
        for target in (directory, directory / 'same-source-chez'):
            record = execute([tools['CHEZ'], '--program', target / 'program.so'], target, environment, stdin=data)
            save(target / ('validation-' + label + '.json'), dict(record, stdin=data, accepted=accepted))
            require_success(record)
            if record['stderr'] or (runner.parse_result(record['stdout'], 'chez', 'string')['status'] == 'ok') != accepted:
                raise ValueError('string harness changed its false initial result, predicate or repeat boundary')


def validate_string_aliases(directory, runner, tools, environment):
    targets = [build_string_chez_probe(directory, adapted, runner, environment, aliases=True) for adapted in (False, True)]
    strict = build_string_wasm_probe(directory, tools, environment, aliases=True)
    shutil.copy2(directory.parent / 'host.mjs', directory / 'host.mjs')
    for index, label in enumerate(('old', 'first-append', 'right-substring', 'left-substring', 'final-append')):
        spec = dict(name='string-alias', export='probe-alias', count=index, inputs=[], expected=1, barriers_per_iteration=0)
        validate_data_wasm_probe(strict, tools, environment, spec, label)
        for target, command in targets:
            record = execute(command, target, environment, stdin=f'{index}\n')
            save(target / ('validation-' + label + '.json'), dict(record, mutated_string=label))
            require_success(record)
            if record['stderr'] or record['stdout'].strip() != '1':
                raise ValueError('string append/substring results must remain independent through aliases')


def validate_string_outputs(directory, runner, tools, environment):
    targets = [build_string_chez_probe(directory, adapted, runner, environment) for adapted in (False, True)]
    strict = build_string_wasm_probe(directory, tools, environment)
    cases = string_port.fixtures()
    save(directory / 'complete-output-oracles.json', cases)
    for case in cases:
        validate_string_case(targets, strict, case, tools, environment)
    validate_string_aliases(directory, runner, tools, environment)
    validate_string_harness(directory, runner, tools, environment)


# ---- Puzzle board, masks, search effects and scalar harness boundaries ----


def build_puzzle_chez_probe(directory, adapted, runner, environment):
    target = directory / ('chez-state-' + ('adapted' if adapted else 'original'))
    target.mkdir()
    kernel = (directory / ('adapted-kernel.scm' if adapted else 'original-kernel.scm')).read_text()
    (target / 'program.scm').write_text(puzzle_port.chez_probe(kernel, adapted, CHEZ_HELPERS['puzzle']))
    return target, build_chez(target, runner, environment, 'build.json')


def build_puzzle_wasm_probe(directory, tools, environment):
    target = directory / 'strict-state-probe'
    target.mkdir()
    source = puzzle_port.strict_probe((directory / 'adapted-kernel.scm').read_text(), PRELUDE)
    save(target / 'spec.json', dict(name='puzzle-probe', export='probe-command', additional_exports=['probe-state']))
    (target / 'strict.scm').write_text(source)
    (target / 'host.mjs').write_text(puzzle_port.PROBE_HOST)
    build_strict(target, tools, environment)
    return target


def validate_puzzle_case(targets, strict, case, tools, environment):
    path = strict / ('spec-' + case['label'] + '.json')
    save(path, case)
    for suffix in ('.raw.wasm', ''):
        record = execute([tools['NODE'], strict / 'host.mjs', strict / ('strict.wasm' + suffix), path], strict, environment)
        save(strict / (case['label'] + ('.raw' if suffix else '') + '.json'), record)
        require_success(record)
        shutil.move(str(path) + '.actual.json', strict / (case['label'] + ('.raw' if suffix else '') + '.actual.json'))
    for target, command in targets:
        data = puzzle_port.probe_input(case)
        record = execute(command, target, environment, stdin=data)
        save(target / ('validation-' + case['label'] + '.json'), dict(record, stdin=data))
        require_success(record)
        if record['stderr'] or input_values(record['stdout'])[0] != case['expected']:
            raise ValueError('puzzle state or ordered effects differ: ' + case['label'])


def validate_puzzle_harness(directory, runner, tools, environment):
    for label, count, size, expected, accepted in puzzle_port.harness_fixtures():
        data = f'{count}\n{size}\n{expected}\n'
        validate_data_wasm_probe(directory, tools, environment, puzzle_port.specification(data.encode()), label, accepted)
        for target in (directory, directory / 'same-source-chez'):
            record = execute([tools['CHEZ'], '--program', target / 'program.so'], target, environment, stdin=data)
            save(target / ('validation-' + label + '.json'), dict(record, stdin=data, accepted=accepted))
            require_success(record)
            if record['stderr'] or (runner.parse_result(record['stdout'], 'chez', 'puzzle')['status'] == 'ok') != accepted:
                raise ValueError('puzzle false/count predicate or repeat boundary differs')


def validate_puzzle_identity(directory, runner, tools, environment):
    host = (directory.parent / 'host.mjs').read_text()
    host = replace_exact(host, 'hide_i64: opacity,', 'hide_i64: value => { assert.equal(value, 512n); return opacity(511n); },')
    (directory / 'returned-size-host.mjs').write_text(host)
    path = directory / 'returned-size-spec.json'
    save(path, puzzle_port.specification(b'1\n512\n2005\n'))
    for suffix in ('.raw.wasm', ''):
        record = execute([tools['NODE'], directory / 'returned-size-host.mjs', directory / ('strict.wasm' + suffix), path, '--validate'], directory, environment)
        save(directory / ('returned-size' + ('.raw' if suffix else '') + '.json'), record)
        require_success(record)
    for original in (directory, directory / 'same-source-chez'):
        target = original / 'returned-size'
        target.mkdir()
        source = (original / 'program.scm').read_text()
        hide = data_ports.form(source, '(define (hide ')
        (target / 'program.scm').write_text(replace_exact(source, hide, '(define (hide count value) (if (= value 512) 511 (error \'probe "unexpected input")))'))
        command = build_chez(target, runner, environment, 'build.json')
        record = execute(command, target, environment, stdin='1\n512\n2005\n')
        save(target / 'validation.json', record)
        require_success(record)
        if record['stderr'] or runner.parse_result(record['stdout'], 'chez', 'puzzle')['status'] != 'ok':
            raise ValueError('puzzle must use the returned hidden size')


def validate_puzzle_outputs(directory, runner, tools, environment):
    targets = [build_puzzle_chez_probe(directory, adapted, runner, environment) for adapted in (False, True)]
    strict = build_puzzle_wasm_probe(directory, tools, environment)
    cases = puzzle_port.fixtures()
    save(directory / 'complete-state-oracles.json', cases)
    for case in cases:
        validate_puzzle_case(targets, strict, case, tools, environment)
    validate_puzzle_harness(directory, runner, tools, environment)
    validate_puzzle_identity(directory, runner, tools, environment)


def build_lattice_probes(directory, runner, tools, environment):
    for adapted in (False, True):
        target = directory / ('probe-adapted-chez' if adapted else 'probe-original-chez')
        target.mkdir()
        kernel = (directory / ('adapted-kernel.scm' if adapted else 'original-kernel.scm')).read_text()
        (target / 'program.scm').write_text(lattice_port.chez_probe(kernel, adapted))
        build_chez(target, runner, environment, 'build.json')
    target = directory / 'probe-strict'
    target.mkdir()
    source = lattice_port.strict_probe((directory / 'adapted-kernel.scm').read_text(), PRELUDE)
    (target / 'strict.scm').write_text(source)
    (target / 'host.mjs').write_text(lattice_port.PROBE_HOST)
    save(target / 'spec.json', dict(name='lattice-probe', export='probe'))
    build_strict(target, tools, environment)


def lattice_probe_observations(directory, tools, environment, command):
    observations = []
    for system in ('original', 'adapted'):
        target = directory / ('probe-' + system + '-chez')
        record = execute([tools['CHEZ'], '--program', target / 'program.so'], target, environment, stdin=str(command))
        save(target / f'command-{command}.json', record)
        require_success(record)
        observations.append(list(map(int, record['stdout'].split())))
    target = directory / 'probe-strict'
    for suffix in ('.raw.wasm', ''):
        record = execute([tools['NODE'], target / 'host.mjs', target / ('strict.wasm' + suffix), str(command)], target, environment)
        save(target / f'command-{command}{suffix or ".optimized"}.json', record)
        require_success(record)
        observations.append(json.loads(record['stdout']))
    return observations


def validate_lattice_scalar(directory, tools, environment, data, label, accepted):
    path = directory / f'validation-spec-{label}.json'
    save(path, case_specification('lattice', data.encode()))
    checks = []
    for suffix in ('.raw.wasm', ''):
        record = execute([tools['NODE'], directory.parent / 'host.mjs',
                          directory / ('strict.wasm' + suffix), path, '--validate'], directory, environment)
        checks.append(dict(record, accepted=accepted, module_suffix=suffix))
        save(directory / f'validation-{label}.json', checks)
        rejected = record.get('returncode') != 0 and "actual: '120549'" in record.get('stderr', '')
        if (accepted and (record.get('returncode') != 0 or record.get('stderr'))) or (not accepted and not rejected):
            raise ValueError('lattice scalar predicate did not accept or reject the actual result')


def validate_lattice_harness(directory, runner, tools, environment):
    for label, data, accepted in [('other-branch', '1\n33\n10\n', True),
                                  ('wrong-result', '1\n44\n120548\n', False)]:
        validate_lattice_scalar(directory, tools, environment, data, label, accepted)
        for target in (directory, directory / 'same-source-chez'):
            record = execute([tools['CHEZ'], '--program', target / 'program.so'], target, environment, stdin=data)
            save(target / f'chez-validation-{label}.json', record)
            require_success(record)
            if record['stderr'] or (runner.parse_result(record['stdout'], 'chez', 'lattice')['status'] == 'ok') != accepted:
                raise ValueError('lattice canonical scalar predicate differs')


def validate_lattice_outputs(directory, runner, tools, environment):
    build_lattice_probes(directory, runner, tools, environment)
    oracles = [lattice_port.complete_oracle(), lattice_port.boundary_oracle(), None,
               lattice_port.list_operation_oracle()]
    for command, expected in enumerate(oracles):
        observations = lattice_probe_observations(directory, tools, environment, command)
        expected = observations[0] if expected is None else expected
        save(directory / f'probe-oracle-{command}.json', dict(expected=expected, observations=observations))
        if any(actual != expected for actual in observations):
            raise ValueError('lattice complete values, comparison order, or list sharing differ: ' + str(command))
    validate_lattice_harness(directory, runner, tools, environment)


def build_destruc_probes(directory, runner, tools, environment):
    for adapted in (False, True):
        target = directory / ('probe-adapted-chez' if adapted else 'probe-original-chez')
        target.mkdir()
        kernel = (directory / ('adapted-kernel.scm' if adapted else 'original-kernel.scm')).read_text()
        (target / 'program.scm').write_text(destruc_port.chez_probe(kernel, adapted))
        build_chez(target, runner, environment, 'build.json')
    target = directory / 'probe-strict'
    target.mkdir()
    (target / 'strict.scm').write_text(destruc_port.strict_probe((directory / 'adapted-kernel.scm').read_text(), PRELUDE))
    (target / 'host.mjs').write_text(destruc_port.PROBE_HOST)
    save(target / 'spec.json', dict(name='destruc-probe', export='probe'))
    build_strict(target, tools, environment)


def destruc_probe_observations(directory, tools, environment, case):
    label, observations = '-'.join(map(str, case)), []
    for system in ('original', 'adapted'):
        target = directory / ('probe-' + system + '-chez')
        record = execute([tools['CHEZ'], '--program', target / 'program.so'], target, environment,
                         stdin=' '.join(map(str, case)))
        save(target / f'case-{label}.json', record)
        require_success(record)
        observations.append(list(map(int, record['stdout'].split())))
    target = directory / 'probe-strict'
    for suffix in ('.raw.wasm', ''):
        record = execute([tools['NODE'], target / 'host.mjs', target / ('strict.wasm' + suffix), *case], target, environment)
        save(target / f'case-{label}{suffix or ".optimized"}.json', record)
        require_success(record)
        observations.append(json.loads(record['stdout']))
    return observations


def validate_destruc_harness(directory, runner, tools, environment):
    for label, data, accepted in destruc_port.harness_fixtures():
        spec = destruc_port.specification(data.encode())
        validate_data_wasm_probe(directory, tools, environment, spec, label, accepted)
        for target in (directory, directory / 'same-source-chez'):
            record = execute([tools['CHEZ'], '--program', target / 'program.so'], target, environment, stdin=data)
            save(target / f'chez-validation-{label}.json', dict(record, stdin=data, accepted=accepted))
            require_success(record)
            if record['stderr'] or (runner.parse_result(record['stdout'], 'chez', 'destruc')['status'] == 'ok') != accepted:
                raise ValueError('destruc full predicate or initial false differs')


def validate_destruc_outputs(directory, runner, tools, environment):
    build_destruc_probes(directory, runner, tools, environment)
    for case in destruc_port.fixtures():
        expected = destruc_port.oracle(*case)[1]
        observations = destruc_probe_observations(directory, tools, environment, case)
        save(directory / ('probe-oracle-' + '-'.join(map(str, case)) + '.json'),
             dict(expected=expected, observations=observations))
        if any(actual != expected for actual in observations):
            raise ValueError('destruc full values, ordered mutations or node graph differ: ' + str(case))
    validate_destruc_harness(directory, runner, tools, environment)


def build_mazefun_probes(directory, runner, tools, environment):
    for adapted in (False, True):
        target = directory / ('probe-adapted-chez' if adapted else 'probe-original-chez')
        target.mkdir()
        source = (directory / ('adapted-kernel.scm' if adapted else 'original-kernel.scm')).read_text()
        (target / 'program.scm').write_text(mazefun_port.chez_probe(source, adapted))
        build_chez(target, runner, environment, 'build.json')
    target = directory / 'probe-strict'
    target.mkdir()
    source = mazefun_port.strict_probe((directory / 'adapted-kernel.scm').read_text(), PRELUDE)
    (target / 'strict.scm').write_text(source)
    (target / 'host.mjs').write_text(mazefun_port.PROBE_HOST)
    save(target / 'spec.json', dict(name='mazefun-probe', export='probe'))
    build_strict(target, tools, environment)


def mazefun_observations(directory, tools, environment, command, n, m):
    label, observations = f'{command}-{n}-{m}', []
    for system in ('original', 'adapted'):
        target = directory / ('probe-' + system + '-chez')
        record = execute([tools['CHEZ'], '--program', target / 'program.so'], target, environment,
                         stdin=f'{command} {n} {m}')
        save(target / f'case-{label}.json', record)
        require_success(record)
        observations.append(list(map(int, record['stdout'].split())))
    target = directory / 'probe-strict'
    for suffix in ('.raw.wasm', ''):
        record = execute([tools['NODE'], target / 'host.mjs', target / ('strict.wasm' + suffix), command, n, m], target, environment)
        save(target / f'case-{label}{suffix or ".optimized"}.json', record)
        require_success(record)
        observations.append(json.loads(record['stdout']))
    if any(value != observations[0] for value in observations):
        raise ValueError('maze complete result or ordered cavity updates differ: ' + label)
    return observations[0]


def validate_mazefun_harness(directory, runner, tools, environment, grids):
    for label, data, accepted in mazefun_port.harness_fixtures(grids):
        spec = mazefun_port.specification(data.encode())
        validate_data_wasm_probe(directory, tools, environment, spec, label, accepted)
        for target in (directory, directory / 'same-source-chez'):
            record = execute([tools['CHEZ'], '--program', target / 'program.so'], target, environment, stdin=data)
            save(target / f'chez-validation-{label}.json', dict(record, stdin=data, accepted=accepted))
            require_success(record)
            if record['stderr'] or (runner.parse_result(record['stdout'], 'chez', 'mazefun')['status'] == 'ok') != accepted:
                raise ValueError('maze complete predicate or initial false differs: ' + label)


def validate_mazefun_outputs(directory, runner, tools, environment):
    build_mazefun_probes(directory, runner, tools, environment)
    grids = {(n, m): mazefun_observations(directory, tools, environment, 0, n, m)
             for n, m in mazefun_port.output_fixtures()}
    if grids[11, 11] != load(directory / 'spec.json')['expected']:
        raise ValueError('complete original maze differs from the original input expectation')
    for n, m in ((3, 3), (3, 5), (5, 3)):
        mazefun_observations(directory, tools, environment, 1, n, m)
    for system in ('original', 'adapted'):
        target = directory / ('probe-' + system + '-chez')
        record = execute([tools['CHEZ'], '--program', target / 'program.so'], target, environment, stdin='2 3 3')
        save(target / 'sharing.json', record)
        require_success(record)
        if record['stderr'] or list(map(int, record['stdout'].split())) != [1] * 15:
            raise ValueError('maze persistent sharing differs in ' + system)
    validate_mazefun_harness(directory, runner, tools, environment, grids)


def prepare_case(name, files, output, runner, tools, environment):
    if name == 'maze':
        return maze_port.prepare_case(files, output, runner, tools, environment, sys.modules[__name__])
    if name == 'parsing':
        return parsing_port.prepare_case(files, output, runner, tools, environment, sys.modules[__name__])
    if name in boyer_port.NAMES:
        return boyer_port.prepare_case(name, files, output, runner, tools, environment, sys.modules[__name__])
    if name == 'conform':
        return conform_port.prepare_case(files, output, runner, tools, environment, sys.modules[__name__])
    if name == 'equal':
        return equal_port.prepare_case(files, output, runner, tools, environment, sys.modules[__name__])
    if name == 'browse':
        return browse_port.prepare_case(files, output, runner, tools, environment, sys.modules[__name__])
    if name in reader_ports.NAMES:
        return reader_ports.prepare_case(name, files, output, runner, tools, environment, sys.modules[__name__])
    if name == 'earley':
        return earley_port.prepare_case(files, output, runner, tools, environment, sys.modules[__name__])
    directory = output / name
    directory.mkdir()
    spec = case_specification(name, files[f'inputs/{name}.input'])
    write_case_sources(name, files, directory, spec, runner)
    if name == 'matrix':
        return matrix_port.prepare_case(directory, runner, tools, environment, sys.modules[__name__])
    if name == 'fft':
        build_fft_provider(directory, tools, environment)
    if name == 'ray':
        ray_port.build_runtime(directory, tools, environment, sys.modules[__name__])
    if name == 'tail':
        tail_port.build_runtime(directory, tools, environment, sys.modules[__name__])
    if name == 'nucleic':
        nucleic_port.build_runtime(directory, tools, environment, sys.modules[__name__])
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
    if name == 'paraffins':
        validate_paraffins_outputs(directory, runner, tools, environment, spec)
    if name == 'gcbench':
        validate_gc_outputs(directory, runner, tools, environment, spec)
    if name in ENUMERATION_PORTS:
        validate_enumeration_outputs(name, directory, runner, tools, environment, spec)
    if name == 'simplex':
        validate_simplex_outputs(directory, runner, tools, environment)
    if name == 'deriv':
        validate_deriv_outputs(directory, runner, tools, environment)
    if name == 'mbrotZ':
        validate_mbrotz_outputs(directory, runner, tools, environment)
    if name == 'string':
        validate_string_outputs(directory, runner, tools, environment)
    if name == 'puzzle':
        validate_puzzle_outputs(directory, runner, tools, environment)
    if name == 'lattice':
        validate_lattice_outputs(directory, runner, tools, environment)
    if name == 'destruc':
        validate_destruc_outputs(directory, runner, tools, environment)
    if name == 'ray':
        ray_port.validate_outputs(directory, runner, tools, environment, sys.modules[__name__])
    if name == 'mazefun':
        validate_mazefun_outputs(directory, runner, tools, environment)
    if name == 'tail':
        tail_port.validate_outputs(directory, runner, tools, environment, sys.modules[__name__])
    if name == 'nucleic':
        nucleic_port.validate_outputs(directory, runner, tools, environment, sys.modules[__name__])
    if name == 'bv2string':
        bv2string_port.validate_outputs(directory, runner, tools, environment, sys.modules[__name__])
    status = 'retention-blocked' if name == 'gcbench' else 'ready'
    return dict(name=name, status=status, spec=spec, chez_command=run,
                systems=['strict', 'chez', 'chez-adapted'] if name in NEXT_PORTS + ('quicksort', 'simplex', 'deriv', 'mbrotZ', 'string', 'puzzle', 'lattice', 'destruc', 'ray', 'mazefun', 'tail', 'nucleic', 'bv2string') + DATA_PORTS + ENUMERATION_PORTS else ['strict', 'chez-adapted'] if name == 'fft' else ['strict', 'chez'],
                hashes={str(p.relative_to(directory)): digest(p) for p in directory.rglob('*') if p.is_file()})


def write_case_sources(name, files, directory, spec, runner):
    save(directory / 'spec.json', spec)
    (directory / 'input.txt').write_bytes(files[f'inputs/{name}.input'])
    (directory / 'upstream.scm').write_bytes(files[f'src/{name}.scm'])
    (directory / 'strict.scm').write_text(strict_program(name, spec, files[f'src/{name}.scm'].decode()))
    (directory / 'program.scm').write_text(runner.source_text(files, name, 'chez'))
    if name == 'tail':
        tail_port.seed_files(directory, spec, files[spec['pathnames'][0]])


def compiler_basis(sources, revision):
    commit = subprocess.check_output(['git', 'rev-parse', revision], cwd=ROOT, text=True).strip()
    for source in sources:
        original = subprocess.check_output(['git', 'show', commit + ':' + str(source.relative_to(ROOT))], cwd=ROOT)
        if source.read_bytes() != original:
            raise ValueError(f'compiler source differs from declared basis {commit}: {source}')
    return commit


def prepare(options):
    runner, tools = upstream_runner(), tool_paths(options.benchmarks)
    environment = {**os.environ, **tools, 'BINARYEN_CORES': '1'}
    files = runner.suite_sources()
    options.output.mkdir(parents=True, exist_ok=False)
    shutil.copy2(HERE / 'host.mjs', options.output / 'host.mjs')
    shutil.copy2(__file__, options.output / 'measure.py')
    shutil.copy2(HERE / 'data_ports.py', options.output / 'data_ports.py')
    shutil.copy2(HERE / 'enumeration_ports.py', options.output / 'enumeration_ports.py')
    shutil.copy2(HERE / 'simplex_port.py', options.output / 'simplex_port.py')
    shutil.copy2(HERE / 'deriv_port.py', options.output / 'deriv_port.py')
    shutil.copy2(HERE / 'mbrotz_port.py', options.output / 'mbrotz_port.py')
    shutil.copy2(HERE / 'string_port.py', options.output / 'string_port.py')
    shutil.copy2(HERE / 'puzzle_port.py', options.output / 'puzzle_port.py')
    shutil.copy2(HERE / 'lattice_port.py', options.output / 'lattice_port.py')
    shutil.copy2(HERE / 'destruc_port.py', options.output / 'destruc_port.py')
    shutil.copy2(HERE / 'ray_port.py', options.output / 'ray_port.py')
    shutil.copy2(HERE / 'ray-host.mjs', options.output / 'ray-host.mjs')
    shutil.copy2(HERE / 'mazefun_port.py', options.output / 'mazefun_port.py')
    shutil.copy2(HERE / 'tail_port.py', options.output / 'tail_port.py')
    shutil.copy2(HERE / 'bv2string_port.py', options.output / 'bv2string_port.py')
    shutil.copy2(HERE / 'matrix_port.py', options.output / 'matrix_port.py')
    shutil.copy2(HERE / 'reader_ports.py', options.output / 'reader_ports.py')
    shutil.copy2(HERE / 'browse_port.py', options.output / 'browse_port.py')
    shutil.copy2(HERE / 'equal_port.py', options.output / 'equal_port.py')
    shutil.copy2(HERE / 'conform_port.py', options.output / 'conform_port.py')
    shutil.copy2(HERE / 'browse-observe.mjs', options.output / 'browse-observe.mjs')
    shutil.copy2(HERE / 'reader-timing.mjs', options.output / 'reader-timing.mjs')
    shutil.copy2(HERE / 'reader-host.mjs', options.output / 'reader-host.mjs')
    shutil.copy2(HERE / 'tail-host.mjs', options.output / 'tail-host.mjs')
    shutil.copy2(HERE / 'nucleic_port.py', options.output / 'nucleic_port.py')
    shutil.copy2(HERE / 'nucleic-host.mjs', options.output / 'nucleic-host.mjs')
    shutil.copy2(HERE / 'earley_port.py', options.output / 'earley_port.py')
    shutil.copy2(HERE / 'boyer_port.py', options.output / 'boyer_port.py')
    shutil.copy2(HERE / 'maze_port.py', options.output / 'maze_port.py')
    shutil.copy2(HERE / 'parsing_port.py', options.output / 'parsing_port.py')
    shutil.copy2(ROOT / 'benchmarks/r7rs.py', options.output / 'r7rs.py')
    sources = [*ROOT.glob('src/**/*.sld'), ROOT / 'scripts/build-strict', ROOT / 'tests/build-strict-program.scm']
    if any(name in options.benchmarks for name in ('ray', 'tail', 'nucleic', 'earley', 'browse', 'equal', 'conform', 'maze', 'parsing') + reader_ports.NAMES + boyer_port.NAMES):
        sources += [*ROOT.glob('src/**/*.rs'), *(ROOT / name for name in
                    ('Cargo.toml', 'Cargo.lock', 'rust-toolchain.toml', 'scripts/link-strict-runtime'))]
    if any(name in options.benchmarks for name in ('bv2string', 'matrix', 'browse', 'equal', 'conform', 'maze', 'parsing') + reader_ports.NAMES + boyer_port.NAMES):
        sources += [*ROOT.glob('src/**/*.rs'), *ROOT.glob('src/*.c'), *ROOT.glob('src/*.h'),
                    *(ROOT / name for name in ('Cargo.toml', 'Cargo.lock', 'rust-toolchain.toml',
                                               'scripts/build-native', 'scripts/build-native.scm'))]
    if any(name in options.benchmarks for name in ('browse', 'equal', 'maze', 'parsing') + boyer_port.NAMES):
        sources += [*ROOT.glob('tests/strict-reader/*'), *ROOT.glob('tests/strict-browse/*')]
    if 'conform' in options.benchmarks:
        sources += [*ROOT.glob('tests/strict-reader/*'), *ROOT.glob('tests/strict-conform/*')]
    if 'maze' in options.benchmarks:
        sources += [*ROOT.glob('tests/strict-maze/*')]
    if 'earley' in options.benchmarks:
        sources += [ROOT / 'scripts/build-native', ROOT / 'scripts/build-native.scm',
                    *ROOT.glob('src/**/*.c'), *ROOT.glob('src/**/*.h')]
    sources = list(dict.fromkeys(sources))
    for source in sources:
        target = options.output / 'compiler-source' / source.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    basis = compiler_basis(sources, options.compiler_basis)
    report = dict(date=datetime.now(timezone.utc).isoformat(), cases=[],
                  tools={key: dict(path=value, sha256=digest(value)) for key, value in tools.items()},
                  compiler_commit=basis,
                  driver_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                  data_ports_sha256=digest(HERE / 'data_ports.py'),
                  enumeration_ports_sha256=digest(HERE / 'enumeration_ports.py'),
                  simplex_port_sha256=digest(HERE / 'simplex_port.py'),
                  deriv_port_sha256=digest(HERE / 'deriv_port.py'),
                  mbrotz_port_sha256=digest(HERE / 'mbrotz_port.py'),
                  string_port_sha256=digest(HERE / 'string_port.py'),
                  puzzle_port_sha256=digest(HERE / 'puzzle_port.py'),
                  lattice_port_sha256=digest(HERE / 'lattice_port.py'),
                  destruc_port_sha256=digest(HERE / 'destruc_port.py'),
                  ray_port_sha256=digest(HERE / 'ray_port.py'),
                  ray_host_sha256=digest(HERE / 'ray-host.mjs'),
                  mazefun_port_sha256=digest(HERE / 'mazefun_port.py'),
                  tail_port_sha256=digest(HERE / 'tail_port.py'),
                  bv2string_port_sha256=digest(HERE / 'bv2string_port.py'),
                  matrix_port_sha256=digest(HERE / 'matrix_port.py'),
                  reader_ports_sha256=digest(HERE / 'reader_ports.py'),
                  browse_port_sha256=digest(HERE / 'browse_port.py'),
                  equal_port_sha256=digest(HERE / 'equal_port.py'),
                  boyer_port_sha256=digest(HERE / 'boyer_port.py'),
                  conform_port_sha256=digest(HERE / 'conform_port.py'),
                  maze_port_sha256=digest(HERE / 'maze_port.py'),
                  parsing_port_sha256=digest(HERE / 'parsing_port.py'),
                  reader_host_sha256=digest(HERE / 'reader-host.mjs'),
                  tail_host_sha256=digest(HERE / 'tail-host.mjs'),
                  nucleic_port_sha256=digest(HERE / 'nucleic_port.py'),
                  nucleic_host_sha256=digest(HERE / 'nucleic-host.mjs'),
                  earley_port_sha256=digest(HERE / 'earley_port.py'),
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
    if case['name'] == 'ray':
        ray_port.reset_output(directory, case['spec'])
    if case['name'] == 'tail':
        tail_port.seed_files(directory, case['spec'])
    if system == 'strict':
        host = case['name'] + '-host.mjs' if case['name'] in ('ray', 'tail', 'nucleic') else 'host.mjs'
        warning = ['--disable-warning=ExperimentalWarning'] if case['name'] in ('ray', 'tail', 'nucleic') else []
        command = [tools['NODE']['path'], *warning, output / host, directory / 'strict.wasm', directory / 'spec.json']
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
        parsed = json.loads(result['stdout'].splitlines()[-1]) if system == 'strict' else upstream_runner().parse_result(result['stdout'], 'chez', case['name'])
        seconds = parsed['seconds']
        assert math.isfinite(seconds) and seconds > 0
        if system != 'strict' and parsed['status'] != 'ok':
            raise ValueError('Chez predicate rejected the result')
        if case['name'] == 'ray':
            parsed['image'] = ray_port.check_image(directory, case['spec'])
        if case['name'] == 'tail':
            parsed['file'] = tail_port.check_output(directory, case['spec'])
        return dict(result, valid=True, workload_seconds=seconds, checked_result=parsed)
    except (KeyError, ValueError, AssertionError) as error:
        return dict(result, valid=False, validation_error=str(error))


def checked_preparation(output):
    if os.environ.get('NODE_OPTIONS'):
        raise ValueError('NODE_OPTIONS must be unset')
    prepared = load(output / 'prepared.json')
    if prepared.get('maze_port_sha256', digest(HERE / 'maze_port.py')) != digest(HERE / 'maze_port.py'):
        raise ValueError('Maze source adapter changed')
    if prepared.get('parsing_port_sha256', digest(HERE / 'parsing_port.py')) != digest(HERE / 'parsing_port.py'):
        raise ValueError('Parsing source adapter changed')
    if prepared.get('boyer_port_sha256', digest(HERE / 'boyer_port.py')) != digest(HERE / 'boyer_port.py'):
        raise ValueError('Boyer source adapter changed')
    if prepared.get('conform_port_sha256', digest(HERE / 'conform_port.py')) != digest(HERE / 'conform_port.py'):
        raise ValueError('Conform source adapter changed')
    if prepared.get('equal_port_sha256', digest(HERE / 'equal_port.py')) != digest(HERE / 'equal_port.py'):
        raise ValueError('Equal source adapter changed')
    if prepared.get('browse_port_sha256', digest(HERE / 'browse_port.py')) != digest(HERE / 'browse_port.py'):
        raise ValueError('Browse source adapter changed')
    if prepared.get('driver_sha256', digest(__file__)) != digest(__file__):
        raise ValueError('driver changed')
    if prepared.get('data_ports_sha256', digest(HERE / 'data_ports.py')) != digest(HERE / 'data_ports.py'):
        raise ValueError('data port source adapters changed')
    if prepared.get('enumeration_ports_sha256', digest(HERE / 'enumeration_ports.py')) != digest(HERE / 'enumeration_ports.py'):
        raise ValueError('enumeration port source adapters changed')
    if prepared.get('simplex_port_sha256', digest(HERE / 'simplex_port.py')) != digest(HERE / 'simplex_port.py'):
        raise ValueError('simplex port source adapter changed')
    if prepared.get('deriv_port_sha256', digest(HERE / 'deriv_port.py')) != digest(HERE / 'deriv_port.py'):
        raise ValueError('deriv port source adapter changed')
    if prepared.get('mbrotz_port_sha256', digest(HERE / 'mbrotz_port.py')) != digest(HERE / 'mbrotz_port.py'):
        raise ValueError('mbrotZ port source adapter changed')
    if prepared.get('string_port_sha256', digest(HERE / 'string_port.py')) != digest(HERE / 'string_port.py'):
        raise ValueError('string port source adapter changed')
    if prepared.get('puzzle_port_sha256', digest(HERE / 'puzzle_port.py')) != digest(HERE / 'puzzle_port.py'):
        raise ValueError('puzzle port source adapter changed')
    if prepared.get('lattice_port_sha256', digest(HERE / 'lattice_port.py')) != digest(HERE / 'lattice_port.py'):
        raise ValueError('lattice port source adapter changed')
    if prepared.get('destruc_port_sha256', digest(HERE / 'destruc_port.py')) != digest(HERE / 'destruc_port.py'):
        raise ValueError('destruc port source adapter changed')
    if prepared.get('ray_port_sha256', digest(HERE / 'ray_port.py')) != digest(HERE / 'ray_port.py'):
        raise ValueError('Ray source adapter changed')
    if 'ray_host_sha256' in prepared and prepared['ray_host_sha256'] != digest(output / 'ray-host.mjs'):
        raise ValueError('Ray host changed')
    if prepared.get('mazefun_port_sha256', digest(HERE / 'mazefun_port.py')) != digest(HERE / 'mazefun_port.py'):
        raise ValueError('mazefun port source adapter changed')
    if prepared.get('tail_port_sha256', digest(HERE / 'tail_port.py')) != digest(HERE / 'tail_port.py'):
        raise ValueError('tail port source adapter changed')
    if prepared.get('bv2string_port_sha256', digest(HERE / 'bv2string_port.py')) != digest(HERE / 'bv2string_port.py'):
        raise ValueError('bv2string source adapter changed')
    if prepared.get('matrix_port_sha256', digest(HERE / 'matrix_port.py')) != digest(HERE / 'matrix_port.py'):
        raise ValueError('Matrix source adapter changed')
    if 'tail_host_sha256' in prepared and prepared['tail_host_sha256'] != digest(output / 'tail-host.mjs'):
        raise ValueError('tail host changed')
    if prepared.get('nucleic_port_sha256', digest(HERE / 'nucleic_port.py')) != digest(HERE / 'nucleic_port.py'):
        raise ValueError('nucleic port source adapter changed')
    if prepared.get('earley_port_sha256', digest(HERE / 'earley_port.py')) != digest(HERE / 'earley_port.py'):
        raise ValueError('Earley port source adapter changed')
    if 'nucleic_host_sha256' in prepared and prepared['nucleic_host_sha256'] != digest(output / 'nucleic-host.mjs'):
        raise ValueError('nucleic host changed')
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
    if any(case['name'] in reader_ports.NAMES + ('browse', 'equal', 'conform', 'maze', 'parsing') + boyer_port.NAMES for case in prepared['cases']):
        raise ValueError('reader, browse, equal, conform, Maze, Parsing and Boyer workloads require separately frozen timing plans')
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
    parser.add_argument('--compiler-basis', default='HEAD', help='commit whose compiler files must match preparation')
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
