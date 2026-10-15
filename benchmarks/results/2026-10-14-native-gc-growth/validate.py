#!/usr/bin/env python3
"""Validate heap growth with the frozen, complete Boyer native modules."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CONTROLS = ('SNAIL_GC_HEAP_BYTES', 'SNAIL_GC_INITIAL_BYTES', 'SNAIL_GC_MIN_BYTES',
            'SNAIL_GC_STATS', 'SNAIL_NATIVE_GC_INTERVAL', 'SNAIL_GC_SCAN_ALL')


# ---- Frozen build inputs and recorded process outcomes ----


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def run(command, directory, environment):
    started = time.monotonic()
    process = subprocess.Popen(list(map(str, command)), cwd=directory, env=environment,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True, start_new_session=True)
    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=300)
    except subprocess.TimeoutExpired:
        timed_out = True
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate()
    return dict(command=list(map(str, command)), cwd=str(directory), returncode=process.returncode,
                stdout=stdout, stderr=stderr, timeout=timed_out,
                process_seconds=time.monotonic() - started,
                controls={name: environment.get(name) for name in CONTROLS})


def compile_runtime(source, target, environment):
    manifests = list(source.glob('native.native-*/build.json'))
    assert len(manifests) == 1, manifests
    artifact = manifests[0].parent
    manifest = json.loads((artifact / 'build.json').read_text())
    recorded = manifest['commands']
    command = next(row['command'] for row in recorded if str(artifact / 'module.ll') in row['command'])
    inputs = [Path(value) for value in command if Path(value).is_file() and value != command[-1]]
    inputs += [artifact / 'optimized.wasm', source / 'native-provider.c', source / 'native-provider.h']
    for path in inputs:
        expected = manifest['sha256'].get(str(path))
        if expected:
            assert digest(path) == expected, path
    old_gc = next(path for path in inputs if path.name == 'precise-gc.c')
    old_host = next(path for path in inputs if path.name == 'native.c')
    assert digest(ROOT / 'src/native.c') == digest(old_host)
    assert digest(ROOT / 'src/precise-gc.h') == digest(old_gc.with_suffix('.h'))
    command = [str(ROOT / 'src/precise-gc.c') if value == str(old_gc) else value for value in command]
    command[-1] = str(target / 'program')
    before = {str(path): digest(path) for path in inputs}
    record = run(command, ROOT, environment)
    save(target / 'build.json', record)
    assert not record['timeout'] and record['returncode'] == 0 and not record['stderr'], record
    assert all(digest(Path(path)) == value for path, value in before.items())
    return dict(frozen_inputs=before, collector_sha256=digest(ROOT / 'src/precise-gc.c'),
                executable_sha256=digest(target / 'program'), build=record)


# ---- Clean correctness and separately labeled collector diagnostics ----


def check_result(record, spec, diagnostic=False):
    assert not record['timeout'] and record['returncode'] == 0, record
    assert diagnostic or not record['stderr'], record
    expected = dict(result=spec['expected'], barriers=spec['count'] * spec['barriers_per_iteration'],
                    setup_closed=1, worker_closed=0, closed=1)
    assert json.loads(record['stdout']) == expected, record


def execute_case(source, target, label, environment, diagnostic=False):
    fixture = source / 'checks' / ('canonical' if diagnostic else label)
    directory = target / label
    directory.mkdir()
    (directory / 'input.txt').write_bytes((fixture / 'input.txt').read_bytes())
    spec = json.loads((fixture / 'spec.json').read_text())
    record = run([target / 'program'], directory, environment)
    record['input_sha256'] = digest(directory / 'input.txt')
    record['expected'] = spec
    save(directory / 'record.json', record)
    check_result(record, spec, diagnostic)
    return record


def statistics(record):
    assert re.fullmatch(r'immix-gc [^\n]+\n', record['stderr']), record
    return dict(re.findall(r'(\w+)=([\w.]+)', record['stderr']))


def validate_workload(source, target, environment):
    target.mkdir(parents=True)  # Refuse to overwrite any previously built evidence.
    evidence = compile_runtime(source, target, environment)
    evidence['correctness'] = {}
    for label in ['canonical', 'small', 'repeat-reset', 'wrong-rewrites', 'zero-repetitions']:
        evidence['correctness'][label] = execute_case(source, target, label, environment)
    diagnostic = execute_case(source, target, 'growth-diagnostic', dict(environment, SNAIL_GC_STATS='1'), True)
    stats = statistics(diagnostic)
    assert int(stats['growths']) >= 1 and int(stats['heap_limit']) == 0, stats
    assert int(stats['initial_heap_bytes']) == 256 * 1024**2, stats
    evidence['growth_diagnostic'] = dict(record=diagnostic, statistics=stats)
    cap = diagnostic['expected']['native_heap_bytes']
    fixed = execute_case(source, target, 'fixed-cap-diagnostic',
                         dict(environment, SNAIL_GC_STATS='1', SNAIL_GC_HEAP_BYTES=str(cap)), True)
    stats = statistics(fixed)
    assert int(stats['growths']) == 0 and int(stats['regions']) == 1, stats
    assert int(stats['heap_limit']) == cap and int(stats['initial_heap_bytes']) == cap, stats
    evidence['fixed_cap_diagnostic'] = dict(record=fixed, statistics=stats)
    return evidence


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepared', type=Path,
                        default=Path('/tmp/snail-strict-boyer-20261014/build/boyer-prepared-combined'))
    parser.add_argument('--output', type=Path, default=ROOT / 'build/gc-growth/boyer')
    options = parser.parse_args()
    prepared, output = options.prepared.resolve(), options.output.resolve()
    environment = {key: value for key, value in os.environ.items() if key not in CONTROLS}
    evidence = dict(purpose='correctness and separate GC diagnostics; no comparative timing',
                    base='b756cce5217c8d57820a9f20250194f883968991', workloads={})
    for name in ['nboyer', 'sboyer']:
        evidence['workloads'][name] = validate_workload(prepared / name, output / name, environment)
        save(HERE / 'validation.json', evidence)
        print(f'PASS {name}: complete default-heap correctness, four boundary cases and separate growth/fixed-cap diagnostics', flush=True)


if __name__ == '__main__':
    main()
