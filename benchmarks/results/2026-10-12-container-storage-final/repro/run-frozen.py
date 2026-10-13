#!/usr/bin/env python3
"""Verify and restore frozen evidence; optionally replay one coordinated clean matrix."""
import argparse
import hashlib
import importlib.util
import json
import os
import re
import sys
import tarfile
from pathlib import Path

REPORT = Path(__file__).resolve().parent.parent
sys.dont_write_bytecode = True


# ---- Verify every blob before restoring logical files ----


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def restore(manifest, output):
    archive_path = REPORT/'artifacts.tar.xz'
    if digest(archive_path) != manifest['archive_sha256']:
        raise ValueError('archive checksum mismatch')
    directory = output/'blobs'
    directory.mkdir()
    seen = set()
    with tarfile.open(archive_path, 'r|xz') as archive:
        for member in archive:
            if not member.isfile() or not re.fullmatch(r'blobs/[0-9a-f]{64}', member.name):
                raise ValueError('unexpected archive member')
            checksum = member.name.split('/')[1]
            data = archive.extractfile(member).read()
            if hashlib.sha256(data).hexdigest() != checksum or checksum in seen:
                raise ValueError('blob checksum or uniqueness mismatch')
            path = directory/checksum
            path.write_bytes(data)
            path.chmod(0o444)
            seen.add(checksum)
    if seen != set(manifest['logical_files'].values()) or len(seen) != manifest['blob_count']:
        raise ValueError('manifest coverage mismatch')
    for name, checksum in manifest['logical_files'].items():
        relative = Path(name)
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('unsafe logical path')
        path = output/'files'/relative
        path.parent.mkdir(parents=True, exist_ok=True)
        os.link(directory/checksum, path)


# ---- Relocate reports without changing their original archived bytes ----


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def relocated(value, mappings):
    if isinstance(value, str):
        for old, new in sorted(mappings.items(), key=lambda item: -len(item[0])):
            if value.startswith(old):
                return new+value[len(old):]
        return value
    if isinstance(value, list):
        return [relocated(item, mappings) for item in value]
    if isinstance(value, dict):
        return {key: relocated(item, mappings) for key, item in value.items()}
    return value


def relocated_report(source, name, output, mappings):
    report = relocated(json.loads(source.read_text()), mappings)
    for case in report['cases']:
        (Path(case['directory'])/'outputs').mkdir(exist_ok=True)
    target = output/'reports'/(name+'.json')
    target.parent.mkdir(exist_ok=True)
    target.write_text(json.dumps(report, indent=2)+'\n')
    return target


def frozen_reports(output, manifest):
    files = output/'files'
    mappings = {old: str(files/new) for old, new in manifest['relocations'].items()}
    sources = {
        'baseline': files/'trees/baseline-five/build/pre-storage-five/results.json',
        'ordinary': files/'trees/ordinary/build/ordinary-five-prepared/results.json',
        'api': files/'trees/api-five/build/ordinary-five-prepared/results.json',
        'off': files/'trees/regression/build/storage-off-prepared/results.json',
        'split': files/'trees/regression/build/pair-reader-split-prepared/results.json',
    }
    return {name: relocated_report(path, name, output, mappings) for name, path in sources.items()}


def preflight(output, paths):
    files = output/'files'
    comparison = load('frozen_comparison', files/'trees/ordinary/build/compare-frozen.py')
    reports = {name: json.loads(path.read_text()) for name, path in paths.items()}
    for report in reports.values():
        comparison.validate_files(report)
    for label in ['ordinary', 'api']:
        comparison.check_comparable(reports['baseline'], reports[label])
    small = load('frozen_micro', files/'trees/ordinary/build/run-clean-micro.py')
    small.BASE = files/'trees/baseline'
    small.CONTROL_BASE = files/'trees/control-base'
    ordinary_cases = len(small.preflight()['modules'])
    os.environ['SNAIL_ORDINARY_MEASUREMENT_ROOT'] = str(files/'trees/ordinary')
    api = load('frozen_api', files/'trees/api/build/run-clean-api.py')
    api.micro.BASE, api.micro.CONTROL_BASE = small.BASE, small.CONTROL_BASE
    api_cells = len(api.preflight()['modules'])
    return comparison, small, api, {'ordinary_micro_cells': ordinary_cases, 'api_cells': api_cells,
                                   'frozen_full_workload_cases': sum(len(r['cases']) for r in reports.values()),
                                   'all_artifact_host_tool_source_checks': 'passed'}


