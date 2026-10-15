#!/usr/bin/env python3
"""Explicitly package Ackermann evidence, or verify its saved archive read-only."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys
import tarfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import review

REPORT = Path(__file__).resolve().parent


# ---- Measurement evidence; executable controls remain in their existing archive ----

def evidence_files(campaign, preparation):
    files = {'campaign/' + path.name: path for path in campaign.glob('*.json')}
    for name in ('measure.py', 'timing-plan.json'):
        files['preparation/' + name] = preparation / name
    for path in (preparation / 'supervisor').glob('*.py'):
        files['preparation/supervisor/' + path.name] = path
    for name in ('README.md', 'review.py', 'package.py', 'independent-review.json', 'coordination.json'):
        files['comparison/' + name] = REPORT / name
    return dict(sorted(files.items()))


def write_archive(files):
    archive = REPORT / 'artifacts.tar.xz'
    review.require(not archive.exists(), 'refusing to replace a recorded archive')
    with tarfile.open(archive, 'w:xz', preset=6) as target:
        for name, path in files.items():
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = path.stat().st_size, 0o644, 0
            with path.open('rb') as source:
                target.addfile(info, source)
    return archive


def prepare(campaign, preparation):
    checked = review.review(campaign, preparation, True)
    (REPORT / 'independent-review.json').write_text(json.dumps(checked, indent=2) + '\n')
    files = evidence_files(campaign, preparation)
    hashes = {name: review.digest(path) for name, path in files.items()}
    archive = write_archive(files)
    control = review.read(REPORT.parent / '2026-10-14-strict-ack-preparation/manifest.json')
    manifest = dict(archive_sha256=review.digest(archive), bytes=archive.stat().st_size, files=hashes,
                    executable_controls='../2026-10-14-strict-ack-preparation/',
                    executable_control_archive=control['archive'])
    (REPORT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


# ---- Verify the exact regular-member inventory without extraction or execution ----

def safe_member(member):
    path = PurePosixPath(member.name)
    return (member.isfile() and not path.is_absolute() and str(path) == member.name
            and '..' not in path.parts and '\\' not in member.name and ':' not in member.name)


def verify():
    manifest, archive = review.read(REPORT / 'manifest.json'), REPORT / 'artifacts.tar.xz'
    review.require(review.digest(archive) == manifest['archive_sha256'], 'archive digest differs')
    observed = {}
    with tarfile.open(archive, 'r:xz') as source:
        for member in source:
            review.require(safe_member(member) and member.name not in observed, 'invalid archive member')
            observed[member.name] = hashlib.sha256(source.extractfile(member).read()).hexdigest()
    review.require(observed == manifest['files'], 'archive members differ')
    print(f'Verified {len(observed)} regular members; no guests started')


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
