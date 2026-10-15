#!/usr/bin/env python3
"""Freeze the verified Conform preparation and seven-system comparison without timing."""

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import signal
import sys
import tarfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
PREPARATION_REPORT = ROOT / 'benchmarks/results/2026-10-14-strict-conform-preparation'
EVIDENCE = ROOT / 'build/conform-evidence-2b47be4'
PREPARED = EVIDENCE / 'build/strict-conform-preparation-attempt1'
CORE = PREPARED / 'conform'
DIAGNOSTICS = REPORT / 'diagnostics'
AUTHOR = '/tmp/snail-strict-conform-20261014'
COMPILER = '43322a25b23e7c1d110378793247f984d2043d21'
spec = importlib.util.spec_from_file_location('conform_measurement', REPORT / 'measure-seven.py')
measurement = importlib.util.module_from_spec(spec)
spec.loader.exec_module(measurement)


# ---- Restore the complete archive and preserve its original source basis ----

def load(path):
    return json.loads(path.read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def restore_evidence():
    manifest = load(PREPARATION_REPORT / 'manifest.json')
    archive = PREPARATION_REPORT / 'artifacts.tar.xz'
    if archive.stat().st_size != manifest['archive']['bytes'] or digest(archive) != manifest['archive']['sha256']:
        raise ValueError('complete preparation archive changed')
    with tarfile.open(archive) as source:
        members = source.getmembers()
        names = [member.name for member in members]
        if len(names) != len(set(names)) or set(names) != set(manifest['files']) or not all(row.isfile() for row in members):
            raise ValueError('complete archive inventory is not unique regular files')
        if not EVIDENCE.exists():
            EVIDENCE.mkdir(parents=True, exist_ok=False)
            source.extractall(EVIDENCE, filter='data')
    for name, expected in manifest['files'].items():
        if digest(EVIDENCE / name) != expected:
            raise ValueError('restored preparation differs: ' + name)
    return dict(archive_sha256=manifest['archive']['sha256'], archive_bytes=archive.stat().st_size,
                verified_members=len(names), destination=str(EVIDENCE))


def verify_preparation():
    prepared = load(PREPARED / 'prepared.json')
    case, = prepared['cases']
    if prepared['compiler_commit'] != COMPILER or prepared['driver_commit'] != COMPILER or case['status'] != 'ready':
        raise ValueError('prepared compiler/driver basis or readiness differs')
    for name, expected in case['hashes'].items():
        if digest(CORE / name) != expected:
            raise ValueError('prepared Conform artifact changed: ' + name)
    for name, expected in prepared['compiler_files'].items():
        if digest(PREPARED / 'compiler-source' / name) != expected:
            raise ValueError('archived compiler source changed: ' + name)
    for tool in prepared['tools'].values():
        if digest(Path(tool['path'])) != tool['sha256']:
            raise ValueError('preparation tool changed: ' + tool['path'])
    return prepared


def verify_workload():
    configured = load(CORE / 'spec.json')
    if (configured['count'] != 500 or configured['names'] != ['a', 'b', '"c"', '"d"']
            or configured['expected_names'] != list(measurement.RESULT_NAMES)
            or configured['expected'] != 1 or configured['observe'] is not False
            or digest(CORE / 'input.txt') != measurement.INPUT_SHA256):
        raise ValueError('complete canonical Conform input or final predicate changed')
    native = CORE / 'controls/native'
    final, = native.glob('native.native-*/optimized.wasm')
    if final.read_bytes() != (native / 'native-final.wasm').read_bytes():
        raise ValueError('native-final Wasm is not the actual lowering input')
    for name in ('input.txt', 'spec.json'):
        if (native / name).read_bytes() != (CORE / name).read_bytes():
            raise ValueError('native control has a different complete input: ' + name)
    return dict(count=500, expected_strings=31, identical_native_final_sha256=digest(final))


def terminal_preparation_records():
    paths = sorted(PREPARED.rglob('commands/*/record.json'))
    records = [load(path) for path in paths]
    if any('returncode' not in row or row.get('timeout') or row.get('executing_descendants') for row in records):
        raise ValueError('preparation contains an unfinished or timed-out process')
    failures = [path for path, row in zip(paths, records) if row['returncode'] != 0]
    fatal = sum('/observations/fatal/' in str(path) for path in failures)
    negatives = sum('/controls/rust/commands/' in str(path) for path in failures)
    if len(records) != 119 or len(failures) != 32 or fatal != 20 or negatives != 12:
        raise ValueError('complete preparation terminal/failure inventory differs')
    return dict(terminal_records=len(records), expected_fatal_failures=fatal,
                expected_negative_rust_failures=negatives, timeouts=0, executing_descendants=0)


# ---- Map only the archived author paths; preserve exact commands and input ----

def relocated(name):
    if name.startswith(AUTHOR + '/'):
        return str(EVIDENCE / name[len(AUTHOR) + 1:])
    return name


def comparison_systems():
    original = load(PREPARATION_REPORT / 'comparison-commands.json')
    if tuple(row['system'] for row in original) != measurement.SYSTEMS:
        raise ValueError('seven prepared comparison systems differ')
    configured = {row['system']: dict(argv=[relocated(name) for name in row['command']],
        cwd=relocated(row['cwd']), stdin=relocated(row['stdin_file']) if row.get('stdin_file') else None)
        for row in original}
    measurement.save(REPORT / 'path-mapping.json', dict(original_worktree=AUTHOR,
        restored_worktree=str(EVIDENCE), original_commands=original, mapped_systems=configured,
        rule='Replace only the original worktree prefix; preserve every other argv/cwd/stdin byte.'))
    return configured


def protocol_records():
    return {system: EVIDENCE / 'build' / path for system, path in (
        ('snail-production-v8', 'strict-conform-audit/commands/snail-production-v8-host-correctness/record.json'),
        ('snail-native64', 'strict-conform-preparation-attempt1/conform/controls/native/commands/full-count-validation/record.json'),
        ('snail-identical-wasm-v8', 'strict-conform-audit/commands/snail-identical-wasm-v8-host-correctness/record.json'),
        ('chez', 'strict-conform-preparation-attempt1/conform/validation/canonical/commands/chez/record.json'),
        ('chez-adapted', 'strict-conform-preparation-attempt1/conform/validation/canonical/commands/chez-adapted/record.json'),
        ('rust-native', 'strict-conform-preparation-attempt1/conform/controls/rust/commands/canonical-native/record.json'),
        ('rust-optimized-wasm', 'strict-conform-preparation-attempt1/conform/controls/rust/commands/canonical-optimized-wasm/record.json'))}


# ---- Diagnostics exercise the actual launcher outside the clean schedule ----

def diagnostic(name, command, cwd=ROOT, stdin=None):
    target = DIAGNOSTICS / name
    target.mkdir(parents=True, exist_ok=False)
    path = target / 'record.json'
    record = dict(command=list(map(str, command)), cwd=str(cwd), phase='setup-diagnostic',
                  clean_sample=False, retained=False, status='starting')
    measurement.save(path, record)
    try:
        measurement.run_owned_process(dict(environment={'BINARYEN_CORES': '1'}, timeout_seconds=120),
            dict(cwd=str(cwd), stdin=str(stdin) if stdin else None), record, path,
            measurement.supervisor(str(PREPARED)))
        record['status'] = 'completed'
    except BaseException as error:
        record.update(status='failed', error=repr(error))
        raise
    finally:
        measurement.save(path, record)
    return record


def require_success(record):
    if record['returncode'] != 0 or record['stderr'] or record.get('timeout') or record.get('error'):
        raise ValueError('setup diagnostic failed: ' + str(record['command']))


def validate_frames(plan):
    archived = {system: str(path) for system, path in protocol_records().items()}
    measurement.test_result_frames(plan, archived)
    current = {}
    for system, config in plan['systems'].items():
        command = [plan['taskset'], '-c', str(plan['cpu']), *config['argv']]
        record = diagnostic('host-' + system, command, Path(config['cwd']), config['stdin'])
        measurement.workload_seconds(plan, system, record)
        current[system] = str(DIAGNOSTICS / ('host-' + system) / 'record.json')
    measurement.save(REPORT / 'protocol-records.json', dict(archived=archived, current=current))
    measurement.test_result_frames(plan, current)
    return dict(archived_complete_frames=len(archived), restored_host_complete_frames=len(current))


def imported_dependencies():
    record = diagnostic('fresh-import-closure', [sys.executable, REPORT / 'measure-seven.py', '--dependency-files', PREPARED])
    require_success(record)
    return {Path(name) for name in json.loads(record['stdout'])}


def linked_dependencies(tools, imported):
    files = {Path(row['path']) for row in tools.values()}
    ldd = Path(shutil.which('ldd'))
    files.add(ldd)
    executables = [*(Path(tools[name]['path']) for name in ('NODE', 'CHEZ', 'TASKSET', 'PYTHON')),
        CORE / 'controls/native/native', CORE / 'controls/rust/conform.native',
        *(path for path in sorted(imported) if path.suffix == '.so')]
    for index, executable in enumerate(executables):
        record = diagnostic('linked-dependencies-' + str(index), [ldd, executable])
        require_success(record)
        files.update(Path(name) for name in re.findall(r'(/[^\s()]+)', record['stdout']) if Path(name).is_file())
    files.update(Path(tools['CHEZ']['path']).resolve().parents[1].glob('lib/**/*.boot'))
    if os.environ.get('NIX_LD') and Path(os.environ['NIX_LD']).is_file():
        files.add(Path(os.environ['NIX_LD']))
    return files


def identity_files(prepared, imported):
    files = {PREPARED / 'compiler-source' / name for name in prepared['compiler_files']}
    files.update(CORE / name for name in ('upstream.scm', 'upstream-kernel.scm', 'adapted-kernel.scm',
        'strict.scm', 'spec.json', 'input.txt', 'raw.wasm', 'optimized.wasm', 'strict-native.wasm', 'runtime.wasm',
        'chez/program.scm', 'chez/program.so', 'chez-adapted/program.scm', 'chez-adapted/program.so',
        'controls/timing-host.mjs', 'controls/native/native', 'controls/native/native-final.wasm',
        'controls/native/provider.wasm', 'controls/native/spec.json', 'controls/native/input.txt',
        'controls/native/native-provider.c', 'controls/native/native-provider.h', 'controls/native/native-entry.c',
        'controls/native/final-module.json', 'controls/rust/conform.native', 'controls/rust/conform.wasm',
        'controls/rust/conform.raw.wasm', 'controls/rust/run-wasi.mjs', 'controls/toolchain.json'))
    files.update((CORE / 'controls/rust/src').rglob('*.rs'))
    files.update(CORE / 'controls/rust' / name for name in ('Cargo.toml', 'Cargo.lock'))
    files.update(PREPARED / name for name in ('prepared.json', 'prepared.before-prefix-correction.json',
        'matrix_port.py', 'data_ports.py', 'conform_port.py', 'conform_port.before-prefix-correction.py'))
    files.update(PREPARATION_REPORT / name for name in ('manifest.json', 'artifacts.tar.xz',
        'comparison-commands.json', 'source-identities.json', 'metadata-refresh.json', 'retained-work.json'))
    files.update(REPORT / name for name in ('measure-seven.py', 'freeze-plan.py', 'path-mapping.json', 'protocol-records.json'))
    files.update(protocol_records().values())
    files.update(Path(name) for name in load(REPORT / 'protocol-records.json')['current'].values())
    return files | imported | linked_dependencies(prepared['tools'], imported)


# ---- Exactly seven discarded warmups and seven balanced serial rotations ----

def timing_plan(prepared):
    return dict(compiler_commit=COMPILER, driver_commit=COMPILER, metadata_refresh_commit='7bd327f',
        preparation_report_commit='2b47be48bf7fabd3ce4e226fbcf5a1e7a48a6940', upstream_commit=prepared['upstream_commit'],
        cpu=5, timeout_seconds=120, preparation=str(PREPARED), taskset=prepared['tools']['TASKSET']['path'],
        environment={'BINARYEN_CORES': '1'},
        inherited_environment={name: os.environ.get(name) for name in measurement.RECORDED_ENVIRONMENT},
        input_count=500, input_names=['a', 'b', '"c"', '"d"'], expected_names=list(measurement.RESULT_NAMES),
        input_sha256=measurement.INPUT_SHA256, chez_workload_name='conform:500', systems=comparison_systems(),
        schedule=[dict(system=system, round=number, retained=number >= 0) for number in range(-1, 7)
            for system in measurement.SYSTEMS[max(0, number):] + measurement.SYSTEMS[:max(0, number)]],
        exclusions='Exactly the first seven processes are discarded; retain all49 balanced observations; no replacement samples.',
        workload_clock='Setup/input parsing precede the clock; all500 original invocations and complete final predicate are inside it.',
        process_clock='Popen through capture, actual leader reap, capture-handle closure and bounded owned-group cleanup.',
        module_control='Native64 and its V8 control share exact native-final Scheme Wasm; scalar providers and linkage differ.',
        ownership_assumptions='Descendants retain the inherited session/group, are visible in /proc and remain signalable/killable.',
        release='Explicit root quiet-window release is required before --run; this preparation is not a timing campaign.')


def main():
    if (REPORT / 'timing-plan.json').exists():
        raise ValueError('do not replace an existing frozen timing plan')
    signal.signal(signal.SIGTERM, measurement.request_stop)
    signal.signal(signal.SIGINT, measurement.request_stop)
    restored = restore_evidence()
    prepared = verify_preparation()
    workload = verify_workload()
    terminal = terminal_preparation_records()
    plan = timing_plan(prepared)
    measurement.verify_policy(plan)
    measurement.verify_environment(plan)
    frames = validate_frames(plan)
    imported = imported_dependencies()
    plan['identities'] = {str(path): digest(path) for path in sorted(identity_files(prepared, imported))}
    measurement.save(REPORT / 'timing-plan.json', plan)
    record = diagnostic('fresh-plan-verification', [sys.executable, REPORT / 'measure-seven.py'])
    require_success(record)
    measurement.save(REPORT / 'readiness-audit.json', dict(status='ready', measured=False, **restored, **workload,
        **terminal, **frames, imported_files=len(imported), frozen_identities=len(plan['identities']),
        jobs=len(plan['schedule']), discarded=7, retained=49, compiler_commit=COMPILER, metadata_refresh_commit='7bd327f'))
    print('Frozen', len(plan['schedule']), 'jobs and', len(plan['identities']), 'identities; no clean timing run')


if __name__ == '__main__':
    main()
