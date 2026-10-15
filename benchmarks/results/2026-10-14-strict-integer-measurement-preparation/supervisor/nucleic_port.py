"""Preserve Nucleic's complete database, geometry and ordered linked search."""

import hashlib
import json
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import time

from data_ports import form, replace
from string_port import exact_json_integer, i64
import ray_port


# ---- Shared coordinate vectors and explicit mutable assignment identity ----

BASES = dict(rA='adenine', rC='cytosine', rG='guanine', rU='uracil')
DATABASE = [name for base in BASES for name in [base, *(base + f'{i:02}' for i in range(1, 11))]] + ['rG*', 'rU*']
RELATIONS = ['wc-tfo', 'wc-Dumas-tfo', 'helix5*-tfo', 'helix3*-tfo', 'G37-A38-tfo', 'A38-G37-tfo']
STRICT_TYPES = '''(define-data Base (adenine) (cytosine) (guanine) (uracil))
(define-data Nucleotide
  (nucleotide (base Base nucleotide-base)
              (fields (Vector (Vector F64)) nucleotide-fields)))
(define-data Assignment
  (assignment (id I64 assignment-id) (tfo (Vector F64) assignment-tfo)
              (nuc Nucleotide assignment-nuc)))
(define (base-code base)
  (match base ((adenine) 0) ((cytosine) 1) ((guanine) 2) ((uracil) 3)))
'''
CHEZ_TYPES = '''(define-syntax : (syntax-rules () ((_ . signature) (begin))))
(define-syntax ann (syntax-rules () ((_ value type) value)))
(define (adenine) 0)
(define (cytosine) 1)
(define (guanine) 2)
(define (uracil) 3)
(define (base-code base) base)
(define (nucleotide base fields) (vector base fields))
(define (nucleotide-base value) (vector-ref value 0))
(define (nucleotide-fields value) (vector-ref value 1))
(define (assignment id tfo nuc) (vector id tfo nuc))
(define (assignment-id value) (vector-ref value 0))
(define (assignment-tfo value) (vector-ref value 1))
(define (assignment-nuc value) (vector-ref value 2))
(define (ref value) (vector value))
(define (ref-get value) (vector-ref value 0))
(define (ref-set! cell value) (vector-set! cell 0 value))
(define ref-eq? eq?)
(define vector-eq? eq?)
(define (unit) (if #f #f))
'''
COMMON = ''';; Every operand occurs once. Preserve left-associated binary64 sums
;; and unary sign reversal, including both signs of zero.
(define-syntax nucleic+
  (syntax-rules ()
    ((_ a b) (+ a b))
    ((_ a b c) (+ (+ a b) c))
    ((_ a b c d) (+ (+ (+ a b) c) d))))
(define-syntax nucleic-
  (syntax-rules () ((_ x) (* -1.0 x)) ((_ x y) (- x y))))
(define (nucleic-list . elements) elements)
(: nucleic-append (All (T) (-> (List T) (List T) (List T))))
(define (nucleic-append first last)
  (if (null? first) last (cons (car first) (nucleic-append (cdr first) last))))
(: nucleic-map (All (A B) (-> (-> A B) (List A) (List B))))
(define (nucleic-map procedure values)
  (if (null? values) '()
      (let ((head (procedure (car values))))
        (cons head (nucleic-map procedure (cdr values))))))
'''
CONTRACTS = '''(: math-atan2 (-> F64 F64 F64))
(: make-pt (-> F64 F64 F64 (Vector F64)))
(: make-tfo (-> F64 F64 F64 F64 F64 F64 F64 F64 F64 F64 F64 F64 (Vector F64)))
(: atom-pos (-> (-> Nucleotide (Vector F64)) (Ref Assignment) (Vector F64)))
(: get-var (-> I64 (List (Ref Assignment)) (Ref Assignment)))
(: reference (-> Nucleotide I64 (-> (List (Ref Assignment)) (List (Ref Assignment)))))
(: search (-> (List (Ref Assignment))
              (List (-> (List (Ref Assignment)) (List (Ref Assignment))))
              (-> (Ref Assignment) (List (Ref Assignment)) Bool)
              (List (List (Ref Assignment)))))
(: run (-> (List (Ref Assignment)) F64))
'''
INPUTS = '''(define input0
  (ann (if (= (native-input-i64 (ann 0 I32)) 0) '() (unreachable))
       (List (Ref Assignment))))
(define expected-result (native-input-f64 (ann 1 I32)))
(: hide-input (-> I64 (List (Ref Assignment)) (List (Ref Assignment))))
(define (hide-input count value) (if (barrier) value (unreachable)))
'''
WORKER = '''(let loop ((i 0) (result 0.0))
  (if (< i count)
      (loop (+ i 1) (run (hide-input count input0)))
      (if (and (> count 0)
               (let ((x (/ result expected-result)))
                 (and (> x 0.999999) (< x 1.000001)))) 1 0)))'''


