"""Preserve the original random bytes, UTF-8 roundtrips and failure diagnostics."""

import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import struct
import subprocess
import time

from data_ports import form, replace
from string_port import exact_json_integer, i64


# ---- Scalar inputs and the original positive-count result predicate ----


def specification(data):
    tokens = re.sub(r';[^\n]*', '', data.decode()).split()
    if len(tokens) != 4:
        raise ValueError('bv2string requires count, stress tests, maximum size and expected failures')
    count, tests, maximum, expected = map(i64, tokens)
    return dict(name='bv2string', count=exact_json_integer(count),
                inputs=list(map(exact_json_integer, (tests, maximum, expected))),
                original_expected=expected, expected=1, setup_barriers=0,
                barriers_per_iteration=2, predicate='original numeric failure-count equality')


WORKER = '''(let loop ((i 0) (result 0))
  (if (< i count)
      (begin
        (string-bytevector-tests (hide count input0) (hide count input1))
        (loop (+ i 1) (length (ref-get failed-tests))))
      (if (and (> i 0) (= result input2)) 1 0)))'''


# ---- Exact integer rounding and typed diagnostic output ----

COMMON = '''(: bv-same-bool? (-> Bool Bool Bool))
(define (bv-same-bool? actual expected) (if actual expected (not expected)))
(define (bv-zero? value) (= value 0))
(define (bv-odd? value) (not (= (remainder value 2) 0)))
;; The generator supplies a nonnegative integer. Rational round(n/4) chooses
;; the even quotient at a tie: 2 -> 0, 6 -> 2, 10 -> 2, 14 -> 4.
(define (bv-round-quarter value)
  (let ((whole (quotient value 4)) (part (remainder value 4)))
    (if (or (> part 2) (and (= part 2) (bv-odd? whole))) (+ whole 1) whole)))
'''
DIAGNOSTICS = '''(define-extern bv-write-character "benchmark" "write_character" (-> Char Unit))
(: bv-display (-> String Unit))
(define (bv-display text)
  (let loop ((index 0))
    (unless (= index (string-length text))
      (bv-write-character (string-ref text index))
      (loop (+ index 1)))))
(define (bv-newline) (bv-write-character #\\newline))
'''
CONTRACTS = '''(: test (-> String Bool Bool Unit))
(: string-bytevector-tests (-> I64 I64 Unit))
'''
CHEZ_BOUNDARY = '''(define-syntax : (syntax-rules () ((_ . signature) (begin))))
(define-syntax ann (syntax-rules () ((_ value type) value)))
(define (ref value) (vector value))
(define (ref-get cell) (vector-ref cell 0))
(define (ref-set! cell value) (vector-set! cell 0 value))
(define (unit) (if #f #f))
(define bv-display display)
(define bv-newline newline)
'''


def adaptation(source):
    edits = [
        ("(define failed-tests '())", "(define failed-tests (ref (ann '() (List String))))", 1),
        ('(equal? actual expected)', '(bv-same-bool? actual expected)', 1),
        ('(display ', '(bv-display ', 2), ('(newline)', '(bv-newline)', 1),
        ('(set! failed-tests (cons name failed-tests))',
         '(ref-set! failed-tests (cons name (ref-get failed-tests)))', 1),
        ('(x 1)', '(x (ref 1))', 1),
        ('(set! x (remainder (+ (* a x) c) (+ m 1)))',
         '(ref-set! x (remainder (+ (* a (ref-get x)) c) (+ m 1)))', 1),
        ('(quotient x 8)', '(quotient (ref-get x) 8)', 1),
        ('(zero? ', '(bv-zero? ', 1), ('(odd? ', '(bv-odd? ', 1),
        ('(round (/ n 4))', '(bv-round-quarter n)', 1),
        ('((= i *random-stress-tests*))', '((= i *random-stress-tests*) (unit))', 1),
    ]
    adapted = source
    for before, after, count in edits:
        adapted = replace(adapted, before, after, count)
    restored = adapted
    for before, after, count in reversed(edits):
        restored = replace(restored, after, before, count)
    if restored != source:
        raise ValueError('bv2string edits did not restore the complete original kernel')
    return CONTRACTS + adapted, [dict(before=b, after=a, count=c) for b, a, c in edits]


def kernel(source):
    return adaptation(source)[0]


def adapt_chez_harness(source, reverse=False):
    before, after = '(length failed-tests)', '(length (ref-get failed-tests))'
    return replace(source, after if reverse else before, before if reverse else after)


# ---- Every preparation child belongs to a bounded process group ----


