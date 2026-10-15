#!/usr/bin/env python3
"""Preserve audited Conform evidence, or verify the published archive read-only."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
PREPARED = ROOT / 'build/conform-evidence-2b47be4'
PREPARATION_REPORT = ROOT / 'benchmarks/results/2026-10-14-strict-conform-preparation'
PUBLISHED = ('artifacts.tar.xz', 'manifest.json', 'archive-verification.json')


# ---- Capture the selected evidence once, excluding regenerable caches ----

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def retained_files(root):
    for directory, children, names in os.walk(root):
        if any((Path(directory) / name).is_symlink() for name in children):
            raise ValueError('symlink evidence directory: ' + directory)
        children[:] = sorted(name for name in children if name not in ('target', '__pycache__'))
        for name in sorted(names):
            path = Path(directory) / name
            if path.is_symlink() or not path.is_file():
                raise ValueError('missing or nonregular selected evidence: ' + str(path))
            yield path


def evidence_files():
    roots = [PREPARED, REPORT, PREPARATION_REPORT]
    files = [path for root in roots for path in retained_files(root)]
    files = [path for path in files if not (path.parent == REPORT and path.name in PUBLISHED)]
    files += [ROOT / name for name in ('BENCHMARKS.md', 'benchmarks/README.md',
        'benchmarks/strict-suite/README.md', 'benchmarks/strict-suite/capabilities.md',
        'benchmarks/strict-suite/capabilities.json')]
    return {str(path.relative_to(ROOT)): path for path in sorted(set(files))}


def capture(files, directory):
    captured = {}
    for name, source in files.items():
        target = directory / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        captured[name] = target
    return captured


# ---- Bind the snapshot to the parent's semantic audit; never rerun guests ----

def check_audited_snapshot(directory, files):
    report = directory / REPORT.relative_to(ROOT)
    audit = json.loads((report / 'independent-review.json').read_text())
    campaign = REPORT.relative_to(ROOT) / 'measurements-attempt1'
    required = {str(REPORT.relative_to(ROOT) / 'timing-plan.json'), str(campaign / 'campaign.json')}
    required.update(str(campaign / f'sample-{index:02}.json') for index in range(56))
    required.update(str(REPORT.relative_to(ROOT) / name) for name in ('coordination-before.json', 'coordination-after.json'))
    if audit['complete'] is not True or audit['clean_processes'] != 56 or audit['retained_processes'] != 49:
        raise ValueError('completed independent audit of the frozen Conform schedule required')
    if not required.issubset(audit['audited_files']):
        raise ValueError('audit must bind the plan and every raw clean record')
    for name, expected in audit['audited_files'].items():
        if name not in files or digest(files[name]) != expected:
            raise ValueError('captured evidence differs from the independent audit: ' + name)


def check_original_preparation(directory):
    report = directory / PREPARATION_REPORT.relative_to(ROOT)
    plan = json.loads((directory / REPORT.relative_to(ROOT) / 'timing-plan.json').read_text())
    for name in ('manifest.json', 'artifacts.tar.xz'):
        if digest(report / name) != plan['identities'][str(PREPARATION_REPORT / name)]:
            raise ValueError('captured original preparation identity differs: ' + name)
    original = json.loads((report / 'manifest.json').read_text())
    if (report / 'artifacts.tar.xz').stat().st_size != original['archive']['bytes']:
        raise ValueError('captured original preparation archive size differs')
    actual = {}
    with tarfile.open(report / 'artifacts.tar.xz', 'r:xz') as source:
        for member in source:
            if not safe_member(member) or member.name in actual:
                raise ValueError('unsafe or duplicate original preparation member')
            with source.extractfile(member) as contents:
                actual[member.name] = hashlib.file_digest(contents, 'sha256').hexdigest()
    if len(actual) != 1111 or actual != original['files']:
        raise ValueError('captured original preparation member inventory differs')
    return dict(sha256=original['archive']['sha256'], bytes=original['archive']['bytes'],
                verified_members=len(actual), compiler_basis='43322a25b23e7c1d110378793247f984d2043d21',
                separate_metadata_correction='7bd327f')


def write_archive(archive, files):
    with tarfile.open(archive, 'w:xz', preset=6) as target:
        for name, path in files.items():
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = path.stat().st_size, path.stat().st_mode & 0o777, 0
            with path.open('rb') as contents:
                target.addfile(info, contents)


def manifest(archive, files, original):
    members = {name: dict(sha256=digest(path), bytes=path.stat().st_size, mode=path.stat().st_mode & 0o777)
               for name, path in files.items()}
    return dict(archive_sha256=digest(archive), bytes=archive.stat().st_size,
                regular_files=len(members), uncompressed_bytes=sum(row['bytes'] for row in members.values()), files=members,
                original_preparation=original,
                omitted='Expanded regenerable Cargo targets and Python caches are omitted; all original members remain in the intact preparation archive. External tools/libraries/boot files are identity-pinned in the plan, not bundled.',
                capture_assumption='Coordinated evidence inputs and directories have no competing writer or path replacement; this is a sequential captured snapshot, not a simultaneous filesystem snapshot.')


# ---- Full decompression and exact safe member inventory establish byte integrity ----

def safe_member(member):
    path = PurePosixPath(member.name)
    return (member.isfile() and bool(path.parts) and not path.is_absolute() and str(path) == member.name
            and '..' not in path.parts and '\\' not in member.name and ':' not in member.name)


def verify_archive(archive, expected):
    if digest(archive) != expected['archive_sha256'] or archive.stat().st_size != expected['bytes']:
        raise ValueError('compressed archive identity differs')
    actual = {}
    with tarfile.open(archive, 'r:xz') as source:
        for member in source:
            if not safe_member(member) or member.name in actual:
                raise ValueError('unsafe, duplicate or nonregular archive member')
            with source.extractfile(member) as contents:
                actual[member.name] = dict(sha256=hashlib.file_digest(contents, 'sha256').hexdigest(),
                                          bytes=member.size, mode=member.mode)
    if (actual != expected['files'] or len(actual) != expected['regular_files']
            or sum(row['bytes'] for row in actual.values()) != expected['uncompressed_bytes']):
        raise ValueError('archive member inventory differs')
    return dict(complete=True, regular_files=len(actual), archive_sha256=expected['archive_sha256'],
                scope='Archive and member byte integrity only; no semantic replay or guest execution.')


# ---- Exclusive publication preserves existing evidence and rejects partial bundles ----

def publish(directory):
    created = []
    try:
        for name in PUBLISHED:
            destination = REPORT / name
            target = destination.open('xb')
            created.append(destination)
            with target, (directory / name).open('rb') as source:
                shutil.copyfileobj(source, target)
    except BaseException:
        for path in reversed(created):
            path.unlink()
        raise


def prepare():
    if any((REPORT / name).exists() for name in PUBLISHED):
        raise ValueError('refusing to replace existing or partial published evidence')
    with tempfile.TemporaryDirectory(prefix='conform-evidence-') as temporary:
        directory = Path(temporary)
        files = capture(evidence_files(), directory)
        check_audited_snapshot(directory, files)
        original = check_original_preparation(directory)
        archive = directory / 'artifacts.tar.xz'
        write_archive(archive, files)
        expected = manifest(archive, files, original)
        checked = verify_archive(archive, expected)
        save(directory / 'manifest.json', expected)
        checked['manifest_sha256'] = digest(directory / 'manifest.json')
        save(directory / 'archive-verification.json', checked)
        publish(directory)


def verify():
    expected = json.loads((REPORT / 'manifest.json').read_text())
    recorded = json.loads((REPORT / 'archive-verification.json').read_text())
    checked = verify_archive(REPORT / 'artifacts.tar.xz', expected)
    checked['manifest_sha256'] = digest(REPORT / 'manifest.json')
    if recorded != checked:
        raise ValueError('published verification record differs')
    print('Verified', checked['regular_files'], 'safe regular files; byte integrity only, no guests started')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare', action='store_true')
    parser.add_argument('--test', action='store_true', help='check synthetic snapshot/archive/publication failures; no guests')
    options = parser.parse_args()
    if options.test:
        test_package_contract()
        return
    if options.prepare:
        prepare()
    verify()


# ---- Tests ----

def require_rejected(operation):
    try:
        operation()
    except (ValueError, FileExistsError):
        return
    raise AssertionError('accepted invalid archive or audited snapshot')


def test_audit_binding(directory):
    prefix = REPORT.relative_to(ROOT)
    campaign = prefix / 'measurements-attempt1'
    names = [prefix / name for name in ('timing-plan.json', 'coordination-before.json', 'coordination-after.json')]
    names += [campaign / 'campaign.json', *(campaign / f'sample-{index:02}.json' for index in range(56))]
    files = {}
    for name in names:
        path = directory / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(str(name))
        files[str(name)] = path
    audit = dict(complete=True, clean_processes=56, retained_processes=49,
                 audited_files={name: digest(path) for name, path in files.items()})
    audit_path = directory / prefix / 'independent-review.json'
    save(audit_path, audit)
    check_audited_snapshot(directory, files)
    files[str(names[-1])].write_text('changed after capture')
    require_rejected(lambda: check_audited_snapshot(directory, files))
    audit['audited_files'].pop(str(names[-1]))
    save(audit_path, audit)
    require_rejected(lambda: check_audited_snapshot(directory, files))


def test_safe_inventory(directory, expected):
    for index, names in enumerate((('../escape',), ('/absolute',), ('payload.txt', 'payload.txt'))):
        archive = directory / f'unsafe-{index}.tar.xz'
        with tarfile.open(archive, 'w:xz') as target:
            for name in names:
                member = tarfile.TarInfo(name)
                target.addfile(member)
        changed = dict(expected, archive_sha256=digest(archive), bytes=archive.stat().st_size)
        require_rejected(lambda: verify_archive(archive, changed))


def test_partial_publication(directory):
    global REPORT
    previous = REPORT
    REPORT = directory / 'published'
    REPORT.mkdir()
    staged = directory / 'publication-stage'
    staged.mkdir()
    for name in PUBLISHED:
        (staged / name).write_text('new bytes')
    (REPORT / 'manifest.json').write_text('preexisting bytes')
    try:
        require_rejected(lambda: publish(staged))
        if (REPORT / 'manifest.json').read_text() != 'preexisting bytes' or (REPORT / 'artifacts.tar.xz').exists():
            raise AssertionError('publication failure changed preexisting evidence or retained its new partial file')
        require_rejected(prepare)
    finally:
        REPORT = previous


def test_package_contract():
    with tempfile.TemporaryDirectory(prefix='conform-package-tests-') as temporary:
        directory = Path(temporary)
        source = directory / 'source.txt'
        source.write_text('captured bytes')
        snapshot = directory / 'snapshot'
        files = capture({'payload.txt': source}, snapshot)
        source.write_text('later live source bytes')
        if files['payload.txt'].read_text() != 'captured bytes':
            raise AssertionError('capture did not preserve its own source bytes')
        archive = directory / 'snapshot.tar.xz'
        write_archive(archive, files)
        expected = manifest(archive, files, {})
        before = (digest(archive), archive.stat().st_mtime_ns)
        verify_archive(archive, expected)
        if (digest(archive), archive.stat().st_mtime_ns) != before:
            raise AssertionError('verification wrote the archive')
        test_safe_inventory(directory, expected)
        archive.write_bytes(archive.read_bytes() + b'changed')
        require_rejected(lambda: verify_archive(archive, expected))
        symlink = snapshot / 'symlink'
        symlink.symlink_to(source)
        require_rejected(lambda: list(retained_files(snapshot)))
        test_audit_binding(directory / 'audit-fixture')
        test_partial_publication(directory)
    print('Validated snapshot mutation, audited-byte mismatch/missing last sample, safe inventory, read-only verification, changed archive, symlink rejection and partial publication cleanup; no guests')


if __name__ == '__main__':
    main()