# ---- Counted reversible edits leave the complete algorithm visible ----

def nucleotide_constructor(source, base):
    before = form(source, '(define (make-' + base + ' ')
    after = replace(before, '(vector ', '(nucleotide (' + BASES[base] + ') (vector ')
    after = replace(after, "'" + base + ' ', '')
    return before, after + ')'


def database_constant(source, name):
    before = form(source, '(define ' + name + '\n')
    base = name[:2]
    after = replace(before, "'#(", '(make-' + base + ' ')
    after = replace(after, '\n   ' + base + '\n', '\n')
    after = after.replace('#(', '(vector ')
    if decimal_tokens(before) != decimal_tokens(after):
        raise ValueError('Nucleic coordinate literal changed: ' + name)
    return before, after


def decimal_tokens(source):
    source = re.sub(r';[^\n]*', '', source)
    return re.findall(r'(?<![^\s()])[-+]?\d+\.\d+(?:[eE][-+]?\d+)?(?=[\s()]|$)', source)


def assignment_edits(source):
    yield form(source, '(define (make-var '), '(define (make-var id tfo nuc) (ref (assignment id tfo nuc)))'
    for field in ('id', 'tfo', 'nuc'):
        yield form(source, '(define (var-' + field + ' '), (
            f'(define (var-{field} var) (assignment-{field} (ref-get var)))')
        values = ['val' if item == field else f'(assignment-{item} old)' for item in ('id', 'tfo', 'nuc')]
        yield form(source, '(define (var-' + field + '-set! '), (
            f'(define (var-{field}-set! var val)\n'
            f'  (let ((old (ref-get var))) (ref-set! var (assignment {" ".join(values)}))))')


def field_edits(source):
    pattern = r'\(define \(([^ ]+) nuc(?: val)?\) \(vector-(ref|set!) nuc (\d+)(?: val)?\)\)'
    fields = list(re.finditer(pattern, source))
    if len(fields) != 114:
        raise ValueError('expected all 57 nucleotide getters and setters')
    for match in fields:
        old, index = match.group(), int(match[3])
        if index == 29:
            raise ValueError('the base tag has its own concrete type')
        new = old.replace(' nuc ' + str(index), ' (nucleotide-fields nuc) ' + str(index - (index > 29)))
        yield old, new


