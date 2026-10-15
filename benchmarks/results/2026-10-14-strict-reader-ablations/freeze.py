#!/usr/bin/env python3
"""Freeze three independently validated preparations for the reviewed serial runner."""

from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
ORIGINAL = ROOT / 'benchmarks/results/2026-10-14-strict-reader-timing-correction'
BASE = 'c0ba036499de55622538fc4c077fb8951b510502'
PREPARATIONS = {
    'baseline': ROOT / 'build/reader-ablation-prepared',
    'delimiters': Path('/tmp/snail-reader-delimiter-ablation-20261014/build/reader-ablation-prepared'),
    'staging': Path('/tmp/snail-reader-staging-ablation-20261014/build/reader-ablation-prepared'),
}


# ---- Each completed preparation proves its own source and artifact identities ----

def load(path):
    return json.loads(path.read_text())


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def checked_preparations():
    results = {}
    for label, path in PREPARATIONS.items():
        value = load(path / 'prepared.json')
        assert {case['name'] for case in value['cases']} == {'sum1', 'read1'}
        for case in value['cases']:
            assert case['status'] == 'ready', label + ': preparation incomplete'
            for name, expected in case['hashes'].items():
                assert digest(path / case['name'] / name) == expected, label + ': changed preparation'
        for name, expected in value['compiler_files'].items():
            assert digest(path / 'compiler-source' / name) == expected
        results[label] = value
    return results


def check_independent_sources(preparations):
    baseline = preparations['baseline']['compiler_files']
    allowed = {'delimiters': {'src/snail/read.sld'},
               'staging': {'src/snail/read.sld', 'src/snail/datum.sld', 'src/strict_datum.rs'}}
    assert preparations['baseline']['compiler_commit'] == BASE
    for label, changed in allowed.items():
        candidate = preparations[label]['compiler_files']
        assert set(candidate) == set(baseline)
        assert {name for name in baseline if candidate[name] != baseline[name]} == changed
        assert candidate['src/snail-scheme/strict-compiler.sld'] == baseline['src/snail-scheme/strict-compiler.sld']


# ---- The accepted runner and complete local supervisor closure are unchanged ----

def copy_runner():
    target = REPORT / 'measure.py'
    shutil.copy2(ORIGINAL / 'measure-seven.py', target)
    assert digest(target) == digest(ORIGINAL / 'measure-seven.py')
    shutil.copytree(ORIGINAL / 'supervisor', REPORT / 'supervisor', dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('__pycache__'))
    paths = sorted((REPORT / 'supervisor').glob('*.py'))
    assert {path.name for path in paths} == {path.name for path in (ORIGINAL / 'supervisor').glob('*.py')}
    assert all(digest(path) == digest(ORIGINAL / 'supervisor' / path.name) for path in paths)
    shutil.copy2(ROOT / 'benchmarks/strict-suite/reader-timing.mjs', REPORT / 'reader-timing.mjs')
    spec = importlib.util.spec_from_file_location('reviewed_reader_runner', target)
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    return runner, [target, *paths, REPORT / 'reader-timing.mjs', Path(__file__)]


def timed_systems(preparations, name):
    result = {}
    for label, path in PREPARATIONS.items():
        node = preparations[label]['tools']['NODE']['path']
        case = path / name
        result['strict-v8-' + label] = dict(argv=[node, '--disable-warning=ExperimentalWarning',
            str(REPORT / 'reader-timing.mjs'), str(case / 'optimized.wasm'), str(case / 'spec.json')],
            cwd=str(case), stdin=None)
    return result


def identity_files(preparations, paths):
    for label, directory in PREPARATIONS.items():
        paths += [directory / 'prepared.json', directory / 'reader_ports.py', directory / 'reader-host.mjs']
        paths += list((directory / 'compiler-source').rglob('*'))
        for tool in preparations[label]['tools'].values():
            paths.append(Path(tool['path']))
        for case in preparations[label]['cases']:
            folder = directory / case['name']
            paths += [folder / name for name in ('upstream.scm', 'adapted-kernel.scm', 'strict.scm',
                      'optimized.wasm', 'raw.wasm', 'strict-native.wasm', 'runtime.wasm', 'native',
                      'spec.json', 'input.txt', 'canonical-validation.json', case['spec']['pathnames'][0])]
    return {str(path): digest(path) for path in sorted(set(paths)) if path.is_file()}


# ---- Predetermined discard and nine balanced rotations precede any quiet release ----

def main():
    preparations = checked_preparations()
    check_independent_sources(preparations)
    runner, paths = copy_runner()
    schedule = []
    for name in ('sum1', 'read1'):
        order = list(timed_systems(preparations, name))
        for round_number in range(-1, 9):
            rotation = 0 if round_number == -1 else round_number % 3
            for system in order[rotation:] + order[:rotation]:
                schedule.append(dict(benchmark=name, system=system, round=round_number, retained=round_number >= 0))
    tools = preparations['baseline']['tools']
    plan = dict(common_compiler_basis=BASE, source_bases={label: value['compiler_commit'] for label, value in preparations.items()},
                upstream_commit=preparations['baseline']['upstream_commit'], cpu=5, timeout_seconds=120,
                preparation=str(REPORT / 'supervisor'), taskset=tools['TASKSET']['path'], environment={'BINARYEN_CORES': '1'},
                inherited_environment={name: os.environ.get(name) for name in runner.RECORDED_ENVIRONMENT},
                workloads={name: dict(count=count) for name, count in [('sum1', 25), ('read1', 2500)]},
                systems={name: timed_systems(preparations, name) for name in ('sum1', 'read1')},
                schedule=schedule, identities=identity_files(preparations, paths), created_utc=datetime.now(timezone.utc).isoformat())
    save(REPORT / 'timing-plan.json', plan)
    runner.verify(plan)
    print('PASS frozen identities and accepted supervisor origins; 60 processes declared; no benchmark started')


if __name__ == '__main__':
    main()
