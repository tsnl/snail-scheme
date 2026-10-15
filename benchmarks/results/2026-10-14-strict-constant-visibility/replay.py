#!/usr/bin/env python3
"""Verify an extracted diagnostic archive and replay its three full-count checks."""

import argparse
import hashlib
import json
from pathlib import Path
import runpy
import sys


# ---- Frozen records ----


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def verify_snapshot(root, manifest):
    for relative, expected in manifest['files'].items():
        actual = hashlib.sha256((root / relative).read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError('archive identity changed: ' + relative)


def validate_output(record):
    if record['returncode'] != 0 or record['stderr'] or record['timeout']:
        raise ValueError('diagnostic process failed')
    value = json.loads(record['stdout'])
    if (record['stdout'].count('\n') != 1 or
            set(value) != {'seconds', 'result', 'barriers', 'setup_barriers'} or
            value['result'] != '1' or value['barriers'] != 200 or value['setup_barriers'] != 0):
        raise ValueError('full-count correctness or opacity contract failed')
    return value


# ---- Bounded functional replay, separate from clean timing ----


def replay_variant(root, output, variant, node, supervisor, runner):
    config = dict(argv=[node, str(root / 'inputs/host.mjs'), str(root / variant / 'strict.wasm'),
                       str(root / 'inputs/spec.json'), '--validate'], cwd=str(root), stdin=None)
    plan = dict(environment={'BINARYEN_CORES': '1'}, timeout_seconds=300, group_cleanup_seconds=10)
    record = dict(command=config['argv'], variant=variant, scope='full100 diagnostic; not a timing sample')
    path = output / (variant + '.json')
    try:
        runner['run_owned_process'](plan, config, record, path, supervisor)
        record.update(observation=validate_output(record), status='valid')
    finally:
        save(path, record)
    return record


def replay(root, output, manifest):
    verify_snapshot(root, manifest)
    output.mkdir(parents=True, exist_ok=False)
    sys.path.insert(0, str(root / 'supervisor'))
    import bv2string_port
    runner = runpy.run_path(str(root / 'supervisor/measure.py'), run_name='replay_supervision')
    node = json.loads((root / 'tools.json').read_text())['versions']['node']['argv'][0]
    records = [replay_variant(root, output, name, node, bv2string_port, runner)
               for name in ('baseline', 'scalar', 'readiness')]
    verify_snapshot(root, manifest)
    save(output / 'verification.json', dict(complete=True, verified_files=len(manifest['files']), samples=records))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, default=Path(__file__).with_name('manifest.json'))
    args = parser.parse_args()
    replay(args.root.resolve(), args.output.resolve(), json.loads(args.manifest.read_text()))
    print('Three relocated full-count checks passed; no clean timing campaign run')


if __name__ == '__main__':
    main()
