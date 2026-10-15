#!/usr/bin/env python3
"""Package a reviewed campaign, or verify its immutable saved evidence."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys
import tarfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import review

REPORT = Path(__file__).resolve().parent


# ---- Explicit evidence selection; executable controls remain in preparation ----

def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


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
    if archive.exists():
        raise ValueError('refusing to replace the recorded campaign archive')
    with tarfile.open(archive, 'w:xz', preset=6) as target:
        for name, path in files.items():
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = path.stat().st_size, 0o644, 0
            with path.open('rb') as source:
                target.addfile(info, source)
    return archive


def prepare(campaign, preparation):
    checked = review.review(campaign, preparation, True)
    save(REPORT / 'independent-review.json', checked)
    files = evidence_files(campaign, preparation)
    hashes = {name: review.digest(path) for name, path in files.items()}
    archive = write_archive(files)
    controls = review.read(REPORT.parent / '2026-10-14-strict-integer-controls/manifest.json')
    save(REPORT / 'manifest.json', dict(archive_sha256=review.digest(archive),
        bytes=archive.stat().st_size, files=hashes,
        executable_controls='../2026-10-14-strict-integer-controls/',
        executable_control_archives=controls['archives']))


# ---- Check every member without extracting or executing it ----

def verify():
    manifest, archive = review.read(REPORT / 'manifest.json'), REPORT / 'artifacts.tar.xz'
    review.require(review.digest(archive) == manifest['archive_sha256'], 'archive digest differs')
    observed = {}
    with tarfile.open(archive, 'r:xz') as source:
        for member in source:
            path = PurePosixPath(member.name)
            review.require(member.isfile() and member.name not in observed
                           and not path.is_absolute() and '..' not in path.parts, 'invalid archive member')
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
