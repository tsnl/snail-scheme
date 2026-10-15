#!/usr/bin/env python3
"""Copy matched Equal evidence and freeze the plan without starting any guest."""

import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile

import measure

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
SOURCE = Path('/tmp/snail-equal-profiling-20261014')
ORIGINAL = SOURCE/'build/equal-hash'
PREPARED = ROOT/'build/equal-hash-matched-20261014'
BASE = '27604d44652f74169104d25c3a3edc8a0bb653ca'
SOURCE_SCOPE = ('src', 'scripts', 'Cargo.toml', 'Cargo.lock', 'build.rs',
                'benchmarks/strict-suite', 'tests/strict', 'doc/strict-core.md', 'TOUR.md')


# ---- Copies preserve artifact origins and the candidate's uncommitted source ----

def read(path):
    return json.loads(path.read_text())


def git(*arguments):
    return subprocess.check_output(['git', *arguments], cwd=SOURCE)


def identities(directory):
    return {str(path.relative_to(directory)): measure.digest(path)
            for path in sorted(directory.rglob('*')) if path.is_file()}


def copy_artifacts():
    PREPARED.mkdir(parents=True, exist_ok=False)
    shutil.copytree(ORIGINAL/'baseline', PREPARED/'baseline')
    shutil.copytree(ORIGINAL/'candidate-explicit', PREPARED/'candidate')
    shutil.copytree(ORIGINAL/'candidate/native', PREPARED/'candidate/native')
    frozen = PREPARED/'frozen'
    frozen.mkdir()
    for name in ('reader-timing.mjs', 'explicit-word-comparison.json'):
        shutil.copy2(ORIGINAL/name, frozen/name)
    shutil.copy2(ORIGINAL/'candidate/basis.json', frozen/'initial-candidate-basis.json')
    shutil.copy2(SOURCE/'build/native-runtime/release/libsnail_runtime.a', frozen/'libsnail_runtime.a')


def baseline_snapshot(target):
    names = git('ls-tree', '-r', '--name-only', BASE, '--', *SOURCE_SCOPE).decode().splitlines()
    payload = git('archive', '--format=tar', BASE, *names)
    with tarfile.open(fileobj=io.BytesIO(payload)) as archive:
        for member in archive:
            if member.isdir():
                continue
            measure.require(member.isfile(), 'nonregular source snapshot: ' + member.name)
            path = target/member.name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(archive.extractfile(member).read())
            path.chmod(member.mode)


def candidate_snapshot(target):
    names = git('ls-files', '--cached', '--others', '--exclude-standard', '-z', '--', *SOURCE_SCOPE)
    for name in names.decode().strip('\0').split('\0'):
        source, destination = SOURCE/name, target/name
        measure.require(source.is_file() and not source.is_symlink(), 'nonregular candidate source: ' + name)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)


def initial_compiler_snapshot(target):
    source = PREPARED/'sources/candidate'
    for name in ('src', 'scripts'):
        shutil.copytree(source/name, target/name)
    for name in ('Cargo.toml', 'Cargo.lock', 'build.rs'):
        if (source/name).is_file():
            shutil.copy2(source/name, target/name)
    datum = target/'src/snail/datum.sld'
    datum.write_text(datum.read_text().replace('(i64-mul ', '(* ').replace('(i64-add ', '(+ '))
    expected = read(PREPARED/'frozen/initial-candidate-basis.json')['source']
    measure.require(all(measure.digest(target/name) == value for name, value in expected.items()),
                    'initial compiler reconstruction does not match recorded source hashes')


def retain_sources():
    target = PREPARED/'sources'
    baseline_snapshot(target/'baseline')
    candidate_snapshot(target/'candidate')
    initial_compiler_snapshot(target/'initial-native-compiler')
    (target/'candidate-dirty.patch').write_bytes(git('diff', '--binary', BASE, '--', *SOURCE_SCOPE))
    (target/'candidate-status.txt').write_bytes(git('status', '--porcelain=v1', '--ignore-submodules=all', '--', *SOURCE_SCOPE))
    record = dict(base_commit=BASE, candidate_head_at_freeze=git('rev-parse', 'HEAD').decode().strip(),
        candidate_uncommitted=True, original_source_root=str(SOURCE), scope=list(SOURCE_SCOPE),
        files={name: identities(target/name) for name in ('baseline', 'candidate', 'initial-native-compiler')},
        initial_native_compiler='Reconstructed from final candidate by reverting only i64-mul/add spelling; every recorded source hash matches.',
        commit_policy='Captured HEAD and dirty patch describe provenance at freeze. The candidate is not represented as a clean commit.')
    measure.save(target/'provenance.json', record)


# ---- Existing correctness, mandatory optimization and exact native Wasm are replayed ----

