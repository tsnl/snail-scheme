#!/usr/bin/env python3
"""Repeat an intrusive heap-footprint diagnostic using verified frozen sources."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

REPORT = Path(__file__).resolve().parent
SOURCES = ('list-layout-probe.wat', 'list-layout-probe.wasm',
           'heap-layout-common.mjs', 'run-layout-node.mjs',
           'run-layout-chromium.mjs', 'browser-probe/heap.html')


# ---- Frozen inputs and tool identities ----

def verify(path, expected):
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise ValueError(f'identity mismatch: {path}')


def prepare(archive, output, reversed_order):
    manifest = json.loads((REPORT / 'manifest.json').read_text())['files']
    prefix = 'replicate/' if reversed_order else ''
    output.mkdir(parents=True, exist_ok=False)
    for name in SOURCES:
        source = archive / (prefix + name)
        verify(source, manifest[prefix + name])
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)


def checked_tool(archive, name):
    manifest = json.loads((REPORT / 'manifest.json').read_text())['files']
    source = archive / 'heap-layout-tools.json'
    verify(source, manifest[source.name])
    entry = json.loads(source.read_text())[name]
    verify(Path(entry['path']).resolve(), entry['sha256'])
    if 'executable' in entry:
        verify(Path(entry['executable']['path']), entry['executable']['sha256'])
    return entry['path']


# ---- One fresh engine process ----

def run(options):
    prepare(options.archive, options.output, options.reversed)
    node = checked_tool(options.archive, 'node')
    if options.engine == 'chromium':
        checked_tool(options.archive, 'chromium')
    flags = ['--expose-gc'] if options.engine == 'node' else []
    command = [node, *flags, str(options.output / f'run-layout-{options.engine}.mjs')]
    result = subprocess.run(command, capture_output=True, text=True, timeout=120)
    (options.output / 'process.json').write_text(json.dumps(dict(
        command=command, returncode=result.returncode,
        stdout=result.stdout, stderr=result.stderr), indent=2) + '\n')
    result.check_returncode()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('engine', choices=['node', 'chromium'])
    parser.add_argument('output', type=Path)
    parser.add_argument('--reversed', action='store_true')
    arguments = parser.parse_args()
    arguments.archive = arguments.archive.resolve()
    arguments.output = arguments.output.resolve()
    run(arguments)
