"""Preserve Sum1 and Read1 while using the ordinary strict datum reader."""

import hashlib
import json
import difflib
import os
from pathlib import Path
import re
import shutil
import signal
import struct
import sys

from data_ports import replace
import matrix_port


# ---- Typed boundaries preserve every original read and do-loop update ----

NAMES = ('sum1', 'read1')
CONTRACTS = {
    'sum1': '''(: sumport (-> InputPort F64 F64))
(: sum (-> InputPort F64))
(: go (-> String F64))
''',
    'read1': '(: read-from-file-benchmark (-> String Datum))\n',
}
COMMON = '''(: workload-read (-> InputPort ReadResult))
(define (workload-read port)
  (let ((result (read port)))
    (match result
      ((read-error message) (datum-fail (string-append "read: " message)))
      ((read-value value) result) ((read-end) result))))
(: real-datum (-> Datum F64))
(define (real-datum value)
  (if (datum-number? value) (number->f64 (datum-number-value value))
      (datum-fail "sum1: expected a real number")))
(: exact-datum (-> Datum I64))
(define (exact-datum value)
  (match (datum-number-value value)
    ((exact-number value) value)
    ((rational-number value) (datum-fail "benchmark count must be exact"))
    ((inexact-number value) (datum-fail "benchmark count must be exact"))
    ((complex-number real imaginary) (datum-fail "benchmark count must be exact"))))
'''
STRICT_ABS = '''(: abs (-> F64 F64))
(define (abs value) (if (< value 0.0) (- 0.0 value) value))
'''
INPUTS = '''(define-data Specification
  (specification (count I64 specification-count) (path String specification-path)
                 (expected Datum specification-expected)))
(: read-specification (-> InputPort Specification))
(define (read-specification port)
  (let* ((count (exact-datum (read-value! (workload-read port))))
         (path (datum-string-value (read-value! (workload-read port))))
         (expected (read-value! (workload-read port))))
    (specification count path expected)))
(define configured (call-with-input-file "input.txt" read-specification))
(define input0 (specification-path configured))
(define expected (specification-expected configured))
(: configured-count (-> I64))
(define (configured-count) (specification-count configured))
(: hide-path (-> I64 String String))
(define (hide-path count path) (if (barrier) path (unreachable)))
'''


def adaptation(name, source):
    edits = [dict(before='(read ', after='(workload-read ', count=1 if name == 'sum1' else 2),
             dict(before='(eof-object? x)', after='(read-end? x)', count=1)]
    edits += ([dict(before='(+ x sum-so-far)', after='(+ (real-datum (read-value! x)) sum-so-far)', count=1)]
              if name == 'sum1' else [dict(before='(y #f x)', after='(y (datum-boolean #f) (read-value! x))', count=1)])
    adapted = source
    for edit in edits:
        adapted = replace(adapted, edit['before'], edit['after'], edit['count'])
    restored = adapted
    for edit in reversed(edits):
        restored = replace(restored, edit['after'], edit['before'], edit['count'])
    if restored != source:
        raise ValueError('reader kernel edits do not reverse exactly')
    return CONTRACTS[name] + adapted, edits


def kernel(name, source):
    return adaptation(name, source)[0]


def worker(name):
    call = '(go (hide-path count input0))' if name == 'sum1' else '(read-from-file-benchmark (hide-path count input0))'
    value = f'(datum-number (inexact-number {call}))' if name == 'sum1' else call
    predicate = '(<= (abs (- (real-datum result) (real-datum expected))) 1e-9)' if name == 'sum1' else '(datum=? result expected)'
    return f'''(let loop ((i 0) (result (datum-boolean #f)))
  (if (< i count) (loop (+ i 1) {value})
      (if {predicate} 1 0)))'''


def specification(name, data):
    count, path, expected = [line for line in data.decode().splitlines() if line.strip()]
    return dict(name=name, count=int(count), pathnames=[json.loads(path)], expected=1,
                expected_datum=expected, inputs=[], barriers_per_iteration=1, setup_barriers=0,
                additional_exports=['configured-count'], runtime='scalar-datum-reader')


def program(name, source, driver):
    prelude = replace(driver.PRELUDE, '(import (snail strict))',
                      '(import (snail strict) (snail io) (snail datum) (snail read))')
    return (prelude + STRICT_ABS + COMMON + kernel(name, driver.upstream_kernel(source)) + INPUTS
            + '(: bench (-> I64 I64))\n(define (bench count) ' + worker(name) + ')\n(unit)\n')


# ---- Chez uses the exact Scheme datum and parser bodies with scalar services ----

