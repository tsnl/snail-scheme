#!/usr/bin/env python3
"""Select validated artifacts and a fixed fresh-process schedule, without timing."""

import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
CORE = ROOT / 'build/strict-reader-ports-attempt6'
CONTROLS = ROOT / 'build/strict-reader-controls-attempt2'
BOUNDARIES = ROOT / 'build/strict-reader-controls-validation-attempt1'
SYSTEMS = ('strict-v8', 'strict-v8-native-module', 'strict-native',
           'chez-original', 'chez-adapted', 'rust-wasm', 'rust-native')


# ---- Every selected file must still match successful preparation ----

def load(path):
    return json.loads(path.read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checked_preparation():
    core, controls = load(CORE / 'prepared.json'), load(CONTROLS / 'prepared.json')
    if controls['status'] != 'ready' or any(case['status'] != 'ready' for case in core['cases']):
        raise ValueError('preparation is incomplete')
    for case in core['cases']:
        for name, expected in case['hashes'].items():
            if digest(CORE / case['name'] / name) != expected:
                raise ValueError('canonical preparation changed: ' + name)
    for name, expected in controls['hashes'].items():
        if digest(CONTROLS / name) != expected:
            raise ValueError('comparison control changed: ' + name)
    if len(load(BOUNDARIES / 'validation.json')) != 4:
        raise ValueError('final host/predicate/provider checks are incomplete')
    return core, controls


def configuration(argv, cwd, stdin=None):
    return dict(argv=list(map(str, argv)), cwd=str(cwd), stdin=str(stdin) if stdin else None)


def systems(name, tools):
    case, native, rust = CORE / name, CONTROLS / name / 'native-timing', CONTROLS / 'rust-reference'
    node = [tools['NODE']['path'], '--disable-warning=ExperimentalWarning']
    return {
        'strict-v8': configuration([*node, CONTROLS / 'reader-timing.mjs', case / 'optimized.wasm', case / 'spec.json'], case),
        'strict-v8-native-module': configuration([*node, CONTROLS / 'reader-timing.mjs', native / 'native-final.wasm',
                                                  native / 'spec.json', native / 'provider.wasm'], native),
        'strict-native': configuration([native / 'native'], native),
        'chez-original': configuration([tools['CHEZ']['path'], '--program', case / 'chez/program.so'], case / 'chez', case / 'input.txt'),
        'chez-adapted': configuration([tools['CHEZ']['path'], '--program', case / 'chez-adapted/program.so'], case / 'chez-adapted', case / 'input.txt'),
        'rust-wasm': configuration([*node, rust / 'run-wasi.mjs', rust / (name + '.wasm')], rust, case / 'input.txt'),
        'rust-native': configuration([rust / (name + '.native')], rust, case / 'input.txt'),
    }


def identity_files(core, controls):
    files = [CORE / 'prepared.json', CORE / 'reader_ports.py', CORE / 'measure.py', CORE / 'reader-host.mjs',
             CONTROLS / 'prepared.json', CONTROLS / 'reader_ports.py', CONTROLS / 'reader-host.mjs',
             CONTROLS / 'reader-timing.mjs', CONTROLS / 'matrix_port.py', CONTROLS / 'libsnail_runtime.a',
             CONTROLS / 'toolchain.json', BOUNDARIES / 'validation.json', REPORT / 'measure-seven.py', Path(__file__)]
    files += [Path(controls['tools'][name]['path']) for name in ('NODE', 'CHEZ', 'TASKSET', 'PYTHON')]
    rust = CONTROLS / 'rust-reference'
    files += [rust / name for name in ('Cargo.toml', 'Cargo.lock', 'src/lib.rs', 'run-wasi.mjs')]
    for case in core['cases']:
        name, path = case['name'], case['spec']['pathnames'][0]
        original, native = CORE / name, CONTROLS / name / 'native-timing'
        files += [original / item for item in ('strict.scm', 'upstream.scm', 'adapted-kernel.scm', 'optimized.wasm',
                  'strict-native.wasm', 'runtime.wasm', 'spec.json', 'input.txt', path,
                  'chez/program.scm', 'chez/program.so', 'chez-adapted/program.scm', 'chez-adapted/program.so')]
        files += [original / control / path for control in ('chez', 'chez-adapted')]
        files += [native / item for item in ('native', 'native-final.wasm', 'provider.wasm', 'provider-interface.json',
                  'spec.json', 'input.txt', path, 'native-provider.h', 'native-provider.c', 'native-entry.c', 'final-module.json')]
        generated = list(native.glob('native.native-*'))
        if len(generated) != 1:
            raise ValueError('native final-module identity is ambiguous')
        files += [generated[0] / item for item in ('module.ll', 'optimized.wasm', 'provider-0.o', 'build.json')]
        files += [rust / item for item in (name + '.native', name + '.raw.wasm', name + '.wasm',
                  f'src/bin/{name}.rs', name + '-validation.json', path)]
    return sorted(set(files))


# ---- One discarded round and a complete seven-position rotation per workload ----

def main():
    core, controls = checked_preparation()
    spec = importlib.util.spec_from_file_location('reader_timing_runner', REPORT / 'measure-seven.py')
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    schedule = []
    for name in ('sum1', 'read1'):
        for round_number in range(-1, 7):
            offset = max(0, round_number)
            order = SYSTEMS[offset:] + SYSTEMS[:offset]
            schedule += [dict(benchmark=name, system=system, round=round_number, retained=round_number >= 0) for system in order]
    plan = dict(compiler_commit=core['compiler_commit'], upstream_commit=core['upstream_commit'], cpu=5,
                timeout_seconds=120, preparation=str(CONTROLS), taskset=controls['tools']['TASKSET']['path'],
                environment={'BINARYEN_CORES': '1'},
                inherited_environment={name: os.environ.get(name) for name in runner.RECORDED_ENVIRONMENT},
                workloads={'sum1': dict(count=25, rust_result_line='Result: 15794.97500000012'),
                           'read1': dict(count=2500, rust_result_line='Result: (should return this list)')},
                systems={name: systems(name, controls['tools']) for name in ('sum1', 'read1')}, schedule=schedule,
                identities={str(path): digest(path) for path in identity_files(core, controls)},
                scope='Both complete original workloads; actual per-invocation file I/O remains inside all clocks.',
                module_control='Only the final Scheme module is identical between native and its V8 control; Rust provider targets/linkage differ.',
                exclusions='Exactly the first seven processes per workload are discarded in advance; no replacement samples.',
                process_clock='Popen through capture, leader reap and bounded process-group cleanup, including post-exit checks.',
                storage='OS file cache is uncontrolled and warmed by preparation/discard rounds; each retained sample is a fresh process.')
    runner.verify(plan)
    (REPORT / 'timing-plan.json').write_text(json.dumps(plan, indent=2) + '\n')
    print('Frozen', len(schedule), 'fresh processes;', len(plan['identities']), 'identities; no timings run')


if __name__ == '__main__':
    main()