def adaptation(source):
    original, edits = source, []

    def edit(before, after, count=1):
        nonlocal source
        source = replace(source, before, after, count)
        edits.append(dict(before=before, after=after, count=count))

    for base in BASES:
        edit(*nucleotide_constructor(source, base))
        edit(form(source, '(define (' + base + '? '),
             f'(define ({base}? nuc) (= (base-code (nucleotide-base nuc)) {list(BASES).index(base)}))')
    for before, after in field_edits(source):
        edit(before, after)
    for before, after in assignment_edits(source):
        edit(before, after)
    for name in DATABASE:
        edit(*database_constant(source, name))
    for name in RELATIONS:
        before = form(source, '(define ' + name + '\n')
        edit(before, replace(before, "'#(", '(vector '))
    before = form(source, '(define (pseudoknot-constraint? ')
    after = replace(before, '(case (var-id v)', '(let ((id (var-id v)))\n    (cond')
    after = replace(replace(after, '((18)', '((= id 18)'), '((6)', '((= id 6)')
    edit(before, after + ')')
    for name in ('+', '-', 'list', 'append', 'map'):
        replacement = 'nucleic' + name if name in ('+', '-') else 'nucleic-' + name
        for before in sorted(set(re.findall(r'\(' + re.escape(name) + r'\s', source))):
            edit(before, '(' + replacement + before[-1], source.count(before))
    restored = source
    for step in reversed(edits):
        restored = replace(restored, step['after'], step['before'], step['count'])
    if restored != original:
        raise ValueError('Nucleic edits did not restore the complete original kernel')
    return CONTRACTS + source, edits


def kernel(source):
    return adaptation(source)[0]


# ---- Read the actual workload datums before execution ----

INPUT_DECODER = '''(import (chezscheme))
(let* ((count (read)) (input (read)) (expected (read)))
  (unless (and (integer? count) (exact? count) (null? input) (real? expected))
    (error 'nucleic-input "expected integral count, empty partial assignment and real result"))
  (write count) (newline) (write (inexact expected)) (newline))
'''


def specification(data):
    with tempfile.TemporaryDirectory(prefix='snail-nucleic-input-') as temporary:
        decoder = Path(temporary) / 'decode.scm'
        decoder.write_text(INPUT_DECODER)
        record = subprocess.run([os.environ.get('CHEZ', 'scheme'), '--script', decoder],
                                input=data, capture_output=True, check=True)
    count, expected = record.stdout.decode().splitlines()
    return dict(name='nucleic', count=exact_json_integer(i64(count)), inputs=[0, float(expected)],
                expected=1, barriers_per_iteration=1, setup_barriers=0, runtime='scalar-math')


def build_runtime(directory, tools, environment, driver):
    ray_port.build_runtime(directory, tools, environment, driver)
    (directory / 'input-decoder.scm').write_text(INPUT_DECODER)


# ---- Bound complete builds and retain every failed child-process attempt ----

def build_record(command, cwd, environment, timeout=1200):
    command = list(map(str, command))
    record = dict(command=command, timeout_seconds=timeout)
    started = time.perf_counter()
    with subprocess.Popen(command, cwd=cwd, env=environment, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True) as process:
        try:
            record['stdout'], record['stderr'] = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGTERM)
                process.communicate(timeout=5)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                pass
            # A reaped leader or closed pipes do not imply that its group is empty.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            record['stdout'], record['stderr'] = process.communicate()
            record['error'] = 'bounded Nucleic preparation timeout; owned process group terminated'
        record['returncode'] = process.returncode
    return dict(record, process_seconds=time.perf_counter() - started)


def link_runtime(directory, tools, environment, driver):
    for suffix in ('', '.raw.wasm'):
        output = directory / ('strict.wasm' + suffix)
        source = directory / ('strict-native.wasm' + suffix)
        output.rename(source)
        flags = ['--diagnostic-prune-only'] if suffix else []
        command = [driver.ROOT / 'scripts/link-strict-runtime', '--runtime', directory / 'runtime.wasm',
                   *flags, source, output]
        record = build_record(command, driver.ROOT, environment)
        driver.save(directory / ('runtime-link' + ('-raw' if suffix else '') + '.json'), record)
        driver.require_success(record)


# ---- Complete values and order are observed outside the benchmark worker ----