CHEZ_TYPES = r'''(define-syntax : (syntax-rules () ((_ . signature) (begin))))
(define-syntax ann (syntax-rules () ((_ value type) value)))
(define-syntax define-data
  (lambda (form)
    (syntax-case form ()
      ((context name variant ...)
       (datum->syntax #'context
         (cons 'begin
           (apply append
             (map (lambda (variant)
                    (let ((tag (car variant)) (fields (cdr variant)))
                      (cons `(define (,tag ,@(map car fields)) (vector ',tag ,@(map car fields)))
                        (let loop ((fields fields) (index 1))
                          (if (null? fields) '()
                              (append
                                (if (= (length (car fields)) 3)
                                    `((define (,(caddar fields) value)
                                        (unless (eq? (vector-ref value 0) ',tag)
                                          (error ',tag "wrong typed variant" value))
                                        (vector-ref value ,index))) '())
                                (loop (cdr fields) (+ index 1))))))))
                  (syntax->datum #'(variant ...))))))))))
(define-syntax match
  (lambda (form)
    (syntax-case form ()
      ((context value arm ...)
       (let ((temporary (syntax->datum (car (generate-temporaries #'(value))))))
         (datum->syntax #'context
           `(let ((,temporary ,(syntax->datum #'value)))
              (cond
                ,@(map (lambda (arm)
                         (let ((pattern (car arm)))
                           `((eq? (vector-ref ,temporary 0) ',(car pattern))
                             (let ,(let loop ((names (cdr pattern)) (index 1))
                                     (if (null? names) '()
                                         (cons `(,(car names) (vector-ref ,temporary ,index))
                                           (loop (cdr names) (+ index 1)))))
                               ,@(cdr arm)))))
                       (syntax->datum #'(arm ...)))
                (else (error 'match "invalid typed variant" ,temporary))))))))))
(define (unit) (if #f #f))
(define (unreachable) (error 'reader "unreachable typed branch"))
(define (ref value) (vector value))
(define (ref-get value) (vector-ref value 0))
(define (ref-set! cell value) (vector-set! cell 0 value))
(define ref-eq? eq?)
(define vector-eq? eq?)
(define string-eq? eq?)
(define bytevector-eq? eq?)
(define i32-eq eqv?)
(define i32->i64 values)
(define i64->i32 values)
(define i64->f64 inexact)
;; The identical Datum body hashes complete wrapping I64 words. Chez's generic
;; integers do not wrap, so these scalar adapters make that boundary explicit.
(define (i64-word value)
  (let ((bits (bitwise-bit-field value 0 64)))
    (if (< bits 9223372036854775808) bits (- bits 18446744073709551616))))
(define (i64-add a b) (i64-word (+ a b)))
(define (i64-mul a b) (i64-word (* a b)))
(define (i64-bitwise-and a b) (bitwise-if a b 0))
(define i64-bitwise-xor bitwise-xor)
(define (i64-shift-right/logical value count)
  (i64-word (bitwise-arithmetic-shift-right (bitwise-bit-field value 0 64)
                                          (bitwise-bit-field count 0 6))))
(define (string-copy! target at source start end)
  (do ((index start (+ index 1))) ((= index end))
    (string-set! target (+ at (- index start)) (string-ref source index))))
'''
CHEZ_SCALARS = r'''(define-data CharacterResult (character-end) (character-value (value Char)))
(define (read-char port)
  (let ((value (host-read-char port)))
    (if (eof-object? value) (character-end) (character-value value))))
(define (peek-char port)
  (let ((value (host-peek-char port)))
    (if (eof-object? value) (character-end) (character-value value))))
(define (has-character? text character)
  (let loop ((index 0))
    (and (< index (string-length text))
         (or (char=? (string-ref text index) character) (loop (+ index 1))))))
(define (initial? character)
  (or (char-alphabetic? character) (has-character? "!$%&*/:<=>?^_~@" character)))
(define (sign-next? character) (or (initial? character) (has-character? "+-" character)))
(define (dot-next? character) (or (sign-next? character) (char=? character #\.)))
(define (identifier-text? text)
  (let ((size (string-length text)))
    (define (at index predicate) (and (< index size) (predicate (string-ref text index))))
    (define (tail index)
      (or (= index size)
          (and (let ((c (string-ref text index)))
                 (or (initial? c) (char<=? #\0 c #\9) (has-character? "+-." c)))
               (tail (+ index 1)))))
    (and (> size 0)
         (let ((first (string-ref text 0)))
           (cond ((has-character? "+-" first)
                  (or (= size 1) (if (char=? (string-ref text 1) #\.)
                                    (and (at 2 dot-next?) (tail 3))
                                    (and (at 1 sign-next?) (tail 2)))))
                 ((char=? first #\.) (and (at 1 dot-next?) (tail 2)))
                 (else (and (initial? first) (tail 1))))))))
(define (temporary-open) (vector 'text '() #f))
(define (temporary-text handle)
  (case (vector-ref handle 0)
    ((text) (list->string (reverse (vector-ref handle 1))))
    ((parsed error) (vector-ref handle 2))
    (else (error 'token "not owned text"))))
(define (temporary-character handle character)
  (unless (eq? (vector-ref handle 0) 'text) (error 'token "not owned text"))
  (vector-set! handle 1 (cons character (vector-ref handle 1))))
(define (temporary-close handle)
  (when (eq? (vector-ref handle 0) 'closed) (error 'token "already consumed"))
  (vector-set! handle 0 'closed) (vector-set! handle 1 #f) (vector-set! handle 2 #f))
(define (supported-scalar? value)
  (or (and (exact? value) (integer? value) (<= -9223372036854775808 value 9223372036854775807))
      (flonum? value)))
(define (numeric-kind value)
  (if (not (real? value)) 3
      (if (exact? value) 1 2)))
(define (temporary-parse handle)
  (let* ((text (temporary-text handle)) (value (host-string->number text))
         (kind (if value (numeric-kind value) 0)))
    (vector-set! handle 2 text)
    (if (and value
             (or (has-character? text #\/) (not (supported-scalar? (real-part value)))
                 (not (supported-scalar? (imag-part value)))))
        (begin (vector-set! handle 0 'error)
               (vector-set! handle 1 "unsupported rational or out-of-range number") 4)
        (begin (vector-set! handle 0 'parsed) (vector-set! handle 1 value) kind))))
(define (numeric-component handle index)
  (unless (and (eq? (vector-ref handle 0) 'parsed) (number? (vector-ref handle 1)))
    (error 'token "no successful numeric result"))
  (let ((value (vector-ref handle 1)))
    (if (= index 0) (real-part value)
        (if (and (= index 1) (= (numeric-kind value) 3)) (imag-part value)
            (error 'token "component out of range")))))
(define (temporary-error handle)
  (unless (eq? (vector-ref handle 0) 'error) (error 'token "no numeric error"))
  (vector-ref handle 1))
(define (temporary-intern handle)
  (let ((allowed (or (eq? (vector-ref handle 0) 'text)
                     (and (eq? (vector-ref handle 0) 'parsed) (not (vector-ref handle 1)))))
        (text (temporary-text handle)))
    (temporary-close handle)
    (unless allowed (error 'token "symbol interning requires an unparsed text handle"))
    (host-string->symbol text)))
(define (temporary-fail handle)
  (let ((text (temporary-text handle))) (temporary-close handle) (error 'reader text)))
(define-syntax define-extern
  (syntax-rules () ((_ name module foreign signature) (define name (scalar-service foreign)))))
(define (scalar-service name)
  (cond
    ((string=? name "snail:datum/token-open") temporary-open)
    ((string=? name "snail:datum/token-character") temporary-character)
    ((string=? name "snail:datum/token-close") temporary-close)
    ((string=? name "snail:datum/token-parse") temporary-parse)
    ((string=? name "snail:datum/token-identifier")
     (lambda (handle) (if (identifier-text? (temporary-text handle)) 1 0)))
    ((string=? name "snail:datum/token-intern") temporary-intern)
    ((string=? name "snail:datum/number-kind")
     (lambda (handle index) (if (exact? (numeric-component handle index)) 0 1)))
    ((or (string=? name "snail:datum/number-integer") (string=? name "snail:datum/number-real")) numeric-component)
    ((string=? name "snail:datum/error-length") (lambda (handle) (string-length (temporary-error handle))))
    ((string=? name "snail:datum/error-character") (lambda (handle index) (string-ref (temporary-error handle) index)))
    ((string=? name "snail:datum/fail") temporary-fail)
    ((string=? name "snail:datum/symbol-length") (lambda (name) (string-length (host-symbol->string name))))
    ((string=? name "snail:datum/symbol-character") (lambda (name index) (string-ref (host-symbol->string name) index)))
    ((string=? name "snail:datum/real-equivalent")
     (lambda (left right) (if (or (eqv? left right) (and (nan? left) (nan? right))) 1 0)))
    ((string=? name "snail:datum/whitespace") (lambda (character) (if (char-whitespace? character) 1 0)))
    (else (error 'scalar-service "unknown scalar export" name))))
'''


def library_body(root, name):
    source = (root / f'src/snail/{name}.sld').read_text()
    anchor = '\n  (begin\n'
    if source.count(anchor) != 1 or not source.endswith('))\n'):
        raise ValueError('expected one concrete library body: ' + name)
    body, depth = source.split(anchor, 1)[1], 1
    for token in re.finditer(r'#\\(?:[()]|[^\s()]+)|"(?:[^"\\]|\\.)*"|;[^\n]*|[()]', body):
        depth += (token[0] == '(') - (token[0] == ')')
        if depth == 0:
            return body[:token.start()] + '\n'
    raise ValueError('unclosed concrete library body: ' + name)


def chez_reader(root, exports):
    captures = 'read-char peek-char string->number string->symbol symbol->string'.split()
    bindings = ' '.join(f'(host-{name} {name})' for name in captures)
    names = [(name, name) if isinstance(name, str) else name for name in exports]
    unpack = ''.join(f'(define {public} (vector-ref reader-interface {index}))\n'
                     for index, (public, private) in enumerate(names))
    return (CHEZ_TYPES + f'(define reader-interface\n  (let ({bindings})\n'
            + CHEZ_SCALARS + library_body(root, 'datum') + library_body(root, 'read')
            + COMMON + f'    (vector {" ".join(private for public, private in names)})))\n' + unpack)


def adapted_chez(name, original, root, driver):
    source_kernel = driver.upstream_kernel(original)
    adapted, edits = adaptation(name, source_kernel)
    without_import = re.sub(r'^\(import [^\n]*\)\s*$', '', original, flags=re.M)
    body = replace(without_import, source_kernel, adapted)
    harness_edits = []
    for before, after in [('(count (read))', '(count (exact-datum (read-value! (workload-read (current-input-port)))))'),
                          ('(input1 (read))', '(input1 (datum-string-value (read-value! (workload-read (current-input-port)))))'),
                          ('(output (read))', '(output ' + ('(real-datum ' if name == 'sum1' else '')
                           + '(read-value! (workload-read (current-input-port)))' + (')' if name == 'sum1' else '') + ')')]:
        body = replace(body, before, after)
        harness_edits.append(dict(before=before, after=after, count=1))
    if name == 'read1':
        body = replace(body, '(equal? result output)', '(datum=? result output)')
        harness_edits.append(dict(before='(equal? result output)', after='(datum=? result output)', count=1))
    restored = body
    for edit in reversed(harness_edits):
        restored = replace(restored, edit['after'], edit['before'], edit['count'])
    if replace(restored, adapted, source_kernel) != without_import:
        raise ValueError('adapted Chez edits do not restore complete original source')
    exports = ['workload-read', 'read-end?', 'read-value!', 'real-datum', 'exact-datum',
               'datum=?', 'datum-boolean', 'datum-string-value']
    return chez_reader(root, exports) + body, dict(kernel=edits, harness=harness_edits, complete_reverse_verified=True)


# ---- Preparation owns every build and invocation process group ----

