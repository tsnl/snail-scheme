#!/usr/bin/env python3
"""Check frozen Chez Number controls and exact scalar-formatting bytes."""

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

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'tests/sfir-numbers'
CONTROLS = FIXTURES / 'chez'

execute = runpy.run_path(str(ROOT / 'scripts/test-sfir-integer'))['execute']
ENVIRONMENT = dict(os.environ, BINARYEN_CORES='1')


# ---- The existing independent Number oracle also checks the Chez control ----


def case_data(cases):
    return ''.join('#(' + ' '.join([json.dumps(item['label']), str(item['operation']),
        json.dumps(item['a']), json.dumps(item['b']), item['input'], item['bits'],
        json.dumps(item['text']), '#t' if item['error'] else '#f']) + ')\n' for item in cases)


def check_domain(libraries, output):
    cases = runpy.run_path(str(libraries / 'tests/sfir-numbers/domain.py'))['fixtures']()
    data = output / 'domain-input.scm'; data.write_text(case_data(cases))
    (output / 'domain-oracle.json').write_text(json.dumps(cases, indent=2) + '\n')
    record = execute(['scheme', '--script', CONTROLS / 'domain.scm', data],
                     output / 'domain-chez.json', ENVIRONMENT)
    assert record['stdout'] == str(len(cases)) + '\n', record
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
    body = source[source.index('fn float_text('):source.index('// ---- Tests ----')]
    rust = FIXTURES / 'format-reference.rs'
    assert rust.read_text().startswith(body + 'fn main()'), 'static Rust formatter reference drifted'
    bits = formatting_bits(); data = output / 'format-input.txt'
    data.write_text(''.join(f'{value:016x}\n' for value in bits))
    binary = output / 'format-reference'
    execute(['rustc', '-O', rust, '-o', binary], output / 'format-reference-build.json', ENVIRONMENT)
    reference = execute([binary, data], output / 'format-reference-run.json', ENVIRONMENT)['stdout'].splitlines()
    actual = execute(['scheme', '--script', CONTROLS / 'format.scm', data],
                     output / 'format-chez.json', ENVIRONMENT)['stdout'].splitlines()
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
    data = output / 'scalar-input.scm'; data.write_text(case_data(cases))
    record = execute(['scheme', '--script', CONTROLS / 'scalar.scm', data],
                     output / 'scalar-chez.json', ENVIRONMENT)
    assert record['stdout'] == str(len(cases)) + '\n', record
    execute(['scheme', '--script', CONTROLS / 'ownership.scm'],
            output / 'ownership-chez.json', ENVIRONMENT)


def check_abi(target, runtime, output, cases):
    fixture = target / 'tests/sfir-numbers'
    wasm = output / 'scalar.wasm'; native = output / 'scalar-native'
    valid_cases = output / 'scalar-valid.json'
    valid_cases.write_text(json.dumps([item for item in cases if not item['error']], indent=2) + '\n')
    failures = []
    for index, item in enumerate(item for item in cases if item['error']):
        path = output / f'scalar-failure-{index}-oracle.json'
        path.write_text(json.dumps([dict(item, error=False)], indent=2) + '\n')
        failures.append((index, item, path))
    execute([target / 'scripts/build-sfir', '--export', 'probe', ROOT / 'tests/sfir-numbers/bridge.sfir', wasm],
            output / 'scalar-compile.json', ENVIRONMENT)
    for kind, source in [('raw', Path(str(wasm) + '.raw.wasm')), ('optimized', wasm)]:
        linked = output / f'scalar-{kind}-linked.wasm'
        flags = ['--diagnostic-prune-only'] if kind == 'raw' else []
        execute([target / 'scripts/link-sfir-runtime', '--runtime', runtime, *flags, source, linked],
                output / f'scalar-{kind}-link.json', ENVIRONMENT)
        execute(['node', '--disable-warning=ExperimentalWarning', fixture / 'oracle.mjs', linked, valid_cases],
                output / f'scalar-{kind}-run.json', ENVIRONMENT)
        # Rust scalar failures are terminal WASI failures, not recoverable guest
        # unreachable traps. Each negative call owns a fresh supervised process.
        for index, item, path in failures:
            record = execute(['node', '--disable-warning=ExperimentalWarning', fixture / 'oracle.mjs', linked, path],
                             output / f'scalar-{kind}-failure-{index}.json', ENVIRONMENT, expected='error')
            assert item['message'] in record['stderr'], record
    transport = target / 'tests/sfir-integer'
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