PROBE_COMMON = '''(: probe-each (All (T) (-> (-> T Unit) (List T) Unit)))
(define (probe-each procedure values)
  (unless (null? values) (procedure (car values)) (probe-each procedure (cdr values))))
(define (probe-check value) (emit-i64 (if value 1 0)))
(define (probe-vector values)
  (emit-i64 (vector-length values))
  (let loop ((i 0))
    (unless (= i (vector-length values)) (emit-f64 (vector-ref values i)) (loop (+ i 1)))))
(define (probe-nucleotide value)
  (emit-i64 (cond ((rA? value) 0) ((rC? value) 1) ((rG? value) 2) (else 3)))
  (probe-vector (nuc-dgf-base-tfo value))
  (probe-vector (nuc-P-O3*-275-tfo value))
  (probe-vector (nuc-P-O3*-180-tfo value))
  (probe-vector (nuc-P-O3*-60-tfo value))
  (let ((atoms (list-of-atoms value)))
    (emit-i64 (length atoms)) (probe-each probe-vector atoms)))
(define (probe-nucleotide-index value)
  (let loop ((values probe-database) (index 0))
    (if (null? values) -1
        (if (probe-same-nuc? value (car values)) index (loop (cdr values) (+ index 1))))))
(define (probe-variable value)
  (emit-i64 (var-id value))
  (emit-i64 (probe-nucleotide-index (var-nuc value)))
  (probe-vector (var-tfo value)))
(define (probe-solution values)
  (emit-i64 (length values)) (probe-each probe-variable values))
(define (probe-solutions values)
  (emit-i64 (length values)) (probe-each probe-solution values))
(define (probe-geometry)
  (probe-vector (tfo-apply wc-tfo (make-pt 1.25 -2.0 0.5)))
  (probe-vector (tfo-combine wc-tfo helix3*-tfo))
  (probe-vector (tfo-inv-ortho wc-Dumas-tfo))
  (probe-vector (tfo-align (make-pt 1.0 2.0 3.0) (make-pt 4.0 1.0 2.0)
                           (make-pt 0.5 2.0 4.0)))
  (probe-each (lambda (n) (probe-nucleotide (make-relative-nuc wc-tfo n)))
              (nucleic-list rA rC rG rU)))
(define (probe-assignment-mutation)
  (let* ((tfo (vector-copy tfo-id)) (value (make-var 1 tfo rA)) (alias value)
         (shared (nucleic-list value)) (replacement (vector-copy wc-tfo)))
    (var-id-set! alias 9)
    (emit-i64 (var-id (car shared)))
    (probe-check (probe-same-var? alias value))
    (probe-check (vector-eq? (var-tfo alias) tfo))
    (probe-check (probe-same-nuc? (var-nuc alias) rA))
    (var-tfo-set! value replacement)
    (probe-check (vector-eq? (var-tfo alias) replacement))
    (emit-i64 (var-id alias)) (probe-check (probe-same-nuc? (var-nuc alias) rA))
    (tfo-tx-set! replacement 71.0) (emit-f64 (tfo-tx (var-tfo alias)))
    (var-nuc-set! alias rU) (probe-check (probe-same-nuc? (var-nuc value) rU))
    (emit-i64 (var-id value)) (probe-check (vector-eq? (var-tfo value) replacement))))
(define (probe-point-mutation)
  (let* ((n (make-relative-nuc tfo-id rA)) (alias n) (point (nuc-P n))
         (replacement (make-pt 10.0 20.0 30.0)))
    (pt-x-set! point -7.0) (pt-y-set! point -8.0) (pt-z-set! point -9.0)
    (probe-vector (nuc-P alias))
    (nuc-P-set! n replacement)
    (probe-check (vector-eq? (nuc-P alias) replacement))
    (probe-vector point) (probe-vector (nuc-P n))))
(define (probe-unmodified-fields getters before value changed)
  (let loop ((getters getters) (before before) (index 0))
    (unless (null? getters)
      (unless (= index changed)
        (probe-check (vector-eq? ((car getters) value) (car before))))
      (loop (cdr getters) (cdr before) (+ index 1)))))
(define (probe-angle-and-maximum)
  (probe-each (lambda (y)
    (probe-each (lambda (x) (emit-f64 (math-atan2 y x)))
                (nucleic-list -1.0 -0.0 0.0 1.0)))
    (nucleic-list -1.0 -0.0 0.0 1.0))
  (emit-f64 (maximum (nucleic-list -0.0 0.0)))
  (emit-f64 (maximum (nucleic-list 0.0 -0.0)))
  (emit-f64 (maximum (nucleic-list 1.0 9.0 -3.0 9.0))))
(: probe (-> I64 I64))
(define (probe command)
  (cond ((= command 0) (emit-i64 (length probe-database)) (probe-each probe-nucleotide probe-database))
        ((= command 1) (probe-solutions (pseudoknot '())))
        ((= command 2) (probe-solutions (anticodon)))
        ((= command 3) (probe-geometry))
        ((= command 4) (probe-assignment-mutation) (probe-point-mutation) (probe-all-fields))
        ((= command 5) (probe-angle-and-maximum))
        (else (emit-f64 (run '()))))
  1)
'''
STRICT_OBSERVERS = '''(define-extern emit-i64 "benchmark" "emit_i64" (-> I64 Unit))
(define-extern emit-f64 "benchmark" "emit_f64" (-> F64 Unit))
(define (probe-same-nuc? left right)
  (vector-eq? (nucleotide-fields left) (nucleotide-fields right)))
(define probe-same-var? ref-eq?)
'''
CHEZ_OBSERVERS = '''(define (emit-i64 value) (display "i ") (write value) (newline))
(define (emit-f64 value) (display "f ") (write value) (newline))
'''