def check_protocol(path, system):
    record = read(path)
    measure.require(record['returncode'] == 0 and not record['timeout'] and not record['stderr']
                    and not record['executing_descendants'], 'preparation process failed: ' + str(path))
    measure.frame_seconds(system, record['stdout'].encode())


def normalized_native_commands(revision):
    directory = PREPARED/revision/'native'
    build, = directory.glob('native.native-*')
    record = read(build/'build.json')
    origin = ORIGINAL/('baseline' if revision == 'baseline' else 'candidate')/'native'
    origin_build = origin/build.name
    result = []
    for row in record['commands']:
        measure.require(row['status'] == 0, 'native build failed')
        result.append([argument.replace(str(origin_build), '<build>').replace(str(origin), '<native>')
                       .replace(str(SOURCE), '<source>') for argument in row['command']])
    return result


def check_compile_basis(directory, source):
    basis = read(directory/'basis.json')
    measure.require(all(measure.digest(source/name) == value for name, value in basis['source'].items()), 'compile source mismatch')
    measure.require(basis['source_commit'] == BASE and basis['input_sha256'] == measure.digest(directory/'input.txt'), 'basis mismatch')
    link = read(directory/'optimized.wasm.link.json')
    measure.require(all(row['status'] == 0 for row in link) and any('-O3' in row['command'] for row in link), 'production Binaryen absent')
    return basis['tools']


def check_native_artifacts(directory, build):
    trace = read(build/'compile.trace.json')
    measure.require(any(row.get('name') == 'build.optimize-scheme' for row in trace), 'native Binaryen absent')
    measure.require(measure.digest(build/'optimized.wasm') == measure.digest(directory/'native/native-final.wasm'), 'native-final Wasm mismatch')
    measure.require(measure.digest(directory/'strict-native.wasm') == measure.digest(directory/'native/strict-native.wasm'), 'native input mismatch')


def check_revision(revision):
    directory = PREPARED/revision
    tools = check_compile_basis(directory, PREPARED/'sources'/revision)
    build, = (directory/'native').glob('native.native-*')
    check_native_artifacts(directory, build)
    check_native_provenance(revision, build)
    for label, mode in [('complete-correctness', 'native64'), ('production-v8-correctness', 'production-v8'),
                        ('identical-wasm-v8-correctness', 'native-final-v8')]:
        check_protocol(directory/'native/commands'/label/'record.json', revision+'-'+mode)
    return tools


def check_native_provenance(revision, build):
    origin = ORIGINAL/('baseline' if revision == 'baseline' else 'candidate')/'native'
    for name, expected in read(build/'build.json')['sha256'].items():
        path = Path(name)
        if path.is_relative_to(origin):
            frozen = PREPARED/revision/'native'/path.relative_to(origin)
        elif path == SOURCE/'build/native-runtime/release/libsnail_runtime.a':
            frozen = PREPARED/'frozen/libsnail_runtime.a'
        elif path.is_relative_to(SOURCE):
            frozen = PREPARED/'sources/initial-native-compiler'/path.relative_to(SOURCE)
        else:
            frozen = path
        measure.require(measure.digest(frozen) == expected, 'native provenance mismatch: ' + name)


def check_matched():
    tools = check_revision('baseline')
    measure.require(tools == check_revision('candidate'), 'tool records differ')
    for name in ('strict.scm', 'input.txt', 'spec.json', 'runtime.wasm', 'native/native-entry.c',
                 'native/native-provider.c', 'native/native-provider.h', 'native/provider.wasm'):
        measure.require(measure.digest(PREPARED/'baseline'/name) == measure.digest(PREPARED/'candidate'/name), 'matched input/provider changed: ' + name)
    comparison = read(PREPARED/'frozen/explicit-word-comparison.json')
    for name, row in comparison.items():
        measure.require(row['identical'] and row['first'] == row['explicit'] == measure.digest(PREPARED/'candidate'/name), 'final spelling changed artifact')
    measure.require(normalized_native_commands('baseline') == normalized_native_commands('candidate'), 'native commands differ')
    return tools


# ---- Executable, import and dynamic-library closure is frozen without guests ----

def import_files():
    command = [sys.executable, str(REPORT/'measure.py'), '--dependency-files']
    return set(map(Path, json.loads(subprocess.check_output(command))))


def linked_files(executables):
    dependencies, records = set(), []
    for path in sorted(executables):
        run = subprocess.run(['ldd', str(path)], capture_output=True, timeout=30)
        records.append(dict(command=['ldd', str(path)], returncode=run.returncode,
                            stdout=run.stdout.decode(), stderr=run.stderr.decode()))
        measure.require(run.returncode == 0, 'dynamic dependency discovery failed: ' + str(path))
        dependencies.update(Path(name) for name in re.findall(r'(/[^\s()]+)', run.stdout.decode()) if Path(name).is_file())
    measure.save(PREPARED/'linked-dependencies.json', records)
    return dependencies