def execute(command, cwd, environment, timeout=300, stdin=None):
    started, command = time.perf_counter(), list(map(str, command))
    try:
        child = subprocess.Popen(command, cwd=cwd, env=environment, text=True,
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, start_new_session=True)
    except OSError as error:
        return dict(command=command, error=str(error), process_seconds=time.perf_counter() - started)
    return finish_process(child, command, started, timeout, stdin)


def finish_process(child, command, started, timeout, stdin):
    expired = False
    try:
        stdout, stderr = child.communicate(stdin, timeout=timeout)
    except subprocess.TimeoutExpired:
        expired = True
        kill_process_group(child)
        stdout, stderr = child.communicate(timeout=10)
    finally:
        # A successful leader can leave a child that has closed both pipes.
        kill_process_group(child)
    return dict(command=command, returncode=child.returncode, stdout=stdout, stderr=stderr,
                timeout=expired, process_seconds=time.perf_counter() - started)


def kill_process_group(child):
    try:
        os.killpg(child.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


# ---- Complete observations of RNG transitions and all four buffers ----

OBSERVERS = '''(define probe-mode (ref 0))
(define (bv-observe-random state value)
  (bv-observe 0) (bv-observe state) (bv-observe value) value)
(define (bv-observe-bytes tag bytes)
  (bv-observe tag) (bv-observe (bytevector-length bytes))
  (let loop ((index 0))
    (unless (= index (bytevector-length bytes))
      (bv-observe (bytevector-u8-ref bytes index)) (loop (+ index 1)))) bytes)
(define (bv-observe-string tag text)
  (bv-observe tag) (bv-observe (string-length text))
  (let loop ((index 0))
    (unless (= index (string-length text))
      (bv-observe (char->integer (string-ref text index))) (loop (+ index 1)))) text)
(define (bv-ascii)
  (let ((bytes (make-bytevector 128)))
    (let loop ((index 0))
      (if (= index 128) bytes
          (begin (bytevector-u8-set! bytes index index) (loop (+ index 1)))))))
(define (bv-observe-failures names)
  (bv-observe 7) (bv-observe (length names))
  (let loop ((names names))
    (unless (null? names)
      (bv-observe-string 8 (car names)) (loop (cdr names)))))
'''
PROBE_DRIVER = '''  (define (probe-generate maximum)
    (if (= (ref-get probe-mode) 1) (random-bytevector2 maximum)
        (if (= (ref-get probe-mode) 2) (random-bytevector4 maximum)
            (random-bytevector maximum))))
  (if (= (ref-get probe-mode) 3)
      (do ((i 0 (+ i 1))) ((= i *random-stress-tests*) (unit))
        (let ((value (random *random-stress-test-max-size*)))
          (bv-observe 5) (bv-observe value)))
      (if (= (ref-get probe-mode) 6)
          (test-roundtrip (bv-ascii) utf8->string string->utf8)
          (begin
            (test-roundtrip (probe-generate 10) utf8->string string->utf8)
            (do ((i 0 (+ i 1))) ((= i *random-stress-tests*) (unit))
              (test-roundtrip (probe-generate *random-stress-test-max-size*)
                              utf8->string string->utf8)))))'''
PROBE_ENTRY = '''(define (bv-probe-rounding count)
  (let loop ((value 0))
    (unless (= value count)
      (bv-observe 6) (bv-observe value) (bv-observe (bv-round-quarter value))
      (loop (+ value 1)))))
(define (bv-probe-failures)
  (test "first\\x0;λ" (string=? "left" "right") #t)
  (test "truth" #t #t)
  (test "second😀" (string=? "same" "same") #f)
  (test "false" #f #f))
(: probe (-> I64 I64 I64 I64))
(define (probe mode tests maximum)
  (ref-set! probe-mode mode)
  (if (= mode 4) (bv-probe-rounding tests)
      (if (= mode 5) (bv-probe-failures)
          (begin
            (string-bytevector-tests tests maximum)
            (when (= mode 7) (string-bytevector-tests tests maximum)))))
  (bv-observe-failures FAILURE_NAMES)
  (length FAILURE_NAMES))
'''
FAILURE_DIAGNOSTICS = ('******** FAILED TEST ******** first\0λ\n'
                       '******** FAILED TEST ******** second😀\n')


def observed_kernel(source, adapted):
    state = '(ref-get x)' if adapted else 'x'
    rng = f'(remainder (quotient {state} 8) n)'
    source = replace(source, rng, f'(bv-observe-random {state} {rng})')
    source = replace(source, '((s1 (tostring bvec))',
                     '((observed (bv-observe-bytes 1 bvec))\n'
                     '           (s1 (bv-observe-string 2 (tostring observed)))')
    source = replace(source, '(b2 (tobvec s1))', '(b2 (bv-observe-bytes 3 (tobvec s1)))')
    source = replace(source, '(s2 (tostring b2))', '(s2 (bv-observe-string 4 (tostring b2)))')
    begin = source.index('  (test-roundtrip (random-bytevector 10)')
    return source[:begin] + PROBE_DRIVER + '\n\n  )\n'


def probe_entry(adapted):
    names = '(ref-get failed-tests)' if adapted else 'failed-tests'
    result = PROBE_ENTRY.replace('FAILURE_NAMES', names)
    return result if adapted else result.replace('(bv-round-quarter value)', '(round (/ value 4))')


def strict_probe(source, prelude):
    prelude = replace(prelude, '(import (snail strict))', '(import (snail strict) (snail bytes))')
    observer = '(define-extern bv-observe "benchmark" "observe" (-> I64 Unit))\n'
    return prelude + COMMON + DIAGNOSTICS + observer + OBSERVERS + observed_kernel(source, True) + probe_entry(True) + '(unit)\n'


CHEZ_OBSERVER = '''(define probe-output (open-file-output-port (cadr (command-line))
                      (file-options no-fail) (buffer-mode block)))
(define (bv-observe value)
  (do ((shift 0 (+ shift 8))) ((= shift 32))
    (put-u8 probe-output (bitwise-and (bitwise-arithmetic-shift-right value shift) 255))))
'''


def chez_probe(source, adapted):
    helpers = CHEZ_BOUNDARY + COMMON if adapted else CHEZ_BOUNDARY
    ending = '''(let* ((mode (read)) (tests (read)) (maximum (read))
                  (result (probe mode tests maximum)))
  (close-port probe-output) (display result) (newline))\n'''
    return ('(import (chezscheme))\n' + helpers + CHEZ_OBSERVER + OBSERVERS
            + observed_kernel(source, adapted) + probe_entry(adapted) + ending)


# ---- Independent integer stream and complete-byte oracles ----


def fixtures():
    return [('canonical-stream', 0, 1000, 1000), ('sanity-only', 0, 0, 1000),
            ('small', 0, 15, 20), ('even', 1, 70, 19), ('multiple-of-four', 2, 70, 19),
            *[(f'rng-{limit}', 3, 9, limit) for limit in (16383, 16384, 16385, 268435457)],
            ('rounding-all-canonical-lengths', 4, 1040, 1), ('failure-diagnostics', 5, 0, 1),
            ('all-ascii', 6, 0, 1), ('repeat-resets-rng', 7, 20, 33)]


def rounded_quarter(value):
    whole, part = divmod(value, 4)
    return whole + int(part > 2 or (part == 2 and whole % 2 == 1))


class StreamOracle:
    def __init__(self):
        self.state, self.values, self.generated = 1, [], []

    def random14(self, bound):
        self.state = (701 * self.state + 743483) % 524288
        value = (self.state // 8) % bound
        self.values.extend((0, self.state, value))
        return value

    def random(self, bound):
        if bound < 16384:
            return self.random14(bound)
        remaining, result = bound // 16384, self.random14(16384)
        while remaining:
            remaining //= 16384
            result = 16384 * result + self.random14(16384)
        return result % bound

    def bytevector(self, bound, mode):
        length = self.random(bound)
        if mode == 1:
            length += length % 2
        if mode == 2:
            length = 4 * rounded_quarter(length)
        result = [self.random(128) for _ in range(length)]
        self.generated.append(result)
        return result

    def roundtrip(self, values):
        first = bytes(values).decode('utf-8')
        copied = first.encode('utf-8')
        second = copied.decode('utf-8')
        for tag, data in ((1, values), (2, list(map(ord, first))),
                          (3, list(copied)), (4, list(map(ord, second)))):
            self.values.extend((tag, len(data), *data))
        assert first == second


def oracle(case):
    label, mode, tests, maximum = case
    stream = StreamOracle()
    if mode == 3:
        for _ in range(tests):
            value = stream.random(maximum)
            stream.values.extend((5, value))
    elif mode == 4:
        for value in range(tests):
            stream.values.extend((6, value, rounded_quarter(value)))
    elif mode == 6:
        stream.roundtrip(list(range(128)))
    elif mode != 5:
        for _ in range(2 if mode == 7 else 1):
            stream.state = 1
            for bound in [10] + [maximum] * tests:
                stream.roundtrip(stream.bytevector(bound, mode))
        if mode == 0:
            assert stream.generated[0] == [42, 16, 6, 43, 36, 0, 21]
    names = ['second😀', 'first\0λ'] if mode == 5 else []
    stream.values.extend((7, len(names)))
    for name in names:
        stream.values.extend((8, len(name), *map(ord, name)))
    return stream, b''.join(struct.pack('<I', value) for value in stream.values)


PROBE_HOST = '''import fs from 'node:fs';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
const [artifact, expectedPath, mode, tests, maximum] = process.argv.slice(2);
const expected = fs.readFileSync(expectedPath);
let cursor = 0, diagnostics = '';
const imports = {benchmark: {
  observe: value => {
    assert.ok(cursor + 4 <= expected.length, 'unexpected trailing observation');
    assert.equal(value, BigInt(expected.readUInt32LE(cursor)), `observation ${cursor / 4}`);
    cursor += 4;
  },
  write_character: scalar => { diagnostics += String.fromCodePoint(scalar); },
}};
const {instance} = await WebAssembly.instantiate(fs.readFileSync(artifact), imports);
instance.exports.main();
const result = instance.exports.probe(BigInt(mode), BigInt(tests), BigInt(maximum));
assert.equal(cursor, expected.length, 'missing observation');
console.log(JSON.stringify({result: Number(result), diagnostics, values: cursor / 4,
  sha256: crypto.createHash('sha256').update(expected).digest('hex')}));
'''


# ---- The optimized Wasm also enters the actual native backend ----

NATIVE_HEADER = '''#include <stdint.h>
int64_t input_i64(int32_t);
int64_t hide_i64(int64_t);
void write_character(uint32_t);
void observe(int64_t);
'''
NATIVE_PROVIDER = '''#include "native-provider.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
static uint64_t barriers, observations;
static FILE *expected;
int64_t input_i64(int32_t index) {
    static const int64_t inputs[] = {INPUT_VALUES};
    assert(index >= 0 && index < 3);
    return inputs[index];
}
int64_t hide_i64(int64_t value) { barriers++; return value; }
uint64_t barrier_count(void) { return barriers; }
void write_character(uint32_t value) {
    if (value < 128) { putchar(value); return; }
    unsigned width = value < 2048 ? 2 : value < 65536 ? 3 : 4;
    unsigned first[] = {0, 0, 192, 224, 240};
    putchar(first[width] | (value >> (6 * (width - 1))));
    for (unsigned index = width - 1; index; index--)
        putchar(128 | ((value >> (6 * (index - 1))) & 63));
}
void observation_file(const char *path) {
    expected = fopen(path, "rb"); assert(expected);
}
void observe(int64_t actual) {
    unsigned char bytes[4];
    size_t size = fread(bytes, 1, 4, expected);
    uint32_t value = size == 4 ? ((uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8)
                      | ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24)) : 0;
    if (size != 4 || actual != value) {
        fprintf(stderr, "observation %llu: actual %lld, expected %u, bytes %zu\\n",
                (unsigned long long)observations, (long long)actual, value, size);
        exit(80);
    }
    observations++;
}
uint64_t observation_count(void) {
    assert(fgetc(expected) == EOF); fclose(expected); return observations;
}
'''
NATIVE_ENTRY = '''#include "native-provider.h"
#include <assert.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern void guest_main(void) __asm__("wasm.main");
void observation_file(const char *);
uint64_t observation_count(void);
uint64_t barrier_count(void);
EXPORT
int main(int argc, char **argv) {
    native_host_init(argc, argv); native_module_init(); guest_main();
    INVOKE
    return native_finish(0);
}
'''
NATIVE_BENCH = '''extern int64_t bench(int64_t) __asm__("wasm.bench");'''
NATIVE_BENCH_INVOKE = '''int64_t count = argc == 2 ? strtoll(argv[1], NULL, 10) : 100;
    struct timespec before, after;
    assert(clock_gettime(CLOCK_MONOTONIC, &before) == 0);
    int64_t result = bench(count);
    assert(clock_gettime(CLOCK_MONOTONIC, &after) == 0);
    double seconds = (double)(after.tv_sec - before.tv_sec) + (double)(after.tv_nsec - before.tv_nsec) / 1e9;
    printf("{\\"result\\":%" PRId64 ",\\"barriers\\":%" PRIu64 ",\\"seconds\\":%.9f}\\n", result, barrier_count(), seconds);'''
NATIVE_PROBE = '''extern int64_t probe(int64_t, int64_t, int64_t) __asm__("wasm.probe");'''
NATIVE_PROBE_INVOKE = '''if (argc != 5) return 81;
    observation_file(argv[1]);
    int64_t result = probe(strtoll(argv[2], NULL, 10), strtoll(argv[3], NULL, 10), strtoll(argv[4], NULL, 10));
    printf("{\\"result\\":%" PRId64 ",\\"values\\":%" PRIu64 "}\\n", result, observation_count());'''


def build_native(directory, tools, environment, driver, probe=False, count_barriers=True):
    inputs = driver.load(directory / 'spec.json').get('inputs', [0, 0, 0])
    provider = NATIVE_PROVIDER if count_barriers else NATIVE_PROVIDER.replace('barriers++; ', '')
    (directory / 'native-provider.h').write_text(NATIVE_HEADER)
    (directory / 'native-provider.c').write_text(provider.replace('INPUT_VALUES', ', '.join(map(str, inputs))))
    entry = NATIVE_ENTRY.replace('EXPORT', NATIVE_PROBE if probe else NATIVE_BENCH)
    (directory / 'native-entry.c').write_text(entry.replace('INVOKE', NATIVE_PROBE_INVOKE if probe else NATIVE_BENCH_INVOKE))
    command = [driver.ROOT / 'scripts/build-native', '--wasm', '--c-provider', 'benchmark',
               directory / 'native-provider.h', directory / 'native-provider.c', '--entry-c',
               directory / 'native-entry.c', directory / 'strict.wasm', directory / 'native']
    record = execute(command, driver.ROOT, environment, timeout=600)
    driver.save(directory / 'native-build.json', record)
    driver.require_success(record)


# ---- Build separate observations without changing the measured kernel ----


def build_probes(directory, runner, tools, environment, driver):
    for adapted in (False, True):
        target = directory / ('probe-adapted' if adapted else 'probe-original')
        target.mkdir()
        source = (directory / ('adapted-kernel.scm' if adapted else 'original-kernel.scm')).read_text()
        (target / 'program.scm').write_text(chez_probe(source, adapted))
        driver.build_chez(target, runner, environment, 'build.json')
    target = directory / 'probe-strict'
    target.mkdir()
    (target / 'strict.scm').write_text(strict_probe((directory / 'adapted-kernel.scm').read_text(), driver.PRELUDE))
    (target / 'host.mjs').write_text(PROBE_HOST)
    driver.save(target / 'spec.json', dict(name='bv2string-probe', export='probe'))
    driver.build_strict(target, tools, environment)
    build_native(target, tools, environment, driver, probe=True)


def probe_command(directory, system, tools, oracle_path, case):
    _, mode, tests, maximum = case
    if system == 'native':
        return [directory / 'probe-strict/native', oracle_path, mode, tests, maximum], None
    if system in ('raw', 'optimized'):
        suffix = '.raw.wasm' if system == 'raw' else ''
        target = directory / 'probe-strict'
        return [tools['NODE'], target / 'host.mjs', target / ('strict.wasm' + suffix),
                oracle_path, mode, tests, maximum], None
    target = directory / ('probe-' + system)
    return [tools['CHEZ'], '--program', target / 'program.so', target / 'observed.bin'], f'{mode}\n{tests}\n{maximum}\n'


def check_probe(record, directory, system, expected, case):
    failure = case[1] == 5
    diagnostics, result = (FAILURE_DIAGNOSTICS, 2) if failure else ('', 0)
    if record['stderr']:
        raise ValueError('unexpected probe stderr in ' + system)
    if system in ('original', 'adapted'):
        actual = (directory / ('probe-' + system) / 'observed.bin').read_bytes()
        if actual != expected or record['stdout'] != diagnostics + str(result) + '\n':
            raise ValueError('complete byte/character stream or failure diagnostics differ in ' + system)
    else:
        text = record['stdout'] if system != 'native' else record['stdout'].removeprefix(diagnostics)
        observed = json.loads(text)
        if observed['result'] != result or observed['values'] != len(expected) // 4:
            raise ValueError('wrong failure count or observed stream length in ' + system)
        if system != 'native' and observed['diagnostics'] != diagnostics:
            raise ValueError('lost or changed diagnostic text in ' + system)
        if system == 'native' and record['stdout'] != diagnostics + text:
            raise ValueError('lost native diagnostic text')


def validate_case(directory, case, tools, environment, driver, records):
    stream, expected = oracle(case)
    path = directory / (case[0] + '.bin')
    path.write_bytes(expected)
    for system in ('original', 'adapted', 'raw', 'optimized', 'native'):
        command, stdin = probe_command(directory, system, tools, path, case)
        record = execute(command, directory, environment, stdin=stdin)
        records.append(dict(label=case[0], system=system, parameters=case[1:], execution=record,
                            expected_sha256=hashlib.sha256(expected).hexdigest(), values=len(stream.values)))
        driver.save(directory / 'complete-stream-validation.json', records)
        driver.require_success(record)
        check_probe(record, directory, system, expected, case)
    (directory / (case[0] + '.bin.gz')).write_bytes(gzip.compress(expected, mtime=0))
    path.unlink()


def validate_native_canonical(directory, tools, environment, driver):
    build_native(directory, tools, environment, driver)
    records = []
    for count in (1, 2, int(driver.load(directory / 'spec.json')['count'])):
        record = execute([directory / 'native', count], directory, environment)
        records.append(dict(count=count, execution=record))
        driver.save(directory / 'native-validation.json', records)
        driver.require_success(record)
        value = json.loads(record['stdout'])
        if record['stderr'] or value['result'] != 1 or value['barriers'] != 2 * count or value['seconds'] < 0:
            raise ValueError('native canonical input or opacity count differs')


def prepare_native_timing(directory, tools, environment, driver):
    target = directory / 'timing-native'
    target.mkdir()
    for name in ('strict.wasm', 'spec.json'):
        shutil.copy2(directory / name, target / name)
    build_native(target, tools, environment, driver, count_barriers=False)
    record = execute([target / 'native', driver.load(target / 'spec.json')['count']], target, environment)
    driver.save(target / 'canonical-validation.json', record)
    driver.require_success(record)
    result = json.loads(record['stdout'])
    if record['stderr'] or result['result'] != 1 or result['barriers'] != 0:
        raise ValueError('native timing artifact failed full-count validation')
    before, after = (directory / 'native-provider.c').read_text(), (target / 'native-provider.c').read_text()
    if replace(after, 'int64_t hide_i64(int64_t value) { return value; }',
               'int64_t hide_i64(int64_t value) { barriers++; return value; }') != before:
        raise ValueError('native timing provider differs beyond barrier counting')


def retain_native_toolchain(directory, tools, environment, driver):
    records = {}
    for name, command in (('rust', ['rustc', '--version', '--verbose']), ('cargo', ['cargo', '--version']),
                          ('clang', ['clang', '--version']), ('lld', ['ld.lld', '--version'])):
        path = shutil.which(command[0])
        record = execute([path, *command[1:]], driver.ROOT, environment)
        records[name] = dict(record, path=path, sha256=driver.digest(path))
        driver.save(directory / 'native-toolchain.json', records)
        driver.require_success(record)
    driver.freeze_fft_toolchain(directory, tools['RUSTC'], environment, prefix='rust-reference')
    record = execute([tools['RUSTC'], '--print', 'target-libdir'], driver.ROOT, environment)
    driver.require_success(record)
    library = Path(record['stdout'].strip())
    driver.save(directory / 'native-rust-libraries.json', dict(query=record,
                files={str(path): driver.digest(path) for path in library.rglob('*') if path.is_file()}))


# ---- Rust retains its UTF-8 String storage and original three allocations ----

RUST_OBSERVERS = '''thread_local! {
    static OBSERVED: std::cell::RefCell<Vec<u32>> = const { std::cell::RefCell::new(Vec::new()) };
}
fn observe_numbers(values: &[u32]) {
    OBSERVED.with_borrow_mut(|output| output.extend_from_slice(values));
}
fn observe_bytes(tag: u32, values: &[u8]) {
    observe_numbers(&[tag, values.len() as u32]);
    OBSERVED.with_borrow_mut(|output| output.extend(values.iter().map(|&value| value as u32)));
}
fn observe_text(tag: u32, text: &str) {
    observe_numbers(&[tag, text.chars().count() as u32]);
    OBSERVED.with_borrow_mut(|output| output.extend(text.chars().map(|value| value as u32)));
}
'''
RUST_PROBE_MAIN = '''fn main() -> std::io::Result<()> {
    let args: Vec<_> = std::env::args().collect();
    let result = run(args[2].parse().unwrap(), args[3].parse().unwrap());
    observe_numbers(&[7, result as u32]);
    let observed = OBSERVED.with_borrow(|values| values.iter().flat_map(|value| value.to_le_bytes()).collect::<Vec<_>>());
    assert_eq!(observed, std::fs::read(&args[1])?);
    println!("{{\\"result\\":{result},\\"values\\":{}}}", observed.len() / 4);
    Ok(())
}
'''


def rust_probe(source):
    begin, end = source.index('fn main()'), source.index('// ---- Tests ----')
    edits = [
        (source[begin:end], RUST_OBSERVERS + RUST_PROBE_MAIN + '\n'),
        ('        (self.x / 8) % n',
         '        let value = (self.x / 8) % n;\n'
         '        observe_numbers(&[0, self.x as u32, value as u32]);\n        value'),
        ('    let first = std::str::from_utf8(&bytes).unwrap().to_owned();',
         '    observe_bytes(1, &bytes);\n'
         '    let first = std::str::from_utf8(&bytes).unwrap().to_owned();\n    observe_text(2, &first);'),
        ('    let copied = first.as_bytes().to_vec();',
         '    let copied = first.as_bytes().to_vec();\n    observe_bytes(3, &copied);'),
        ('    let second = std::str::from_utf8(&copied).unwrap().to_owned();',
         '    let second = std::str::from_utf8(&copied).unwrap().to_owned();\n    observe_text(4, &second);'),
    ]
    observed = source
    for before, after in edits:
        observed = replace(observed, before, after)
    restored = observed
    for before, after in reversed(edits):
        restored = replace(restored, after, before)
    if restored != source:
        raise ValueError('Rust observations did not restore the complete reference')
    return observed, [dict(before=before, after=after, count=1) for before, after in edits]


def prepare_rust_reference(directory, environment, driver):
    original = driver.ROOT / 'benchmarks/wasm-reference'
    target = directory / 'rust-reference'
    shutil.copytree(original / 'src', target / 'src')
    for name in ('Cargo.toml', 'Cargo.lock'):
        shutil.copy2(original / name, target / name)
    source = (target / 'src/bin/bv2string.rs').read_text()
    probe, edits = rust_probe(source)
    (target / 'src/bin/bv2string-probe.rs').write_text(probe)
    driver.save(target / 'reversible-probe-edits.json', dict(edits=edits, restored_original=True))
    build_rust_reference(target, environment, driver)
    return target


def build_rust_reference(target, environment, driver):
    environment = {**environment, 'CARGO_TARGET_DIR': str(target / 'target')}
    commands = [('tests', ['test', '--offline', '--bin', 'bv2string']),
                ('build', ['rustc', '--offline', '--release', '--bin', 'bv2string', '--', '--emit=asm,llvm-ir']),
                ('probe-build', ['build', '--offline', '--release', '--bin', 'bv2string-probe'])]
    for label, arguments in commands:
        record = execute(['cargo', *arguments], target, environment, timeout=600)
        driver.save(target / (label + '.json'), record)
        driver.require_success(record)
    record = execute([target / 'target/release/bv2string'], target, environment,
                     stdin=(target.parent / 'input.txt').read_text())
    driver.save(target / 'canonical-validation.json', record)
    driver.require_success(record)
    if record['stderr'] or not record['stdout'].startswith('Result: 0\n'):
        raise ValueError('Rust canonical result differs')


def validate_rust_stream(directory, target, environment, driver):
    case = fixtures()[0]
    stream, expected = oracle(case)
    path = directory / 'rust-canonical-stream.bin'
    path.write_bytes(expected)
    record = execute([target / 'target/release/bv2string-probe', path, case[2], case[3]], target, environment)
    driver.save(target / 'complete-stream-validation.json', dict(execution=record,
                expected_sha256=hashlib.sha256(expected).hexdigest(), values=len(stream.values)))
    driver.require_success(record)
    if record['stderr'] or json.loads(record['stdout']) != dict(result=0, values=len(stream.values)):
        raise ValueError('Rust generated bytes or conversion buffers differ')
    path.unlink()


def build_rust_wasm(target, tools, environment, driver):
    environment = {**environment, 'CARGO_TARGET_DIR': str(target / 'target')}
    arguments = ['--offline', '--release', '--target', 'wasm32-wasip1']
    for name in ('bv2string', 'bv2string-probe'):
        record = execute(['cargo', 'rustc', *arguments, '--bin', name, '--', '--emit=llvm-ir'],
                         target, environment, timeout=600)
        driver.save(target / (name + '-wasm-build.json'), record)
        driver.require_success(record)
        raw = target / (name + '.raw.wasm')
        shutil.copy2(target / ('target/wasm32-wasip1/release/' + name + '.wasm'), raw)
        optimize_rust_wasm(target, name, tools, environment, driver)
    shutil.copy2(driver.ROOT / 'benchmarks/wasm-reference/run-wasi.mjs', target / 'run-wasi.mjs')


# Match the established Rust/WASI pipeline and this toolchain's target_features.
# --all-features also permits compact imports, which the pinned V8 cannot read.
RUST_WASM_FEATURES = ['--mvp-features', '--enable-mutable-globals',
    '--enable-nontrapping-float-to-int', '--enable-bulk-memory', '--enable-sign-ext',
    '--enable-reference-types', '--enable-multivalue', '--enable-extended-const',
    '--enable-bulk-memory-opt', '--enable-call-indirect-overlong']


def optimize_rust_wasm(target, name, tools, environment, driver):
    output = target / (name + '.wasm')
    command = [tools['WASM_OPT'], '-O3', '-g', *RUST_WASM_FEATURES,
               target / (name + '.raw.wasm'), '-o', output]
    record = execute(command, target, environment)
    driver.save(target / (name + '-wasm-optimize.json'), record)
    driver.require_success(record)
    record = execute([tools['WASM_DIS'], output, '-o', target / (name + '.wat')], target, environment)
    driver.save(target / (name + '-wasm-disassemble.json'), record)
    driver.require_success(record)


def validate_rust_wasm(directory, target, tools, environment, driver):
    _, expected = oracle(fixtures()[0])
    path = target / 'canonical-stream.bin'
    path.write_bytes(expected)
    records = []
    for suffix in ('.raw.wasm', '.wasm'):
        command = [tools['NODE'], '--disable-warning=ExperimentalWarning', target / 'run-wasi.mjs']
        record = execute([*command, target / ('bv2string' + suffix)], target, environment,
                         stdin=(directory / 'input.txt').read_text())
        records.append(dict(kind='canonical', module_suffix=suffix, execution=record))
        driver.save(target / 'wasm-validation.json', records)
        driver.require_success(record)
        if record['stderr'] or not record['stdout'].startswith('Result: 0\n'):
            raise ValueError('Rust/WASI canonical result differs')
        record = execute([*command, target / ('bv2string-probe' + suffix), '/canonical-stream.bin', 1000, 1000],
                         target, environment)
        records.append(dict(kind='complete-stream', module_suffix=suffix, execution=record,
                            expected_sha256=hashlib.sha256(expected).hexdigest()))
        driver.save(target / 'wasm-validation.json', records)
        driver.require_success(record)
        if record['stderr'] or json.loads(record['stdout']) != dict(result=0, values=len(expected) // 4):
            raise ValueError('Rust/WASI complete stream differs')
    path.unlink()


def validate_outputs(directory, runner, tools, environment, driver):
    original = (directory / 'original-kernel.scm').read_text()
    adapted, edits = adaptation(original)
    if adapted != (directory / 'adapted-kernel.scm').read_text():
        raise ValueError('adapted kernel changed before validation')
    driver.save(directory / 'reversible-source-edits.json', dict(edits=edits, restored_original=True))
    retain_native_toolchain(directory, tools, environment, driver)
    validate_native_canonical(directory, tools, environment, driver)
    prepare_native_timing(directory, tools, environment, driver)
    build_probes(directory, runner, tools, environment, driver)
    records = []
    for case in fixtures():
        validate_case(directory, case, tools, environment, driver, records)
    target = prepare_rust_reference(directory, environment, driver)
    validate_rust_stream(directory, target, environment, driver)
    build_rust_wasm(target, tools, environment, driver)
    validate_rust_wasm(directory, target, tools, environment, driver)


# ---- Tests ----


if __name__ == '__main__':
    import sys
    import unittest

    class ProcessCleanupTests(unittest.TestCase):
        def check_descendant(self, delay, timeout):
            script = ('import subprocess,sys,time\n'
                      'child=subprocess.Popen([sys.executable,"-c","import time;time.sleep(30)"],'
                      'stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)\n'
                      'print(child.pid,flush=True)\n' + f'time.sleep({delay})\n')
            record = execute([sys.executable, '-c', script], '.', os.environ.copy(), timeout=timeout)
            path = Path('/proc') / record['stdout'].strip() / 'stat'
            for _ in range(100):
                if not path.exists() or path.read_text().split()[2] == 'Z':
                    return record
                time.sleep(0.01)
            self.fail('owned child survived the completed process group')

        def test_normal_exit_closes_pipe_closing_child(self):
            record = self.check_descendant(0, 5)
            self.assertEqual(record['returncode'], 0)
            self.assertFalse(record['timeout'])

        def test_timeout_closes_whole_group(self):
            record = self.check_descendant(30, 0.5)
            self.assertTrue(record['timeout'])
            self.assertLess(record['process_seconds'], 3)

        def test_vanished_group_is_already_clean(self):
            record = execute([sys.executable, '-c', 'pass'], '.', os.environ.copy())
            self.assertEqual(record['returncode'], 0)

    unittest.main()
