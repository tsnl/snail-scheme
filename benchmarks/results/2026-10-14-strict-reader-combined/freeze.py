#!/usr/bin/env python3
"""Freeze baseline/combined reader artifacts using the already reviewed runner."""

from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
SHARED_ROOT = Path('/tmp/snail-reader-ablation-preparation-20261014')
SHARED = SHARED_ROOT / 'benchmarks/results/2026-10-14-strict-reader-ablations'
BASE = 'c0ba036499de55622538fc4c077fb8951b510502'
COMBINED = '20b4d2100c3640c50fb535a70956d0b4128a9554'
PREPARATIONS = {'baseline': SHARED_ROOT / 'build/reader-ablation-prepared',
                'combined': ROOT / 'build/reader-combined-prepared'}


# ---- Completed preparations and the exact union of the two source changes ----

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def checked_preparations():
    results = {}
    for label, path in PREPARATIONS.items():
        value = json.loads((path / 'prepared.json').read_text())
        assert {case['name'] for case in value['cases']} == {'sum1', 'read1'}
        for case in value['cases']:
            assert case['status'] == 'ready', label + ': incomplete preparation'
            assert all(digest(path / case['name'] / name) == expected for name, expected in case['hashes'].items())
        assert all(digest(path / 'compiler-source' / name) == expected for name, expected in value['compiler_files'].items())
        results[label] = value
    return results


def check_sources(preparations):
    baseline, combined = [preparations[label] for label in ('baseline', 'combined')]
    assert baseline['compiler_commit'] == BASE and combined['compiler_commit'] == COMBINED
    left, right = baseline['compiler_files'], combined['compiler_files']
    assert set(left) == set(right)
    assert {name for name in left if left[name] != right[name]} == {'src/snail/read.sld', 'src/snail/datum.sld', 'src/strict_datum.rs'}
    assert baseline['tools'] == combined['tools']
    assert baseline['upstream_commit'] == combined['upstream_commit']


# ---- Reuse the unchanged runner and its entire accepted dependency closure ----

def checked_runner():
    prior = SHARED / 'timing-plan.json'
    assert digest(prior) == 'e55ab9ec987cf14371fbcd06850348db4e178a01be4494f84b6df508ef7cee7a'
    assert all(digest(path) == expected for path, expected in json.loads(prior.read_text())['identities'].items())
    target = SHARED / 'measure.py'
    assert digest(target) == 'e2ddab6bec989227cf9b639fd98f16ad75dfced6e11b414395a2ca3d0645ccfd'
    spec = importlib.util.spec_from_file_location('reviewed_combined_reader_runner', target)
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    return runner


def timed_systems(preparations, name):
    result = {}
    for label, path in PREPARATIONS.items():
        case = path / name
        result['strict-v8-' + label] = dict(argv=[preparations[label]['tools']['NODE']['path'],
            '--disable-warning=ExperimentalWarning', str(SHARED / 'reader-timing.mjs'),
            str(case / 'optimized.wasm'), str(case / 'spec.json')], cwd=str(case), stdin=None)
    return result


def identities(preparations):
    paths = [Path(__file__), SHARED / 'timing-plan.json', SHARED / 'measure.py', SHARED / 'reader-timing.mjs']
    paths += sorted((SHARED / 'supervisor').glob('*.py'))
    assert len(list((SHARED / 'supervisor').glob('*.py'))) == 18
    for label, directory in PREPARATIONS.items():
        paths += [directory / 'prepared.json', directory / 'reader_ports.py', directory / 'reader-host.mjs']
        paths += list((directory / 'compiler-source').rglob('*'))
        paths += [Path(tool['path']) for tool in preparations[label]['tools'].values()]
        for case in preparations[label]['cases']:
            folder = directory / case['name']
            paths += [folder / name for name in ('upstream.scm', 'adapted-kernel.scm', 'strict.scm',
                      'optimized.wasm', 'raw.wasm', 'strict-native.wasm', 'runtime.wasm', 'native',
                      'spec.json', 'input.txt', 'canonical-validation.json', case['spec']['pathnames'][0])]
    return {str(path): digest(path) for path in sorted(set(paths)) if path.is_file()}


# ---- One discard and ten balanced retained rounds are fixed before release ----

def main():
    preparations = checked_preparations()
    check_sources(preparations)
    runner = checked_runner()
    schedule = []
    for name in ('sum1', 'read1'):
        order = list(timed_systems(preparations, name))
        for round_number in range(-1, 10):
            rotation = 0 if round_number == -1 else round_number % 2
            for system in order[rotation:] + order[:rotation]:
                schedule.append(dict(benchmark=name, system=system, round=round_number, retained=round_number >= 0))
    plan = dict(common_compiler_basis=BASE, source_bases={label: value['compiler_commit'] for label, value in preparations.items()},
                upstream_commit=preparations['baseline']['upstream_commit'], cpu=5, timeout_seconds=120,
                preparation=str(SHARED / 'supervisor'), taskset=preparations['baseline']['tools']['TASKSET']['path'],
                environment={'BINARYEN_CORES': '1'},
                inherited_environment={name: os.environ.get(name) for name in runner.RECORDED_ENVIRONMENT},
                workloads={name: dict(count=count) for name, count in [('sum1', 25), ('read1', 2500)]},
                systems={name: timed_systems(preparations, name) for name in ('sum1', 'read1')},
                schedule=schedule, identities=identities(preparations), created_utc=datetime.now(timezone.utc).isoformat())
    (REPORT / 'timing-plan.json').write_text(json.dumps(plan, indent=2) + '\n')
    runner.verify(plan)
    print('PASS frozen identities and accepted supervisor origins; 44 processes declared; no benchmark started')


if __name__ == '__main__':
    main()
