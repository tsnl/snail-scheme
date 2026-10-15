#!/usr/bin/env python3
"""Preserve Matrix diagnostic evidence and verify relocated full-count checks."""

import argparse
from pathlib import Path
import shutil
import sys
import tarfile

import diagnose as d


# ---- A closed archive retains inputs, outputs and failed attempts ----


def pack(report):
    d.verify_inputs()
    extras = [d.OWNER / 'src/native.c', d.OWNER / 'src/precise-gc.c', d.OWNER / 'src/precise-gc.h',
              d.OWNER / 'src/snail-scheme/llvm.sld', d.CASE / 'native-timing/native-build.json',
              d.CASE / 'native-timing/native.native-r2n6qggl/reader.scm',
              d.CASE / 'native-timing/native.native-r2n6qggl/optimized.wat',
              d.CASE / 'native-timing/native.native-r2n6qggl/build.json']
    for path in extras:
        target = d.BUILD / 'inputs' / str(path).lstrip('/')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    files = sorted(path for path in d.BUILD.rglob('*') if path.is_file() and '__pycache__' not in path.parts)
    manifest = dict(files={'evidence/' + str(path.relative_to(d.BUILD)): d.identity(path)['sha256'] for path in files})
    archive = report / 'artifacts.tar.xz'
    d.require(not archive.exists(), 'refusing to overwrite evidence archive')
    with tarfile.open(archive, 'w:xz', preset=3) as output:
        for path in files:
            member = output.gettarinfo(path, 'evidence/' + str(path.relative_to(d.BUILD)))
            member.uid, member.gid, member.uname, member.gname, member.mtime = 0, 0, '', '', 0
            with path.open('rb') as source:
                output.addfile(member, source)
    plan = d.load(d.PLAN)
    external = {path: value for path, value in plan['identities'].items() if not path.startswith(str(d.OWNER) + '/')}
    for path in [d.PERF, Path(sys.executable), Path(shutil.which('llvm-nm')), Path(shutil.which('llvm-objdump'))]:
        external[str(path)] = d.identity(path)['sha256']
    manifest.update(archive_sha256=d.identity(archive)['sha256'], archive_bytes=archive.stat().st_size,
                    external_tools=external, clean_timing=False)
    d.save(report / 'manifest.json', manifest)
    print('Packed', len(files), 'regular files;', archive.stat().st_size, 'archive bytes', flush=True)


def verify_restored(root, manifest):
    for leaf, expected in manifest['files'].items():
        d.require(d.identity(root / leaf)['sha256'] == expected, 'restored file differs: ' + leaf)
    for path, expected in manifest['external_tools'].items():
        d.require(d.identity(path)['sha256'] == expected, 'external tool differs: ' + path)
    return len(manifest['files'])


def restore(report, root):
    manifest, archive = d.load(report / 'manifest.json'), report / 'artifacts.tar.xz'
    d.require(d.identity(archive)['sha256'] == manifest['archive_sha256'], 'archive hash differs')
    root.mkdir(exist_ok=False)
    with tarfile.open(archive) as source:
        members = source.getmembers()
        names = [member.name for member in members]
        d.require(len(names) == len(set(names)) and set(names) == set(manifest['files']), 'archive names differ')
        d.require(all(member.isfile() for member in members), 'archive includes nonregular entries')
        source.extractall(root, filter='data')
    return manifest, verify_restored(root, manifest)


# ---- Relocated execution checks correctness, never performance ----


def replay_guest(kind, report):
    plan, directory = d.load(d.PLAN), report / 'replay' / kind
    prefix = [plan['taskset'], '-c', str(plan['cpu'])]
    original_case = d.OWNER / 'build/matrix-attempt5/matrix'
    case = d.audited_path(original_case)
    if kind == 'v8':
        original = plan['systems']['strict-v8-native-final']['argv']
        command = [original[0], *[d.audited_path(path) for path in original[1:]]]
    else:
        original = plan['systems']['strict-native']['argv']
        binary = d.audited_path(original[0]) if kind == 'native' else d.BUILD / 'counter-sources-03/native-counter'
        command = [binary, original[1], d.audited_path(original[2])]
    environment = {'SNAIL_MATRIX_DIAGNOSTICS': str(directory / 'counts.json')} if kind == 'counters' else {}
    record = d.execute([*prefix, *command], directory, case, environment)
    d.validate_result(record, directory, native=kind != 'v8')
    d.require(not (directory / 'stderr.bin').read_bytes(), 'relocated guest wrote stderr')
    if kind == 'counters':
        d.require(d.load(directory / 'counts.json') == d.load(d.BUILD / 'native-counters-03/counts.json'), 'relocated counters differ')
    record.update(status='valid', relocated=True, profiler=False, clean_timing=False)
    d.save(directory / 'attempt.json', record)
    return dict(kind=kind, valid=True, full_count=2500, leader_reaped=record['cleanup']['leader_reaped'],
                live_members=record['cleanup']['live_members'])


def replay(report, root):
    manifest, count = restore(report, root)
    d.BUILD, d.SNAPSHOT_ROOT = root / 'evidence', root / 'evidence/inputs'
    d.PLAN, d.CASE = d.audited_path(d.PLAN), d.audited_path(d.CASE)
    (report / 'replay').mkdir(exist_ok=False)
    runs = [replay_guest(kind, report) for kind in ('v8', 'native', 'counters')]
    d.require(verify_restored(root, manifest) == count, 'restored verification changed')
    d.save(report / 'archive-verification.json', dict(valid=True, archive_sha256=manifest['archive_sha256'],
           regular_files=count, all_bytes_verified_before_and_after=True, relocated_root=str(root),
           full_count_correctness_replays=runs, clean_timing=False))
    print('Verified', count, 'files and three relocated full2500 correctness replays', flush=True)


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
