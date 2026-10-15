#!/usr/bin/env python3
"""Restore and verify the recorded strict-kernel artifacts without timing them."""

import argparse
import hashlib
import json
from pathlib import Path
import tarfile

REPORT = Path(__file__).resolve().parents[1] / 'results/2026-10-13-strict-kernels'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def restore(destination, report=REPORT):
    manifest = json.loads((report / 'manifest.json').read_text())
    archive = report / 'artifacts.tar.xz'
    if digest(archive) != manifest['archive_sha256']:
        raise ValueError('archive hash mismatch')
    destination.mkdir(parents=True, exist_ok=False)
    with tarfile.open(archive) as source:
        members = source.getmembers()
        names = [member.name for member in members]
        if len(names) != len(set(names)) or set(names) != set(manifest['files']):
            raise ValueError('archive entries differ from manifest')
        if not all(member.isfile() for member in members):
            raise ValueError('archive must contain only regular files')
        source.extractall(destination, filter='data')
    for name, expected in manifest['files'].items():
        if digest(destination / name) != expected:
            raise ValueError(f'file hash mismatch: {name}')
    print(f"Verified {len(manifest['files'])} files in {destination}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--report', type=Path, default=REPORT)
    options = parser.parse_args()
    restore(options.destination.resolve(), options.report.resolve())
