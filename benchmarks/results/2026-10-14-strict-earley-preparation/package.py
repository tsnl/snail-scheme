#!/usr/bin/env python3
"""Archive frozen preparation attempts, failures, successful controls and clocks."""

import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import tarfile

REPORT = Path(__file__).resolve().parent
ROOT = REPORT.parents[2]
sys.path.insert(0, str(ROOT / 'build/earley-prepare-04'))
import earley_port


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(name, value):
    (REPORT / name).write_text(json.dumps(value, indent=2) + '\n')


def main():
    names = ['earley-source-attempt01', 'earley-probe-02', 'earley-audit', 'earley-timing-prepare-01']
    names += [f'earley-prepare-{index:02}' for index in range(1, 5)]
    names += [f'earley-prepare-{index:02}-command.json' for index in range(1, 5)]
    members = {}
    for name in names:
        root = ROOT / 'build' / name
        paths = root.rglob('*') if root.is_dir() else [root]
        for path in paths:
            if path.is_file() and '__pycache__' not in path.parts and path.suffix != '.pyc':
                if path.is_symlink():
                    raise ValueError('archive must freeze bytes: ' + str(path))
                members[str(path.relative_to(ROOT))] = dict(sha256=digest(path), bytes=path.stat().st_size,
                                                          mode=stat.S_IMODE(path.stat().st_mode))
    archive = REPORT / 'artifacts.tar.xz'
    if archive.exists():
        raise ValueError('refusing to replace a frozen evidence archive')
    command = ['tar', '--sort=name', '--mtime=@0', '--owner=0', '--group=0', '--numeric-owner',
               '--exclude=__pycache__', '--exclude=*.pyc', '-I', 'xz -T1 -6', '-cf', str(archive),
               *['build/' + name for name in names]]
    record = earley_port.bounded_execute(command, ROOT, os.environ, timeout=180)
    save('package-command.json', record)
    if record.get('returncode') != 0 or record.get('error'):
        raise ValueError('packaging failed; raw command record retained')
    save('manifest.json', dict(archive=archive.name, sha256=digest(archive), bytes=archive.stat().st_size,
                              excluded=['__pycache__', '*.pyc'], members=members))
    seen = set()
    with tarfile.open(archive, 'r:xz') as packed:
        for member in packed:
            if member.isfile():
                expected = members[member.name]
                actual = hashlib.sha256(packed.extractfile(member).read()).hexdigest()
                if actual != expected['sha256'] or member.mode != expected['mode']:
                    raise ValueError('archive member differs: ' + member.name)
                seen.add(member.name)
            elif not member.isdir():
                raise ValueError('unexpected archive member kind: ' + member.name)
    if seen != set(members):
        raise ValueError('archive members differ from manifest')
    save('archive-verification.json', dict(complete=True, files=len(seen),
         uncompressed_bytes=sum(row['bytes'] for row in members.values()),
         archive_bytes=archive.stat().st_size, sha256=digest(archive), executable_modes_verified=True))
    print(f'Archived and verified {len(seen)} files, {archive.stat().st_size} compressed bytes')


if __name__ == '__main__':
    main()
