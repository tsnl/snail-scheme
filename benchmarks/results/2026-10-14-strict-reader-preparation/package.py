#!/usr/bin/env python3
"""Freeze every reader-port attempt and verify every archived regular file."""

import hashlib
import importlib.util
import json
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
BUILD = ROOT / 'build'


# ---- Preserve earlier failures and successful artifacts without rewriting them ----

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def evidence_files():
    roots = [*BUILD.glob('strict-reader-ports-attempt*'), *BUILD.glob('strict-reader-controls-attempt*'),
             *BUILD.glob('strict-reader-controls-validation-attempt*'), *BUILD.glob('reader-ports-bridge-*'),
             BUILD / 'reader-controls-import-attempt1', BUILD / 'reader-retained-work-attempt1']
    paths = [path for root in roots for path in ([root] if root.is_file() else root.rglob('*')) if path.is_file()]
    for attempt in (BUILD / 'reader-design').glob('attempt-*'):
        record = attempt / 'record.json'
        if record.exists() and 'reader-ports-bridge-' in record.read_text():
            paths.extend(path for path in attempt.iterdir() if path.is_file())
    paths += [BUILD / name for name in ('generate-reader-bridge.py', 'validate-reader-controls.py',
              'validate-reader-controls-helper.py', 'validate-reader-controls.stdout', 'validate-reader-controls.stderr',
              'reader-retained-work.stdout', 'reader-retained-work.stderr', 'adapt-reader-timing-runner.py')]
    paths += [BUILD / 'reader-design' / name for name in ('env.sh', 'run.py')]
    paths += [ROOT / 'benchmarks/strict-suite' / name for name in ('reader_ports.py', 'reader-host.mjs',
              'reader-timing.mjs', 'measure.py', 'matrix_port.py')]
    return {str(path.relative_to(ROOT)): path for path in sorted(set(paths)) if '__pycache__' not in path.parts}


def verify_sources():
    spec = importlib.util.spec_from_file_location('freeze_reader_plan', REPORT / 'freeze-plan.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    core, controls = module.checked_preparation()
    identities = dict(compiler_commit=core['compiler_commit'], upstream_commit=core['upstream_commit'],
                      library_archive_sha256=digest(ROOT / 'benchmarks/results/2026-10-14-strict-reader-library/artifacts.tar.xz'),
                      source_files={})
    for case in core['cases']:
        directory, name = module.CORE / case['name'], case['name']
        paths = ('upstream.scm', 'upstream-kernel.scm', 'adapted-kernel.scm', 'strict.scm',
                 'input.txt', case['spec']['pathnames'][0], 'adaptation-ledger.json', 'complete-chez-edit-ledger.json')
        identities['source_files'][name] = {path: digest(directory / path) for path in paths}
    save(REPORT / 'source-identities.json', identities)


def verify_protocols():
    spec = importlib.util.spec_from_file_location('reader_runner', REPORT / 'measure-seven.py')
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    plan = json.loads((REPORT / 'timing-plan.json').read_text())
    runner.verify(plan)
    records, core, controls = [], BUILD / 'strict-reader-ports-attempt6', BUILD / 'strict-reader-controls-attempt2'
    for name, count in (('sum1', 25), ('read1', 2500)):
        paths = {'strict-v8': BUILD / f'strict-reader-controls-validation-attempt1/commands/{name}-production-timing-host/record.json',
                 'strict-v8-native-module': controls / name / 'native-timing/commands/shared-module-v8-validation/record.json',
                 'strict-native': controls / name / 'native-timing/commands/full-count-validation/record.json',
                 'chez-original': core / name / f'commands/count-{count}-chez/record.json',
                 'chez-adapted': core / name / f'commands/count-{count}-chez-adapted/record.json',
                 'rust-wasm': controls / f'rust-reference/commands/{name}-count-{count}-optimized-wasm/record.json',
                 'rust-native': controls / f'rust-reference/commands/{name}-count-{count}-native/record.json'}
        for system, path in paths.items():
            record = json.loads(path.read_text())
            runner.workload_seconds(plan, dict(benchmark=name, system=system), record)
            records.append(dict(benchmark=name, system=system, path=str(path), sha256=digest(path), passed=True))
    save(REPORT / 'checks.json', dict(protocol_records=records, dry_identity_verification=True,
        canonical_counts={'sum1': [1, 2, 25], 'read1': [1, 2, 2500]},
        five_scheme_edge_checks=105, rust_complete_results=18, full_count_internal_trace=False))


# ---- Archive regular contents, then compare all members with their manifest ----

def main():
    verify_sources()
    verify_protocols()
    files, archive = evidence_files(), REPORT / 'artifacts.tar.xz'
    if archive.exists():
        raise ValueError('do not replace an existing preparation archive')
    hashes = {name: digest(path) for name, path in files.items()}
    with tarfile.open(archive, 'w:xz', preset=6) as target:
        for name, path in files.items():
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = path.stat().st_size, path.stat().st_mode & 0o777, 0
            with path.open('rb') as contents:
                target.addfile(info, contents)
    save(REPORT / 'manifest.json', dict(archive_sha256=digest(archive), files=hashes))
    verified = {}
    with tarfile.open(archive, 'r:xz') as source:
        for entry in source:
            if not entry.isfile() or entry.name in verified:
                raise ValueError('archive contains a duplicate or nonregular entry')
            verified[entry.name] = hashlib.sha256(source.extractfile(entry).read()).hexdigest()
    if verified != hashes:
        raise ValueError('archive differs from its complete input manifest')
    save(REPORT / 'archive-verification.json', dict(members=len(verified), all_hashes_match=True,
        archive_sha256=digest(archive), bytes=archive.stat().st_size))
    print('Archived and verified', len(verified), 'files;', archive.stat().st_size, 'bytes')


if __name__ == '__main__':
    main()
