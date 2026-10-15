#!/usr/bin/env python3
"""Freeze or verify the existing complete Ackermann preparation."""

import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import tarfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SOURCE = ROOT / 'build/strict-ack-current-20261014'


# ---- The fixed preparation excludes only compiler caches ----

def digest(data):
    return hashlib.sha256(data).hexdigest()


def prepare():
    if (HERE / 'artifacts.tar.xz').exists():
        raise FileExistsError('preserve the existing archive; default mode verifies it')
    assert (SOURCE / 'prepared.json').is_file() and (SOURCE / 'ack-native').is_file()
    paths = sorted(path for path in SOURCE.rglob('*')
                   if path.is_file() and 'target' not in path.relative_to(SOURCE).parts)
    manifest = dict(source=str(SOURCE), files={})
    with tarfile.open(HERE / 'artifacts.tar.xz', 'w:xz', preset=6) as archive:
        for path in paths:
            name, data = str(path.relative_to(SOURCE)), path.read_bytes()
            member = tarfile.TarInfo(name)
            member.size, member.mode = len(data), 0o755 if path.stat().st_mode & 0o111 else 0o644
            archive.addfile(member, io.BytesIO(data))
            manifest['files'][name] = dict(bytes=len(data), sha256=digest(data))
    artifact = (HERE / 'artifacts.tar.xz').read_bytes()
    manifest['archive'] = dict(bytes=len(artifact), sha256=digest(artifact))
    (HERE / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


# ---- Verification reads each unique regular member without extraction ----

def verify():
    manifest = json.loads((HERE / 'manifest.json').read_text())
    artifact = (HERE / 'artifacts.tar.xz').read_bytes()
    assert manifest['archive'] == dict(bytes=len(artifact), sha256=digest(artifact))
    with tarfile.open(HERE / 'artifacts.tar.xz', 'r:xz') as archive:
        members = archive.getmembers()
        assert len(members) == len(manifest['files']) == len({member.name for member in members})
        for member in members:
            path = PurePosixPath(member.name)
            assert member.isfile() and not path.is_absolute() and '..' not in path.parts
            data = archive.extractfile(member).read()
            assert manifest['files'][member.name] == dict(bytes=len(data), sha256=digest(data))
    print(json.dumps(dict(verified_members=len(members), **manifest['archive'])))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare', action='store_true')
    if parser.parse_args().prepare:
        prepare()
    verify()
