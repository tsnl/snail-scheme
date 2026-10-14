#!/usr/bin/env python3
"""Freeze the five reviewed systems and balanced 30-process Earley schedule."""

import hashlib
import importlib.util
import json
import os
from pathlib import Path

REPORT = Path(__file__).resolve().parent
ROOT = REPORT.parents[2]
PREP = ROOT / 'build/earley-prepare-04'
CASE = PREP / 'earley'
TIMER = ROOT / 'build/earley-timing-prepare-01'
NATIVE = next(CASE.glob('native.native-*'))
METADATA = json.loads((PREP / 'prepared.json').read_text())
module = importlib.util.spec_from_file_location('earley_measure_five', REPORT / 'measure-five.py')
RUNNER = importlib.util.module_from_spec(module)
module.loader.exec_module(RUNNER)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def config(argv, stdin=None, environment=None):
    return dict(argv=list(map(str, argv)), stdin=str(stdin) if stdin else None,
                environment=environment or {}, cwd=str(CASE))


tools = {name: row['path'] for name, row in METADATA['tools'].items()}
systems = {
    'v8-production': config([tools['NODE'], PREP / 'host.mjs', CASE / 'strict.wasm', CASE / 'spec.json']),
    'v8-common': config([tools['NODE'], PREP / 'host.mjs', NATIVE / 'optimized.wasm', CASE / 'spec.json']),
    'native-common': config([TIMER / 'native', '1'], environment={
        'SNAIL_GC_HEAP_BYTES': '1073741824', 'EARLEY_SIZE': '15',
        'EARLEY_EXPECTED_KIND': '1', 'EARLEY_EXPECTED': '2674440'}),
    'chez-original': config([tools['CHEZ'], '--program', CASE / 'program.so'], CASE / 'input.txt'),
    'chez-adapted': config([tools['CHEZ'], '--program', CASE / 'same-source-chez/program.so'], CASE / 'input.txt'),
}
order = list(systems)
schedule = [dict(round=-1, retained=False, system=name, position=index)
            for index, name in enumerate(order)]
for rotation in range(5):
    rotated = order[rotation:] + order[:rotation]
    schedule += [dict(round=rotation, retained=True, system=name, position=index)
                 for index, name in enumerate(rotated)]

files = [PREP / name for name in ('prepared.json', 'host.mjs', 'measure.py', 'earley_port.py', 'r7rs.py')]
files += [path for path in (PREP / 'compiler-source').rglob('*') if path.is_file()]
files += [CASE / name for name in ('input.txt', 'spec.json', 'strict.scm', 'strict.wasm', 'strict.wasm.raw.wasm',
          'strict.wasm.wat', 'strict.optimized.wat', 'original-kernel.scm', 'adapted-kernel.scm',
          'source-edits.json', 'source-proof.json', 'program.scm', 'program.so', 'native',
          'provider.c', 'provider.h', 'entry.c', 'same-source-chez/program.scm', 'same-source-chez/program.so')]
files += [NATIVE / name for name in ('optimized.wasm', 'optimized.wat', 'module.ll', 'provider-0.o', 'build.json')]
files += [path for path in TIMER.iterdir() if path.is_file()]
files += [REPORT / name for name in ('measure-five.py', 'inspect-retention.py', 'retention-audit.json', 'freeze-plan.py')]
files += [Path(path) for path in tools.values()]
identities = {str(path): sha256(path) for path in files}

plan = dict(status='prepared; awaiting explicit parent quiet-window release',
    compiler_commit=METADATA['compiler_commit'], driver_commit=METADATA['driver_commit'],
    count=1, size=15, expected=2674440, cpu=5, taskset=tools['TASKSET'],
    timeout_seconds=180, group_cleanup_seconds=10, environment={'BINARYEN_CORES': '1'},
    inherited_environment={name: os.environ.get(name) for name in RUNNER.RECORDED_ENVIRONMENT},
    systems=systems, schedule=schedule, identities=identities,
    optimization_flags=['-g', '--mvp-features', '--enable-gc', '--enable-reference-types', '--enable-tail-call',
        '--enable-mutable-globals', '--enable-sign-ext', '--enable-bulk-memory', '--enable-nontrapping-float-to-int',
        '-O3', '--closed-world', '--always-inline-max-function-size=40', '--converge'],
    wasm_identity={name: dict(sha256=sha256(path), bytes=path.stat().st_size) for name, path in
        [('once_optimized', CASE / 'strict.wasm'), ('final_common', NATIVE / 'optimized.wasm')]},
    byte_identical=False,
    clocks={
        'v8': 'process.hrtime.bigint around bench plus scalar status assertion; module instantiate and main excluded',
        'native': 'CLOCK_MONOTONIC around bench only; host/module initialization, main, printing, native_finish excluded',
        'chez': 'unchanged run-r7rs-benchmark loop and predicate with monotonic nanosecond jiffies; reading/compilation/startup/output excluded',
        'process': 'parent perf_counter around spawn, pipe capture, reap and owned-group cleanup; secondary duration only'},
    exclusions='First complete five-system round discarded in advance; no other exclusions or silent retries.',
    failure_policy='Stop campaign on timeout, stderr, nonzero exit, invalid framing, incorrect result, identity or environment drift; preserve every started sample.',
    comparison_scope='Production V8 versus original/adapted Chez; common-artifact V8 versus mechanical native; production/common V8 separates repeated Binaryen effects.',
    native_resource_limit='Default 256 MiB arena exhausted canonical input; same body passes with explicit 1 GiB reservation. No GC stats or profiler during clean runs.')
RUNNER.save(REPORT / 'timing-plan.json', plan)
RUNNER.verify(plan)
print(f'Frozen {len(identities)} identities and {len(schedule)} fresh processes; no measurement launched')
