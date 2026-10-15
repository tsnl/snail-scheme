"""Preserve Tail's complete file reads, retained lines and reversed output."""

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

from data_ports import form, replace
from string_port import exact_json_integer, i64
import ray_port


# ---- Concrete line results leave the original recursion visible ----

CONTRACTS = '''(: tail-r-aux (-> InputPort (List String) (List String)))
(: echo-lines-in-reverse-order (-> InputPort OutputPort Unit))
(: go (-> String String Unit))
'''
COMMON = '''(: tail-for-each (All (T) (-> (-> T Unit) (List T) Unit)))
(define (tail-for-each procedure values)
  (unless (null? values)
    (procedure (car values))
    (tail-for-each procedure (cdr values))))
'''
INPUTS = '''(define-extern path-length "benchmark" "path_length" (-> I32 I64))
(define-extern path-character "benchmark" "path_character" (-> I32 I64 Char))
(: input-path (-> I32 String))
(define (input-path which)
  (let* ((size (path-length which)) (text (make-string size)))
    (let loop ((index 0))
      (if (= index size) text
          (begin (string-set! text index (path-character which index)) (loop (+ index 1)))))))
(define input0 (input-path (ann 0 I32)))
(define input1 (input-path (ann 1 I32)))
(: hide-path (-> I64 String String))
(define (hide-path count value) (if (barrier) value (unreachable)))
'''
WORKER = '''(let loop ((i 0))
  (if (< i count)
      (begin (go (hide-path count input0) (hide-path count input1)) (loop (+ i 1)))
      1))'''
INPUT_DECODER = '''(import (chezscheme))
(let* ((count (read)) (source (read)) (target (read)) (ignored (read)))
  (unless (and (integer? count) (exact? count) (string? source) (string? target))
    (error 'tail-input "expected count and input/output pathnames"))
  (write count) (newline)
  (for-each (lambda (path)
              (string-for-each (lambda (character) (write (char->integer character)) (display " ")) path)
              (newline)) (list source target)))
'''


def specification(data):
    with tempfile.TemporaryDirectory(prefix='snail-tail-input-') as temporary:
        decoder = Path(temporary) / 'decode.scm'
        decoder.write_text(INPUT_DECODER)
        record = subprocess.run([os.environ.get('CHEZ', 'scheme'), '--script', decoder],
                                input=data, capture_output=True, check=True)
    count, *paths = record.stdout.decode().splitlines()
    return dict(name='tail', count=exact_json_integer(i64(count)), inputs=[],
                pathnames=[''.join(map(chr, map(int, path.split()))) for path in paths],
                expected=1, barriers_per_iteration=2, setup_barriers=0, runtime='scalar-io')


def adaptation(source):
    edits = [dict(before='(cons x file-so-far)', after='(cons (line-text x) file-so-far)', count=1),
             dict(before='(eof-object? x)', after='(line-eof? x)', count=1),
             dict(before='(for-each ', after='(tail-for-each ', count=1)]
    adapted = source
    for edit in edits:
        adapted = replace(adapted, edit['before'], edit['after'], edit['count'])
    restored = adapted
    for edit in reversed(edits):
        restored = replace(restored, edit['after'], edit['before'], edit['count'])
    if restored != source:
        raise ValueError('Tail edits did not restore the complete original kernel')
    return CONTRACTS + adapted, edits


def kernel(source):
    return adaptation(source)[0]


# ---- The adapted Chez control runs the same Scheme line builder ----

CHEZ_BOUNDARY = '''(define-syntax : (syntax-rules () ((_ . signature) (begin))))
(define-syntax ann (syntax-rules () ((_ value type) value)))
(define (unit) (if #f #f))
(define (unreachable) (error 'tail "unreachable"))
(define i32-eq =)
(define i32->i64 values)
(define input-handle values)
(define ref-get values)
(define (end-of-file) (vector 0))
(define (line text) (vector 1 text))
(define (line-text value) (vector-ref value 1))
(define (line-eof? value) (= (vector-ref value 0) 0))
(define (port-read port)
  (let ((character (read-char port))) (if (eof-object? character) -1 (char->integer character))))
(define (port-peek port)
  (let ((character (peek-char port))) (if (eof-object? character) -1 (char->integer character))))
(define (string-copy! target at source start end)
  (let loop ((index start))
    (unless (= index end)
      (string-set! target (+ at (- index start)) (string-ref source index))
      (loop (+ index 1)))))
'''