def record(directory, label, command, environment, cwd=None, stdin=None, timeout=1200, failure=False):
    folder = directory / 'commands' / label
    folder.mkdir(parents=True)
    target = folder / 'record.json'
    target.write_text(json.dumps(dict(command=list(map(str, command)), cwd=str(cwd or directory),
                                      timeout_seconds=timeout, status='started'), indent=2) + '\n')
    try:
        result = matrix_port.execute(command, cwd or directory, environment, timeout=timeout, stdin=stdin)
    except BaseException as error:
        target.write_text(json.dumps(dict(command=list(map(str, command)), exception=repr(error),
                                          cwd=str(cwd or directory), status='interrupted'), indent=2) + '\n')
        raise
    result.update(cwd=str(cwd or directory), timeout_seconds=timeout)
    target.write_text(json.dumps(result, indent=2) + '\n')
    if ('returncode' not in result or result.get('timeout') or result.get('executing_descendants')
            or (result.get('returncode') != 0) != failure):
        raise RuntimeError(f'{label}: unexpected process result; see {target}')
    return result


def seed_files(directory, spec, input_data, runtime_data):
    (directory / 'input.txt').write_bytes(input_data)
    target = directory / spec['pathnames'][0]
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(runtime_data)


def write_sources(name, files, directory, runner, driver):
    original = files[f'src/{name}.scm'].decode()
    source_kernel = driver.upstream_kernel(original)
    adapted_kernel, edits = adaptation(name, source_kernel)
    chez = directory / 'chez'
    control = directory / 'chez-adapted'
    chez.mkdir(); control.mkdir()
    original_program = runner.source_text(files, name, 'chez')
    # Replace exactly the original body, leaving the upstream harness intact.
    adjusted, full_edits = adapted_chez(name, original, driver.ROOT, driver)
    import_line = re.search(r'^\(import [^\n]*\)\s*$', original, re.M).group()
    body = original.replace(import_line, '')
    adjusted = adjusted.replace(import_line, '')
    control_program = replace(original_program, body, adjusted)
    full_edits['common_harness'] = []
    if name == 'read1':
        edit = dict(before='(result #f)', after='(result (datum-boolean #f))', count=1)
        control_program = replace(control_program, edit['before'], edit['after'])
        full_edits['common_harness'].append(edit)
    restored = control_program
    for edit in reversed(full_edits['common_harness']):
        restored = replace(restored, edit['after'], edit['before'])
    if replace(restored, adjusted, body) != original_program:
        raise ValueError('adapted Chez harness edits do not restore the original control')
    for path, text in [(directory / 'upstream.scm', original), (directory / 'upstream-kernel.scm', source_kernel),
                       (directory / 'adapted-kernel.scm', adapted_kernel),
                       (directory / 'strict.scm', program(name, original, driver)),
                       (chez / 'program.scm', original_program), (control / 'program.scm', control_program)]:
        path.write_text(text)
    driver.save(directory / 'adaptation-ledger.json', edits)
    driver.save(directory / 'complete-chez-edit-ledger.json', full_edits)
    patch = difflib.unified_diff(original_program.splitlines(True), control_program.splitlines(True),
                                fromfile='original-chez', tofile='adapted-chez')
    (directory / 'chez-adaptation.patch').write_text(''.join(patch))


NATIVE_HEADER = '''#include <stdint.h>
int32_t barrier(void);
uint64_t reader_barriers(void);
'''
NATIVE_PROVIDER = '''#include "native-provider.h"
static uint64_t count;
int32_t barrier(void) { count++; return 1; }
uint64_t reader_barriers(void) { return count; }
'''
NATIVE_ENTRY = r'''#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include "native-provider.h"
extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern uint64_t native_resource_release_count(void);
extern void guest_main(void) __asm__("wasm.main");
extern int64_t configured_count(void) __asm__("wasm.configured-count");
extern int64_t bench(int64_t) __asm__("wasm.bench");
int main(int argc, char **argv) {
    native_host_init(argc, argv);
    native_module_init();
    guest_main();
    uint64_t setup = native_resource_release_count();
    int64_t count = configured_count();
    int64_t result = bench(count);
    uint64_t worker = native_resource_release_count() - setup;
    int status = native_finish(0);
    printf("{\"result\":%" PRId64 ",\"barriers\":%" PRIu64 ",\"setup_closed\":%" PRIu64
           ",\"worker_closed\":%" PRIu64 ",\"closed\":%" PRIu64 "}\n",
           result, reader_barriers(), setup, worker, native_resource_release_count());
    return status;
}
'''


def build(directory, tools, environment, driver):
    if environment.get('READER_PREP_REUSE'):
        reuse_artifacts(directory, Path(environment['READER_PREP_REUSE']), driver)
        return
    record(directory, 'strict-build', [driver.ROOT / 'scripts/build-strict', '--export', 'bench',
           '--export', 'configured-count', directory / 'strict.scm', directory / 'strict-native.wasm'],
           environment, driver.ROOT)
    record(directory, 'rust-runtime', [tools['CARGO'], 'rustc', '--crate-type=cdylib', '--quiet', '--offline',
           '--release', '--target', 'wasm32-wasip1', '--target-dir', driver.ROOT / 'build/wasm-runtime'], environment, driver.ROOT)
    runtime = driver.ROOT / 'build/wasm-runtime/wasm32-wasip1/release/snail_runtime.wasm'
    shutil.copyfile(runtime, directory / 'runtime.wasm')
    for label, suffix, flags in [('raw', '.raw.wasm', ['--diagnostic-prune-only']), ('optimized', '', [])]:
        record(directory, label + '-link', [driver.ROOT / 'scripts/link-strict-runtime', '--runtime', directory / 'runtime.wasm',
               *flags, directory / ('strict-native.wasm' + suffix), directory / (label + '.wasm')], environment, driver.ROOT)
    for name, text in [('native-provider.h', NATIVE_HEADER), ('native-provider.c', NATIVE_PROVIDER), ('native-entry.c', NATIVE_ENTRY)]:
        (directory / name).write_text(text)
    record(directory, 'native-build', [driver.ROOT / 'scripts/build-native', '--wasm', '--c-provider', 'benchmark',
           directory / 'native-provider.h', directory / 'native-provider.c', '--entry-c', directory / 'native-entry.c',
           directory / 'strict-native.wasm', directory / 'native'], environment, driver.ROOT)


def reuse_artifacts(directory, previous, driver):
    manifest = driver.load(previous / 'prepared.json')
    for name, expected in manifest['compiler_files'].items():
        if driver.digest(driver.ROOT / name) != expected:
            raise ValueError('cannot reuse after compiler change: ' + name)
    source = previous / directory.name
    if (source / 'strict.scm').read_bytes() != (directory / 'strict.scm').read_bytes():
        raise ValueError('cannot reuse after strict program change')
    shutil.copytree(source, directory / 'reused-case')
    names = ['raw.wasm', 'optimized.wasm', 'strict-native.wasm', 'strict-native.wasm.raw.wasm',
             'runtime.wasm', 'native', 'native-provider.h', 'native-provider.c', 'native-entry.c']
    for name in names:
        shutil.copy2(source / name, directory / name)
    driver.save(directory / 'reused-artifacts.json', dict(previous=str(previous),
        compiled_source_identical=True, compiler_files_verified=True,
        sha256={name: driver.digest(directory / name) for name in names}))


def build_chez(directory, runner, tools, environment):
    commands = {}
    for name in ('chez', 'chez-adapted'):
        control = directory / name
        compile_command, command = runner.chez_commands(control, str(control / 'program.scm'))
        record(directory, name + '-build', compile_command, environment, control)
        commands[name] = command
    return commands


def validate_count(directory, spec, count, input_data, runtime_data, commands, tools, environment, driver):
    input_data = str(count).encode() + b'\n' + input_data.split(b'\n', 1)[1]
    probe = dict(spec, count=count)
    driver.save(directory / 'check-spec.json', probe)
    for control in [directory, directory / 'chez', directory / 'chez-adapted']:
        seed_files(control, spec, input_data, runtime_data)
    observations = {}
    for kind in ('raw', 'optimized', 'native'):
        command = ([directory / 'native'] if kind == 'native' else [tools['NODE'], '--disable-warning=ExperimentalWarning',
                   directory.parent / 'reader-host.mjs', directory / (kind + '.wasm'), directory / 'check-spec.json'])
        result = record(directory, f'count-{count}-{kind}', command, environment)
        value = json.loads(result['stdout'])
        if value['result'] != 1 or value['barriers'] != count or value['setup_closed'] != 1 or value['worker_closed'] != count:
            raise ValueError('incorrect workload result/opacity/file lifecycle: ' + kind)
        if kind != 'native':
            validate_io(value, len(input_data), spec['pathnames'][0], [len(runtime_data)] * count)
        observations[kind] = value
    for name, command in commands.items():
        result = record(directory, f'count-{count}-{name}', command, environment, directory / name, input_data.decode())
        if ',INCORRECT' in result['stdout'] or '+!CSVLINE!+' not in result['stdout']:
            raise ValueError('Chez canonical result failed: ' + name)
        observations[name] = dict(correct=True)
    return dict(count=count, observations=observations)