def field_probes(original):
    # Each source getter/setter pair is exercised on a fresh constructed record.
    fields = re.findall(r'\(define \(([^ ]+) nuc\) \(vector-ref nuc (\d+)\)\)', original)
    functions = []
    for base in BASES:
        operations = [name for name, _ in fields if name.startswith(('nuc-', base + '-'))]
        lines = [f'(define (probe-fields-{base})',
                 f'  (let* ((value (make-relative-nuc tfo-id {base})) (alias value)',
                 f'         (getters (nucleic-list {" ".join(operations)})))']
        lines += [f'    (let ((before (nucleic-map (lambda (getter) (getter value)) getters))\n'
                  f'          (replacement (vector {i}.0)))\n'
                  f'      ({name}-set! value replacement)\n'
                  f'      (probe-check (vector-eq? ({name} alias) replacement))\n'
                  f'      (probe-vector ({name} alias))\n'
                  f'      (probe-unmodified-fields getters before alias {i}))'
                  for i, name in enumerate(operations)]
        functions.append('\n'.join(lines) + '))\n')
    transforms = re.findall(r'\(define \((tfo-[^ ]+) tfo\) \(vector-ref tfo (\d+)\)\)', original)
    functions.append('(define (probe-tfo-fields)\n  (let* ((value (vector-copy tfo-id)) (alias value))\n' + ''.join(
        f'    ({name}-set! value {index}.5) (probe-vector alias)\n' for name, index in transforms) + '))\n')
    return (''.join(functions) + '(define (probe-all-fields) (probe-tfo-fields) '
            + ' '.join(f'(probe-fields-{b})' for b in BASES) + ')\n')


def probe_body(original):
    return ('(define probe-database (nucleic-list ' + ' '.join(DATABASE) + '))\n'
            + field_probes(original) + PROBE_COMMON)


def strict_probe(original, adapted, prelude):
    prelude = replace(prelude, '(import (snail strict))', '(import (snail strict) (snail math))')
    return prelude + STRICT_TYPES + COMMON + adapted + STRICT_OBSERVERS + probe_body(original) + '(unit)\n'


