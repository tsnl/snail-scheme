#!/usr/bin/env python3
"""Freeze the reviewed current seven-system Parsing plan without clean execution."""

import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
PREPARED = ROOT/'build/parsing-measurement-prepared-8930aaa'
spec = importlib.util.spec_from_file_location('parsing_measurement', REPORT/'measure-seven.py')
measurement = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = measurement
spec.loader.exec_module(measurement)


# ---- Complete current preparation and exact lowering input establish readiness ----

def read(path):
    return json.loads(path.read_text())


def check_preparation():
    prepared = read(PREPARED/'prepared.json')
    measurement.require(prepared['status'] == 'ready' and prepared['compiler_commit'] == measurement.BASIS, 'current source basis differs')
    for name, expected in prepared['artifacts'].items():
        measurement.require(measurement.digest(PREPARED/name) == expected, 'prepared bytes changed: '+name)
    native, = (PREPARED/'native').glob('native.native-*')
    measurement.require(measurement.digest(native/'optimized.wasm') == measurement.digest(PREPARED/'native/native-final.wasm'), 'native-final control is not actual LLVM input')
    measurement.require(measurement.digest(PREPARED/'parsing/input.txt') == measurement.INPUT_SHA256, 'canonical input changed')
    measurement.require(measurement.digest(PREPARED/'parsing/inputs/parsing.data') == measurement.DATA_SHA256, 'complete28300-byte input changed')
    measurement.require(read(PREPARED/'utf8-host/validation.json')['node_executed'] is True, 'UTF8 host was not executed in Node')
    measurement.require(read(PREPARED/'current-predicate-controls.json')['total'] == 36, 'current predicate controls incomplete')
    records = [read(path) for path in PREPARED.glob('commands/*/record.json')]
    measurement.require(all(row['returncode'] == 0 and row['capture_complete'] and not row['timeout'] and not row['executing_descendants'] for row in records), 'current preparation has unclosed or failed child')
    return prepared


def check_native_sources():
    build, = (PREPARED/'native').glob('native.native-*')
    sources = read(PREPARED/'source.json')['files']
    for name, expected in sources.items():
        measurement.require(measurement.digest(PREPARED/'compiler-source'/name) == expected and measurement.digest(ROOT/name) == expected, 'compiler/GC source changed: '+name)
    for name, expected in read(build/'build.json')['sha256'].items():
        original = Path(name)
        frozen = PREPARED/'native-runtime.a' if original == ROOT/'build/native-runtime/release/libsnail_runtime.a' else original
        measurement.require(measurement.digest(frozen) == expected, 'native build provenance changed: '+name)
    trace = read(build/'compile.trace.json')
    measurement.require(any(row.get('name') == 'build.optimize-scheme' for row in trace), 'native Binaryen stage absent')


# ---- Actual imported Python, executable libraries and Chez heaps are frozen ----

def imports():
    output = subprocess.check_output([sys.executable, REPORT/'measure-seven.py', '--dependency-files'])
    return set(map(Path, json.loads(output)))


def linked_files(executables):
    files, records = set(), []
    ldd = Path(shutil.which('ldd'))
    for executable in sorted(executables):
        row = subprocess.run([ldd, executable], capture_output=True, timeout=30)
        measurement.require(row.returncode == 0, 'dynamic library discovery failed: '+str(executable))
        records.append(dict(command=[str(ldd), str(executable)], returncode=row.returncode, stdout=row.stdout.decode(), stderr=row.stderr.decode()))
        files.update(Path(name) for name in re.findall(r'(/[^\s()]+)', row.stdout.decode()) if Path(name).is_file())
    measurement.save(PREPARED/'linked-dependencies.json', records)
    return files | {ldd, PREPARED/'linked-dependencies.json'}


def frozen_identities(tools):
    imported = imports() | set(map(Path, measurement.dependency_files()))
    files = imported | {path for path in PREPARED.rglob('*') if path.is_file()}
    files.update(REPORT/name for name in ('measure-seven.py','prepare.py','freeze-plan.py'))
    files.update(Path(row['path']) for row in tools.values())
    executables = {Path(tools[name]['path']) for name in ('NODE','CHEZ','TASKSET','PYTHON')}
    executables |= {PREPARED/'native/native', PREPARED/'rust/parsing.native'}
    executables.update(path for path in imported if path.suffix == '.so')
    files |= linked_files(executables)
    files.update(Path(tools['CHEZ']['path']).resolve().parents[1].glob('lib/**/*.boot'))
    for row in tools.values():
        measurement.require(measurement.digest(row['path']) == row['sha256'], 'actual tool changed')
    return {str(path):measurement.digest(path) for path in sorted(files)}


