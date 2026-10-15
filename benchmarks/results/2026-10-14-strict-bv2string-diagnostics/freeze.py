#!/usr/bin/env python3
"""Freeze all diagnostic inputs/attempts; restore and validate complete bytes."""

import argparse
from pathlib import Path
import sys
import tarfile

import diagnose as d


# ---- Closed regular-file archive with separate external tool identities ----


def pack(report):
    d.verify_inputs()
    files = sorted(path for path in d.BUILD.rglob('*') if path.is_file() and '__pycache__' not in path.parts)
    manifest = {'files': {'evidence/' + str(path.relative_to(d.BUILD)): d.identity(path)['sha256'] for path in files}}
    archive = report / 'artifacts.tar.xz'
    d.require(not archive.exists(), 'refusing to overwrite evidence archive')
    with tarfile.open(archive, 'w:xz', preset=3) as output:
        for path in files:
            name = 'evidence/' + str(path.relative_to(d.BUILD))
            member = output.gettarinfo(path, name)
            member.uid, member.gid, member.uname, member.gname, member.mtime = 0, 0, '', '', 0
            with path.open('rb') as source:
                output.addfile(member, source)
    plan = d.load(d.copied(d.PLAN))
    external = {path: value for path, value in plan['identities'].items() if not path.startswith(d.OWNER + '/')}
    external.update({str(Path(sys.executable)): d.identity(sys.executable)['sha256']})
    manifest.update(archive_sha256=d.identity(archive)['sha256'], archive_bytes=archive.stat().st_size,
                    external_tools=external, root='evidence', clean_timing=False)
    d.save(report / 'manifest.json', manifest)
    print('Packed', len(files), 'regular files;', archive.stat().st_size, 'archive bytes', flush=True)


def verify_restored(root, manifest):
    for leaf, expected in manifest['files'].items():
        d.require(d.identity(root / leaf)['sha256'] == expected, 'restored file changed: ' + leaf)
    for path, expected in manifest['external_tools'].items():
        d.require(d.identity(path)['sha256'] == expected, 'external tool changed: ' + path)
    return len(manifest['files'])


def restore(report, root):
    manifest = d.load(report / 'manifest.json')
    archive = report / 'artifacts.tar.xz'
    d.require(d.identity(archive)['sha256'] == manifest['archive_sha256'], 'archive hash differs')
    root.mkdir(exist_ok=False)
    with tarfile.open(archive) as source:
        members = source.getmembers()
        names = [member.name for member in members]
        d.require(len(names) == len(set(names)) and set(names) == set(manifest['files']), 'archive names differ')
        d.require(all(member.isfile() for member in members), 'archive includes nonregular entries')
        source.extractall(root, filter='data')
    return manifest, verify_restored(root, manifest)


# ---- Two actual relocated full-count checks, with no profiler ----


def replay_guest(kind, report, root):
    directory = report / 'replay' / kind
    directory.mkdir(parents=True, exist_ok=False)
    plan = d.load(d.copied(d.PLAN))
    host = d.copied(d.PREPARATION + '/host.mjs') if kind == 'original' else d.BUILD / 'counters-host.mjs'
    module = d.copied(d.CASE + '/strict.wasm') if kind == 'original' else d.BUILD / 'counters.wasm'
    command = [plan['taskset'], '-c', str(plan['cpu']), plan['systems']['strict-v8']['argv'][0],
               host, module, d.copied(d.CASE + '/spec.json'), '--diagnostics', directory]
    record = d.execute(command, directory)
    try:
        d.validate_snail(record)
        d.require(not record['stderr'], 'relocated guest wrote stderr')
        if kind == 'counters':
            d.require(d.load(directory / 'counts.json') == d.load(d.BUILD / 'counters/counts.json'), 'relocated counters differ')
        record.update(status='valid', relocated=True, profiler=False, archive=report.joinpath('manifest.json').as_posix())
    except BaseException as error:
        record['validation_error'] = repr(error)
        raise
    finally:
        d.save(directory / 'attempt.json', record)
    return dict(kind=kind, valid=True, full_count=100, group_live_members=record['cleanup']['live_members'])


def replay(report, root):
    manifest, count = restore(report, root)
    d.BUILD = root / 'evidence'
    runs = [replay_guest(kind, report, root) for kind in ('original', 'counters')]
    d.require(verify_restored(root, manifest) == count, 'restored archive verification changed')
    result = dict(valid=True, archive_sha256=manifest['archive_sha256'], archive_bytes=manifest['archive_bytes'],
                  regular_files=count, all_bytes_verified_before_and_after=True, relocated_root=str(root),
                  full_count_correctness_replays=runs, clean_timing=False)
    d.save(report / 'archive-verification.json', result)
    print('Verified', count, 'files and both relocated full100 correctness replays', flush=True)


# ---- Explicit command entry ----


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('pack', 'replay'))
    parser.add_argument('--report', type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument('--root', type=Path)
    options = parser.parse_args()
    if options.action == 'pack':
        pack(options.report.resolve())
    else:
        d.require(options.root is not None, 'replay requires a new --root')
        replay(options.report.resolve(), options.root.resolve())
