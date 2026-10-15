#!/usr/bin/env python3
"""Check compiler-port foundations; this does not run the compiler workload."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/strict-suite'))
import compiler_port
import reader_ports

# Reuse the reviewed process-group owner: timeouts kill and drain descendants,
# and every invocation retains its return code and unmodified output streams.
execute = runpy.run_path(str(ROOT / 'scripts/test-strict-integer'))['execute']
ENVIRONMENT = dict(os.environ, BINARYEN_CORES='1')


# ---- Identical bodies, with target-specific assertion entry points ----


def chez_source(support, fixture, failure):
    prelude = reader_ports.chez_reader(ROOT, ['datum-boolean', 'datum-boolean-value', 'datum-fail'])
    if failure:
        return prelude + support + fixture
    start, end = list(compiler_port.source_forms(fixture))[-1]
    check = ('(let ((result ' + fixture[start:end] + '))\n'
             '  (unless (= result 42) (error \'probe "unexpected result" result))\n'
             '  (display "PASS compiler internal probe: 42\\n"))\n')
    return prelude + support + fixture[:start] + check


def check_probe(output, name, support_name, failure=None):
    support = (ROOT / f'benchmarks/strict-suite/compiler-{support_name}.scm').read_text() + '\n'
    fixture = (ROOT / f'tests/strict-compiler/{name}.scm').read_text()
    source, chez, wasm = [output / (name + suffix) for suffix in ['.scm', '.chez.scm', '.wasm']]
    source.write_text('(import (snail strict) (snail datum))\n' + support + fixture)
    chez.write_text(chez_source(support, fixture, failure))
    records = [execute(['scheme', '--script', chez], output / f'{name}-chez.json', ENVIRONMENT,
                       expected='error' if failure else 0)]
    execute([ROOT / 'scripts/build-strict', source, wasm], output / f'{name}-build.json', ENVIRONMENT)
    for kind, module in [('raw', Path(str(wasm) + '.raw.wasm')), ('optimized', wasm)]:
        linked = output / f'{name}-linked-{kind}.wasm'
        flags = ['--diagnostic-prune-only'] if kind == 'raw' else []
        execute([ROOT / 'scripts/link-strict-runtime', '--runtime', output / 'runtime.wasm',
                 *flags, module, linked], output / f'{name}-{kind}-link.json', ENVIRONMENT)
        records.append(execute(['node', '--disable-warning=ExperimentalWarning',
                                ROOT / 'tests/strict-compiler/data-probe.mjs', linked],
                               output / f'{name}-{kind}-run.json', ENVIRONMENT,
                               expected='error' if failure else 0))
    native = output / f'{name}-native'
    execute([ROOT / 'scripts/build-native', '--wasm', wasm, native],
            output / f'{name}-native-build.json', ENVIRONMENT)
    records.append(execute([native], output / f'{name}-native-run.json', ENVIRONMENT,
                           expected='error' if failure else 42))
    if failure:
        assert all(failure in record['stderr'] for record in records), records
    print('PASS', name, 'Chez/raw/optimized/native64', flush=True)


# ---- Original source controls and complete input preservation ----


def record_source(output):
    corpus = ROOT / 'benchmarks/r7rs-benchmarks'
    source = (corpus / 'src/compiler.scm').read_text()
    data = (corpus / 'inputs/compiler.input').read_bytes()
    (output / 'compiler-original.scm').write_text(source)
    (output / 'compiler.input').write_bytes(data)
    forms, spec = compiler_port.source_inventory(source), compiler_port.specification(data)
    assert len(forms) == 1345 and sum(form['name'] is not None for form in forms) == 1344
    assert spec['count'] == 2000 and len(spec['expected_lines']) == 497
    suffix = '\n(define after-harness (list #\\( #\\) "quoted ( )"))\n'
    assert compiler_port.kernel(source + suffix).endswith(suffix)
    inventory = dict(source_sha256=hashlib.sha256(source.encode()).hexdigest(), forms=forms, specification=spec)
    (output / 'source-inventory.json').write_text(json.dumps(inventory, indent=2) + '\n')
    return source


def check_original_controls(output, source):
    prefixes = ['(define (fatal-err ', '(define (with-exception-handling ',
                '(define (throw-to-exception-handler ', '(define (compiler-abort)']
    controls = '\n'.join(compiler_port.named_form(source, prefix) for prefix in prefixes)
    original = output / 'result-original-probe.scm'
    original.write_text(controls + '\n' + (ROOT / 'tests/strict-compiler/result-original-probe.scm').read_text())
    execute(['scheme', '--script', original], output / 'result-original-chez.json', ENVIRONMENT)
    execute(['scheme', '--script', ROOT / 'tests/strict-compiler/original-map-mutation.scm'],
            output / 'original-map-mutation-chez.json', ENVIRONMENT)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--runtime', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True)  # An existing directory is never overwritten.
    shutil.copy2(args.runtime, output / 'runtime.wasm')
    (output / 'runtime.json').write_text(json.dumps(dict(source=str(args.runtime.resolve()),
        sha256=hashlib.sha256((output / 'runtime.wasm').read_bytes()).hexdigest()), indent=2) + '\n')
    check_original_controls(output, record_source(output))
    check_probe(output, 'data-probe', 'data')
    check_probe(output, 'result-probe', 'result')
    check_probe(output, 'result-host-failure', 'result', 'compiler probe ordinary host failure')
    check_probe(output, 'result-no-handler', 'result', 'Internal error, no exception handler at this point')


if __name__ == '__main__':
    main()