def execution_dependencies(configurations, identities):
    # Immutable runtime libraries/heaps are read by each guest before timing.
    # Local command/module/input/provider files are checked before every row.
    external = [path for path in identities if not Path(path).is_relative_to(ROOT)]
    for config in configurations.values():
        config['dependencies'] = list(dict.fromkeys([*config['dependencies'], *external]))
    return configurations


# ---- Seven warmups and seven rotations balance retained positions only ----

def plan(prepared):
    protocols = read(PREPARED/'protocols.json')
    identities = frozen_identities(prepared['tools'])
    return dict(measurement_started=False, coordinated_release_required=True, compiler_commit=measurement.BASIS,
        preparation_author_commit='c67ef8cc21e50c77fd0da8ca2e63b8bd78cb7fb5', historical_compiler_commit='45214e314d6f3f4424de47d04368f01ccd98a3af',
        integration_preparation_basis='4c191323d08272591fc1346fdb1cbd53fa464b70',
        upstream_commit='85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1', gc_policy='current growing precise collector',
        cpu=5, timeout_seconds=120, rounds=7, warmup_processes=7, measured_processes=49,
        input_count=2500, data_bytes=28300, input_sha256=measurement.INPUT_SHA256,data_sha256=measurement.DATA_SHA256,
        expected_datum=protocols['expected_datum'],expected_rust_output=protocols['expected_rust_output'],
        systems=list(measurement.SYSTEMS), configurations=execution_dependencies(protocols['configurations'], identities),
        schedule=measurement.schedule(), environment={'BINARYEN_CORES':'1'},
        inherited_environment={name:os.environ.get(name) for name in measurement.RECORDED_ENVIRONMENT},
        fresh_processes=True, serial_execution=True, balance='Seven cyclic rotations: each retained system occupies each position once. No adjacency-balance claim.',
        clock_boundary='One original worker loads the complete28300-byte file, parses2500 times, and checks the full proper(should return this list) predicate. Configuration/expectation setup precedes the clock; data loading and closing remain inside it. Serialization/final cleanup follow it.',
        analysis='Retain all seven samples per system; report median/min/max and descriptive ratios to original Chez plus native/exact-native-final V8. No trimming, replacement or adaptive stopping.',
        failure_policy='Abort before another row on failed exit, stderr, invalid complete frame/predicate, timeout/interruption, unexpected or surviving original-group descendants, changed executable dependencies or settings. Initial/final broader provenance discrepancy invalidates campaign. Preserve all attempts.',
        capture_policy='Regular-file stdin/stdout/stderr. Record actual wait status, inspect original-group members, bounded SIGKILL cleanup, close handles and preserve bytes before validation. Frozen guests are non-daemonizing; arbitrary escaped children are outside this original-group check.',
        source_scope='Fresh current Scheme Wasm/native and both Chez controls use8930aaa source bytes, including growing GC; all eight generated source/input files match current integration4c19132. Counter-free native provider retains UTF8 diagnostics. Exact native-final V8 shares actual lowering bytes and verified scalar-provider import closure. Timing host adds the narrow UTF8 scalar import and executes real Node controls. Rust binaries/sources are retained author controls, not freshly built. Historical45214e3 preparation remains separate.',
        protocol_records=protocols['protocol_records'], identities=identities)


def main():
    measurement.require(not (REPORT/'timing-plan.json').exists(), 'refusing to replace a frozen plan')
    prepared = check_preparation()
    check_native_sources()
    frozen = plan(prepared)
    measurement.verify(frozen)
    measurement.save(REPORT/'timing-plan.json', frozen)
    measurement.save(REPORT/'readiness-audit.json', dict(ready=True, clean_measurement_started=False,
        compiler_commit=measurement.BASIS, fresh_complete_frames=7, fresh_predicate_controls=36,
        processes_planned=56, source_kernel_unchanged=True, native_gc_current=True, native_provider_counter_free=True,
        plan_sha256=measurement.digest(REPORT/'timing-plan.json'), frozen_identities=len(frozen['identities'])))
    print('PASS frozen complete Parsing plan;',len(frozen['identities']),'identities;56 invocations planned,none launched')


if __name__ == '__main__':
    main()
