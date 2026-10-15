#!/usr/bin/env python3
"""Audit current Equal correctness and freeze its seven-system clean plan."""

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
PREPARED = ROOT / 'build/equal-prepared-6fd5ca4'
CORE = PREPARED / 'equal'
FROZEN = PREPARED / 'frozen'
SYSTEMS = ('strict-v8', 'strict-v8-native-module', 'strict-native',
           'chez-original', 'chez-adapted', 'rust-wasm', 'rust-native')
sys.path.insert(0, str(ROOT / 'benchmarks/strict-suite'))
import equal_port
import measure
import reader_ports


# ---- Full source and complete result replays establish current readiness ----

def load(path):
    return json.loads(path.read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_prepared_files():
    prepared = load(PREPARED / 'prepared.json')
    case, = prepared['cases']
    if case['status'] != 'ready' or prepared['compiler_commit'] != '6fd5ca453cc58903cdb64f13abc3cdc656b06226':
        raise ValueError('unexpected current Equal source basis or readiness')
    for name, expected in case['hashes'].items():
        if digest(CORE / name) != expected:
            raise ValueError('prepared artifact changed: ' + name)
    for name, expected in prepared['compiler_files'].items():
        if digest(PREPARED / 'compiler-source' / name) != expected or digest(ROOT / name) != expected:
            raise ValueError('archived or current compiler source changed: ' + name)
    for tool in prepared['tools'].values():
        if digest(Path(tool['path'])) != tool['sha256']:
            raise ValueError('preparation tool changed: ' + tool['path'])
    return prepared


def verify_generated_sources():
    runner = measure.upstream_runner()
    files = runner.suite_sources()
    if (CORE / 'input.txt').read_bytes() != files['inputs/equal.input']:
        raise ValueError('complete canonical Equal input changed')
    with tempfile.TemporaryDirectory(prefix='equal-sources-', dir=ROOT / 'build') as temporary:
        target = Path(temporary)
        equal_port.write_sources(files, target, runner, measure)
        for path in target.rglob('*'):
            if path.is_file() and path.read_bytes() != (CORE / path.relative_to(target)).read_bytes():
                raise ValueError('generated source changed: ' + str(path.relative_to(target)))


def replay_complete_results():
    scheme, rust = 0, 0
    for label, data, accepted in equal_port.fixtures((CORE / 'input.txt').read_bytes()):
        target = CORE / 'checks' / label
        specification = load(target / 'spec.json')
        for system in ('raw', 'optimized', 'native'):
            equal_port.compiled_result(load(target / 'commands' / system / 'record.json'), specification)
            scheme += 1
        for system in ('chez', 'chez-adapted'):
            equal_port.chez_result(load(target / 'commands' / system / 'record.json'), specification)
            scheme += 1
        for system in ('native', 'raw-wasm', 'optimized-wasm'):
            equal_port.rust_result(load(CORE / 'controls/rust/commands' / (label + '-' + system) / 'record.json'), accepted)
            rust += 1
    return dict(scheme_complete_frames=scheme, rust_complete_frames=rust)


def verify_separate_observations():
    observed = load(CORE / 'observations/validation.json')
    expected = dict(shared_pair_occurrences=5050, unshared_pair_occurrences=109600, vector_length=1000,
                    shallow_spine=2000, shallow_shared_subtree_pairs=15, deep_car_chain=5000,
                    canonical_equality_calls=[0, 100, 8, 1000, 2000, 5000], separate_cyclic_case_calls=17,
                    negative_equality_phases=5)
    if any(observed.get(key) != value for key, value in expected.items()):
        raise ValueError('full equality shapes, counts or false probes changed')
    if any(value['result'] != 42 for value in load(CORE / 'datum-tests/validation.json').values()):
        raise ValueError('current Datum module tests failed')
    return expected


def verify_terminal_preparation():
    records = [load(path) for path in PREPARED.rglob('commands/*/record.json')]
    if any('returncode' not in row or row.get('timeout') or row.get('executing_descendants') for row in records):
        raise ValueError('preparation has an unfinished or timed-out process')
    failures = [row for row in records if row['returncode'] != 0]
    if len(failures) != 15 or any('assertion failed: result' not in row['stderr'] for row in failures):
        raise ValueError('unexpected preparation failure')
    return dict(captured_terminal_processes=len(records), expected_negative_rust_processes=len(failures), timeouts=0)


def verify_rust_sources():
    source = ROOT / 'benchmarks/wasm-reference'
    for path in [*source.glob('src/**/*.rs'), *(source / name for name in ('Cargo.toml', 'Cargo.lock', 'run-wasi.mjs'))]:
        retained = CORE / 'controls/rust' / path.relative_to(source)
        if retained.read_bytes() != path.read_bytes():
            raise ValueError('Rust control source changed: ' + str(path.relative_to(source)))


# ---- Snapshot the exact supervisor and command dependencies ----

def retain_runner_dependencies():
    FROZEN.mkdir(exist_ok=True)
    for name in ('matrix_port.py', 'data_ports.py', 'reader-timing.mjs'):
        shutil.copy2(ROOT / 'benchmarks/strict-suite' / name, FROZEN / name)


def configuration(argv, cwd, stdin=None):
    return dict(argv=list(map(str, argv)), cwd=str(cwd), stdin=str(stdin) if stdin else None)


def systems(tools):
    native, rust = CORE / 'controls/native', CORE / 'controls/rust'
    node = [tools['NODE']['path'], '--disable-warning=ExperimentalWarning']
    return {
        'strict-v8': configuration([*node, FROZEN / 'reader-timing.mjs', CORE / 'optimized.wasm', CORE / 'spec.json'], CORE),
        'strict-v8-native-module': configuration([*node, FROZEN / 'reader-timing.mjs', native / 'native-final.wasm',
                                                native / 'spec.json', native / 'provider.wasm'], native),
        'strict-native': configuration([native / 'native'], native),
        'chez-original': configuration([tools['CHEZ']['path'], '--program', CORE / 'chez/program.so'], CORE / 'chez', CORE / 'input.txt'),
        'chez-adapted': configuration([tools['CHEZ']['path'], '--program', CORE / 'chez-adapted/program.so'], CORE / 'chez-adapted', CORE / 'input.txt'),
        'rust-wasm': configuration([*node, rust / 'run-wasi.mjs', rust / 'equal.wasm'], rust, CORE / 'input.txt'),
        'rust-native': configuration([rust / 'equal.native'], rust, CORE / 'input.txt'),
    }


def imported_dependencies():
    command = [sys.executable, REPORT / 'measure-seven.py', '--dependency-files', FROZEN]
    run = reader_ports.record(PREPARED / 'plan-diagnostics', 'fresh-import-closure', command, dict(os.environ))
    return {Path(path) for path in json.loads(run['stdout'])}


def linked_dependencies(tools, imported):
    files = {Path(record['path']) for record in tools.values()}
    executables = [*(Path(tools[name]['path']) for name in ('NODE', 'CHEZ', 'TASKSET', 'PYTHON')),
                   CORE / 'controls/native/native', CORE / 'controls/rust/equal.native',
                   *(path for path in sorted(imported) if path.suffix == '.so')]
    for index, executable in enumerate(executables):
        run = reader_ports.record(PREPARED / 'plan-diagnostics', 'linked-dependencies-' + str(index),
                                  ['ldd', executable], dict(os.environ))
        files.update(Path(path) for path in re.findall(r'(/[^\s()]+)', run['stdout']) if Path(path).is_file())
    files.update(Path(tools['CHEZ']['path']).resolve().parents[1].glob('lib/**/*.boot'))
    return files


def identity_files(prepared):
    native, rust = CORE / 'controls/native', CORE / 'controls/rust'
    files = [CORE / name for name in ('strict.scm', 'upstream.scm', 'adapted-kernel.scm', 'input.txt', 'spec.json',
             'optimized.wasm', 'raw.wasm', 'strict-native.wasm', 'runtime.wasm', 'chez/program.so', 'chez-adapted/program.so')]
    files += [native / name for name in ('native', 'native-final.wasm', 'provider.wasm', 'spec.json', 'input.txt',
              'native-provider.c', 'native-provider.h', 'native-entry.c')]
    files += [rust / name for name in ('equal.native', 'equal.wasm', 'equal.raw.wasm', 'run-wasi.mjs')]
    files += [PREPARED / 'prepared.json', PREPARED / 'retention/retained-work.json']
    files += [ROOT / name for name in prepared['compiler_files']]
    files += [PREPARED / 'compiler-source' / name for name in prepared['compiler_files']]
    files += [FROZEN / name for name in ('matrix_port.py', 'data_ports.py', 'reader-timing.mjs')]
    files += [REPORT / name for name in ('measure-seven.py', 'freeze-plan.py')]
    imported = imported_dependencies()
    return set(files) | imported | linked_dependencies(prepared['tools'], imported)


# ---- Diagnostic frame runs precede the fixed discarded/retained rotation ----

def protocol_records():
    return {system: CORE / path / 'record.json' for system, path in [
        ('strict-v8', 'plan-protocols/commands/strict-v8'),
        ('strict-v8-native-module', 'plan-protocols/commands/strict-v8-native-module'),
        ('strict-native', 'controls/native/commands/full-count-validation'),
        ('chez-original', 'checks/canonical/commands/chez'), ('chez-adapted', 'checks/canonical/commands/chez-adapted'),
        ('rust-wasm', 'controls/rust/commands/canonical-optimized-wasm'),
        ('rust-native', 'controls/rust/commands/canonical-native')]}


def run_timing_host_diagnostics(configured):
    for system in ('strict-v8', 'strict-v8-native-module'):
        config = configured[system]
        reader_ports.record(CORE / 'plan-protocols', system, config['argv'], dict(os.environ), Path(config['cwd']))


def verify_protocols(plan):
    paths = protocol_records()
    target = PREPARED / 'plan-diagnostics/protocol-records.json'
    measure.save(target, {system: str(path) for system, path in paths.items()})
    reader_ports.record(PREPARED / 'plan-diagnostics', 'frame-replays-and-corruptions',
        [sys.executable, REPORT / 'measure-seven.py', '--check-records', target], dict(os.environ))
    return {system: dict(path=str(path), sha256=digest(path)) for system, path in protocol_records().items()}


def main():
    if (REPORT / 'timing-plan.json').exists():
        raise ValueError('do not replace an existing frozen timing plan')
    prepared = verify_prepared_files()
    verify_generated_sources()
    frames = replay_complete_results()
    observations = verify_separate_observations()
    terminal = verify_terminal_preparation()
    verify_rust_sources()
    retain_runner_dependencies()
    configured = systems(prepared['tools'])
    run_timing_host_diagnostics(configured)
    plan = dict(compiler_commit=prepared['compiler_commit'], driver_commit=prepared['driver_commit'],
                upstream_commit=prepared['upstream_commit'], cpu=5, timeout_seconds=120,
                preparation=str(FROZEN), taskset=prepared['tools']['TASKSET']['path'],
                environment={'BINARYEN_CORES': '1'},
                inherited_environment={name: os.environ.get(name) for name in
                    ('NODE_OPTIONS', 'NODE_V8_COVERAGE', 'NODE_DEBUG', 'NODE_DEBUG_NATIVE', 'LD_PRELOAD',
                     'SNAIL_NATIVE_GC_INTERVAL', 'SNAIL_GC_STATS', 'SNAIL_GC_HEAP_BYTES', 'SNAIL_GC_MIN_BYTES',
                     'LD_LIBRARY_PATH', 'LANG', 'LC_ALL', 'TZ')},
                input_parameters=[100, 100, 8, 1000, 2000, 5000], chez_workload_name='equal:100:100:8:1000:2000:5000',
                systems=configured, identities={str(path): digest(path) for path in sorted(identity_files(prepared))},
                schedule=[dict(system=system, round=round_number, retained=round_number >= 0)
                          for round_number in range(-1, 7)
                          for system in SYSTEMS[max(0, round_number):] + SYSTEMS[:max(0, round_number)]],
                scope='Complete original enabled Equal aggregate; setup precedes every workload clock; exact-#t predicate is timed.',
                exclusions='Exactly the first seven processes are discarded; seven balanced retained rounds; no replacement samples.',
                module_control='Native and its V8 control share exact final Scheme Wasm bytes; scalar service providers differ.',
                process_clock='Popen through capture, leader reap and bounded process-group cleanup.')
    measure.save(REPORT / 'timing-plan.json', plan)
    protocols = verify_protocols(plan)
    reader_ports.record(PREPARED / 'plan-diagnostics', 'fresh-plan-verification',
                        [sys.executable, REPORT / 'measure-seven.py'], dict(os.environ))
    measure.save(REPORT / 'readiness-audit.json', dict(status='ready', measured=False,
        compiler_commit=prepared['compiler_commit'], prior_author_source='610d6e9; prior evidence only',
        prepared_artifact_hashes=len(prepared['cases'][0]['hashes']), archived_compiler_files=len(prepared['compiler_files']),
        observations=observations, protocol_records=protocols, **frames, **terminal))
    print('Frozen', len(plan['schedule']), 'fresh processes and', len(plan['identities']), 'identities; no clean timing run')


if __name__ == '__main__':
    main()
