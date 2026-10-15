#!/usr/bin/env python3
"""Freeze the reviewed artifacts and pre-campaign machine state; run no guest."""

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
PREPARATION = ROOT / 'build/matrix-attempt5'
CASE = PREPARATION / 'matrix'
sys.path.insert(0, str(PREPARATION))
from matrix_port import scheme_value


# ---- Capture the fixed input and execution environment ----

def load(path):
    return json.loads(path.read_text())


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_state(path):
    try:
        return dict(path=str(path), value=path.read_text().strip())
    except OSError as error:
        return dict(path=str(path), error=str(error))


def machine_state(cpu):
    fields = ['scaling_governor', 'scaling_driver', 'scaling_min_freq', 'scaling_max_freq', 'energy_performance_preference']
    cpu_root = Path(f'/sys/devices/system/cpu/cpu{cpu}')
    models = sorted({line.split(':', 1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines()
                     if line.startswith('model name')})
    return dict(captured=datetime.now(timezone.utc).isoformat(), uname=list(os.uname()), models=models,
                available_affinity=sorted(os.sched_getaffinity(0)), selected_cpu=cpu,
                frequency=[read_state(cpu_root / 'cpufreq' / field) for field in fields],
                siblings=read_state(cpu_root / 'topology/thread_siblings_list'))


def systems(tools):
    node, chez = tools['NODE']['path'], tools['CHEZ']['path']
    commands = {
        'strict-v8': [node, PREPARATION / 'host.mjs', CASE / 'strict.wasm', CASE / 'spec.json'],
        'strict-native': [CASE / 'native-timing/native', '2500', CASE / 'native-timing/native-input-canonical.txt'],
        'chez-original': [chez, '--program', CASE / 'program.so'],
        'chez-adapted': [chez, '--program', CASE / 'same-source-chez/program.so'],
        'rust-native': [CASE / 'rust-reference/matrix.native'],
        'rust-wasm-v8': [node, '--disable-warning=ExperimentalWarning', CASE / 'rust-reference/run-wasi.mjs',
                         CASE / 'rust-reference/matrix.wasm']}
    return {name: dict(argv=list(map(str, argv)), cwd=str(CASE),
                       stdin=str(CASE / 'input.txt') if not name.startswith('strict-') else None)
            for name, argv in commands.items()}


def frozen_identities(prepared, selected):
    paths = [Path(tool['path']) for tool in prepared['tools'].values()]
    paths += [PREPARATION / name for name in ('prepared.json', 'host.mjs', 'matrix_port.py', 'measure.py', 'data_ports.py', 'r7rs.py')]
    paths += [CASE / name for name in (*selected, 'input.txt', 'upstream.scm', 'spec.json', 'strict.scm', 'program.scm',
        'same-source-chez/program.scm', 'adapted-kernel.scm', 'original-kernel.scm', 'adaptation-ledger.json',
        'native-timing/native-provider.c', 'native-timing/native-provider.h', 'native-timing/native-entry.c',
        'native-timing/native-input-canonical.txt', 'rust-reference/run-wasi.mjs',
        'rust-reference/src/bin/matrix.rs', 'rust-reference/src/lib.rs', 'rust-reference/Cargo.toml', 'rust-reference/Cargo.lock')]
    paths += [REPORT / name for name in ('measure-six.py', 'freeze-plan.py', 'timing-plan.md', 'hardware-before.json',
                                         'inspect-retained-work.py', 'retained-work.json', 'retained-work.md')]
    return {str(path): digest(path) for path in paths}


# ---- Six fresh processes per round, with no replacement policy ----

def main():
    if (REPORT / 'timing-plan.json').exists():
        raise ValueError('plan already frozen; retain its historical identity before replacing it')
    prepared, spec = load(PREPARATION / 'prepared.json'), load(CASE / 'spec.json')
    selected = ('strict.wasm', 'strict.wasm.raw.wasm', 'native-timing/native', 'program.so',
                'same-source-chez/program.so', 'rust-reference/matrix.native',
                'rust-reference/matrix.raw.wasm', 'rust-reference/matrix.wasm')
    import importlib.util
    module = importlib.util.spec_from_file_location('timing_runner', REPORT / 'measure-six.py')
    runner = importlib.util.module_from_spec(module)
    module.loader.exec_module(runner)
    save(REPORT / 'hardware-before.json', machine_state(5))
    configs = systems(prepared['tools'])
    order = list(configs)
    schedule = [dict(round=round_number, retained=round_number != 0, system=name)
                for round_number in range(7)
                for name in order[max(0, round_number - 1):] + order[:max(0, round_number - 1)]]
    plan = dict(status='awaiting-parent-release', preparation=str(PREPARATION),
        compiler_commit=prepared['compiler_commit'], upstream_commit=prepared['upstream_commit'],
        cpu=5, taskset=prepared['tools']['TASKSET']['path'], timeout_seconds=300,
        capture_cleanup_seconds=10, group_cleanup_seconds=5, final_group_cleanup_seconds=5, leader_reap_seconds=10,
        environment={'BINARYEN_CORES': '1'}, input=spec, systems=configs, schedule=schedule,
        inherited_environment={name: os.environ.get(name) for name in runner.RECORDED_ENVIRONMENT},
        observations='One complete canonical output/prime-chain invocation, repeated-call and full-count checks; no full2500 internal trace.',
        rust_control='Validated complete outputs, with separately disclosed algorithm/layout differences.',
        rust_result_line='Result: ' + scheme_value(spec['original_expected']),
        selected_hashes={name: digest(CASE / name) for name in selected},
        identities=frozen_identities(prepared, selected))
    runner.verify(plan)
    save(REPORT / 'timing-plan.json', plan)
    print('Frozen six-system plan with', len(plan['identities']), 'identities and', len(schedule), 'processes')


if __name__ == '__main__':
    main()