def chez_helpers():
    here = Path(__file__).resolve()
    library_path = here.parents[2] / 'src/snail/io.sld'
    if not library_path.exists():
        library_path = here.parent / 'compiler-source/src/snail/io.sld'
    library = library_path.read_text()
    names = ('read-line', 'consume-line-feed', 'read-line-text', 'line-capacity', 'write-string')
    definitions = '\n'.join(form(library, '(define (' + name + ' ') for name in names)
    return CHEZ_BOUNDARY + definitions + '\n' + COMMON


def adapt_chez_harness(source, reverse=False):
    edits = [(' (define read-line\n   get-line)', '; read-line is supplied by the same Scheme line builder.'),
             (ray_port.ORIGINAL_WRITE_STRING, '; write-string is supplied by the same Scheme character loop.')]
    for before, after in edits:
        source = replace(source, after if reverse else before, before if reverse else after)
    return source


# ---- Real files and an independent complete byte oracle ----

def reversed_bytes(data):
    lines = re.split(r'\r\n|\r|\n', data.decode('utf-8'))
    if lines[-1] == '':
        lines.pop()
    return ''.join(line + '\n' for line in reversed(lines)).encode('utf-8')


def seed_files(directory, spec, data=None, existing=False):
    source, target = [directory / path for path in spec['pathnames']]
    source.parent.mkdir(parents=True, exist_ok=True)
    target.parent.mkdir(parents=True, exist_ok=True)
    if data is not None:
        source.write_bytes(data)
    target.unlink(missing_ok=True)
    if existing:
        target.write_bytes(b'previous contents must disappear\n' * 7)


def check_output(directory, spec):
    source, target = [directory / path for path in spec['pathnames']]
    actual, expected = target.read_bytes(), reversed_bytes(source.read_bytes())
    if actual != expected:
        raise ValueError('Tail output differs in complete line contents, count or reversed order')
    return dict(bytes=len(actual), sha256=hashlib.sha256(actual).hexdigest(),
                lines=actual.count(b'\n'), input_sha256=hashlib.sha256(source.read_bytes()).hexdigest())


# ---- Link the ordinary Rust scalar provider through both compiler forms ----

def build_runtime(directory, tools, environment, driver):
    ray_port.build_runtime(directory, tools, environment, driver)
    (directory / 'input-decoder.scm').write_text(INPUT_DECODER)


def link_runtime(directory, tools, environment, driver):
    for suffix in ('', '.raw.wasm'):
        output = directory / ('strict.wasm' + suffix)
        source = directory / ('strict-native.wasm' + suffix)
        output.rename(source)
        flags = ['--diagnostic-prune-only'] if suffix else []
        command = [driver.ROOT / 'scripts/link-strict-runtime', '--runtime', directory / 'runtime.wasm',
                   *flags, source, output]
        record = driver.execute(command, driver.ROOT, environment)
        driver.save(directory / ('runtime-link' + ('-raw' if suffix else '') + '.json'), record)
        driver.require_success(record)


# ---- The same optimized Scheme module also runs through the native backend ----