def checked_library_profile(libraries, provenance):
    actual = {name: hashlib.sha256((libraries / name).read_bytes()).hexdigest()
              for name in provenance['sfir_libraries']}
    profiles = {'original-freeze': provenance['sfir_libraries']}
    profiles.update({review['name']: review['sfir_libraries']
                     for review in provenance.get('compatibility_reviews', [])})
    for name, expected in profiles.items():
        if actual == expected:
            return name
    raise ValueError('SFIR libraries do not match a complete reviewed Chez control profile')


def record_inputs(libraries, target, runtime, output):
    provenance = json.loads((CONTROLS / 'provenance.json').read_text())
    profile = checked_library_profile(libraries, provenance)
    (output / 'library-review.json').write_text(json.dumps(dict(profile=profile), indent=2) + '\n')
    for name, expected in provenance['fixtures'].items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == expected, name
    files = [Path(__file__), FIXTURES / 'bridge.sfir', FIXTURES / 'domain.sfir',
             FIXTURES / 'domain.py', FIXTURES / 'format-reference.rs', *CONTROLS.glob('*')]
    files += [libraries / name for name in provenance['sfir_libraries']]
    files += [target / f'src/{name}' for name in ['lib.rs', 'strict_number.rs', 'strict_datum.rs']]
    files += [target / 'scripts' / name for name in ['build-sfir', 'link-sfir-runtime', 'build-native']]
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


def checked_benchmark(output, name):
    rows = [line.removeprefix('+!CSVLINE!+').split(',') for line in output.splitlines()
            if line.startswith('+!CSVLINE!+')]
    assert len(rows) == 1 and len(rows[0]) == 3, output
    system, benchmark, duration = rows[0]
    assert system == 'chez' and benchmark.split(':', 1)[0] == name and duration != 'INCORRECT', rows
    assert math.isfinite(float(duration)) and float(duration) > 0, rows


def check_reader_controls(benchmarks, output):
    directory = output / 'reader-controls'; directory.mkdir()
    cases = runpy.run_path(str(ROOT / 'scripts/test-sfir-reader'))['valid_cases']()
    observations = []
    for name, sources in cases.items():
        source, oracle = sources if isinstance(sources, tuple) else (sources, sources)
        records = []
        for system, text in [('original', oracle), ('adapted', source)]:
            working = directory / name / system; working.mkdir(parents=True)
            (working / 'input.scm').write_text(text)
            program = ROOT / 'tests/sfir-reader/oracle.scm' if system == 'original' else CONTROLS / 'reader.scm'
            records.append(execute(['scheme', '--script', program], working / 'run.json', ENVIRONMENT, cwd=working))
        assert records[0]['stdout'] == records[1]['stdout'], name
        observations.append(dict(name=name, fields=len(records[0]['stdout'].splitlines()),
                                 sha256=hashlib.sha256(records[0]['stdout'].encode()).hexdigest()))
    (directory / 'streams.json').write_text(json.dumps(observations, indent=2) + '\n')
    print(f'PASS {len(cases)} complete adapted reader streams', flush=True)
    for name in ['sum1', 'read1', 'parsing']:
        static = benchmarks / 'benchmarks/sfir' / name
        data = (static / 'input.txt').read_bytes()
        for system in ['original', 'adapted']:
            working = directory / name / system; (working / 'inputs').mkdir(parents=True)
            (working / 'input.txt').write_bytes(data)
            for file in ['sum1.data', 'parsing.data']:
                original = ROOT / 'benchmarks/r7rs-benchmarks/inputs' / file
                (working / 'inputs' / file).write_bytes(original.read_bytes())
            program = static / ('chez-' + system + '.scm')
            snapshot = working / 'control.scm'; snapshot.write_bytes(program.read_bytes())
            identity = dict(path=str(program), sha256=hashlib.sha256(snapshot.read_bytes()).hexdigest(),
                            input_sha256=hashlib.sha256(data).hexdigest())
            (working / 'source.json').write_text(json.dumps(identity, indent=2) + '\n')
            record = execute(['scheme', '--script', program], working / 'canonical.json',
                             ENVIRONMENT, cwd=working, stdin=data.decode())
            checked_benchmark(record['stdout'], name)
            assert program.read_bytes() == snapshot.read_bytes(), program
        print(f'PASS complete canonical {name}: original and adapted Chez', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library-root', type=Path, default=ROOT)
    parser.add_argument('--target-root', type=Path, default=ROOT)
    parser.add_argument('--runtime', type=Path, help='Also run linked raw/optimized Wasm and actual native64')
    parser.add_argument('--reader-root', type=Path, help='Also check reader streams and static canonical controls in this benchmark root')
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
    print(f'PASS static Chez bridge: {count} Number cases, {formats} Rust text comparisons, {len(cases)} scalar cases; '
          f'linked Wasm/native64 checked: {bool(options.runtime)}', flush=True)


if __name__ == '__main__':
    main()
