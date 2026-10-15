#!/usr/bin/env python3
"""Preserve audited Equal evidence, or verify the published archive read-only."""

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
PREPARED = ROOT / 'build/equal-prepared-6fd5ca4'
PUBLISHED = ('artifacts.tar.xz', 'manifest.json', 'archive-verification.json')


# ---- Capture the selected evidence once, excluding regenerable caches ----

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def retained_files(root):
    for directory, children, names in os.walk(root):
        children[:] = sorted(name for name in children if name not in ('target', '__pycache__'))
        for name in sorted(names):
            path = Path(directory) / name
            if not path.is_file():
                raise ValueError('missing or nonregular selected evidence: ' + str(path))
            yield path


def evidence_files():
    roots = [PREPARED, ROOT / 'build/current-checks', *ROOT.glob('build/strict-reader-*')]
    files = [path for root in roots for path in retained_files(root)]
    files += [ROOT / 'build' / name for name in ('validate-current.py', 'audit-retention.py', 'equal-package-checks.json')]
    files += [path for path in REPORT.iterdir() if path.is_file() and path.suffix in ('.py', '.md', '.json')
              and path.name not in PUBLISHED]
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
    campaign = PREPARED.relative_to(ROOT) / 'clean-campaign'
    required = {str(REPORT.relative_to(ROOT) / 'timing-plan.json'), str(campaign / 'campaign.json')}
    required.update(str(campaign / f'sample-{index:02}.json') for index in range(56))
    if audit['complete'] is not True or audit['clean_processes'] != 56 or audit['retained_processes'] != 49:
        raise ValueError('completed independent audit of the frozen Equal schedule required')
    if not required.issubset(audit['audited_files']):
        raise ValueError('audit must bind the plan and every raw clean record')
    for name, expected in audit['audited_files'].items():
        if name not in files or digest(files[name]) != expected:
            raise ValueError('captured evidence differs from the independent audit: ' + name)


def write_archive(archive, files):
    with tarfile.open(archive, 'w:xz', preset=6) as target:
        for name, path in files.items():
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = path.stat().st_size, path.stat().st_mode & 0o777, 0
            with path.open('rb') as contents:
                target.addfile(info, contents)


def manifest(archive, files):
    members = {name: dict(sha256=digest(path), bytes=path.stat().st_size, mode=path.stat().st_mode & 0o777)
               for name, path in files.items()}
    return dict(archive_sha256=digest(archive), bytes=archive.stat().st_size,
                regular_files=len(members), uncompressed_bytes=sum(row['bytes'] for row in members.values()), files=members,
                omitted='Regenerable Cargo targets, Python bytecode caches and external tool binaries; frozen identities remain in the plan.')


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
    with tempfile.TemporaryDirectory(prefix='equal-evidence-') as temporary:
        directory = Path(temporary)
        files = capture(evidence_files(), directory)
        check_audited_snapshot(directory, files)
        archive = directory / 'artifacts.tar.xz'
        write_archive(archive, files)
        expected = manifest(archive, files)
        checked = verify_archive(archive, expected)
        save(directory / 'manifest.json', expected)
        save(directory / 'archive-verification.json', checked)
        publish(directory)


def verify():
    expected = json.loads((REPORT / 'manifest.json').read_text())
    recorded = json.loads((REPORT / 'archive-verification.json').read_text())
    checked = verify_archive(REPORT / 'artifacts.tar.xz', expected)
    if recorded != checked:
        raise ValueError('published verification record differs')
    print('Verified', checked['regular_files'], 'safe regular files; byte integrity only, no guests started')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare', action='store_true')
    options = parser.parse_args()
    if options.prepare:
        prepare()
    verify()


if __name__ == '__main__':
    main()