def chez_probe(original, adapted=None):
    identity = ('(define (probe-same-nuc? a b) (eq? (nucleotide-fields a) (nucleotide-fields b)))'
                if adapted else '(define probe-same-nuc? eq?)')
    return ('(import (chezscheme))\n' + CHEZ_TYPES + COMMON + (adapted or original)
            + identity + '\n(define probe-same-var? eq?)\n' + CHEZ_OBSERVERS
            + probe_body(original) + '(probe (read))\n')


def float_value(value):
    return float({'+nan.0': 'nan', '-nan.0': 'nan', '+inf.0': 'inf', '-inf.0': '-inf'}.get(value, value))


def same_values(actual, expected, tolerance):
    if len(actual) != len(expected):
        return False
    for (kind, value), (target_kind, target) in zip(actual, expected):
        if kind != target_kind or kind not in ('i', 'f'):
            return False
        if kind == 'i':
            if int(value) != int(target):
                return False
        elif not same_float(float_value(value), float_value(target), tolerance):
            return False
    return True


def same_float(value, target, tolerance):
    if math.isnan(target):
        return math.isnan(value)
    if math.isinf(target):
        return value == target
    if target == 0.0 and value == 0.0:
        return math.copysign(1.0, value) == math.copysign(1.0, target)
    return math.isfinite(value) and math.isclose(value, target, rel_tol=tolerance, abs_tol=tolerance)


# ---- Native execution uses the same scalar Rust implementations ----

NATIVE_HEADER = '''#include <stdint.h>
int32_t barrier(void);
int64_t input_i64(int32_t);
double input_f64(int32_t);
void emit_i64(int64_t);
void emit_f64(double);
void set_expected(double);
'''
NATIVE_PROVIDER = '''#include "native-provider.h"
#include <assert.h>
#include <inttypes.h>
#include <stdio.h>
static double expected = 33.797594890762724;
int32_t barrier(void) { return 1; }
int64_t input_i64(int32_t index) { assert(index == 0); return 0; }
double input_f64(int32_t index) { assert(index == 1); return expected; }
void emit_i64(int64_t value) { printf("i %" PRId64 "\\n", value); }
void emit_f64(double value) { printf("f %.17g\\n", value); }
void set_expected(double value) { expected = value; }
'''
NATIVE_ENTRY = '''#include "native-provider.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void guest_main(void) __asm__("wasm.main");
extern int64_t worker(int64_t) __asm__("wasm.EXPORT");
int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    if (argc > 2) set_expected(strtod(argv[2], NULL));
    guest_main();
    int64_t result = worker(argc > 1 ? strtoll(argv[1], NULL, 10) : 50);
    PRINT
    return native_finish(STATUS);
}
'''


def build_native(directory, environment, driver, probe=False):
    (directory / 'native-provider.h').write_text(NATIVE_HEADER)
    (directory / 'native-provider.c').write_text(NATIVE_PROVIDER)
    entry = NATIVE_ENTRY.replace('EXPORT', 'probe' if probe else 'bench')
    entry = entry.replace('PRINT', '' if probe else 'printf("%" PRId64 "\\n", result);')
    entry = entry.replace('STATUS', 'result == 1 ? 0 : 1' if probe else '0')
    (directory / 'native-entry.c').write_text(entry)
    command = [driver.ROOT / 'scripts/build-native', '--wasm', '--c-provider', 'benchmark',
               directory / 'native-provider.h', directory / 'native-provider.c', '--entry-c',
               directory / 'native-entry.c', directory / 'strict-native.wasm', directory / 'native']
    record = build_record(command, driver.ROOT, environment)
    driver.save(directory / 'native-build.json', record)
    driver.require_success(record)


# ---- Freeze source correspondence before validating complete outputs ----

