#!/usr/bin/env python3
"""Check the shared Chez Number bodies and exact scalar-formatting bytes."""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import random
import runpy
import struct
import sys
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/strict-suite'))
import compiler_port
import reader_ports

execute = runpy.run_path(str(ROOT / 'scripts/test-strict-integer'))['execute']
ENVIRONMENT = dict(os.environ, BINARYEN_CORES='1')


# ---- The existing independent Number oracle also checks the Chez control ----


EXPORTS = '''string->number number->string number-equivalent? inexact-number
number-exact number-inexact number-numerator number-denominator number-real-part
number-imag-part number-negate number-abs number-from-integer number->integer
number->f64 number-exact? number-real? number-rational? number-integer?
number-exact-integer? number-add number-subtract number-multiply number-divide
number-truncate number=? number<? number<=? number>? number>=? parsed-number-value
integer->i64 integer-from-string integer-from-string/radix'''.split()
TRANSPORT = '''(define case-arguments (vector "" ""))
(define case-output (open-output-string))
(define (argument-length index) (string-length (vector-ref case-arguments index)))
(define (argument-character index at) (string-ref (vector-ref case-arguments index) at))
(define (emit-character character) (write-char character case-output))
(define (float-from-bits bits)
  (let ((bytes (make-bytevector 8)))
    (bytevector-u64-native-set! bytes 0 bits) (bytevector-ieee-double-native-ref bytes 0)))
(define (float-bits value)
  (let ((bytes (make-bytevector 8)))
    (bytevector-ieee-double-native-set! bytes 0 value) (bytevector-u64-native-ref bytes 0)))
'''
DOMAIN_CHECK = '''(define (check-case item)
  (set! case-arguments (vector (vector-ref item 2) (vector-ref item 3)))
  (set! case-output (open-output-string))
  (let* ((failed #f)
         (value (guard (condition (else (set! failed #t) 0.0))
                  (probe (vector-ref item 1) (float-from-bits (vector-ref item 4))))))
    (unless (eq? failed (vector-ref item 7)) (error 'domain "failure status" item failed))
    (unless failed
      (let ((text (get-output-string case-output)))
        (unless (and (= (float-bits value) (vector-ref item 5)) (string=? text (vector-ref item 6)))
          (error 'domain "wrong result" item value text))))))
'''


def domain_body(libraries):
    source = (libraries / 'tests/strict-numbers/domain.scm').read_text()
    bodies = [source[start:end] for start, end in compiler_port.source_forms(source)]
    source = '\n'.join(body for body in bodies if not body.startswith(('(import ', '(define-extern ')))
    # Resolve only the Number operations that the strict checker selects here.
    # The library implementations themselves remain byte-for-byte unchanged.
    edits = []
    for before, after in [*(('(' + op + ' left right)', '(' + name + ' left right)') for op, name in
                           [('+', 'number-add'), ('-', 'number-subtract'), ('*', 'number-multiply'),
                            ('/', 'number-divide'), ('=', 'number=?'), ('<', 'number<?'),
                            ('<=', 'number<=?'), ('>', 'number>?'), ('>=', 'number>=?')]),
                          ('(truncate value)', '(number-truncate value)')]:
        assert source.count(before) == 1, before
        source = source.replace(before, after)
        edits.append(dict(before=before, after=after, count=1))
    return source, edits


def check_domain(libraries, output):
    cases = runpy.run_path(str(libraries / 'tests/strict-numbers/domain.py'))['fixtures']()
    body, edits = domain_body(libraries)
    rows = ['#(' + ' '.join([json.dumps(item['label']), str(item['operation']), json.dumps(item['a']),
                            json.dumps(item['b']), item['input'], item['bits'], json.dumps(item['text']),
                            '#t' if item['error'] else '#f']) + ')' for item in cases]
    source = reader_ports.chez_reader(libraries, EXPORTS) + TRANSPORT + body + '\n' + DOMAIN_CHECK
    source += "(for-each check-case '(\n" + '\n'.join(rows) + '))\n'
    source += f'(display "PASS {len(cases)} shared Number contracts under Chez\\n")\n'
    path = output / 'domain.chez.scm'; path.write_text(source)
    (output / 'domain-oracle.json').write_text(json.dumps(cases, indent=2) + '\n')
    (output / 'domain-static-resolution.json').write_text(json.dumps(edits, indent=2) + '\n')
    execute(['scheme', '--script', path], output / 'domain-chez.json', ENVIRONMENT)
    return len(cases)


