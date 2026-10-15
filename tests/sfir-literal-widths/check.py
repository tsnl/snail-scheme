#!/usr/bin/env python3
"""Check intrinsic literal widths and the two direct annotation boundaries."""

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
SPECIAL_ERRORS = {'reject-default-range': 'integer literal is outside representation range',
                  'reject-any-range': 'integer literal is outside representation range',
                  'reject-overload': 'no compatible overload signature'}


# ---- Reject contextual selection before specialization ----


def reject(source, output):
    record = run([os.environ.get('CHIBI', 'chibi-scheme'), '-I', ROOT / 'src',
                  ROOT / 'tests/sfir-recursion/infer.scm', ROOT, source,
                  output / (source.stem + '.trace.json')], output / (source.stem + '.json'))
    message = record['stdout'] + record['stderr']
    error = SPECIAL_ERRORS.get(source.stem, 'type mismatch; cannot unify')
    assert record['status'] > 0 and re.search(re.escape(source.name) + r':\d+:\d+: ' + re.escape(error), message), record
    return dict(name=source.stem, status=record['status'], expected=error)


# ---- Preserve default representation through Any on both targets ----


def execute(name, expected, output):
    directory = output / name
    directory.mkdir()
    wasm = directory / 'program.wasm'
    succeeded(run([ROOT / 'scripts/build-sfir', '--export', 'observed',
                   FIXTURES / (name + '.sfir'), wasm], directory / 'compile.json'))
    raw = Path(str(wasm) + '.raw.wasm')
    for label, artifact in [('raw', raw), ('optimized', wasm)]:
        succeeded(run([os.environ.get('NODE', 'node'), INSTANCES / 'run.mjs', artifact, expected, '1'],
                      directory / (label + '.json')))
    hashes = SUPPORT['check_native'](ROOT, directory, wasm, raw, expected, '1')
    return dict(name=name, expected=expected, sha256=hashes)


# ---- Tests ----


def main():
    parent = ROOT / 'build/sfir-literal-widths'
    parent.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix='attempt-', dir=parent))
    results = []
    for source in sorted(FIXTURES.glob('reject-*.sfir')):
        results.append(reject(source, output))
        (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
        print('PASS inference rejection:', source.stem, flush=True)
    for name, expected in [('defaults', '42'), ('any-projection', 'trap')]:
        results.append(execute(name, expected, output))
        (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
        print('PASS raw/optimized Wasm and identical native guest:', name, flush=True)
    print('Retained outcomes:', output, flush=True)


if __name__ == '__main__':
    main()
