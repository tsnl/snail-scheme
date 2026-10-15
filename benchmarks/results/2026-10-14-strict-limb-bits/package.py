#!/usr/bin/env python3
"""Preserve audited bigint evidence, or verify the published archive read-only."""

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
TEMP = Path('/tmp')
PREPARED = TEMP / 'snail-limb-bits-production-comparison-20261014'
CLEAN = TEMP / 'snail-limb-bits-production-clean-20261014'
PROBE = TEMP / 'snail-integer-profiling-20261014/build/limb-bit-extraction'
PROBE_CLEAN = TEMP / 'snail-bigint-limb-bits-clean-20261014'
VALIDATION = TEMP / 'snail-strict-limb-bits-20261014/build/limb-bits-validation'
PUBLISHED = ('artifacts.tar.xz', 'manifest.json', 'archive-verification.json')


# ---- Capture the selected evidence once, excluding regenerable caches ----

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def retained_files(root):
    if not root.is_dir():
        raise ValueError('missing selected evidence directory: ' + str(root))
    for directory, children, names in os.walk(root):
        children[:] = sorted(name for name in children if name not in ('target', '__pycache__'))
        for name in sorted(names):
            path = Path(directory) / name
            if not path.is_file():
                raise ValueError('missing or nonregular selected evidence: ' + str(path))
            yield path


def evidence_files():
    roots = [PREPARED, CLEAN, PROBE, PROBE_CLEAN, VALIDATION,
             PROBE.parent / 'limb-bits-code-captures']
    files = {path.relative_to(TEMP).as_posix(): path for root in roots for path in retained_files(root)}
    plans = [(PREPARED / 'timing-plan.json', 'artifact_sha256'), (PROBE / 'timing-plan.json', 'identities')]
    for path, key in plans:
        for original in json.loads(path.read_text())[key]:
            dependency = Path(original)
            if dependency.is_relative_to(TEMP):
                files[dependency.relative_to(TEMP).as_posix()] = dependency
    for path in REPORT.iterdir():
        if path.is_file() and path.suffix in ('.py', '.md', '.json') and path.name not in PUBLISHED:
            files['report/' + path.name] = path
    return dict(sorted(files.items()))


def capture(files, directory):
    captured = {}
    for name, source in files.items():
        target = directory / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        captured[name] = target
    return captured


# ---- Bind the snapshot to the parent's semantic audit; never rerun guests ----

def captured_original(path, files):
    name = Path(path).relative_to(TEMP).as_posix()
    if name not in files:
        raise ValueError('missing audited local evidence: ' + name)
    return files[name]


def check_audited_snapshot(directory, files):
    audit = json.loads(captured_original(PREPARED / 'independent-review.json', files).read_text())
    if not audit['passed'] or audit['warmups'] != 12 or audit['retained'] != 144:
        raise ValueError('completed parent production audit required')
    required = [PREPARED / 'timing-plan.json', CLEAN / 'campaign.json']
    required += [CLEAN / f'sample-{index:03}.json' for index in range(156)]
    if not all(str(path) in audit['capture_sha256'] for path in required):
        raise ValueError('parent audit must bind the plan and all 156 raw records')
    for original, expected in audit['capture_sha256'].items():
        if Path(original).is_relative_to(TEMP) and digest(captured_original(original, files)) != expected:
            raise ValueError('captured production evidence differs from parent audit: ' + original)
    check_probe_snapshot(files)


def check_probe_snapshot(files):
    read = lambda path: json.loads(captured_original(path, files).read_text())
    audit, plan = read(PROBE_CLEAN / 'parent-independent-review.json'), read(PROBE / 'timing-plan.json')
    required = [(PROBE / 'timing-plan.json', audit['plan_sha256']),
                (PROBE_CLEAN / 'campaign.json', audit['campaign_sha256']),
                (PROBE / 'measure.py', audit['runner_sha256'])]
    if not audit['valid'] or audit['processes'] != 110 or audit['retained'] != 100:
        raise ValueError('completed parent instruction-ablation audit required')
    for original, expected in [*required, *plan['identities'].items()]:
        if Path(original).is_relative_to(TEMP) and digest(captured_original(original, files)) != expected:
            raise ValueError('captured instruction-ablation evidence differs: ' + str(original))
    campaign = read(PROBE_CLEAN / 'campaign.json')
    records = campaign['samples']
    if len(records) != 110:
        raise ValueError('expected 110 ablation records')
    for index, record in enumerate(records):
        if read(PROBE_CLEAN / f'sample-{index:03}.json') != record:
            raise ValueError('ablation raw record differs from audited campaign')


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
    with tempfile.TemporaryDirectory(prefix='limb-bits-evidence-') as temporary:
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
