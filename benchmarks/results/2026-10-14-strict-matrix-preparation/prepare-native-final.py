#!/usr/bin/env python3
"""Freeze the native build's final inputs and validate its exact Wasm once on V8."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
PREPARATION = ROOT / 'build/matrix-attempt5'
CASE = PREPARATION / 'matrix'
FINAL = CASE / 'native-timing/native.native-r2n6qggl'
OUTPUT = ROOT / 'build/matrix-native-final-control-20261014'
sys.path.insert(0, str(PREPARATION))
import matrix_port


# ---- Freeze actual build products, preserving the initial preparation ----

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_text())


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def freeze_native_inputs():
    prepared, build = load(PREPARATION / 'prepared.json'), load(FINAL / 'build.json')
    files = {name: FINAL / name for name in ('optimized.wasm', 'optimized.wat', 'module.ll', 'provider-0.o', 'build.json')}
    for path in files.values():
        if digest(path) != prepared['cases'][0]['hashes'][str(path.relative_to(CASE))]:
            raise ValueError('prepared native-final file changed: ' + str(path))
    archive = ROOT / 'build/native-runtime/release/libsnail_runtime.a'
    if digest(archive) != build['sha256'][str(archive)]:
        raise ValueError('native Rust archive changed since the recorded build')
    files['libsnail_runtime.a'] = archive
    for name, path in files.items():
        shutil.copy2(path, OUTPUT / name)
    save(OUTPUT / 'identities.json', dict(files={name: dict(original=str(path), sha256=digest(path)) for name, path in files.items()},
         input_sha256=digest(CASE / 'strict.wasm'), final_sha256=digest(FINAL / 'optimized.wasm'),
         preparation_sha256=digest(PREPARATION / 'prepared.json'), native_rebuilt=False))


def validate_native_final():
    node = load(PREPARATION / 'prepared.json')['tools']['NODE']['path']
    command = [node, PREPARATION / 'host.mjs', FINAL / 'optimized.wasm', CASE / 'spec.json', '--validate']
    record = matrix_port.execute(command, CASE, dict(os.environ), timeout=300)
    record.update(cwd=str(CASE), timeout_seconds=300, purpose='full-count correctness only; not clean timing')
    save(OUTPUT / 'validation.json', record)
    if record.get('returncode') != 0 or record.get('stderr') or record.get('timeout') or record.get('executing_descendants'):
        raise ValueError('native-final V8 execution did not finish cleanly')
    result = json.loads(record['stdout'])
    if result['result'] != '1' or result['barriers'] != 5000 or result['setup_barriers'] != 0:
        raise ValueError('native-final V8 did not preserve the full result and opacity count')


# ---- The supplemental archive leaves all earlier evidence unchanged ----

def archive_control():
    report = REPORT / 'native-final-control'
    report.mkdir()
    files = {path.name: path for path in sorted(OUTPUT.iterdir()) if path.is_file()}
    archive = report / 'artifacts.tar.xz'
    with tarfile.open(archive, 'w:xz', preset=6) as target:
        for name, path in files.items():
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = path.stat().st_size, path.stat().st_mode & 0o777, 0
            with path.open('rb') as contents:
                target.addfile(info, contents)
    save(report / 'manifest.json', dict(archive_sha256=digest(archive), files={name: digest(path) for name, path in files.items()}))


def main():
    OUTPUT.mkdir(exist_ok=False)
    shutil.copy2(__file__, OUTPUT / 'prepare-native-final.py')
    freeze_native_inputs()
    validate_native_final()
    archive_control()
    print('Validated native-final Wasm on V8 at count 2500 with 5000 opacity calls; no rebuild')


if __name__ == '__main__':
    main()
