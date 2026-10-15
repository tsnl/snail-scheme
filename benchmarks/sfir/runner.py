#!/usr/bin/env python3
"""Freeze authored SFIR workloads and retain explicit target-validation evidence."""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time


# ---- Corpus and explicit configuration ----

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / 'benchmarks/sfir'
DEFAULT_COMPILE_TIMEOUT = 1200
COMPILER_ROOTS = ('src/', 'lib/', 'runtime/', 'scripts/')
COMPILER_FILES = ('Cargo.toml', 'Cargo.lock', 'rust-toolchain.toml', 'build.rs')
TOOLS = {'CHIBI': 'chibi-scheme', 'WASM_OPT': 'wasm-opt', 'WASM_AS': 'wasm-as',
         'NODE': 'node', 'CHEZ': 'scheme', 'RUSTC': 'rustc', 'CARGO': 'cargo',
         'CLANG': 'clang', 'LLD': 'ld.lld', 'WASM_MERGE': 'wasm-merge', 'PYTHON': 'python3'}


def load(path):
    return json.loads(Path(path).read_text())


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def positive_timeout(value):
    seconds = float(value)
    if isinstance(value, bool) or not math.isfinite(seconds) or seconds <= 0:
        raise ValueError('timeout must be positive and finite')
    return seconds


def relative_path(value):
    path = Path(value)
    if path.is_absolute() or '..' in path.parts or not path.parts:
        raise ValueError(f'expected a nonempty relative path: {value}')
    return path


def selected_cases(corpus, names):
    cases = {case['name']: case for case in corpus['cases']}
    names = list(cases) if names == ['all'] else names
    if len(names) != len(set(names)) or any(name not in cases for name in names):
        raise ValueError('choose distinct names from corpus.json')
    return [cases[name] for name in names]


# ---- Freeze files, never generate target language source ----

def tracked_files(root):
    result = subprocess.run(['git', '-C', str(root), 'ls-files', '-z'],
                            check=True, capture_output=True, timeout=10)
    return [Path(name) for name in result.stdout.decode().split('\0') if name]


def compiler_files(root):
    return [path for path in tracked_files(root)
            if (str(path).startswith(COMPILER_ROOTS) or str(path) in COMPILER_FILES)
            and (root / path).is_file()]


def corpus_files(root):
    return [path.relative_to(root) for path in sorted((root / 'benchmarks/sfir').rglob('*'))
            if path.is_file() and '__pycache__' not in path.parts]


def rust_files(root):
    return [path for path in tracked_files(root)
            if str(path).startswith('benchmarks/wasm-reference/')
            and (root / path).is_file()]


def copy_frozen_file(source_root, destination, relative):
    relative = relative_path(relative)
    source, target = source_root / relative, destination / relative
    if source.is_symlink() or not source.is_file():
        raise ValueError(f'freeze requires an ordinary source file: {source}')
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    return digest(target)


def freeze_files(root, destination, paths):
    return {str(path): copy_frozen_file(root, destination, path) for path in sorted(set(paths))}


def immutable_tools(environment):
    result = {}
    for variable, executable in TOOLS.items():
        found = shutil.which(environment.get(variable, executable))
        if found:
            # Preserve argv[0]: rustup dispatches by the cargo/rustc basename.
            path = Path(found).parent.resolve() / Path(found).name
            if not str(path).startswith('/nix/store/'):
                raise ValueError(f'{variable} must identify an immutable Nix tool: {path}')
            result[variable] = dict(path=str(path), sha256=digest(path),
                                    dispatcher=Path(found).resolve().name == 'rustup')
    return result


def verify_case_sources(root, case):
    source = root / 'benchmarks/sfir'
    provenance = load(source / case['provenance'])
    if digest(source / case['input']) != provenance['canonical_input_sha256']:
        raise ValueError(f'{case["name"]}: canonical input differs from its provenance')
    if case['source'] == 'present' and digest(source / case['sfir']) != provenance['sfir_sha256']:
        raise ValueError(f'{case["name"]}: SFIR source differs from its provenance')
    for name, expected in provenance['controls'].items():
        if digest(source / case['name'] / name) != expected:
            raise ValueError(f'{case["name"]}: external comparison source changed')


def canonical_data(root, destination, corpus):
    upstream = root / 'benchmarks/r7rs-benchmarks'
    revision = subprocess.check_output(['git', '-C', str(upstream), 'rev-parse', 'HEAD'], text=True, timeout=10).strip()
    changes = subprocess.check_output(['git', '-C', str(upstream), 'status', '--porcelain', '--untracked-files=no'], timeout=10)
    if revision != corpus['upstream_revision'] or changes:
        raise ValueError('benchmark input submodule must be clean at the corpus revision')
    paths = [path for path in tracked_files(upstream) if str(path).startswith('inputs/')]
    return freeze_files(upstream, destination, paths)