def prepare_reader_case(name, files, output, runner, tools, environment, driver):
    directory = output / name
    directory.mkdir()
    input_data = files[f'inputs/{name}.input']
    spec = specification(name, input_data)
    runtime_data = files[spec['pathnames'][0]]
    driver.save(directory / 'spec.json', spec)
    write_sources(name, files, directory, runner, driver)
    build(directory, tools, environment, driver)
    commands = build_chez(directory, runner, tools, environment)
    checks = [validate_count(directory, spec, count, input_data, runtime_data, commands, tools, environment, driver)
              for count in (1, 2, spec['count'])]
    driver.save(directory / 'canonical-validation.json', checks)
    validate_probes(directory, runtime_data, commands, tools, environment, driver)
    return dict(name=name, status='ready', spec=spec, chez_commands=commands,
                systems=['strict', 'native', 'chez', 'chez-adapted'],
                hashes={str(path.relative_to(directory)): driver.digest(path) for path in directory.rglob('*') if path.is_file()})


def interrupted(signum, frame):
    raise KeyboardInterrupt(f'reader preparation interrupted by signal {signum}')


def prepare_case(name, files, output, runner, tools, environment, driver):
    previous = signal.signal(signal.SIGTERM, interrupted)
    try:
        return prepare_reader_case(name, files, output, runner, tools, environment, driver)
    finally:
        signal.signal(signal.SIGTERM, previous)


# ---- Wrong predicates, empty files and malformed input exercise real workers ----

def input_text(count, path, expected):
    return f'{count}\n{json.dumps(path)}\n{expected}\n'.encode()


def edge_cases(name, canonical_data, canonical_expected):
    if name == 'sum1':
        return [dict(label='wrong-expected', data=canonical_data, expected='15794.976', accepted=False),
                dict(label='tolerance', data=canonical_data, expected='15794.9750000005', accepted=True),
                dict(label='empty', data=b'', expected='0.0', accepted=True),
                dict(label='comments', data='; λ😀\n#| comment |#\n'.encode(), expected='0.0', accepted=True),
                dict(label='sum-order', data=b'1e16 -1e16 1.0', expected='1.0', accepted=True),
                dict(label='sum-other-order', data=b'1e16 1.0 -1e16', expected='0.0', accepted=True),
                dict(label='real-integers', data=b'#x10 -2 #b11 .5', expected='17.5', accepted=True),
                dict(label='nonnumeric', data=b'1.0 wrong', expected='0.0', failure=True),
                dict(label='malformed', data=b'1.0 1e following', expected='0.0', failure=True),
                dict(label='zero-count', count=0, data=canonical_data, expected=canonical_expected, failure=True)]
    cases = [dict(label=label, data=canonical_data, expected=expected, accepted=False)
             for label, expected in [('wrong-value', '(should reject this list)'),
                                     ('wrong-order', '(return should this list)'),
                                     ('missing-value', '(should return this)'),
                                     ('extra-value', '(should return this list extra)'),
                                     ('wrong-tail', '(should return this . list)')]]
    return cases + [dict(label='empty', data=b'', expected='#f', accepted=True),
                    dict(label='comments', data=b'#| empty |# #; (discard me)', expected='#f', accepted=True),
                    dict(label='unicode-last', data='"old" (λ "😀" . -0.0)'.encode(), expected='(λ "😀" . -0.0)', accepted=True),
                    dict(label='false-last', data=b'1 (a b) #f', expected='#f', accepted=True),
                    dict(label='malformed', data=b'correct (a .)', expected='correct', failure=True),
                    dict(label='zero-count', count=0, data=canonical_data, expected='#f', accepted=True)]


def validate_fixture(directory, case, commands, tools, environment, driver):
    spec = driver.load(directory / 'spec.json')
    count = case.get('count', 1)
    target = directory / 'edge-probes' / case['label']
    target.mkdir(parents=True)
    data = input_text(count, spec['pathnames'][0], case['expected'])
    seed_files(target, spec, data, case['data'])
    driver.save(target / 'spec.json', dict(spec, count=count))
    observations = {}
    for system in ('raw', 'optimized', 'native', 'chez', 'chez-adapted'):
        command = ([directory / 'native'] if system == 'native' else commands[system] if system.startswith('chez') else
                   [tools['NODE'], '--disable-warning=ExperimentalWarning', directory.parent / 'reader-host.mjs',
                    directory / (system + '.wasm'), target / 'spec.json'])
        result = record(target, system, command, environment, target,
                        data.decode() if system.startswith('chez') else None, failure=case.get('failure', False))
        if case.get('failure'):
            if not result['stderr'].strip():
                raise ValueError('missing failed-read diagnostic: ' + system)
            if system in ('raw', 'optimized'):
                value = json.loads(result['stdout'])
                closed = value['worker_closed'] + value['cleanup_closed']
                if not value['failed'] or value['setup_closed'] != 1 or closed != max(0, count):
                    raise ValueError('failed worker left an open input: ' + system)
            observations[system] = dict(failed=True, diagnostic=result['stderr'])
            continue
        if system.startswith('chez'):
            accepted = ',INCORRECT' not in result['stdout']
        else:
            value = json.loads(result['stdout'])
            if value['barriers'] != max(0, count) or value['setup_closed'] != 1 or value['worker_closed'] != max(0, count):
                raise ValueError('edge fixture lost its worker or file lifecycle')
            if system != 'native':
                validate_io(value, len(data), spec['pathnames'][0], [len(case['data'])] * max(0, count))
            accepted = value['result'] == 1
        if accepted != case['accepted']:
            raise ValueError('wrong predicate decision: ' + case['label'] + ' ' + system)
        observations[system] = dict(accepted=accepted)
    return dict(label=case['label'], count=count, observations=observations)


def io_cycles(events, path, sizes, require_eof):
    index = 0
    for size in sizes:
        if events[index:index + 1] != [['open', path, 0]]:
            raise ValueError('worker did not open its data file in order')
        index += 1
        reads = []
        while index < len(events) and events[index][0] == 'read':
            event = events[index]
            if event[1] != path or (reads and reads[-1] == 0):
                raise ValueError('read changed files or continued after EOF')
            reads.append(event[2]); index += 1
        if sum(reads) != size or (require_eof and (not reads or reads[-1] != 0)):
            raise ValueError('worker did not consume the complete file and EOF')
        if events[index:index + 1] != [['close', path, 0]]:
            raise ValueError('worker did not close its data file before returning')
        index += 1
    if index != len(events):
        raise ValueError('unexpected file operations outside complete worker cycles')


def validate_io(value, setup_bytes, path, worker_sizes):
    phases = value['phases']
    io_cycles(phases['setup'], 'input.txt', [setup_bytes], False)
    io_cycles(phases['worker'], path, worker_sizes, True)
    if phases['cleanup']:
        raise ValueError('successful workers depended on terminal resource cleanup')


# ---- Complete result observations and changed files use unchanged kernels ----

def strict_observer(root):
    source = (root / 'tests/strict-reader/reader.scm').read_text()
    return source[source.index('(define-extern emit-i64'):source.index('(: scan ')]


def original_observer(root):
    source = (root / 'tests/strict-reader/oracle.scm').read_text()
    return source[source.index('(define (emit-i64'):source.index('(call-with-input-file "input.scm"')]


PROBE_LOOP = '''(define probe-path
  (call-with-input-file "input.txt"
    (lambda (port)
      (let* ((count READ-COUNT) (path READ-PATH) (expected READ-EXPECTED)) path))))
(define (observe-once) OBSERVE)
(display "call:0") (newline) (observe-once)
(when (file-exists? "replacement.data")
  (delete-file probe-path)
  (call-with-input-file "replacement.data"
    (lambda (input)
      (call-with-output-file probe-path
        (lambda (output)
          (let loop ((character (read-char input)))
            (unless (eof-object? character)
              (write-char character output) (loop (read-char input))))))))
  (display "call:1") (newline) (observe-once))
'''