def source_proof(directory, driver):
    original = (directory / 'original-kernel.scm').read_text()
    adapted, edits = adaptation(original)
    if adapted != (directory / 'adapted-kernel.scm').read_text():
        raise ValueError('Nucleic control kernel differs from the strict kernel')
    numbers = decimal_tokens(original)
    if numbers != decimal_tokens(adapted):
        raise ValueError('Nucleic binary64 literals or their order changed')
    getters = re.findall(r'\(define \(([^ ]+) nuc\) \(vector-ref nuc (\d+)\)\)', original)
    layout = [dict(getter=name, original_index=int(index), strict_index=int(index) - (int(index) > 29))
              for name, index in getters]
    driver.save(directory / 'nucleic-source-proof.json', dict(reversible_edits=edits, fields=layout,
        database=DATABASE, relations=RELATIONS, decimal_literals=len(numbers),
        decimal_token_sha256=hashlib.sha256('\n'.join(numbers).encode()).hexdigest(),
        original_kernel_sha256=hashlib.sha256(original.encode()).hexdigest(),
        adapted_kernel_sha256=hashlib.sha256(adapted.encode()).hexdigest()))


def build_probes(directory, runner, tools, environment, driver):
    original = (directory / 'original-kernel.scm').read_text()
    adapted = (directory / 'adapted-kernel.scm').read_text()
    for label, kernel in [('original', None), ('adapted', adapted)]:
        target = directory / ('probe-' + label)
        target.mkdir()
        (target / 'program.scm').write_text(chez_probe(original, kernel))
        driver.build_chez(target, runner, environment, 'build.json')
    target = directory / 'probe-strict'
    target.mkdir()
    (target / 'strict.scm').write_text(strict_probe(original, adapted, driver.PRELUDE))
    (target / 'runtime.wasm').write_bytes((directory / 'runtime.wasm').read_bytes())
    driver.save(target / 'spec.json', dict(name='nucleic', export='probe'))
    driver.build_strict(target, tools, environment)
    build_native(target, environment, driver, probe=True)


def probe_execution(directory, system, command, tools, environment, driver):
    if system in ('original', 'adapted'):
        target = directory / ('probe-' + system)
        return driver.execute([tools['CHEZ'], '--program', target / 'program.so'], target, environment, stdin=str(command) + '\n')
    target = directory / 'probe-strict'
    if system == 'native':
        return driver.execute([target / 'native', command], target, environment)
    spec = dict(name='nucleic-probe', export='probe', command=command, count=1, inputs=[],
                expected=1, barriers_per_iteration=0, setup_barriers=0)
    driver.save(target / f'spec-{command}.json', spec)
    suffix = '.raw.wasm' if system == 'raw' else ''
    return driver.execute([tools['NODE'], '--disable-warning=ExperimentalWarning', directory.parent / 'nucleic-host.mjs',
        target / ('strict.wasm' + suffix), target / f'spec-{command}.json', '--validate'], target, environment)


def probe_values(record, system):
    if system in ('raw', 'optimized'):
        return json.loads(record['stdout'])['values']
    values = [line.split() for line in record['stdout'].splitlines()]
    if any(len(row) != 2 or row[0] not in ('i', 'f') for row in values):
        raise ValueError('unexpected complete-value probe output')
    return values


def validate_probe(directory, command, tools, environment, driver):
    records, expected = [], None
    tolerance = 0.0 if command in (0, 4) else 1e-11
    for system in ('original', 'adapted', 'raw', 'optimized', 'native'):
        record = probe_execution(directory, system, command, tools, environment, driver)
        records.append(dict(record, system=system, tolerance=tolerance))
        driver.save(directory / f'probe-{command}.json', records)
        driver.require_success(record)
        actual = probe_values(record, system)
        expected = actual if expected is None else expected
        if record['stderr'] or not same_values(actual, expected, tolerance):
            raise ValueError(f'Nucleic complete values/order differ: command {command}, {system}')
    validate_comparator(expected, tolerance)
    return dict(command=command, observations=len(expected),
                original_sha256=hashlib.sha256(json.dumps(expected).encode()).hexdigest())


