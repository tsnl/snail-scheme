#!/usr/bin/env python3
"""Archive every preparation attempt after verifying the authoritative freeze."""

import hashlib
import json
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
BUILD = ROOT / 'build'
PREPARATION = BUILD / 'matrix-attempt5'


# ---- The successful preparation must still match its original manifest ----

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_text())


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def verify_preparation():
    prepared = load(PREPARATION / 'prepared.json')
    case = prepared['cases'][0]
    if case['name'] != 'matrix' or case['status'] != 'ready':
        raise ValueError('authoritative Matrix preparation is not ready')
    for name, expected in case['hashes'].items():
        if digest(PREPARATION / 'matrix' / name) != expected:
            raise ValueError('prepared file changed: ' + name)
    for name, expected in prepared['compiler_files'].items():
        if digest(PREPARATION / 'compiler-source' / name) != expected:
            raise ValueError('frozen compiler file changed: ' + name)
    return prepared


def evidence_files():
    roots = [('prepared', PREPARATION), ('alias-audit', BUILD / 'matrix-alias-audit'),
             ('capabilities', BUILD / 'matrix-capabilities')]
    roots += [('attempts/' + path.name, path) for path in sorted(BUILD.glob('matrix-*-attempt*'))]
    roots += [('attempts/' + path.name, path) for path in sorted(BUILD.glob('matrix-attempt[1-4]'))]
    files = {'run-matrix-prepare.py': BUILD / 'run-matrix-prepare.py'}
    for prefix, root in roots:
        for path in sorted(root.rglob('*')):
            if path.is_file() and '__pycache__' not in path.parts:
                files[prefix + '/' + str(path.relative_to(root))] = path
    return files


def source_identities(prepared):
    case = PREPARATION / 'matrix'
    paths = {'upstream_source': case / 'upstream.scm', 'input': case / 'input.txt',
             'original_kernel': case / 'original-kernel.scm', 'adapted_kernel': case / 'adapted-kernel.scm',
             'adapter': PREPARATION / 'matrix_port.py', 'driver': PREPARATION / 'measure.py',
             'rust_source': case / 'rust-reference/src/bin/matrix.rs', 'preparation': PREPARATION / 'prepared.json'}
    return dict(compiler_commit=prepared['compiler_commit'], upstream_commit=prepared['upstream_commit'],
                files={name: dict(path=str(path), sha256=digest(path)) for name, path in paths.items()},
                canonical_counts=[1, 2, 2500], observation_checks=14 * 5, predicate_checks=12 * 5,
                bad_message_checks=5, chez_identity_checks=16 * 2, rust_result_checks=5 * 3,
                full_count_internal_trace=False)


# ---- Only regular entries make archive restoration unambiguous ----

def archive_files(files):
    archive = REPORT / 'artifacts.tar.xz'
    if archive.exists():
        raise ValueError('archive already exists; do not replace recorded evidence')
    with tarfile.open(archive, mode='w:xz', preset=6) as target:
        for name, path in files.items():
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = path.stat().st_size, path.stat().st_mode & 0o777, 0
            with path.open('rb') as contents:
                target.addfile(info, contents)
    return archive


def main():
    prepared, files = verify_preparation(), evidence_files()
    save(REPORT / 'source-identities.json', source_identities(prepared))
    hashes = {name: digest(path) for name, path in files.items()}
    archive = archive_files(files)
    save(REPORT / 'manifest.json', dict(archive_sha256=digest(archive), files=hashes))
    print('Archived', len(files), 'files;', archive.stat().st_size, 'bytes')


if __name__ == '__main__':
    main()