def prepare(root, destination, names, compile_timeout, run_timeout):
    corpus = load(root / 'benchmarks/sfir/corpus.json')
    cases = selected_cases(corpus, names)
    for case in corpus['cases']:
        verify_case_sources(root, case)
    if destination.exists() or destination == root or root in destination.parents:
        raise ValueError('preparation requires a fresh destination outside the source checkout')
    config = dict(compile_timeout=positive_timeout(compile_timeout), run_timeout=positive_timeout(run_timeout))
    destination.mkdir(parents=True)
    files = freeze_files(root, destination / 'source', compiler_files(root) + corpus_files(root) + rust_files(root))
    inputs = canonical_data(root, destination / 'data', corpus)
    manifest = dict(format=1, kind='sfir-preparation', config=config, files=files, inputs=inputs,
                    tools=immutable_tools(os.environ), cases=cases, measurement='not-measured')
    save(destination / 'manifest.json', manifest)
    return manifest


def verify_files(root, files):
    for name, expected in files.items():
        path = root / relative_path(name)
        if path.is_symlink() or not path.is_file() or digest(path) != expected:
            raise ValueError(f'frozen dependency changed: {path}')


def verify_preparation(directory):
    manifest = load(directory / 'manifest.json')
    for key in ('compile_timeout', 'run_timeout'):
        positive_timeout(manifest['config'][key])
    verify_files(directory / 'source', manifest['files'])
    verify_files(directory / 'data', manifest['inputs'])
    for tool in manifest['tools'].values():
        if digest(tool['path']) != tool['sha256']:
            raise ValueError(f'immutable tool changed: {tool["path"]}')
    return manifest


# ---- Bounded processes keep terminal diagnostics and drain descendants ----

def executing_group(group):
    members = []
    for path in Path('/proc').glob('[0-9]*/stat'):
        try:
            fields = path.read_text().rsplit(')', 1)[1].split()
            if int(fields[2]) == group and fields[0] not in ('Z', 'X'):
                members.append(int(path.parent.name))
        except (OSError, ValueError, IndexError):
            pass
    return members


def stop_group(group):
    deadline = time.monotonic() + 5
    while True:
        try:
            os.killpg(group, signal.SIGKILL)
        except ProcessLookupError:
            pass
        members = executing_group(group)
        if not members or time.monotonic() >= deadline:
            return members
        time.sleep(0.02)