NATIVE_HEADER = '''#include <stdint.h>
int32_t barrier(void);
int64_t path_length(int32_t);
uint32_t path_character(int32_t, int64_t);
'''
NATIVE_PROVIDER = '''#include "native-provider.h"
#include <assert.h>
PATHS
int32_t barrier(void) { return 1; }
int64_t path_length(int32_t which) { assert(which == 0 || which == 1); return lengths[which]; }
uint32_t path_character(int32_t which, int64_t index) {
    assert(index >= 0 && index < path_length(which));
    return which == 0 ? source[index] : target[index];
}
'''
NATIVE_ENTRY = '''#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern uint64_t native_resource_release_count(void);
extern void guest_main(void) __asm__("wasm.main");
extern int64_t bench(int64_t) __asm__("wasm.bench");
int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    guest_main();
    int64_t result = bench(argc == 2 ? strtoll(argv[1], NULL, 10) : 50);
    int status = native_finish(0);
    printf("{\\\"result\\\":%" PRId64 ",\\\"released\\\":%" PRIu64 "}\\n", result, native_resource_release_count());
    return status;
}
'''


def build_native(directory, tools, environment, driver):
    spec = driver.load(directory / 'spec.json')
    arrays = [f'static const uint32_t {name}[] = {{{",".join(str(ord(c)) for c in path)}}};'
              for name, path in zip(('source', 'target'), spec['pathnames'])]
    arrays.append('static const int64_t lengths[] = {' + ','.join(str(len(p)) for p in spec['pathnames']) + '};')
    (directory / 'native-provider.h').write_text(NATIVE_HEADER)
    (directory / 'native-provider.c').write_text(NATIVE_PROVIDER.replace('PATHS', '\n'.join(arrays)))
    (directory / 'native-entry.c').write_text(NATIVE_ENTRY)
    command = [driver.ROOT / 'scripts/build-native', '--wasm', '--c-provider', 'benchmark',
               directory / 'native-provider.h', directory / 'native-provider.c', '--entry-c',
               directory / 'native-entry.c', directory / 'strict-native.wasm', directory / 'native']
    record = driver.execute(command, driver.ROOT, environment)
    driver.save(directory / 'native-build.json', record)
    driver.require_success(record)


# ---- Supplemental values and lifecycle traces never replace the full workload ----

def fixtures():
    data = [('empty', b''), ('blank', b'\n'), ('blanks', b'\n\n'),
            ('terminated', b'one\ntwo\nthree\n'), ('unterminated', b'one\ntwo\nthree'),
            ('crlf', b'one\r\ntwo\r\n'), ('cr', b'one\rtwo\r'),
            ('mixed', b'one\rtwo\r\n\nlast'), ('empty-cr', b'\r'),
            ('unicode', '\0λ😀\U0010ffff\n\t\u0085\u2028\u2029'.encode())]
    data += [(f'growth-{count}', ('😀' * count + '\nlast').encode()) for count in (63, 64, 65, 127, 128, 129)]
    return [(label, value, 2) for label, value in data] + [
        ('zero', b'one\ntwo', 0), ('negative', b'one\ntwo', -1), ('fifty', b'one\n\nlast', 50)]


def fixture_record(directory, system, spec, tools, environment, driver):
    data = f'{spec["count"]}\n' + '\n'.join(json.dumps(p, ensure_ascii=False) for p in spec['pathnames']) + '\nignored\n'
    if system in ('original', 'adapted'):
        target = directory if system == 'original' else directory / 'same-source-chez'
        return driver.execute([tools['CHEZ'], '--program', target / 'program.so'], target, environment, stdin=data)
    if system == 'native':
        return driver.execute([directory / 'native', str(spec['count'])], directory, environment)
    driver.save(directory / 'fixture-spec.json', spec)
    suffix = '.raw.wasm' if system == 'raw' else ''
    command = [tools['NODE'], '--disable-warning=ExperimentalWarning', directory.parent / 'tail-host.mjs',
               directory / ('strict.wasm' + suffix), directory / 'fixture-spec.json', '--validate']
    return driver.execute(command, directory, environment)


def check_trace(events, spec):
    source, target = spec['pathnames']
    iteration = [['open', source, 0], ['delete', 0], ['open', target, 0],
                 ['close', target, 0], ['close', source, 0]]
    actual = [event for event in events if event[0] != 'eof']
    if actual != iteration * max(0, int(spec['count'])):
        raise ValueError('Tail did not preserve every open/delete/output-close/input-close iteration')