# ---- Byte comparison includes boundaries and many binary64 significands ----


def formatting_bits():
    values = [0, 1, 2, 3, 0x000fffffffffffff, 0x0010000000000000,
              0x7fefffffffffffff, 0x7ff0000000000000, 0x7ff8000000000000]
    for power in [-324, -308, -5, -4, -3, 0, 15, 16, 17, 22, 23, 308]:
        value = 10.0 ** power
        for neighbor in [math.nextafter(value, -math.inf), value, math.nextafter(value, math.inf)]:
            values.append(struct.unpack('>Q', struct.pack('>d', neighbor))[0])
    values += [value ^ (1 << 63) for value in values]
    rng = random.Random(0xC0FFEE)
    return sorted(set(values + [rng.getrandbits(64) for _ in range(20000)]))


def check_formatting(libraries, output):
    source = (libraries / 'src/lib.rs').read_text()
    body = source[source.index('fn float_text('):source.index('// ---- Inexact mathematics ----')]
    rust = output / 'format-reference.rs'
    rust.write_text(body + '''fn main() {
    let input = std::fs::read_to_string(std::env::args().nth(1).unwrap()).unwrap();
    for line in input.lines() {
        println!("{}", float_text(f64::from_bits(u64::from_str_radix(line, 16).unwrap())));
    }
}
''')
    bits = formatting_bits(); data = output / 'format-input.txt'
    data.write_text(''.join(f'{value:016x}\n' for value in bits))
    numeric = (ROOT / 'benchmarks/strict-suite/chez-number.scm').read_text()
    chez = output / 'format.chez.scm'
    chez.write_text(reader_ports.CHEZ_TYPES + '(define binary64-text\n'
                    '(let ((host-string->number string->number) (host-number->string number->string))\n'
                    + numeric + '\nbinary64-text))\n' + TRANSPORT + f'''
(call-with-input-file {json.dumps(str(data))}
  (lambda (port)
    (let loop ()
      (let ((line (get-line port)))
        (unless (eof-object? line)
          (display (binary64-text (float-from-bits (string->number line 16)))) (newline) (loop))))))
''')
    binary = output / 'format-reference'
    execute(['rustc', '-O', rust, '-o', binary], output / 'format-reference-build.json', ENVIRONMENT)
    reference = execute([binary, data], output / 'format-reference-run.json', ENVIRONMENT)['stdout'].splitlines()
    actual = execute(['scheme', '--script', chez], output / 'format-chez.json', ENVIRONMENT)['stdout'].splitlines()
    mismatches = [dict(bits=f'{value:016x}', rust=want, chez=got)
                  for value, want, got in zip(bits, reference, actual) if want != got]
    report = dict(cases=len(bits), reference_lines=len(reference), actual_lines=len(actual),
                  rust_body_sha256=hashlib.sha256(body.encode()).hexdigest(), mismatches=mismatches)
    (output / 'format-comparison.json').write_text(json.dumps(report, indent=2) + '\n')
    assert len(reference) == len(actual) == len(bits) and not mismatches, report
    return len(bits)


# ---- The scalar ABI observes lexical fields before numeric construction ----