def chez_probe(name, original, adapted, root, driver):
    source = '(import (chezscheme))\n'
    if adapted:
        exports = ['workload-read', 'read-end?', 'read-value!', 'real-datum', 'exact-datum', 'datum-boolean',
                   'datum-string-value', 'datum-number', 'inexact-number', ('typed-symbol->string', 'symbol->string')]
        exports += ['datum-kind', 'datum-boolean-value', 'datum-character-value', 'datum-symbol-value',
                    'datum-number-value', 'datum-car', 'datum-cdr', 'datum-vector-values', 'datum-bytevector-values']
        source += chez_reader(root, exports) + kernel(name, driver.upstream_kernel(original))
        observer = strict_observer(root)
        observer = observer[observer.index('(: observe-string'):]
        observer = replace(observer, '(symbol->string value)', '(typed-symbol->string value)')
        source += '(define (emit-i64 value) (display "i:") (display value) (newline))\n'
        source += '(define (emit-char value) (display "c:") (display (char->integer value)) (newline))\n'
        scalar_oracle = original_observer(root)
        source += scalar_oracle[scalar_oracle.index('(define (emit-f64'):scalar_oracle.index('(define (observe-string')]
        source += observer
        reads = ['(exact-datum (read-value! (workload-read port)))',
                 '(datum-string-value (read-value! (workload-read port)))', '(read-value! (workload-read port))']
    else:
        source += driver.upstream_kernel(original) + original_observer(root)
        reads = ['(read port)'] * 3
    call = '(go probe-path)' if name == 'sum1' else '(read-from-file-benchmark probe-path)'
    observed = f'(datum-number (inexact-number {call}))' if name == 'sum1' and adapted else call
    loop = PROBE_LOOP.replace('OBSERVE', '(observe ' + observed + ')')
    for token, value in zip(('READ-COUNT', 'READ-PATH', 'READ-EXPECTED'), reads):
        loop = loop.replace(token, value)
    return source + loop


PROBE_ENTRY = r'''#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include "native-provider.h"
extern void native_host_init(int, char **);
extern void native_module_init(void);
extern int native_finish(int);
extern uint64_t native_resource_release_count(void);
extern void guest_main(void) __asm__("wasm.main");
extern int64_t observe_once(void) __asm__("wasm.observe-once");
int main(int argc, char **argv) {
    native_host_init(argc, argv); native_module_init(); guest_main();
    uint64_t setup = native_resource_release_count();
    puts("call:0");
    if (observe_once() != 1) return native_finish(2);
    if (argc == 3) {
        FILE *input = fopen(argv[1], "rb"), *output = fopen(argv[2], "wb");
        if (!input || !output) {
            if (input) fclose(input);
            if (output) fclose(output);
            return native_finish(3);
        }
        int byte, failed = 0;
        while ((byte = fgetc(input)) != EOF) {
            if (fputc(byte, output) == EOF) { failed = 1; break; }
        }
        failed |= ferror(input);
        failed |= fclose(input) != 0;
        failed |= fclose(output) != 0;
        if (failed) return native_finish(5);
        puts("call:1");
        if (observe_once() != 1) return native_finish(6);
    }
    uint64_t worker = native_resource_release_count() - setup;
    int status = native_finish(0);
    printf("{\"result\":1,\"barriers\":%" PRIu64 ",\"setup_closed\":%" PRIu64
           ",\"worker_closed\":%" PRIu64 "}\n", reader_barriers(), setup, worker);
    return status;
}
'''


def build_probe(directory, tools, environment, driver):
    name = driver.load(directory / 'spec.json')['name']
    probe = directory / 'observation'
    probe.mkdir()
    original = (directory / 'upstream.scm').read_text()
    source = (directory / 'strict.scm').read_text().split('(: bench ', 1)[0]
    source = replace(source, '(snail read))', '(snail read) (snail bytes))')
    call = '(go (hide-path 1 input0))' if name == 'sum1' else '(read-from-file-benchmark (hide-path 1 input0))'
    value = '(datum-number (inexact-number ' + call + '))' if name == 'sum1' else call
    source += strict_observer(driver.ROOT) + '(: observe-once (-> I64))\n'
    source += '(define (observe-once) (observe ' + value + ') 1)\n(unit)\n'
    (probe / 'strict.scm').write_text(source)
    record(probe, 'strict-build', [driver.ROOT / 'scripts/build-strict', '--export', 'observe-once',
           '--export', 'configured-count', probe / 'strict.scm', probe / 'strict.wasm'], environment, driver.ROOT)
    for label, suffix, flags in [('raw', '.raw.wasm', ['--diagnostic-prune-only']), ('optimized', '', [])]:
        record(probe, label + '-link', [driver.ROOT / 'scripts/link-strict-runtime', '--runtime', directory / 'runtime.wasm',
               *flags, probe / ('strict.wasm' + suffix), probe / (label + '.wasm')], environment, driver.ROOT)
    for path in ('native-provider.h', 'native-provider.c'):
        shutil.copyfile(directory / path, probe / path)
    (probe / 'native-entry.c').write_text(PROBE_ENTRY)
    fixture = driver.ROOT / 'tests/strict-reader'
    record(probe, 'native-build', [driver.ROOT / 'scripts/build-native', '--wasm', '--c-provider', 'benchmark',
           probe / 'native-provider.h', probe / 'native-provider.c', '--c-provider', 'reader.test',
           fixture / 'observer.h', fixture / 'observer.c', '--entry-c', probe / 'native-entry.c',
           probe / 'strict.wasm', probe / 'native'], environment, driver.ROOT)
    for system in ('chez', 'chez-adapted'):
        (probe / (system + '.scm')).write_text(chez_probe(name, original, system == 'chez-adapted', driver.ROOT, driver))
    return probe


def result_probe(directory, case, tools, environment, driver):
    spec = driver.load(directory / 'spec.json')
    probe = directory / 'observation'
    data = input_text(1, spec['pathnames'][0], spec['expected_datum'])
    observations = {}
    for system in ('chez', 'chez-adapted', 'raw', 'optimized', 'native'):
        target = probe / case['label'] / system
        target.mkdir(parents=True)
        seed_files(target, spec, data, case['data'])
        config = dict(spec, count=1, observe=True)
        if 'replacement' in case:
            (target / 'replacement.data').write_bytes(case['replacement'])
            config['replacement'] = 'replacement.data'
        driver.save(target / 'spec.json', config)
        command = observation_command(directory, probe, target, system, spec, case, tools)
        result = record(target, 'run', command, environment, target)
        trace = observation_trace(result, system, data, spec, case)
        (target / 'trace.txt').write_text(trace)
        observations[system] = dict(sha256=hashlib.sha256(trace.encode()).hexdigest(), fields=len(trace.splitlines()))
    if len({value['sha256'] for value in observations.values()}) != 1:
        raise ValueError('complete result trace differs: ' + case['label'])
    if 'replacement' in case:
        first, second = trace.split('call:1\n')
        if first.removeprefix('call:0\n') == second:
            raise ValueError('changed file did not change the next worker result')
    return dict(label=case['label'], observations=observations)


def observation_command(directory, probe, target, system, spec, case, tools):
    if system.startswith('chez'):
        return [tools['CHEZ'], '--script', probe / (system + '.scm')]
    if system == 'native':
        arguments = ['replacement.data', spec['pathnames'][0]] if 'replacement' in case else []
        return [probe / 'native', *arguments]
    return [tools['NODE'], '--disable-warning=ExperimentalWarning', directory.parent / 'reader-host.mjs',
            probe / (system + '.wasm'), target / 'spec.json']


def observation_trace(result, system, data, spec, case):
    if system.startswith('chez'):
        return result['stdout']
    if system == 'native':
        lines = result['stdout'].splitlines()
        value = json.loads(lines[-1])
        trace = '\n'.join(lines[:-1]) + '\n'
    else:
        value = json.loads(result['stdout'])
        trace = '\n'.join(value['trace']) + '\n'
        sizes = [len(case['data'])] + ([len(case['replacement'])] if 'replacement' in case else [])
        validate_io(value, len(data), spec['pathnames'][0], sizes)
    count = 2 if 'replacement' in case else 1
    if value['result'] != 1 or value['barriers'] != count or value['setup_closed'] != 1 or value['worker_closed'] != count:
        raise ValueError('result observation changed the worker lifecycle')
    return trace