def validate_comparator(expected, tolerance):
    variants = [expected[:-1], expected + [expected[0]]]
    for kind in ('i', 'f'):
        positions = [index for index, row in enumerate(expected) if row[0] == kind]
        if positions:
            index = positions[0]
            changed = [*expected]
            changed[index] = [kind, str(float_value(expected[index][1]) + 1.0) if kind == 'f'
                              else str(int(expected[index][1]) + 1)]
            variants.append(changed)
    first = next((index for index, row in enumerate(expected) if row != expected[0]), None)
    if first is not None:
        changed = [*expected]
        changed[0], changed[first] = changed[first], changed[0]
        variants.append(changed)
    if any(same_values(changed, expected, tolerance) for changed in variants):
        raise ValueError('Nucleic complete-value comparator accepted a damaged trace')


def validate_native(directory, tools, environment, driver):
    build_native(directory, environment, driver)
    checks = []
    for count in (1, 2, 50):
        record = driver.execute([directory / 'native', count], directory, environment)
        checks.append(dict(record, count=count))
        driver.save(directory / 'native-validation.json', checks)
        driver.require_success(record)
        if record['stdout'] != '1\n' or record['stderr']:
            raise ValueError('Nucleic native result predicate failed')


def predicate_fixtures():
    return [('zero', 0, 33.797594890762724, False), ('negative', -1, 33.797594890762724, False),
            ('wrong-expected', 1, 30.0, False), ('within-ratio', 1, 33.79760, True),
            ('outside-low-ratio', 1, 33.7977, False), ('outside-high-ratio', 1, 33.7975, False)]


def validate_predicates(directory, runner, tools, environment, driver):
    checks, canonical = [], driver.load(directory / 'spec.json')
    for label, count, expected, accepted in predicate_fixtures():
        spec = dict(canonical, count=count, inputs=[0, expected], expected=int(accepted))
        path = directory / ('predicate-' + label + '.json')
        driver.save(path, spec)
        for system in ('original', 'adapted', 'raw', 'optimized', 'native'):
            record = predicate_execution(directory, system, spec, path, tools, environment, driver)
            checks.append(dict(record, system=system, label=label, accepted=accepted))
            driver.save(directory / 'predicate-validation.json', checks)
            driver.require_success(record)
            actual = (runner.parse_result(record['stdout'], 'chez', 'nucleic')['status'] == 'ok'
                      if system in ('original', 'adapted') else record['stdout'] == '1\n'
                      if system == 'native' else json.loads(record['stdout'])['result'] == '1')
            if record['stderr'] or actual != accepted:
                raise ValueError('Nucleic numeric predicate or initial-false behavior changed')


def predicate_execution(directory, system, spec, path, tools, environment, driver):
    if system in ('original', 'adapted'):
        target = directory if system == 'original' else directory / 'same-source-chez'
        data = f'{spec["count"]}\n()\n{spec["inputs"][1]}\n'
        return driver.execute([tools['CHEZ'], '--program', target / 'program.so'], target, environment, stdin=data)
    if system == 'native':
        return driver.execute([directory / 'native', spec['count'], spec['inputs'][1]], directory, environment)
    suffix = '.raw.wasm' if system == 'raw' else ''
    return driver.execute([tools['NODE'], '--disable-warning=ExperimentalWarning', directory.parent / 'nucleic-host.mjs',
        directory / ('strict.wasm' + suffix), path, '--validate'], directory, environment)


def validate_outputs(directory, runner, tools, environment, driver):
    source_proof(directory, driver)
    validate_native(directory, tools, environment, driver)
    build_probes(directory, runner, tools, environment, driver)
    summaries = [validate_probe(directory, command, tools, environment, driver) for command in range(7)]
    driver.save(directory / 'probe-summary.json', summaries)
    validate_predicates(directory, runner, tools, environment, driver)