def scalar_cases(output):
    cases = []
    def add(label, operation, a='', radix=10, text='', error=None, bits='0'):
        cases.append(dict(label=label, operation=operation, a=a, b=str(radix), input=bits,
                          bits='0', text=text, error=bool(error), message=error))
    scale_error = '4|exact decimal exponent exceeds supported allocation index range'
    for text, expected in [
            ('', '0'), ('123abc', '0'), ('1e', '0'), ('1s2', '0'), ('1.2.3', '0'),
            ('1/0/2', '0'), ('1/-2', '0'), ('#e#i1', '0'), ('#x#b1', '0'),
            ('-9223372036854775808', '1|1:-9223372036854775808'),
            ('9223372036854775808', '5|5:10:0:9223372036854775808/1'),
            ('#x#i-A/B', '6|6:16:0:-A/B'), ('#i-0/7', '6|6:10:0:-0/7'),
            ('#i-0', '2|2:-0.0'), ('#e12.5e-3', '5|5:10:-4:125/1'),
            ('#e.1e9223372036854775808', '5|5:10:9223372036854775807:1/1'),
            ('#e1e9223372036854775808', scale_error),
            ('#e1.0e-9223372036854775807', scale_error),
            ('#e0.0e999999999999999999999999999999999999999999', '1|1:0'),
            ('#e0.0e+', '0'), ('#e+inf.0', '4|nonfinite number has no exact value'),
            ('#eNaN', '0'), ('0@1/0', '4|zero denominator in numeric token'),
            ('bad@1/0', '4|zero denominator in numeric token'),
            ('1/0@bad', '4|zero denominator in numeric token'),
            ('+i', '3|1:0|1:1'), ('#i+i', '3|2:0.0|2:1.0'),
            ('1/2+3/4i', '3|5:10:0:1/2|5:10:0:+3/4'),
            ('1.0+0i', '3|2:1.0|1:0'), ('1-0.0i', '3|1:1|2:-0.0'),
            ('#e1@1', '8|1:1|1:1'), ('1@0', '7|1:1|1:0'),
            ('0e999999999999999999999999999999999', '2|2:0.0'),
            ('-1e999999999999999999999999999999999', '2|2:-inf.0')]:
        add('metadata-' + text, 0, text, text=expected)
    for source, radix, text in [('FF', 16, '1|1:255'), ('#x10', 2, '1|1:16'),
                               ('1', 3, '0'), ('101', 2, '1|1:5')]:
        add(f'radix-{source}-{radix}', 0, source, radix, text)
    for operation, source, message in [
            (2, '1.0', 'numeric component is not a machine integer'),
            (3, '1', 'numeric component is not inexact'),
            (4, '1', 'invalid or closed token handle'),
            (5, '1', 'token has already been parsed'),
            (6, '1', 'token has already been parsed'),
            (7, '1', 'symbol interning requires an unparsed text handle'),
            (7, '1/0', 'symbol interning requires an unparsed text handle'),
            (7, 'symbol', 'invalid or closed token handle'),
            (8, '1', 'invalid or closed token handle'),
            (9, '1', 'numeric component has no exact digit fields'),
            (10, '1+2i', 'numeric component index out of range'),
            (11, '1', 'invalid or closed token handle'),
            (12, '1/0', 'invalid or closed token handle')]:
        add(f'ownership-or-kind-{operation}-{source}', operation, source, error=message)
    inputs = (output / 'format-input.txt').read_text().splitlines()
    texts = json.loads((output / 'format-reference-run.json').read_text())['stdout'].splitlines()
    for bits, text in zip(inputs, texts):
        add('binary64-' + bits, 1, text=text, bits=str(int(bits, 16)))
    return cases


def scalar_control(libraries, output, cases):
    source = (ROOT / 'tests/strict-numbers/bridge.scm').read_text()
    externs = '''(define-syntax define-extern
  (syntax-rules () ((_ name module foreign signature)
    (define name (if (string=? module "oracle")
                    (cond ((string=? foreign "argument_length") argument-length)
                          ((string=? foreign "argument_character") argument-character)
                          (else emit-character))
                    (scalar-service foreign))))))
'''
    # Transport declarations are supplied above; preserve every other body.
    forms = [source[start:end] for start, end in compiler_port.source_forms(source)]
    body = '\n'.join(form for form in forms if not form.startswith('(import ')
                     and not (form.startswith('(define-extern ') and '"oracle"' in form))
    rows = ['#(' + ' '.join([json.dumps(item['label']), str(item['operation']), json.dumps(item['a']),
                            json.dumps(item['b']), item['input'], item['bits'], json.dumps(item['text']),
                            '#t' if item['error'] else '#f']) + ')' for item in cases]
    path = output / 'scalar.chez.scm'
    path.write_text(reader_ports.chez_reader(libraries, ['scalar-service']) + TRANSPORT + externs + body
                    + '\n' + DOMAIN_CHECK + "(for-each check-case '(\n" + '\n'.join(rows) + '))\n'
                    + f'(display "PASS {len(cases)} scalar ABI cases under Chez\\n")\n')
    execute(['scheme', '--script', path], output / 'scalar-chez.json', ENVIRONMENT)
    ownership = output / 'ownership.chez.scm'
    ownership.write_text(reader_ports.chez_reader(libraries, ['scalar-service'])
                         + (ROOT / 'tests/strict-numbers/bridge-ownership.scm').read_text())
    execute(['scheme', '--script', ownership], output / 'ownership-chez.json', ENVIRONMENT)