def bridge_stream_program(root):
    exports = ['workload-read', 'read-end?', 'read-value!', ('typed-symbol->string', 'symbol->string')]
    exports += ['datum-kind', 'datum-boolean-value', 'datum-character-value', 'datum-string-value',
                'datum-symbol-value', 'datum-number-value', 'datum-car', 'datum-cdr',
                'datum-vector-values', 'datum-bytevector-values']
    observer = strict_observer(root).split('(: observe-string', 1)[1]
    observer = '(: observe-string' + observer
    observer = replace(observer, '(symbol->string value)', '(typed-symbol->string value)')
    scalar = original_observer(root).split('(define (observe-string', 1)[0]
    return ('(import (chezscheme))\n' + chez_reader(root, exports) + scalar + observer
            + '''(call-with-input-file "input.scm"
  (lambda (port)
    (let loop ((count 0))
      (let ((result (workload-read port)))
        (if (read-end? result) (begin (display "result:") (display count) (newline))
            (begin (observe (read-value! result)) (loop (+ count 1))))))))
''')


def validate_bridge_stream(directory, runtime_data, tools, environment, driver):
    target = directory / 'bridge-stream'
    target.mkdir()
    (target / 'input.scm').write_bytes(runtime_data)
    (target / 'adapted.scm').write_text(bridge_stream_program(driver.ROOT))
    shutil.copyfile(driver.ROOT / 'tests/strict-reader/oracle.scm', target / 'original.scm')
    observations = {}
    for system in ('original', 'adapted'):
        result = record(target, system, [tools['CHEZ'], '--script', target / (system + '.scm')], environment, target)
        wire = result['stdout'].encode()
        observations[system] = dict(sha256=hashlib.sha256(wire).hexdigest(), fields=len(wire.splitlines()),
                                    datums=int(wire.splitlines()[-1].removeprefix(b'result:')))
    if observations['original'] != observations['adapted']:
        raise ValueError('adapted Chez parser changed the complete canonical datum stream')
    return observations


def validate_error_boundary(directory, tools, environment, driver):
    spec = driver.load(directory / 'spec.json')
    target = directory / 'error-boundary'
    target.mkdir()
    data = input_text(1, spec['pathnames'][0], spec['expected_datum'])
    # The invalid UTF-8 sentinel would fail a later read. The malformed number
    # must already have raised at the original read expression's boundary.
    seed_files(target, spec, data, b'1.0 1e \xff')
    driver.save(target / 'spec.json', dict(spec, count=1))
    observations = {}
    for system in ('raw', 'optimized', 'native'):
        command = ([directory / 'native'] if system == 'native' else
                   [tools['NODE'], '--disable-warning=ExperimentalWarning', directory.parent / 'reader-host.mjs',
                    directory / (system + '.wasm'), target / 'spec.json'])
        result = record(target, system, command, environment, target, failure=True)
        if 'invalid numeric token or identifier' not in result['stderr'] or 'UTF-8' in result['stderr']:
            raise ValueError('read error was deferred until a later read')
        observations[system] = dict(failed_at_first_malformed_token=True, diagnostic=result['stderr'])
    return observations


def validate_probes(directory, runtime_data, commands, tools, environment, driver):
    spec = driver.load(directory / 'spec.json')
    edge = [validate_fixture(directory, case, commands, tools, environment, driver)
            for case in edge_cases(spec['name'], runtime_data, spec['expected_datum'])]
    driver.save(directory / 'edge-validation.json', edge)
    build_probe(directory, tools, environment, driver)
    results = [result_probe(directory, case, tools, environment, driver) for case in
               [dict(label='canonical', data=runtime_data), changed_file(spec['name'])]]
    driver.save(directory / 'result-validation.json', results)
    driver.save(directory / 'bridge-stream-validation.json', validate_bridge_stream(directory, runtime_data, tools, environment, driver))
    driver.save(directory / 'error-boundary-validation.json', validate_error_boundary(directory, tools, environment, driver))


def changed_file(name):
    initial, replacement = ((b'1.25 2.5', b'9.0 -0.5') if name == 'sum1' else
                            ('(old "λ")'.encode(), '(new "😀" . 7)'.encode()))
    return dict(label='changed-file', data=initial, replacement=replacement)


# ---- Timing controls retain separate setup, worker and cleanup boundaries ----

TIMING_ENTRY = NATIVE_ENTRY.replace('#include <stdlib.h>', '#include <stdlib.h>\n#include <time.h>')
TIMING_ENTRY = replace(TIMING_ENTRY, 'int64_t result = bench(count);', '''struct timespec start, finish;
    if (clock_gettime(CLOCK_MONOTONIC, &start)) return native_finish(3);
    int64_t result = bench(count);
    if (clock_gettime(CLOCK_MONOTONIC, &finish)) return native_finish(4);
    double seconds = finish.tv_sec - start.tv_sec + (finish.tv_nsec - start.tv_nsec) * 1e-9;''')
TIMING_ENTRY = replace(TIMING_ENTRY, '"{\\\"result\\\":%" PRId64', '"{\\\"seconds\\\":%.9f,\\\"result\\\":%" PRId64')
TIMING_ENTRY = replace(TIMING_ENTRY, 'result, reader_barriers()', 'seconds, result, reader_barriers()')


def prepare_native_control(original, target, tools, environment, driver):
    target.mkdir()
    for filename in ('strict-native.wasm', 'spec.json', 'input.txt'):
        shutil.copy2(original / filename, target / filename)
    spec = driver.load(target / 'spec.json')
    path = spec['pathnames'][0]
    seed_files(target, spec, (original / 'input.txt').read_bytes(), (original / path).read_bytes())
    provider = replace(NATIVE_PROVIDER, 'count++; return 1;', 'return 1;')
    for name, text in [('native-provider.h', NATIVE_HEADER), ('native-provider.c', provider), ('native-entry.c', TIMING_ENTRY)]:
        (target / name).write_text(text)
    record(target, 'build', [driver.ROOT / 'scripts/build-native', '--wasm', '--c-provider', 'benchmark',
           target / 'native-provider.h', target / 'native-provider.c', '--entry-c', target / 'native-entry.c',
           target / 'strict-native.wasm', target / 'native'], environment, driver.ROOT)
    run = record(target, 'full-count-validation', [target / 'native'], environment, target)
    value = json.loads(run['stdout'])
    if value['result'] != 1 or value['barriers'] != 0 or value['worker_closed'] != spec['count'] or value['setup_closed'] != 1:
        raise ValueError('non-counting native control changed the canonical workload')
    generated = list(target.glob('native.native-*'))
    if len(generated) != 1:
        raise ValueError('native control must have one recorded final module')
    final = generated[0] / 'optimized.wasm'
    shutil.copy2(final, target / 'native-final.wasm')
    prepare_scalar_provider(final, original / 'runtime.wasm', target, tools, environment, driver)
    run = record(target, 'shared-module-v8-validation', [tools['NODE'], '--disable-warning=ExperimentalWarning',
                 target.parent.parent / 'reader-timing.mjs', final, target / 'spec.json', target / 'provider.wasm'], environment, target)
    if json.loads(run['stdout'])['result'] != 1:
        raise ValueError('V8 did not validate the exact native final module')
    run = record(target, 'shared-module-file-validation', [tools['NODE'], '--disable-warning=ExperimentalWarning',
                 target.parent.parent / 'reader-host.mjs', final, target / 'spec.json', target / 'provider.wasm'], environment, target)
    value = json.loads(run['stdout'])
    if value['result'] != 1 or value['barriers'] != spec['count']:
        raise ValueError('shared module lost an original worker or opacity call')
    validate_io(value, (target / 'input.txt').stat().st_size, path, [(target / path).stat().st_size] * spec['count'])
    driver.save(target / 'final-module.json', dict(path=str(final), sha256=driver.digest(final),
        input_sha256=driver.digest(target / 'strict-native.wasm'), executable_sha256=driver.digest(target / 'native')))