def configurations(tools):
    result = {}
    for system in measure.SYSTEMS:
        revision, mode = system.split('-', 1)
        directory = PREPARED/revision
        native = directory/'native'
        if mode == 'native64':
            arguments, cwd, dependencies = [native/'native'], native, [native/'native', native/'input.txt']
        else:
            module = directory/'optimized.wasm' if mode == 'production-v8' else native/'native-final.wasm'
            cwd = directory if mode == 'production-v8' else native
            provider = [] if mode == 'production-v8' else [native/'provider.wasm']
            arguments = [tools['NODE']['path'], '--disable-warning=ExperimentalWarning', PREPARED/'frozen/reader-timing.mjs', module, cwd/'spec.json', *provider]
            dependencies = [Path(tools['NODE']['path']), PREPARED/'frozen/reader-timing.mjs', module, cwd/'spec.json', cwd/'input.txt', *provider]
        result[system] = dict(command=[tools['TASKSET']['path'], '-c', '5', *map(str, arguments)],
                             cwd=str(cwd), dependencies=list(map(str, [Path(tools['TASKSET']['path']), *dependencies])))
    return result


def frozen_identities(tools):
    files = {path for path in PREPARED.rglob('*') if path.is_file()} | import_files()
    files.update(map(Path, measure.dependency_files()))
    files.update(Path(row['path']) for row in tools.values())
    files.add(REPORT/'freeze.py')
    executables = {Path(sys.executable), Path(tools['NODE']['path']), Path(tools['TASKSET']['path'])}
    executables.update(PREPARED/revision/'native/native' for revision in ('baseline', 'candidate'))
    executables.update(path for path in files if path.suffix == '.so')
    files |= linked_files(executables)
    files.add(PREPARED/'linked-dependencies.json')
    for row in tools.values():
        measure.require(measure.digest(row['path']) == row['sha256'], 'tool identity changed')
    return {str(path): measure.digest(path) for path in sorted(files)}


# ---- A frozen plan records the fixed analysis and abort policy ----

def plan(tools):
    return dict(measurement_started=False, coordinated_release_required=True, cpu=5, timeout_seconds=60,
        base_commit=BASE, candidate_uncommitted_at_freeze=True, input_parameters=[100, 100, 8, 1000, 2000, 5000],
        rounds=12, warmup_processes=6, measured_processes=72, systems=list(measure.SYSTEMS),
        fresh_processes=True, serial_execution=True, environment={'BINARYEN_CORES': '1'},
        inherited_environment={name: os.environ.get(name) for name in measure.RECORDED_ENVIRONMENT},
        clock_boundary='Original complete five-phase Equal aggregate and exact-#t predicate; setup/input parsing precede the clock, serialization and resource cleanup follow it.',
        analysis='Keep all twelve retained samples per system. Report medians, min/max, ratio of candidate/baseline medians and all twelve same-round ratios with their median. No trimming or adaptive stopping.',
        failure_policy='Abort on nonzero exit, stderr, timeout, interruption, invalid full JSON result/lifecycle frame, dependency/environment drift, unexpected descendants, surviving process-group members or competing owned activity. Preserve failed attempts; no silent retry.',
        capture_policy='Raw stdout/stderr files are finalized after leader wait and bounded SIGKILL cleanup. Only then parse. Linux /proc checks the original process group, excluding zombies; frozen guests are non-daemonizing.',
        balance='Two six-row Williams cycles: every serial position twice, every directed within-round adjacent pair twice, candidate before baseline six times and after six times for every mode.',
        source_scope='Baseline library/compiler bytes from base commit; frozen uncommitted final candidate bytes. Both native builds use the same initial candidate lowering compiler and unchanged runtime/providers; final candidate Wasm is byte-identical at all four recorded stages.',
        configurations=configurations(tools), schedule=measure.schedule(), tools=tools,
        source_provenance=str(PREPARED/'sources/provenance.json'), identities=frozen_identities(tools))


def main():
    measure.require(not (REPORT/'timing-plan.json').exists(), 'refusing to replace a frozen plan')
    copy_artifacts()
    retain_sources()
    frozen = plan(check_matched())
    measure.verify(frozen)
    measure.save(REPORT/'timing-plan.json', frozen)
    measure.save(REPORT/'matched-ready.json', dict(passed=True, no_guest_started=True,
        candidate_uncommitted=True, complete_correctness_frames_replayed=6,
        matched_native_commands=True, final_candidate_wasm_identical=True,
        plan_sha256=measure.digest(REPORT/'timing-plan.json'), hashed_files=len(frozen['identities'])))
    print('PASS frozen matched sources and artifacts;', len(frozen['identities']), 'identities; 78 invocations planned, none launched')


if __name__ == '__main__':
    main()