def original_reversed_bytes(data):
    # The pinned Chez prelude aliases read-line to get-line, which recognizes LF
    # only. Preserve and record that observable boundary difference on CR probes.
    lines = data.split(b'\n')
    if lines[-1] == b'':
        lines.pop()
    return b''.join(line + b'\n' for line in reversed(lines))


def validate_fixture(directory, case, spec, runner, tools, environment, driver, records):
    label, data, count = case
    probe = dict(spec, count=count, trace=True)
    for system in ('original', 'adapted', 'raw', 'optimized', 'native'):
        target = directory / 'same-source-chez' if system == 'adapted' else directory
        seed_files(target, probe, data, existing=True)
        expected = (target / probe['pathnames'][1]).read_bytes() if count <= 0 else (
            original_reversed_bytes(data) if system == 'original' else reversed_bytes(data))
        record = fixture_record(directory, system, probe, tools, environment, driver)
        observed = (target / probe['pathnames'][1]).read_bytes()
        records.append(dict(label=label, system=system, count=count, input_hex=data.hex(),
                            expected_hex=expected.hex(), actual_hex=observed.hex(), execution=record))
        driver.save(directory / 'file-correctness.json', records)
        check_fixture_record(record, observed, expected, probe, system, runner, driver)
        if (target / probe['pathnames'][0]).read_bytes() != data:
            raise ValueError('Tail mutated its input file')


def check_fixture_record(record, observed, expected, spec, system, runner, driver):
    driver.require_success(record)
    if record['stderr'] or observed != expected:
        raise ValueError('Tail fixture failed in ' + system)
    if system in ('raw', 'optimized'):
        check_trace(json.loads(record['stdout'])['events'], spec)
    elif system == 'native':
        result = json.loads(record['stdout'])
        if result != dict(result=1, released=2 * max(0, int(spec['count']))):
            raise ValueError('Native Tail did not release every repeated pair of file handles')
    elif runner.parse_result(record['stdout'], 'chez', 'tail')['status'] != 'ok':
        raise ValueError('Original Tail predicate must always accept a normally returning worker')


def line_builder_proof(directory, driver):
    library = (driver.ROOT / 'src/snail/io.sld').read_text()
    control = (directory / 'same-source-chez/program.scm').read_text()
    functions = {}
    for name in ('read-line', 'consume-line-feed', 'read-line-text', 'line-capacity', 'write-string'):
        definition = form(library, '(define (' + name + ' ')
        if control.count(definition) != 1:
            raise ValueError('Chez control differs from the Scheme library operation ' + name)
        functions[name] = hashlib.sha256(definition.encode()).hexdigest()
    driver.save(directory / 'line-builder-identity.json', dict(exact_definitions=True, functions=functions))


def validate_outputs(directory, runner, tools, environment, driver):
    spec = driver.load(directory / 'spec.json')
    original = driver.upstream_kernel((directory / 'upstream.scm').read_text())
    _, edits = adaptation(original)
    driver.save(directory / 'reversible-source-edits.json', dict(edits=edits, restored_original=True))
    line_builder_proof(directory, driver)
    data = (directory / spec['pathnames'][0]).read_bytes()
    (directory / 'upstream-input.bin').write_bytes(data)
    build_native(directory, tools, environment, driver)
    record = fixture_record(directory, 'native', spec, tools, environment, driver)
    driver.save(directory / 'native-canonical.json', record)
    driver.require_success(record)
    record['file'] = check_output(directory, spec)
    driver.save(directory / 'native-canonical.json', record)
    actual = (directory / spec['pathnames'][1]).read_bytes()
    check_fixture_record(record, actual, reversed_bytes(data), spec, 'native', runner, driver)
    (directory / 'canonical-output.bin').write_bytes(actual)
    records = []
    for case in fixtures():
        validate_fixture(directory, case, spec, runner, tools, environment, driver, records)
    for target in (directory, directory / 'same-source-chez'):
        seed_files(target, spec, data)
