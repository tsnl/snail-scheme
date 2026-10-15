#!/usr/bin/env python3
"""Check recursive groups at inference and on identical Wasm/native guests."""

import argparse
import json
import os
from pathlib import Path
import re
import runpy
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent
INSTANCES = ROOT / 'tests/sfir-instances'
SUPPORT = runpy.run_path(str(INSTANCES / 'check.py'))
run, succeeded = SUPPORT['run'], SUPPORT['succeeded']
CASES = [('generic-groups', '42', '123'), ('safe-values', '42', '123'),
         ('early-value', 'trap', '12'), ('early-capture', 'trap', '1')]
REJECTIONS = {
    'inferred-self': 'occurs check',
    'inferred-mutual': 'occurs check',
    'annotated-self': 'occurs check',
    'annotated-mutual': 'occurs check',
    'annotated-narrowing': 'recursive use cannot specialize',
    'independent-binders': 'recursive use cannot specialize',
    'phantom-instantiation': 'occurs check',
    'nested-rigid': 'recursive use cannot specialize|rigid type escapes|type mismatch',
    'phantom-local': 'type mismatch',
    'expansive-shared': 'type mismatch',
    'annotated-expansive': 'recursive use cannot specialize',
    'rigid-body': 'recursive use cannot specialize',
}


# ---- Inference must reject unsupported recursion before code generation ----


def check_rejection(compiler, output, name, diagnostic):
    source = FIXTURES / (name + '.sfir')
    record = run([os.environ.get('CHIBI', 'chibi-scheme'), '-I', compiler / 'src',
                  FIXTURES / 'infer.scm', compiler, source, output / (name + '.trace.json')],
                 output / (name + '.json'))
    assert record['status'] > 0, record
    message = record['stdout'] + record['stderr']
    assert re.search(re.escape(name) + r'\.sfir:\d+:\d+: (' + diagnostic + ')', message), record
    return dict(name=name, expected='inference rejection', status=record['status'])


# ---- Readiness and checked templates survive both execution targets ----


def check_execution(compiler, output, name, expected, history):
    directory = output / name
    directory.mkdir()
    wasm = directory / 'program.wasm'
    succeeded(run([compiler / 'scripts/build-sfir', '--export', 'observed',
                   FIXTURES / (name + '.sfir'), wasm], directory / 'compile.json'))
    raw = Path(str(wasm) + '.raw.wasm')
    for label, artifact in [('raw', raw), ('optimized', wasm)]:
        succeeded(run([os.environ.get('NODE', 'node'), INSTANCES / 'run.mjs', artifact, expected, history],
                      directory / (label + '.json')))
    hashes = SUPPORT['check_native'](compiler, directory, wasm, raw, expected, history)
    return dict(name=name, expected=expected, effects=history, sha256=hashes)


# ---- Tests ----


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path, default=ROOT / 'build/sfir-recursion')
    options = parser.parse_args()
    options.output.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix='attempt-', dir=options.output.resolve()))
    results = []
    for name, diagnostic in REJECTIONS.items():
        results.append(check_rejection(options.compiler.resolve(), output, name, diagnostic))
        (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
        print(f'PASS inference rejection: {name}', flush=True)
    for case in CASES:
        results.append(check_execution(options.compiler.resolve(), output, *case))
        (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
        print(f'PASS {case[0]}: raw/optimized Wasm, identical native guest, forced GC', flush=True)
    print(f'Retained outcomes: {output}', flush=True)


if __name__ == '__main__':
    main()