def check_abi(target, runtime, output, cases):
    fixture = target / 'tests/strict-numbers'
    wasm = output / 'scalar.wasm'; native = output / 'scalar-native'
    valid_cases = output / 'scalar-valid.json'
    valid_cases.write_text(json.dumps([item for item in cases if not item['error']], indent=2) + '\n')
    failures = []
    for index, item in enumerate(item for item in cases if item['error']):
        path = output / f'scalar-failure-{index}-oracle.json'
        path.write_text(json.dumps([dict(item, error=False)], indent=2) + '\n')
        failures.append((index, item, path))
    execute([target / 'scripts/build-strict', '--export', 'probe', ROOT / 'tests/strict-numbers/bridge.scm', wasm],
            output / 'scalar-compile.json', ENVIRONMENT)
    for kind, source in [('raw', Path(str(wasm) + '.raw.wasm')), ('optimized', wasm)]:
        linked = output / f'scalar-{kind}-linked.wasm'
        flags = ['--diagnostic-prune-only'] if kind == 'raw' else []
        execute([target / 'scripts/link-strict-runtime', '--runtime', runtime, *flags, source, linked],
                output / f'scalar-{kind}-link.json', ENVIRONMENT)
        execute(['node', '--disable-warning=ExperimentalWarning', fixture / 'oracle.mjs', linked, valid_cases],
                output / f'scalar-{kind}-run.json', ENVIRONMENT)
        # Rust scalar failures are terminal WASI failures, not recoverable guest
        # unreachable traps. Each negative call owns a fresh supervised process.
        for index, item, path in failures:
            record = execute(['node', '--disable-warning=ExperimentalWarning', fixture / 'oracle.mjs', linked, path],
                             output / f'scalar-{kind}-failure-{index}.json', ENVIRONMENT, expected='error')
            assert item['message'] in record['stderr'], record
    transport = target / 'tests/strict-integer'
    execute([target / 'scripts/build-native', '--wasm', '--c-provider', 'oracle', transport / 'oracle.h',
             transport / 'oracle-provider.c', '--entry-c', fixture / 'oracle.c', wasm, native],
            output / 'scalar-native-build.json', ENVIRONMENT)
    def rows(items):
        return ''.join('\t'.join(str(item[key]) for key in ['operation', 'a', 'b', 'input', 'bits', 'text']) + '\n' for item in items)
    valid = output / 'scalar-valid.tsv'; valid.write_text(rows(item for item in cases if not item['error']))
    execute([native, valid], output / 'scalar-native-run.json', ENVIRONMENT)
    for index, item in enumerate(item for item in cases if item['error']):
        path = output / f'scalar-failure-{index}.tsv'; path.write_text(rows([item]))
        record = execute([native, path], output / f'scalar-failure-{index}.json', ENVIRONMENT, expected='error')
        assert item['message'] in record['stderr'], record


def record_inputs(libraries, target, runtime, output):
    files = [Path(__file__), ROOT / 'benchmarks/strict-suite/reader_ports.py',
             ROOT / 'benchmarks/strict-suite/chez-number.scm', ROOT / 'tests/strict-numbers/bridge.scm',
             ROOT / 'tests/strict-numbers/bridge-ownership.scm']
    files += [libraries / f'src/snail/{name}.sld' for name in ['integer', 'rational', 'number', 'datum', 'read']]
    files += [libraries / 'tests/strict-numbers/domain.scm', libraries / 'tests/strict-numbers/domain.py']
    files += [target / f'src/{name}' for name in ['lib.rs', 'strict_number.rs', 'strict_datum.rs']]
    files += [target / 'scripts' / name for name in ['build-strict', 'link-strict-runtime', 'build-native']]
    records = []
    snapshots = output / 'sources'; snapshots.mkdir()
    for index, path in enumerate(files):
        data = path.read_bytes(); copy = snapshots / f'{index}-{path.name}'; copy.write_bytes(data)
        records.append(dict(path=str(path), copy=str(copy), sha256=hashlib.sha256(data).hexdigest()))
    if runtime:
        data = runtime.read_bytes(); copy = output / 'runtime.wasm'; copy.write_bytes(data)
        records.append(dict(path=str(runtime), copy=str(copy), sha256=hashlib.sha256(data).hexdigest()))
        runtime = copy
    (output / 'inputs.json').write_text(json.dumps(records, indent=2) + '\n')
    return runtime