def module_interfaces(paths, target, label, tools, environment):
    script = '''const fs=require('fs'); console.log(JSON.stringify(process.argv.slice(1).map(path => {
      const m=new WebAssembly.Module(fs.readFileSync(path));
      return {path,imports:WebAssembly.Module.imports(m),exports:WebAssembly.Module.exports(m)};
    })));'''
    result = record(target, label, [tools['NODE'], '-e', script, *paths], environment)
    return json.loads(result['stdout'])


def prepare_scalar_provider(module, runtime, target, tools, environment, driver):
    program, provider = module_interfaces([module, runtime], target, 'provider-input-interfaces', tools, environment)
    required = {item['name'] for item in program['imports'] if item['module'] == 'snail.library'}
    keep = required | {'memory', '_initialize', 'snail:io/close-all', 'snail:report-error'}
    names = {item['name'] for item in provider['exports']}
    if not keep <= names:
        raise ValueError('Rust provider lacks a required concrete scalar export')
    record(target, 'provider-disassemble', [tools['WASM_DIS'], runtime, '-o', target / 'full-provider.wat'], environment)
    prune_export_table(target, keep, names, driver)
    record(target, 'provider-assemble', [tools['WASM_AS'], *matrix_port.RUST_WASM_FEATURES,
           target / 'selected-provider.wat', '-o', target / 'selected-provider.wasm'], environment)
    record(target, 'prune-scalar-provider', [tools['WASM_OPT'], '-g', *matrix_port.RUST_WASM_FEATURES,
           '--remove-unused-module-elements', '-O3', target / 'selected-provider.wasm', '-o', target / 'provider.wasm'], environment)
    final = module_interfaces([target / 'provider.wasm'], target, 'provider-final-interface', tools, environment)[0]
    if any(item['module'] not in ('wasi_snapshot_preview1', 'snail.platform') for item in final['imports']):
        raise ValueError('separate provider retained the legacy Scheme root ABI')
    if {item['name'] for item in final['exports']} != keep:
        raise ValueError('separate provider export set changed')
    driver.save(target / 'provider-interface.json', dict(required=sorted(required), retained=sorted(keep),
                scheme_module_sha256=driver.digest(module), raw_runtime_sha256=driver.digest(runtime),
                provider_sha256=driver.digest(target / 'provider.wasm'), interface=final))


def prune_export_table(target, keep, expected, driver):
    lines = (target / 'full-provider.wat').read_text().splitlines(keepends=True)
    selected, removed, found = [], [], set()
    for index, line in enumerate(lines):
        match = re.fullmatch(r'\s*\(export "([^"]+)" \(.*\)\)\s*', line)
        if match:
            found.add(match[1])
        if match and match[1] not in keep:
            removed.append(dict(index=index, line=line))
        else:
            selected.append(line)
    restored = list(selected)
    for edit in removed:
        restored.insert(edit['index'], edit['line'])
    if found != expected or restored != lines:
        raise ValueError('provider export-table edit did not reverse exactly')
    (target / 'selected-provider.wat').write_text(''.join(selected))
    driver.save(target / 'provider-export-edits.json', dict(removed=removed, complete_reverse_verified=True))


def validate_common_observation(original, target, tools, environment, driver):
    target.mkdir()
    native = list((original / 'observation').glob('native.native-*'))
    if len(native) != 1:
        raise ValueError('expected one native observation module')
    module = target / 'native-final.wasm'
    shutil.copy2(native[0] / 'optimized.wasm', module)
    prepare_scalar_provider(module, original / 'runtime.wasm', target, tools, environment, driver)
    spec, observations = driver.load(original / 'spec.json'), []
    for label in ('canonical', 'changed-file'):
        reference = original / 'observation' / label / 'chez'
        case = target / label
        case.mkdir()
        # Each completed two-call probe has replaced its input on disk. Restore
        # the same explicit first-call fixture before observing this executor.
        if label == 'canonical':
            runtime = (original / spec['pathnames'][0]).read_bytes()
        else:
            runtime = changed_file(spec['name'])['data']
        data = (reference / 'input.txt').read_bytes()
        seed_files(case, spec, data, runtime)
        config = dict(spec, count=1, observe=True)
        fixture = dict(data=runtime)
        if label == 'changed-file':
            replacement = (reference / 'replacement.data').read_bytes()
            (case / 'replacement.data').write_bytes(replacement)
            config['replacement'], fixture['replacement'] = 'replacement.data', replacement
        driver.save(case / 'spec.json', config)
        run = record(case, 'run', [tools['NODE'], '--disable-warning=ExperimentalWarning',
                     target.parent.parent / 'reader-host.mjs', module, case / 'spec.json', target / 'provider.wasm'], environment, case)
        trace = observation_trace(run, 'shared-module-v8', data, spec, fixture)
        if trace != (reference / 'trace.txt').read_text():
            raise ValueError('shared-module V8 result differs from original Chez')
        (case / 'trace.txt').write_text(trace)
        observations.append(dict(label=label, fields=len(trace.splitlines()), sha256=hashlib.sha256(trace.encode()).hexdigest()))
    driver.save(target / 'validation.json', observations)


# ---- Rust retains its unchanged numeric scanner and buffered datum reader ----

def build_rust_bin(target, name, tools, environment):
    environment = dict(environment, CARGO_TARGET_DIR=str(target / 'target'))
    for label, flags in [('native', []), ('wasm', ['--target', 'wasm32-wasip1'])]:
        record(target, name + '-' + label + '-build', [tools['CARGO'], 'rustc', '--offline', '--release', *flags,
               '--bin', name, '--', '--emit=llvm-ir'], environment, target)
    shutil.copy2(target / 'target/release' / name, target / (name + '.native'))
    shutil.copy2(target / 'target/wasm32-wasip1/release' / (name + '.wasm'), target / (name + '.raw.wasm'))
    record(target, name + '-wasm-optimize', [tools['WASM_OPT'], '-O3', '-g', *matrix_port.RUST_WASM_FEATURES,
           target / (name + '.raw.wasm'), '-o', target / (name + '.wasm')], environment, target)
    record(target, name + '-wasm-disassemble', [tools['WASM_DIS'], target / (name + '.wasm'),
           '-o', target / (name + '.wat')], environment, target)


def rust_commands(target, name, tools):
    host = [tools['NODE'], '--disable-warning=ExperimentalWarning', target / 'run-wasi.mjs']
    return [('native', [target / (name + '.native')]),
            ('raw-wasm', [*host, target / (name + '.raw.wasm')]),
            ('optimized-wasm', [*host, target / (name + '.wasm')])]


def rust_observation(name, source):
    kernel = source.split('// ---- Benchmark driver ----', 1)[0]
    before = '        sum += value;' if name == 'sum1' else '        result = value;'
    emit = '        println!("f:{}", value.to_bits());\n' if name == 'sum1' else '        println!("datum: {value}");\n'
    observed = replace(kernel, before, emit + before)
    if replace(observed, emit + before, before) != kernel:
        raise ValueError('Rust observation edit did not reverse exactly')
    path = 'inputs/sum1.data' if name == 'sum1' else 'inputs/parsing.data'
    call = f'sum_file("{path}")?' if name == 'sum1' else f'read_file("{path}")?'
    result = f'({call}).to_bits()' if name == 'sum1' else call
    return (observed + f'fn main() -> std::io::Result<()> {{ println!("result: {{}}", {result}); Ok(()) }}\n',
            dict(before=before, after=emit + before, count=1, kernel_reverse_verified=True))


def validate_rust_results(original, target, name, tools, environment, driver):
    spec = driver.load(original / 'spec.json')
    data, path = (original / 'input.txt').read_bytes(), spec['pathnames'][0]
    target_path = target / path
    target_path.parent.mkdir(exist_ok=True)
    shutil.copyfile(original / path, target_path)
    observations = []
    for count in (1, 2, spec['count']):
        configured = str(count) + '\n' + data.decode().split('\n', 1)[1]
        for system, command in rust_commands(target, name, tools):
            result = record(target, f'{name}-count-{count}-{system}', command, environment, target, configured)
            first = result['stdout'].splitlines()[0]
            if not first.startswith('Result: '):
                raise ValueError('Rust control omitted its complete result')
            if name == 'read1':
                valid = first[8:] == spec['expected_datum']
            else:
                bits = struct.unpack('<Q', struct.pack('<d', float(first[8:])))[0]
                wire = (original / 'observation/canonical/chez/trace.txt').read_text()
                valid = wire.endswith(f'f:{bits}\n')
            if not valid or result['stderr'] or '+!CSVLINE!+' not in result['stdout']:
                raise ValueError('Rust complete canonical result differs')
            observations.append(dict(system=system, count=count, complete_result=first[8:]))
    return observations


