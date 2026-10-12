#!/usr/bin/env python3
"""Check frozen vector artifacts without treating execution times as evidence."""
import hashlib
import itertools
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NODE = '/nix/store/lfaydgacdyngci7p60s8wwvgdm74fjkx-nodejs-24.19.0/bin/node'
PROGRAMS = {
    'd277-reference': Path('/tmp/snail-vector-reference-d2770ab-20261012/build/vector-append/reference/program.wasm'),
    'd4-reference': ROOT / 'build/vector-append/reference/program.wasm',
    'd4-public': ROOT / 'build/vector-append/public/program.wasm',
}
HOST = ROOT / 'build/final-five-prepared/host/scripts/run-wasi.mjs'
MODES = ['direct-one', 'direct-two', 'direct-three', 'typed-three', 'opaque-three', 'apply-three', 'checksum-three']
KINDS = ['integer', 'character', 'reference']


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def invoke(label, program, mode, kind, size, repetitions, choose, number):
    directory = ROOT / 'build/vector-validation' / f'{number:03}-{label}-{mode}-{kind}-{size}-{choose}'
    directory.mkdir(parents=True)
    source = f'{mode}\n{kind}\n{size}\n{repetitions}\n' + ('#t\n' if choose else '#f\n')
    (directory / 'input.txt').write_text(source)
    command = ['taskset', '-c', '5', NODE, '--no-warnings', str(HOST), str(program)]
    completed = subprocess.run(command, cwd=program.parent, input=source, text=True, capture_output=True, timeout=60)
    (directory / 'stdout.txt').write_text(completed.stdout)
    (directory / 'stderr.txt').write_text(completed.stderr)
    rows = [line.removeprefix('+!VECTOR_APPEND!+').split(',') for line in completed.stdout.splitlines()
            if line.startswith('+!VECTOR_APPEND!+')]
    passed = completed.returncode == 0 and len(rows) == 1 and rows[0][:4] == [mode, kind, str(size), str(repetitions)]
    record = {'label': label, 'mode': mode, 'kind': kind, 'size': size, 'repetitions': repetitions,
              'choose_public': choose, 'returncode': completed.returncode, 'passed': passed,
              'command': command, 'cwd': str(program.parent), 'program_sha256': digest(program),
              'source_sha256': digest(program.with_suffix('.scm')), 'host_sha256': digest(HOST),
              'recorded_at_utc': datetime.now(timezone.utc).isoformat(),
              'scope': 'Concurrent integration-test correctness run; emitted durations excluded from timing comparisons.',
              'checksum': int(rows[0][4]) if passed else None}
    (directory / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    if not passed:
        raise RuntimeError(f'vector validation failed: {directory}')
    print(label, mode, kind, size, choose, 'passed', flush=True)
    return record


def main():
    records = []
    for label, program in PROGRAMS.items():
        cases = [(m, k, 8, 3, True) for m, k in itertools.product(MODES, KINDS)]
        cases += [(m, 'integer', n, 3, True) for m, n in itertools.product(['typed-three', 'opaque-three', 'apply-three'], [0, 1])]
        if label == 'd4-public':
            cases += [(m, 'reference', 8, 3, False) for m in ['opaque-three', 'apply-three']]
        for mode, kind, size, repetitions, choose in cases:
            records.append(invoke(label, program, mode, kind, size, repetitions, choose, len(records)))
    output = ROOT / 'build/vector-validation/results.json'
    output.write_text(json.dumps({'records': records, 'all_passed': all(r['passed'] for r in records)}, indent=2) + '\n')


if __name__ == '__main__':
    main()
