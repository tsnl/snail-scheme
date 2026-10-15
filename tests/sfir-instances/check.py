#!/usr/bin/env python3
"""Execute instance initialization and rank-one call contracts on both targets."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent
CASES = [('initialization', '42', '12345'),
         ('unused-forward-alias', 'trap', '1'),
         ('trapping-expression', 'trap', '12'),
         ('ordinary-calls', '42', '12345678')]
REJECTIONS = ['wrong-result', 'immediate-parameter', 'named-parameter', 'aliased-parameter']


# ---- Bounded commands and retained outcomes ----


def run(command, log, **environment):
    process = subprocess.Popen(list(map(str, command)), cwd=ROOT, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               start_new_session=True,
                               env={**os.environ, 'BINARYEN_CORES': '1', **environment})
    expired = False
    try:
        stdout, stderr = process.communicate(timeout=180)
    except subprocess.TimeoutExpired:
        expired = True
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate(timeout=10)
    finally:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    record = dict(command=list(map(str, command)), status=process.returncode,
                  stdout=stdout, stderr=stderr, timeout=expired, environment=environment)
    log.write_text(json.dumps(record, indent=2) + '\n')
    assert not expired, f'command timed out: {log}'
    return record


def succeeded(record):
    assert record['status'] == 0, record


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


# ---- One source initialization on both execution targets ----


def check_wasm(compiler, directory, name, expected, observed):
    wasm = directory / 'program.wasm'
    succeeded(run([compiler / 'scripts/build-sfir', '--export', 'observed',
                   FIXTURES / (name + '.sfir'), wasm], directory / 'compile.json'))
    raw = Path(str(wasm) + '.raw.wasm')
    for label, artifact in [('raw', raw), ('optimized', wasm)]:
        succeeded(run([os.environ.get('NODE', 'node'), FIXTURES / 'run.mjs',
                       artifact, expected, observed],
                      directory / (label + '.json')))
    return wasm, raw


def check_native(compiler, directory, wasm, raw, expected, observed):
    executable = directory / 'program.native'
    succeeded(run([compiler / 'scripts/build-native', '--wasm', '--entry-c', FIXTURES / 'entry.c',
                   '--c-provider', 'instance.probe', FIXTURES / 'probe.h', FIXTURES / 'probe.c',
                   raw, executable], directory / 'native-build.json'))
    optimized, = directory.glob('program.native.native-*/optimized.wasm')
    assert optimized.read_bytes() == wasm.read_bytes(), 'native guest must match optimized Wasm'
    record = run([executable], directory / 'native.json', SNAIL_NATIVE_GC_INTERVAL='1')
    assert record['status'] == int(expected == 'trap'), record
    assert record['stdout'] == ''.join(f'effect:{digit}\n' for digit in observed), record
    assert record['stderr'] == ('WebAssembly trap\n' if expected == 'trap' else ''), record
    return dict(raw=digest(raw), optimized=digest(wasm), native_guest=digest(optimized),
                executable=digest(executable))


def check_type_rejection(compiler, output, name):
    source = FIXTURES / (name + '.sfir')
    record = run([compiler / 'scripts/build-sfir', source, output / (name + '.wasm')],
                 output / (name + '.json'))
    assert record['status'] > 0, record
    assert re.search(re.escape(name) + r'\.sfir:\d+:\d+: type mismatch; cannot unify',
                     record['stdout'] + record['stderr']), record


def check_former_alias(compiler, directory):
    source = ROOT / 'tests/sfir-integration/typeclass-member-initializer.sfir'
    wasm = directory / 'program.wasm'
    succeeded(run([compiler / 'scripts/build-sfir', source, wasm], directory / 'compile.json'))
    raw = Path(str(wasm) + '.raw.wasm')
    for label, artifact in [('raw', raw), ('optimized', wasm)]:
        succeeded(run([os.environ.get('NODE', 'node'), ROOT / 'tests/sfir-integration/run.mjs',
                       artifact, 'trap'], directory / (label + '.json')))
    return check_native(compiler, directory, wasm, raw, 'trap', '')


# ---- Tests ----


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path, default=ROOT / 'build/sfir-instances')
    options = parser.parse_args()
    options.output.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix='attempt-', dir=options.output.resolve()))
    results = []
    for name, expected, observed in CASES:
        directory = output / name
        directory.mkdir()
        wasm, raw = check_wasm(options.compiler.resolve(), directory, name, expected, observed)
        hashes = check_native(options.compiler.resolve(), directory, wasm, raw, expected, observed)
        results.append(dict(name=name, expected=expected, observed=observed, sha256=hashes))
        (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
        print(f'PASS {name}: raw/optimized Wasm, identical native guest, forced GC', flush=True)
    for name in REJECTIONS:
        check_type_rejection(options.compiler.resolve(), output, name)
        print(f'PASS located type rejection: {name}', flush=True)
    directory = output / 'former-forward-alias'
    directory.mkdir()
    hashes = check_former_alias(options.compiler.resolve(), directory)
    results.append(dict(name='former-forward-alias', expected='trap', sha256=hashes))
    (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(f'PASS former alias expectation on both targets; records: {output}', flush=True)


if __name__ == '__main__':
    main()