def validate_rust_stream(original, target, name, tools, environment, driver):
    expected = json.loads((original / 'bridge-stream/commands/original/record.json').read_text())['stdout']
    observations = {}
    for system, command in rust_commands(target, name + '_observe', tools):
        result = record(target, name + '-stream-' + system, command, environment, target)
        lines = result['stdout'].splitlines()
        if name == 'sum1':
            if lines[:-1] != [line for line in expected.splitlines() if line.startswith('f:')]:
                raise ValueError('Rust numeric scanner changed a canonical binary64 value')
            actual = '\n'.join(lines[:-1]) + '\n'
            expected_result = (original / 'observation/canonical/chez/trace.txt').read_text().split('f:')[1].strip()
            if lines[-1] != 'result: ' + expected_result:
                raise ValueError('Rust observed sum changed the accumulation result')
        else:
            if not all(line.startswith('datum: ') for line in lines[:-1]):
                raise ValueError('Rust full stream was not serialized as complete datums')
            parsed = target / (name + '-stream-' + system)
            parsed.mkdir()
            (parsed / 'input.scm').write_text('\n'.join(line[7:] for line in lines[:-1]) + '\n')
            oracle = record(parsed, 'chez-observer', [tools['CHEZ'], '--script',
                            driver.ROOT / 'tests/strict-reader/oracle.scm'], environment, parsed)
            actual = oracle['stdout']
            if actual != expected or lines[-1] != 'result: ' + driver.load(original / 'spec.json')['expected_datum']:
                raise ValueError('Rust buffered reader changed the canonical datum stream')
        observations[system] = dict(complete_stream_sha256=hashlib.sha256(actual.encode()).hexdigest(), fields=len(actual.splitlines()))
    return observations


def prepare_rust_controls(prepared, target, tools, environment, driver):
    source = driver.ROOT / 'benchmarks/wasm-reference'
    shutil.copytree(source / 'src', target / 'src')
    for name in ('Cargo.toml', 'Cargo.lock', 'run-wasi.mjs'):
        shutil.copy2(source / name, target / name)
    record(target, 'reader-tests', [tools['CARGO'], 'test', '--offline', '--lib'],
           dict(environment, CARGO_TARGET_DIR=str(target / 'target')), target)
    for name in NAMES:
        original = (source / f'src/bin/{name}.rs').read_text()
        build_rust_bin(target, name, tools, environment)
        results = validate_rust_results(prepared / name, target, name, tools, environment, driver)
        observed, ledger = rust_observation(name, original)
        (target / f'src/bin/{name}_observe.rs').write_text(observed)
        driver.save(target / (name + '-observation-edit.json'), ledger)
        build_rust_bin(target, name + '_observe', tools, environment)
        streams = validate_rust_stream(prepared / name, target, name, tools, environment, driver)
        if (target / f'src/bin/{name}.rs').read_text() != original:
            raise ValueError('Rust measured source changed during observation preparation')
        driver.save(target / (name + '-validation.json'), dict(canonical_results=results, canonical_streams=streams,
                    source_sha256=driver.digest(target / f'src/bin/{name}.rs')))


def validate_control_boundaries(prepared, controls, output, tools, environment, driver):
    output.mkdir(parents=True)
    observations = []
    for name in NAMES:
        original, native = prepared / name, controls / name / 'native-timing'
        spec = driver.load(original / 'spec.json')
        run = record(output, name + '-production-timing-host', [tools['NODE'], '--disable-warning=ExperimentalWarning',
                     controls / 'reader-timing.mjs', original / 'optimized.wasm', original / 'spec.json'], environment, original)
        if json.loads(run['stdout'])['result'] != 1 or run['stderr']:
            raise ValueError('production V8 timing host changed the full-count result')
        for case in [edge_cases(name, (original / spec['pathnames'][0]).read_bytes(), spec['expected_datum'])[0],
                     dict(label='malformed', data=b'1.0 1e following', expected=spec['expected_datum'], failure=True)]:
            target = output / (name + '-' + case['label'])
            target.mkdir()
            configured = input_text(1, spec['pathnames'][0], case['expected'])
            seed_files(target, spec, configured, case['data'])
            driver.save(target / 'spec.json', dict(spec, count=1))
            commands = [('native', [native / 'native']), ('shared-module-v8', [tools['NODE'], '--disable-warning=ExperimentalWarning',
                        controls / 'reader-host.mjs', native / 'native-final.wasm', target / 'spec.json', native / 'provider.wasm'])]
            for system, command in commands:
                run = record(target, system, command, environment, target, failure=case.get('failure', False))
                if case.get('failure'):
                    if 'invalid numeric token or identifier' not in run['stderr']:
                        raise ValueError('reader diagnostic disappeared at the separate provider boundary')
                    if system == 'shared-module-v8':
                        value = json.loads(run['stdout'])
                        if not value['failed'] or value['setup_closed'] != 1 or value['worker_closed'] + value['cleanup_closed'] != 1:
                            raise ValueError('separate provider did not close the failed worker input')
                elif json.loads(run['stdout'])['result'] != 0:
                    raise ValueError('timing control lost the original negative predicate')
            if not case.get('failure'):
                for system, command in rust_commands(controls / 'rust-reference', name, tools):
                    run = record(target, 'rust-' + system, command, environment, target, configured.decode(), failure=True)
                    if not run['stderr']:
                        raise ValueError('Rust wrong expected value did not report its assertion')
            observations.append(dict(name=name, label=case['label'], passed=True))
    driver.save(output / 'validation.json', observations)


# ---- A separate freeze adds controls without rewriting preparation attempts ----

def prepare_comparison(prepared, output, driver):
    manifest, tools = driver.load(prepared / 'prepared.json'), driver.tool_paths(NAMES)
    if {case['name']: case['status'] for case in manifest['cases']} != {name: 'ready' for name in NAMES}:
        raise ValueError('both full reader workloads must pass preparation first')
    for name, digest in manifest['compiler_files'].items():
        if driver.digest(driver.ROOT / name) != digest:
            raise ValueError('compiler changed after canonical preparation: ' + name)
    output.mkdir(parents=True)
    for name in ('reader_ports.py', 'reader-host.mjs', 'reader-timing.mjs', 'matrix_port.py'):
        shutil.copy2(driver.HERE / name, output / name)
    environment = dict(os.environ, **tools, BINARYEN_CORES='1')
    matrix_port.retain_toolchain(output, tools, environment, driver)
    driver.save(output / 'source-preparation.json', dict(path=str(prepared), sha256=driver.digest(prepared / 'prepared.json'),
                compiler_commit=manifest['compiler_commit'], compiler_files=manifest['compiler_files']))
    for name in NAMES:
        target = output / name
        target.mkdir()
        prepare_native_control(prepared / name, target / 'native-timing', tools, environment, driver)
        validate_common_observation(prepared / name, target / 'common-observation', tools, environment, driver)
    shutil.copy2(driver.ROOT / 'build/native-runtime/release/libsnail_runtime.a', output / 'libsnail_runtime.a')
    prepare_rust_controls(prepared, output / 'rust-reference', tools, environment, driver)
    validate_control_boundaries(prepared, output, output / 'boundary-validation', tools, environment, driver)
    driver.save(output / 'prepared.json', dict(status='ready', original_preparation=str(prepared),
                compiler_commit=manifest['compiler_commit'], tools={key: dict(path=value, sha256=driver.digest(value)) for key, value in tools.items()},
                hashes={str(path.relative_to(output)): driver.digest(path) for path in output.rglob('*') if path.is_file()}))


if __name__ == '__main__':
    import argparse
    import measure as driver
    parser = argparse.ArgumentParser(description='Freeze the seven full reader workload controls after canonical preparation.')
    parser.add_argument('--prepared', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    arguments = parser.parse_args()
    previous = signal.signal(signal.SIGTERM, interrupted)
    try:
        prepare_comparison(arguments.prepared.resolve(), arguments.output.resolve(), driver)
    finally:
        signal.signal(signal.SIGTERM, previous)
