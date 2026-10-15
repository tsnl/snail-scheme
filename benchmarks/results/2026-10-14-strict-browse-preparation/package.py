#!/usr/bin/env python3
"""Package the completed Browse evidence and verify every archived regular file."""

import hashlib
import json
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
CORE = ROOT / 'build/browse-attempt2'


# ---- Build caches are excluded; executable artifacts and failed logs remain ----

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def evidence_files():
    roots = [CORE, ROOT / 'build/browse-dev', ROOT / 'build/browse-probe-chez-initial', REPORT / 'retained-work']
    files = [path for root in roots for path in root.rglob('*') if path.is_file()
             and not {'target', '__pycache__'}.intersection(path.parts)]
    files += [ROOT / 'benchmarks/strict-suite' / name for name in
              ('browse_port.py', 'browse-observe.mjs', 'reader_ports.py', 'reader-timing.mjs',
               'reader-host.mjs', 'matrix_port.py', 'data_ports.py', 'measure.py')]
    files += [path for path in REPORT.iterdir() if path.is_file()
              and path.suffix in ('.py', '.md', '.json')
              and path.name not in ('manifest.json', 'archive-verification.json')]
    return {str(path.relative_to(ROOT)): path for path in sorted(set(files))}


def source_identities():
    names = ('upstream.scm', 'upstream-kernel.scm', 'adapted-kernel.scm', 'strict.scm',
             'input.txt', 'adaptation-ledger.json', 'complete-chez-edit-ledger.json',
             'source-map.tsv', 'reproduced.wat', 'chez/program.scm', 'chez-adapted/program.scm')
    save(REPORT / 'source-identities.json', dict(compiler_commit='15d2c64',
         upstream_commit='85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1',
         source_files={name: digest(CORE / name) for name in names}))


# ---- Deterministic members and a complete decompression/hash check ----

def write_archive(archive, files):
    with tarfile.open(archive, 'w:xz', preset=6) as target:
        for name, path in files.items():
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = path.stat().st_size, path.stat().st_mode & 0o777, 0
            with path.open('rb') as contents:
                target.addfile(info, contents)


def verify_archive(archive, expected):
    actual = {}
    with tarfile.open(archive, 'r:xz') as source:
        for member in source:
            if not member.isfile() or member.name in actual:
                raise ValueError('unexpected archive member')
            with source.extractfile(member) as contents:
                actual[member.name] = hashlib.file_digest(contents, 'sha256').hexdigest()
    if actual != expected:
        raise ValueError('archive member identity mismatch')
    return dict(regular_files=len(actual), complete=True, archive_sha256=digest(archive))


def main():
    archive = REPORT / 'artifacts.tar.xz'
    if archive.exists():
        raise ValueError('do not replace an existing preparation archive')
    source_identities()
    files = evidence_files()
    hashes = {name: digest(path) for name, path in files.items()}
    write_archive(archive, files)
    save(REPORT / 'manifest.json', dict(archive_sha256=digest(archive), files=hashes))
    save(REPORT / 'archive-verification.json', verify_archive(archive, hashes))
    print('Archived and verified', len(hashes), 'regular files;', archive.stat().st_size, 'compressed bytes')


if __name__ == '__main__':
    main()
