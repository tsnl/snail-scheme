#!/usr/bin/env python3
"""Freeze the experiment, verify every member, or replay its full result checks."""

import argparse
import hashlib
import json
from pathlib import Path
import runpy
import sys
import tarfile

REPORT = Path(__file__).resolve().parent
ROOT = REPORT.parents[2]
BUILD = ROOT / 'build/allocator-inline'


# ---- Exact artifacts and source variants ----


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def inputs():
    files = [path for path in BUILD.rglob('*') if path.is_file() and '__pycache__' not in path.parts]
    files += list(REPORT.glob('*.json')) + list(REPORT.glob('*-measurements/*.json'))
    files += [REPORT / name for name in ['measure.py', 'archive.py']]
    files += [ROOT / name for name in ['src/native.c', 'src/precise-gc.c', 'src/precise-gc.h',
              'tests/precise-gc.c', 'tests/immix-gc.c', 'scripts/test-native',
              'build/native-runtime/release/libsnail_runtime.a']]
    files += list((ROOT / 'build/native-tests').glob('results-*.json'))
    files += [ROOT / 'build/native-tests/source-hashes.json', ROOT / 'doc/native.md']
    return sorted(set(path for path in files if path.name != 'manifest.json'))


def pack():
    archive = REPORT / 'artifacts.tar.xz'
    if archive.exists() or (REPORT / 'manifest.json').exists():
        raise ValueError('refusing to replace an existing evidence archive')
    files = inputs()
    names = {path: 'files/' + str(path).lstrip('/') for path in files}
    identities = {names[path]: digest(path) for path in files}
    with tarfile.open(archive, 'w:xz', dereference=True) as output:
        for path in files:
            output.add(path, arcname=names[path], recursive=False)
    save(REPORT / 'manifest.json', dict(root=str(ROOT), files=identities,
         archive_sha256=digest(archive), archive_bytes=archive.stat().st_size))
    print('Packed', len(files), 'files;', archive.stat().st_size, 'bytes')


# ---- Verification before extraction ----


def verify(destination=None):
    manifest = json.loads((REPORT / 'manifest.json').read_text())
    archive = REPORT / 'artifacts.tar.xz'
    if digest(archive) != manifest['archive_sha256']:
        raise ValueError('archive identity changed')
    with tarfile.open(archive, 'r:xz') as stream:
        verify_members(stream, manifest['files'])
        if destination is not None:
            stream.extractall(destination, filter='data')
    return manifest


def verify_members(stream, expected):
    actual = {}
    for member in stream:
        if not member.isfile() or member.name in actual:
            raise ValueError('unexpected archive member: ' + member.name)
        actual[member.name] = hashlib.sha256(stream.extractfile(member).read()).hexdigest()
    if actual != expected:
        raise ValueError('archive members differ from the manifest')


# ---- Relocated correctness runs, never performance samples ----


def relocate(value, original, moved):
    if isinstance(value, str):
        return str(moved) + value[len(original):] if value.startswith(original + '/') else value
    if isinstance(value, list):
        return [relocate(item, original, moved) for item in value]
    if isinstance(value, dict):
        return {relocate(key, original, moved): relocate(item, original, moved) for key, item in value.items()}
    return value


def replay(destination):
    destination.mkdir(parents=True, exist_ok=False)
    manifest = verify(destination)
    moved = destination / 'files' / manifest['root'].lstrip('/')
    archived_report = moved / REPORT.relative_to(ROOT)
    runner = runpy.run_path(str(archived_report / 'measure.py'))
    state = dict(complete=False, archive_sha256=manifest['archive_sha256'], records=[])
    try:
        for name in ['matrix', 'bv2string']:
            original = json.loads((archived_report / (name + '-plan.json')).read_text())
            plan = relocate(original, manifest['root'], moved)
            replay_systems(name, plan, destination, runner, state)
        if verify() != manifest:
            raise ValueError('archive changed during replay')
        state['complete'] = True
    finally:
        save(destination / 'replay.json', state)


def replay_systems(name, plan, destination, runner, state):
    sys.path.insert(0, plan['preparation'])
    import bv2string_port
    for position, system in enumerate(plan['systems']):
        scheduled = dict(round=-2, position=position, system=system, retained=False)
        path = destination / (name + '-' + system + '.json')
        runner['sample'](plan, scheduled, path, bv2string_port)
        runner['verify'](plan)
        state['records'].append(path.name)
        print(name, system, 'full result valid', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pack', action='store_true')
    parser.add_argument('--replay', type=Path)
    options = parser.parse_args()
    if options.pack:
        pack()
    if options.replay is not None:
        replay(options.replay.resolve())
    else:
        print('Verified', len(verify()['files']), 'archive members')


if __name__ == '__main__':
    main()