# ---- Complete reader streams and canonical benchmark controls ----


def check_reader_controls(root, output):
    directory = output / 'reader-controls'; directory.mkdir()
    stream = directory / 'adapted-stream.scm'
    stream.write_text(reader_ports.bridge_stream_program(root))
    cases = runpy.run_path(str(root / 'scripts/test-strict-reader'))['valid_cases']()
    observations = []
    for name, sources in cases.items():
        source, oracle = sources if isinstance(sources, tuple) else (sources, sources)
        records = []
        for system, text in [('original', oracle), ('adapted', source)]:
            working = directory / name / system; working.mkdir(parents=True)
            (working / 'input.scm').write_text(text)
            program = root / 'tests/strict-reader/oracle.scm' if system == 'original' else stream
            records.append(reader_ports.record(working, 'run', ['scheme', '--script', program], ENVIRONMENT))
        assert records[0]['stdout'] == records[1]['stdout'], name
        observations.append(dict(name=name, fields=len(records[0]['stdout'].splitlines()),
                                 sha256=hashlib.sha256(records[0]['stdout'].encode()).hexdigest()))
    (directory / 'streams.json').write_text(json.dumps(observations, indent=2) + '\n')
    print(f'PASS {len(cases)} complete adapted reader streams', flush=True)
    # Loading the existing generators executes no preparation or compilation.
    sys.path.append(str(root / 'benchmarks/strict-suite'))
    driver = SimpleNamespace(**runpy.run_path(str(root / 'benchmarks/strict-suite/measure.py')))
    runner = driver.upstream_runner(); files = runner.suite_sources()
    for name in ['sum1', 'read1', 'parsing']:
        target = directory / name; target.mkdir()
        data = files[f'inputs/{name}.input']; (target / 'input.txt').write_bytes(data)
        if name == 'parsing':
            driver.parsing_port.write_sources(files, target, runner, driver)
        else:
            reader_ports.write_sources(name, files, target, runner, driver)
        for system in ['chez', 'chez-adapted']:
            working = target / system; (working / 'inputs').mkdir()
            for path in ['sum1.data', 'parsing.data']:
                (working / 'inputs' / path).write_bytes(files['inputs/' + path])
            result = reader_ports.record(working, 'canonical', ['scheme', '--script', working / 'program.scm'],
                                         ENVIRONMENT, stdin=data.decode())
            assert runner.parse_result(result['stdout'], 'chez', name)['status'] == 'ok', result
        print(f'PASS complete canonical {name}: original and adapted Chez', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library-root', type=Path, default=ROOT)
    parser.add_argument('--target-root', type=Path, default=ROOT)
    parser.add_argument('--runtime', type=Path, help='Also run linked raw/optimized Wasm and actual native64')
    parser.add_argument('--reader-root', type=Path, help='Also check complete reader streams and canonical controls')
    parser.add_argument('--output', type=Path, required=True)
    options = parser.parse_args(); output = options.output.resolve(); output.mkdir(parents=True)
    libraries = options.library_root.resolve()
    target = options.target_root.resolve()
    runtime = record_inputs(libraries, target, options.runtime.resolve() if options.runtime else None, output)
    count = check_domain(libraries, output)
    formats = check_formatting(libraries, output)
    cases = scalar_cases(output)
    (output / 'scalar-oracle.json').write_text(json.dumps(cases, indent=2) + '\n')
    scalar_control(libraries, output, cases)
    if runtime:
        check_abi(target, runtime, output, cases)
    if options.reader_root:
        check_reader_controls(options.reader_root.resolve(), output)
    print(f'PASS Chez bridge: {count} Number cases, {formats} Rust text comparisons, {len(cases)} scalar cases; '
          f'linked Wasm/native64 checked: {bool(options.runtime)}', flush=True)


if __name__ == '__main__':
    main()