def terminal_record(process, timeout, stdin):
    timed_out = False
    try:
        stdout, stderr = process.communicate(stdin, timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        stop_group(process.pid)
        stdout, stderr = process.communicate(timeout=5)
    descendants = executing_group(process.pid)
    remaining = stop_group(process.pid) if descendants else []
    return dict(returncode=process.returncode, stdout=stdout, stderr=stderr, timeout=timed_out,
                unexpected_descendants=descendants, executing_descendants=remaining)


def record(directory, label, command, environment, cwd, timeout, stdin=None):
    timeout = positive_timeout(timeout)
    folder = directory / 'commands' / relative_path(label)
    folder.mkdir(parents=True)
    result = dict(command=list(map(str, command)), cwd=str(cwd), timeout_seconds=timeout, status='started')
    save(folder / 'record.json', result)
    start = time.monotonic()
    try:
        process = subprocess.Popen(result['command'], cwd=cwd, env=environment, text=True,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        result.update(terminal_record(process, timeout, stdin), status='finished')
    except BaseException as error:
        if 'process' in locals():
            stop_group(process.pid)
        result.update(status='interrupted', exception=repr(error))
        raise
    finally:
        result['wall_seconds'] = time.monotonic() - start
        save(folder / 'record.json', result)
    return result


def succeeded(result):
    return (result.get('returncode') == 0 and not result.get('timeout')
            and not result.get('unexpected_descendants') and not result.get('executing_descendants'))


# ---- Target validation earns evidence; it cannot create timing coverage ----

def frozen_environment(manifest):
    environment = dict(os.environ)
    environment.update({name: tool['path'] for name, tool in manifest['tools'].items()})
    environment['PATH'] = os.pathsep.join(sorted({str(Path(tool['path']).parent) for tool in manifest['tools'].values()}))
    return environment


def case_directory(directory, case):
    target = directory / 'validation' / case['name']
    target.mkdir(parents=True)
    source = directory / 'source/benchmarks/sfir' / case['name']
    for name in ('input.txt', 'spec.json'):
        if (source / name).exists():
            shutil.copy2(source / name, target / name)
    shutil.copytree(directory / 'data/inputs', target / 'inputs')
    (target / 'outputs').mkdir()
    return source, target


def sfir_build(directory, case, source, target, manifest, environment):
    spec = load(source / 'spec.json')
    exports = [case['entry'], *spec.get('additional_exports', [])]
    command = [manifest['tools']['PYTHON']['path'], directory / 'source/scripts/build-sfir']
    command += [part for name in exports for part in ('--export', name)]
    command += [source / 'main.sfir', target / 'program.wasm']
    return record(target, 'sfir-build', command, environment, directory / 'source', manifest['config']['compile_timeout'])


def scalar_validation(directory, target, manifest, environment):
    command = [manifest['tools']['NODE']['path'], directory / 'source/benchmarks/sfir/support/scalar-host.mjs',
               target / 'program.wasm', target / 'spec.json', '--validate']
    result = record(target, 'sfir-wasm', command, environment, target, manifest['config']['run_timeout'])
    return 'passed' if succeeded(result) else 'failed'


def validate_case(directory, case, manifest, environment):
    status = dict(name=case['name'], source=case['source'], build='not-attempted', optimized='not-established',
                  wasm_validation='pending', native_validation='pending', chez_validation='pending',
                  rust_wasm_validation='pending', rust_native_validation='pending', measurement='not-measured')
    if case['source'] != 'present':
        return dict(status, unavailable='complete SFIR source has not been ported')
    source, target = case_directory(directory, case)
    if not (directory / 'source/scripts/build-sfir').exists():
        return dict(status, unavailable='frozen compiler lacks scripts/build-sfir')
    result = sfir_build(directory, case, source, target, manifest, environment)
    status['build'] = 'passed' if succeeded(result) else 'failed'
    if not succeeded(result):
        return status
    if not (target / 'program.wasm.raw.wasm').is_file():
        return dict(status, unavailable='build did not retain the mandatory raw/Binaryen artifact pair')
    status.update(optimized='passed', optimized_sha256=digest(target / 'program.wasm'),
                  raw_sha256=digest(target / 'program.wasm.raw.wasm'))
    if case['host'] == 'scalar' and case['name'] != 'fft':
        status['wasm_validation'] = scalar_validation(directory, target, manifest, environment)
    else:
        status['unavailable'] = f'{case["host"]} execution route has not been integrated'
    return status


def validate(directory):
    manifest = verify_preparation(directory)
    environment = frozen_environment(manifest)
    report = dict(kind='sfir-target-validation', performance_samples=False, cases=[])
    for case in manifest['cases']:
        verify_preparation(directory)
        report['cases'].append(validate_case(directory, case, manifest, environment))
        save(directory / 'validation.json', report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('inventory', 'prepare', 'verify', 'validate'))
    parser.add_argument('--output', type=Path)
    parser.add_argument('--benchmarks', nargs='+', default=['all'])
    parser.add_argument('--compile-timeout', type=positive_timeout, default=DEFAULT_COMPILE_TIMEOUT)
    parser.add_argument('--run-timeout', type=positive_timeout, default=1200)
    args = parser.parse_args()
    if args.action == 'inventory':
        print(json.dumps(selected_cases(load(CORPUS / 'corpus.json'), args.benchmarks), indent=2))
        return
    if args.output is None:
        parser.error('--output is required')
    directory = args.output.resolve()
    if args.action == 'prepare':
        prepare(ROOT, directory, args.benchmarks, args.compile_timeout, args.run_timeout)
    elif args.action == 'verify':
        verify_preparation(directory)
    else:
        report = validate(directory)
        print(json.dumps(report, indent=2))
        if any(case['wasm_validation'] != 'passed' for case in report['cases']):
            raise SystemExit(1)


# ---- Tests ----

import tempfile
import unittest


class FrozenInputTests(unittest.TestCase):
    def test_checkout_changes_do_not_change_snapshot_and_new_freeze_detects_change(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, snapshot = root / 'source', root / 'snapshot'
            source.mkdir()
            (source / 'main.sfir').write_text('(define answer 42)\nanswer\n')
            original = freeze_files(source, snapshot, [Path('main.sfir')])
            (source / 'main.sfir').write_text('(define answer 43)\nanswer\n')
            verify_files(snapshot, original)
            changed = freeze_files(source, root / 'next', [Path('main.sfir')])
            self.assertNotEqual(original, changed)
            (snapshot / 'main.sfir').write_text('changed frozen input')
            with self.assertRaisesRegex(ValueError, 'frozen dependency changed'):
                verify_files(snapshot, original)

    def test_symlink_dependency_and_escaping_paths_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'mutable').write_text('mutable')
            (root / 'alias').symlink_to(root / 'mutable')
            for name in ('alias', '../mutable', '/absolute'):
                with self.assertRaises(ValueError):
                    copy_frozen_file(root, root / 'frozen', name)

    def test_timeouts_are_positive_and_finite(self):
        for value in (0, -1, True, 'nan', 'inf', '-inf'):
            with self.assertRaises(ValueError):
                positive_timeout(value)
        self.assertEqual(positive_timeout('1800.5'), 1800.5)

    def test_timeout_records_failure_and_drains_child_group(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            code = 'import subprocess,time; subprocess.Popen(["sleep","30"]); print("started",flush=True); time.sleep(30)'
            result = record(root, 'timeout', [sys.executable, '-c', code], os.environ, root, 0.2)
            self.assertTrue(result['timeout'])
            self.assertIn('started', result['stdout'])
            self.assertEqual(result['executing_descendants'], [])
            self.assertFalse(succeeded(result))
            self.assertEqual(load(root / 'commands/timeout/record.json'), result)


if __name__ == '__main__':
    main()