# ---- Clean replays use writable output trees and immutable artifact links ----


def replay_tree(output, label):
    source = output/'files/trees'/label
    target = output/'replay'/label
    target.mkdir(parents=True, exist_ok=False)
    for name in ['scripts', 'src', 'benchmarks']:
        (target/name).symlink_to(source/name, target_is_directory=True)
    (target/'build').mkdir()
    for name in ['prepared', 'candidate-preparation.json', 'run-clean-micro.py', 'run-clean-api.py']:
        path = source/'build'/name
        if path.exists():
            (target/'build'/name).symlink_to(path, target_is_directory=path.is_dir())
    return target


def replay(choice, output, paths, comparison, micro, api):
    for key in ['NODE_OPTIONS', 'RUSTFLAGS']:
        os.environ.pop(key, None)
    if choice in ['final-five', 'ordinary-five']:
        candidate = paths['api' if choice == 'final-five' else 'ordinary']
        sys.argv = ['compare-frozen.py', str(paths['baseline']), str(candidate), '--cpu', '5',
                    '--rounds', '3', '--output', str(output/choice)]
        comparison.main()
    elif choice == 'micro':
        micro.ROOT = replay_tree(output, 'ordinary')
        frozen = json.loads((output/'files/trees/ordinary/build/clean-micro/results.json').read_text())
        micro.calibrate = lambda directory, report: frozen['configs']
        sys.argv = ['run-clean-micro.py', '--execute']
        micro.main()
    elif choice == 'api':
        api.ROOT, api.ORDINARY = replay_tree(output, 'api'), replay_tree(output, 'ordinary')
        (api.ORDINARY/'build/clean-micro').symlink_to(output/'files/trees/ordinary/build/clean-micro', target_is_directory=True)
        api.micro.ROOT = output/'files/trees/ordinary'
        sys.argv = ['run-clean-api.py', '--execute']
        api.main()
    else:
        original = output/'files/trees/regression/build/run-clean-regression.py'
        source = original.read_text().replace('/tmp/snail-container-ordinary-22c2006-20261012',
                                             str(output/'files/trees/ordinary'))
        wrapper = original.with_name('replay-regression.py')
        wrapper.write_text(source)
        regression = load('replay_regression', wrapper)
        regression.REPORTS = {name: paths[key] for name, key in [('baseline', 'baseline'), ('off', 'off'),
                                                             ('on', 'ordinary'), ('split', 'split')]}
        sys.argv = ['replay-regression.py', '--output', str(output/'regression-clean'), '--rounds', '3', '--cpu', '5']
        regression.main()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--run-clean', choices=['final-five', 'ordinary-five', 'micro', 'api', 'regression'])
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(exist_ok=False)
    manifest = json.loads((REPORT/'manifest.json').read_text())
    restore(manifest, output)
    paths = frozen_reports(output, manifest)
    comparison, micro, api, check = preflight(output, paths)
    check.update(all_blob_hashes_valid=True, blob_count=manifest['blob_count'],
                 logical_file_count=len(manifest['logical_files']), clean_timings_executed=False)
    (output/'restoration.json').write_text(json.dumps(check, indent=2)+'\n')
    print(json.dumps(check), flush=True)
    if args.run_clean:
        print('Reproduction quiet host must be coordinated separately by its operator.', flush=True)
        replay(args.run_clean, output, paths, comparison, micro, api)


if __name__ == '__main__':
    main()
