#!/usr/bin/env python3
"""Explicitly package Browse evidence, or verify its saved archive read-only."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import sys
import tarfile
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import review

REPORT = Path(__file__).resolve().parent


# ---- Timing evidence; executable controls remain in the preparation archive ----

def evidence_files(campaign, preparation, plan):
    files = {'campaign/' + path.name: path for path in campaign.glob('*.json')}
    for name in ('measure-seven.py', 'timing-plan.json'):
        files['preparation/' + name] = preparation / name
    for name in review.SUPERVISOR:
        files['preparation/supervisor/' + name + '.py'] = Path(plan['preparation']) / (name + '.py')
    for name in ('README.md', 'review.py', 'package.py', 'independent-review.json', 'coordination.json'):
        files['comparison/' + name] = REPORT / name
    return dict(sorted(files.items()))


def write_archive(files):
    archive = REPORT / 'artifacts.tar.xz'
    with tarfile.open(archive, 'w:xz', preset=6) as target:
        for name, path in files.items():
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = path.stat().st_size, 0o644, 0
            with path.open('rb') as source:
                target.addfile(info, source)
    return archive


def audit_live_inputs(campaign, preparation, plan):
    with tempfile.TemporaryDirectory(prefix='browse-audit-') as temporary:
        archived = Path(temporary)
        for name in ('measure-seven.py', 'timing-plan.json'):
            shutil.copyfile(preparation / name, archived / name)
        (archived / 'supervisor').mkdir()
        for name in review.SUPERVISOR:
            source = Path(plan['preparation']) / (name + '.py')
            shutil.copyfile(source, archived / 'supervisor' / source.name)
        return review.review(campaign, archived, True)


def prepare(campaign, preparation):
    review.require(not (REPORT / 'artifacts.tar.xz').exists(), 'refusing to replace a recorded archive')
    plan = review.read(preparation / 'timing-plan.json')
    checked = audit_live_inputs(campaign, preparation, plan)
    (REPORT / 'independent-review.json').write_text(json.dumps(checked, indent=2) + '\n')
    files = evidence_files(campaign, preparation, plan)
    hashes = {name: review.digest(path) for name, path in files.items()}
    archive = write_archive(files)
    controls = REPORT.parent / '2026-10-14-strict-browse-preparation'
    control = review.read(controls / 'manifest.json')
    review.require(review.digest(controls / 'artifacts.tar.xz') == control['archive_sha256'],
                   'existing executable control archive differs')
    manifest = dict(archive_sha256=review.digest(archive), bytes=archive.stat().st_size,
        regular_members=len(files), uncompressed_bytes=sum(path.stat().st_size for path in files.values()),
        files=hashes, executable_controls='../2026-10-14-strict-browse-preparation/',
        executable_control_archive=dict(sha256=control['archive_sha256'],
            bytes=(controls / 'artifacts.tar.xz').stat().st_size, regular_members=len(control['files'])))
    (REPORT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


# ---- Verify the exact safe regular-member inventory without extraction ----

def safe_member(member):
    path = PurePosixPath(member.name)
    return (member.isfile() and not path.is_absolute() and str(path) == member.name
            and '..' not in path.parts and '\\' not in member.name and ':' not in member.name)


def verify():
    manifest, archive = review.read(REPORT / 'manifest.json'), REPORT / 'artifacts.tar.xz'
    review.require(review.digest(archive) == manifest['archive_sha256']
                   and archive.stat().st_size == manifest['bytes'], 'archive identity differs')
    observed, size = {}, 0
    with tarfile.open(archive, 'r:xz') as source:
        for member in source:
            review.require(safe_member(member) and member.name not in observed, 'invalid archive member')
            with source.extractfile(member) as contents:
                observed[member.name] = hashlib.file_digest(contents, 'sha256').hexdigest()
            size += member.size
    review.require(observed == manifest['files'] and len(observed) == manifest['regular_members']
                   and size == manifest['uncompressed_bytes'], 'archive members differ')
    print(f'Verified {len(observed)} safe regular members; no guests started')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare', action='store_true')
    parser.add_argument('--campaign', type=Path)
    parser.add_argument('--preparation', type=Path)
    options = parser.parse_args()
    if options.prepare:
        if options.campaign is None or options.preparation is None:
            parser.error('--prepare requires --campaign and --preparation')
        prepare(options.campaign, options.preparation)
    verify()


if __name__ == '__main__':
    main()
