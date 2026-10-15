#!/usr/bin/env python3
"""Freeze authored SFIR workloads and retain explicit target-validation evidence."""

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
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
TOOLS = {'CHIBI': 'chibi-scheme', 'WASM_OPT': 'wasm-opt', 'WASM_AS': 'wasm-as', 'WASM_DIS': 'wasm-dis',
         'NODE': 'node', 'CHEZ': 'scheme', 'RUSTC': 'rustc', 'CARGO': 'cargo',
         'CLANG': 'clang', 'LLD': 'ld.lld', 'WASM_MERGE': 'wasm-merge', 'PYTHON': 'python3',
         'TASKSET': 'taskset', 'LDD': 'ldd'}
RUNTIME_FEATURES = ['--mvp-features', '--enable-mutable-globals', '--enable-nontrapping-float-to-int',
                    '--enable-bulk-memory', '--enable-sign-ext', '--enable-reference-types',
                    '--enable-multivalue', '--enable-extended-const', '--enable-bulk-memory-opt',
                    '--enable-call-indirect-overlong']
EXECUTION_ENVIRONMENT = ('BINARYEN_CORES', 'RUSTUP_TOOLCHAIN', 'RUSTUP_HOME', 'CARGO_HOME',
                         'NODE_OPTIONS', 'NODE_V8_COVERAGE', 'LD_PRELOAD', 'SNAIL_NATIVE_GC_INTERVAL',
                         'SNAIL_GC_STATS', 'SNAIL_GC_HEAP_BYTES', 'SNAIL_GC_MIN_BYTES',
                         'RUSTFLAGS', 'CARGO_ENCODED_RUSTFLAGS', 'CARGO_BUILD_TARGET', 'CC', 'CXX',
                         'AR', 'LD_LIBRARY_PATH', 'LIBRARY_PATH', 'C_INCLUDE_PATH', 'CPATH',
                         'CHIBI_MODULE_PATH', 'SCHEMEHEAPDIRS', 'LANG', 'LC_ALL', 'TZ')


def load(path):
    return json.loads(Path(path).read_text())


def save(path, value):
    path = Path(path)
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


def digest(path):
    with Path(path).open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


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
                    tools=immutable_tools(os.environ), cases=cases, measurement='not-measured',
                    execution_environment={name: os.environ.get(name) for name in EXECUTION_ENVIRONMENT})
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
    verify_files(directory, manifest.get('build_dependencies', {}))
    for tool in manifest['tools'].values():
        if digest(tool['path']) != tool['sha256']:
            raise ValueError(f'immutable tool changed: {tool["path"]}')
    return manifest


def enter_frozen_driver(directory, action):
    manifest = verify_preparation(directory)
    driver = directory / 'source/benchmarks/sfir/runner.py'
    if Path(__file__).resolve() != driver.resolve():
        python = manifest['tools']['PYTHON']['path']
        os.execv(python, [python, str(driver), action, '--output', str(directory)])


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
    result['environment'] = {name: environment.get(name) for name in EXECUTION_ENVIRONMENT}
    save(folder / 'record.json', result)
    start = time.monotonic()
    try:
        process = subprocess.Popen(result['command'], cwd=cwd, env=environment, text=True,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        result.update(terminal_record(process, timeout, stdin), status='finished')
    except OSError as error:
        if 'process' in locals():
            stop_group(process.pid)
        result.update(status='failed-to-start', exception=repr(error))
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
    for name, value in manifest['execution_environment'].items():
        if value is None:
            environment.pop(name, None)
        else:
            environment[name] = value
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
    return source, target


def execution_directory(directory, target, route):
    working = target / 'runs' / route
    working.mkdir(parents=True)
    shutil.copy2(target / 'input.txt', working / 'input.txt')
    shutil.copytree(directory / 'data/inputs', working / 'inputs')
    (working / 'outputs').mkdir()
    return working


def workload_execution_directory(directory, source, target, route):
    working = execution_directory(directory, target, route)
    for name in load(source / 'spec.json').get('execution_files', []):
        path = relative_path(name)
        shutil.copy2(source / path, working / path)
    return working


def sfir_build(directory, case, source, target, manifest, environment):
    spec = load(source / 'spec.json')
    exports = [case['entry'], *spec.get('additional_exports', [])]
    command = [manifest['tools']['PYTHON']['path'], directory / 'source/scripts/build-sfir']
    command += [part for name in exports for part in ('--export', name)]
    command += [source / 'main.sfir', target / 'program.wasm']
    return record(target, 'sfir-build', command, environment, directory / 'source', manifest['config']['compile_timeout'])


def scalar_validation(directory, target, manifest, environment):
    if load(target / 'spec.json')['name'] == 'fft':
        fft_provider(directory, target, manifest, environment, True)
    command = [manifest['tools']['NODE']['path'], directory / 'source/benchmarks/sfir/support/scalar-host.mjs',
               target / 'program.wasm', target / 'spec.json', '--validate']
    working = execution_directory(directory, target, 'sfir-wasm')
    result = record(target, 'sfir-wasm', command, environment, working, manifest['config']['run_timeout'])
    return 'passed' if succeeded(result) else 'failed'


# ---- Concrete Rust scalar services leave the optimized SFIR module unchanged ----

def module_interface(path, target, label, manifest, environment):
    script = '''const fs=require('fs'), m=new WebAssembly.Module(fs.readFileSync(process.argv[1]));
      console.log(JSON.stringify({imports:WebAssembly.Module.imports(m),exports:WebAssembly.Module.exports(m)}));'''
    result = record(target, label, [manifest['tools']['NODE']['path'], '-e', script, path], environment,
                    target, manifest['config']['compile_timeout'])
    if not succeeded(result):
        raise RuntimeError(f'{label}: cannot inspect the Wasm interface')
    return json.loads(result['stdout'])


def select_runtime_exports(text, expected, keep):
    lines, selected, removed, found = text.splitlines(keepends=True), [], [], set()
    for index, line in enumerate(lines):
        match = re.fullmatch(r'\s*\(export "([^"]+)" \(.*\)\)\s*', line)
        if match:
            found.add(match[1])
        if match and match[1] not in keep:
            removed.append(dict(index=index, line=line))
        else:
            selected.append(line)
    restored = list(selected)
    for edit in removed:
        restored.insert(edit['index'], edit['line'])
    if found != expected or restored != lines or not keep <= found:
        raise ValueError('runtime export selection did not reverse exactly')
    return ''.join(selected), dict(removed=removed, complete_reverse_verified=True)


def build_wasm_runtime(directory, target, manifest, environment):
    command = [manifest['tools']['CARGO']['path'], 'rustc', '--crate-type=cdylib', '--quiet', '--offline',
               '--locked', '--release', '--target', 'wasm32-wasip1', '--manifest-path', directory / 'source/Cargo.toml',
               '--target-dir', directory / 'runtime-target']
    result = record(target, 'runtime-build', command, environment, directory / 'source', manifest['config']['compile_timeout'])
    if not succeeded(result):
        raise RuntimeError('Rust scalar runtime build failed')
    runtime = directory / 'runtime-target/wasm32-wasip1/release/snail_runtime.wasm'
    shutil.copy2(runtime, target / 'runtime.wasm')


def optimize_provider(target, manifest, environment, keep, names):
    tools, timeout = manifest['tools'], manifest['config']['compile_timeout']
    result = record(target, 'runtime-disassemble', [tools['WASM_DIS']['path'], target / 'runtime.wasm', '-o', target / 'runtime.wat'],
                    environment, target, timeout)
    if not succeeded(result):
        raise RuntimeError('Rust scalar runtime disassembly failed')
    text, edits = select_runtime_exports((target / 'runtime.wat').read_text(), names, keep)
    (target / 'provider.wat').write_text(text)
    save(target / 'provider-export-edits.json', edits)
    for label, command in provider_commands(target, tools):
        if not succeeded(record(target, label, command, environment, target, timeout)):
            raise RuntimeError(f'{label}: failed to construct the scalar provider')


def provider_commands(target, tools):
    return [('runtime-assemble', [tools['WASM_AS']['path'], *RUNTIME_FEATURES, target / 'provider.wat', '-o', target / 'provider.raw.wasm']),
            ('runtime-optimize', [tools['WASM_OPT']['path'], '-g', *RUNTIME_FEATURES, '--remove-unused-module-elements', '-O3',
                                  target / 'provider.raw.wasm', '-o', target / 'provider.wasm'])]


def runtime_provider(directory, target, manifest, environment):
    build_wasm_runtime(directory, target, manifest, environment)
    program = module_interface(target / 'program.wasm', target, 'program-interface', manifest, environment)
    provider = module_interface(target / 'runtime.wasm', target, 'runtime-interface', manifest, environment)
    required = {item['name'] for item in program['imports'] if item['module'] == 'snail.library'}
    keep = required | {'memory', '_initialize', 'snail:io/close-all', 'snail:report-error'}
    optimize_provider(target, manifest, environment, keep, {item['name'] for item in provider['exports']})
    check_runtime_provider(target, manifest, environment, required, keep)


def check_runtime_provider(target, manifest, environment, required, keep):
    final = module_interface(target / 'provider.wasm', target, 'provider-interface', manifest, environment)
    if any(item['module'] not in ('wasi_snapshot_preview1', 'snail.platform') for item in final['imports']):
        raise ValueError('scalar provider retained an unsupported runtime dependency')
    if {item['name'] for item in final['exports']} != keep:
        raise ValueError('scalar provider export set changed')
    save(target / 'provider.json', dict(required=sorted(required), retained=sorted(keep), interface=final,
         program_sha256=digest(target / 'program.wasm'), runtime_sha256=digest(target / 'runtime.wasm'),
         provider_sha256=digest(target / 'provider.wasm')))


def datum_validation(directory, target, manifest, environment):
    runtime_provider(directory, target, manifest, environment)
    working = execution_directory(directory, target, 'sfir-wasm')
    command = [manifest['tools']['NODE']['path'], '--no-warnings', directory / 'source/benchmarks/sfir/support/reader-host.mjs',
               target / 'program.wasm', target / 'spec.json', target / 'provider.wasm']
    result = record(target, 'sfir-wasm', command, environment, working, manifest['config']['run_timeout'])
    return 'passed' if succeeded(result) else 'failed'


def specialized_validation(directory, case, target, manifest, environment):
    runtime_provider(directory, target, manifest, environment)
    working = execution_directory(directory, target, 'sfir-wasm')
    spec = dict(load(target / 'spec.json'), trace=True)
    save(target / 'wasm-spec.json', spec)
    command = [manifest['tools']['NODE']['path'], '--no-warnings',
               directory / f'source/benchmarks/sfir/support/{case["host"]}-host.mjs',
               target / 'program.wasm', target / 'wasm-spec.json', '--validate', target / 'provider.wasm']
    result = record(target, 'sfir-wasm', command, environment, working, manifest['config']['run_timeout'])
    source = directory / 'source/benchmarks/sfir' / case['name']
    return 'passed' if succeeded(result) and output_files_match(source, working, target, 'sfir-wasm') else 'failed'


def slatex_validation(directory, target, manifest, environment):
    runtime_provider(directory, target, manifest, environment)
    source = directory / 'source/benchmarks/sfir/slatex'
    working = execution_directory(directory, target, 'sfir-wasm')
    for name in ('lifecycle.json', 'output-manifest.json'):
        shutil.copy2(source / name, working / name)
    command = [manifest['tools']['NODE']['path'], '--no-warnings', source / 'verify.mjs',
               target / 'program.wasm', target / 'provider.wasm']
    result = record(target, 'sfir-wasm', command, environment, working, manifest['config']['run_timeout'])
    return 'passed' if succeeded(result) else 'failed'


def workload_validation(directory, case, target, manifest, environment):
    runtime_provider(directory, target, manifest, environment)
    source = directory / 'source/benchmarks/sfir' / case['name']
    working = workload_execution_directory(directory, source, target, 'sfir-wasm')
    command = [manifest['tools']['NODE']['path'], '--no-warnings', source / 'verify.mjs',
               target / 'program.wasm', target / 'provider.wasm']
    result = record(target, 'sfir-wasm', command, environment, working, manifest['config']['run_timeout'])
    return 'passed' if succeeded(result) else 'failed'


# ---- Compiler diagnostics include the initial fatal handler ----

def compiler_validation(directory, case, target, manifest, environment):
    status = workload_validation(directory, case, target, manifest, environment)
    if status != 'passed':
        return status
    source = directory / 'source/benchmarks/sfir/compiler'
    return compiler_fatal_validation(directory, source, target, manifest, environment, False)


def compiler_native_result(directory, source, target, manifest, environment, result):
    expected = (source / 'expected-observations.txt').read_text() + 'canonical2000 passed\n'
    if not succeeded(result) or result['stdout'] != expected:
        return 'failed'
    return compiler_fatal_validation(directory, source, target, manifest, environment, True)


def compiler_fatal_matches(result):
    diagnostic = '(#f "Internal error, no exception handler at this point" #f)\n'
    return (result.get('status') == 'finished' and result.get('returncode') == 1
            and not result.get('timeout') and not result.get('unexpected_descendants')
            and not result.get('executing_descendants') and result.get('stdout') == diagnostic
            and result.get('stderr', '').startswith('snail-sfir: benchmark primitive error\n')
            and 'fatal compiler handler returned' not in result.get('stderr', ''))


def compiler_fatal_validation(directory, source, target, manifest, environment, native):
    route = 'sfir-native-fatal' if native else 'sfir-wasm-fatal'
    working = workload_execution_directory(directory, source, target, route)
    command = ([target / 'program.native', 'fatal'] if native else
               [manifest['tools']['NODE']['path'], '--no-warnings', source / 'verify.mjs',
                target / 'program.wasm', target / 'provider.wasm', 'fatal'])
    result = record(target, route, command, environment, working, manifest['config']['run_timeout'])
    return 'passed' if compiler_fatal_matches(result) else 'failed'


# ---- Separate scalar sine and decimal-text interfaces preserve the workloads ----

def fft_provider(directory, target, manifest, environment, wasm):
    command = [manifest['tools']['RUSTC']['path'], '--edition=2024', '--crate-name=sfir_fft_math',
               '--crate-type=' + ('cdylib' if wasm else 'lib'), '-C', 'opt-level=3', '-C', 'lto=' + ('yes' if wasm else 'no'),
               '-C', 'codegen-units=1', '-C', 'panic=abort']
    if wasm:
        command += ['--target=wasm32-wasip1']
    else:
        command += ['--emit=obj']
    output = target / ('math-provider.wasm' if wasm else 'math-provider.o')
    command += [directory / 'source/benchmarks/sfir/support/fft-math.rs', '-o', output]
    result = record(target, 'math-' + ('wasm' if wasm else 'native') + '-build', command,
                    environment, target, manifest['config']['compile_timeout'])
    if not succeeded(result):
        raise RuntimeError('FFT scalar sine provider build failed')


def integer_validation(directory, source, target, manifest, environment, native):
    if native:
        built = integer_native_build(directory, source, target, manifest, environment)
        parity = native_build_status(target, built, load(target / 'status.json'))
        if parity != 'passed':
            return parity
    working = execution_directory(directory, target, 'sfir-native' if native else 'sfir-wasm')
    command = ([target / 'program.native', target / 'native-input.txt'] if native else
               [manifest['tools']['NODE']['path'], directory / 'source/benchmarks/sfir/support/integer-host.mjs',
                target / 'program.wasm', target / 'spec.json'])
    result = record(target, 'sfir-native' if native else 'sfir-wasm', command, environment, working, manifest['config']['run_timeout'])
    return 'passed' if succeeded(result) and result['stdout'] == load(source / 'spec.json')['output'] else 'failed'


def integer_native_build(directory, source, target, manifest, environment):
    support, spec = directory / 'source/benchmarks/sfir/support', load(source / 'spec.json')
    for name in ('integer-provider.h', 'integer-provider.c', 'integer-entry.c'):
        shutil.copy2(support / name, target / name)
    data = ' '.join(map(str, [spec['count'], *spec['inputs'], len(spec['expected'])]))
    (target / 'native-input.txt').write_text(data + '\n' + '\n'.join(spec['expected']) + '\n')
    command = [manifest['tools']['PYTHON']['path'], directory / 'source/scripts/build-native', '--wasm',
               '--entry-c', target / 'integer-entry.c', '--c-provider', 'benchmark', target / 'integer-provider.h',
               target / 'integer-provider.c', target / 'program.wasm.raw.wasm', target / 'program.native']
    return record(target, 'native-build', command, environment, target, manifest['config']['compile_timeout'])


# ---- Both targets must consume the same optimized guest program ----

def native_artifact_files(target):
    paths = [target / name for name in ('program.wasm.raw.wasm', 'program.wasm', 'program.native')]
    for attempt in sorted(target.glob('program.native.native-*')):
        paths += [attempt / name for name in ('optimized.wasm', 'module.ll', 'build.json', 'build.scm')]
    if any(path.is_symlink() for path in paths):
        raise ValueError('native build artifacts must be ordinary files')
    return {str(path.relative_to(target)): digest(path) for path in paths if path.is_file()}


def native_optimizer_output(target, files):
    attempts = list(target.glob('program.native.native-*'))
    if len(attempts) != 1 or not attempts[0].is_dir() or attempts[0].is_symlink():
        raise ValueError('native parity requires exactly one retained build attempt')
    attempt = attempts[0]
    if str((attempt / 'build.scm').relative_to(target)) not in files:
        raise ValueError('native parity requires the actual retained build configuration')
    evidence = load(attempt / 'build.json')
    paths = [target / 'program.wasm.raw.wasm', target / 'program.native', attempt / 'optimized.wasm', attempt / 'module.ll']
    for path in paths:
        if evidence['sha256'].get(str(path.resolve())) != files[str(path.relative_to(target))]:
            raise ValueError(f'native build evidence does not identify the retained artifact: {path}')
    return attempt / 'optimized.wasm'


def check_native_parity(target, expected, files):
    verify_files(target, {'program.wasm.raw.wasm': expected['raw_sha256'],
                          'program.wasm': expected['optimized_sha256']})
    optimized = native_optimizer_output(target, files)
    if optimized.read_bytes() != (target / 'program.wasm').read_bytes():
        raise ValueError('native optimized guest Wasm differs from the V8 program')


def native_build_status(target, built, expected):
    # One evidence transition preserves failed builds as well as rejected parity.
    report = dict(status='failed-parity' if succeeded(built) else 'failed-build', command=built['command'])
    try:
        report['files'] = native_artifact_files(target)
        if succeeded(built):
            check_native_parity(target, expected, report['files'])
            report['status'] = 'passed'
    except (OSError, ValueError, KeyError) as error:
        report['reason'] = str(error)
    save(target / 'native-parity.json', report)
    return report['status']


# ---- Concrete native benchmark configuration ----

def c_array(name, kind, values):
    values = values or [0]
    return f'static const {kind} {name}[] = {{' + ', '.join(map(str, values)) + '};\n'


def numeric_arrays(name, values):
    if any(not isinstance(value, (int, float)) for value in values):
        raise ValueError('native scalar host requires flat numeric inputs and expected values')
    if any(isinstance(value, float) and not math.isfinite(value) for value in values):
        raise ValueError('native scalar host requires finite numeric configuration')
    integers = [int(value) if isinstance(value, int) else 0 for value in values]
    if any(value < -(2 ** 63) or value >= 2 ** 63 for value in integers):
        raise ValueError('native scalar input is outside I64')
    return c_array(name + '_integers', 'int64_t', integers) + c_array(name + '_reals', 'double', [int(v) if isinstance(v, bool) else v for v in values])


def c_strings(name, values):
    return f'static const char *{name}[] = {{' + ', '.join(json.dumps(value) for value in values or ['']) + '};\n'


def native_configuration(spec):
    inputs = spec['inputs']
    vectors = [value if isinstance(value, list) else [] for value in inputs]
    expected = spec['expected'] if isinstance(spec['expected'], list) else [spec['expected']]
    header = '#ifndef BENCHMARK_CASE_CONFIG\n#define BENCHMARK_CASE_CONFIG\n#include <stdint.h>\n'
    header += numeric_arrays('input', [0 if isinstance(value, list) else value for value in inputs])
    header += numeric_arrays('vector', [value for vector in vectors for value in vector])
    header += numeric_arrays('expected', expected)
    header += c_array('vector_sizes', 'int64_t', list(map(len, vectors)))
    header += c_array('vector_offsets', 'int64_t', [sum(map(len, vectors[:index])) for index in range(len(vectors))])
    return header + native_expectations(spec, len(expected)) + native_diagnostics(spec) + native_paths(spec) + '#endif\n'


def native_paths(spec):
    paths = spec.get('pathnames', [spec['pathname']] if 'pathname' in spec else [])
    arity = 1 if spec['name'] == 'tail' else 0 if spec['name'] == 'ray' else -1
    text = c_array('path_characters', 'uint32_t', [ord(char) for path in paths for char in path])
    text += c_array('path_sizes', 'int64_t', list(map(len, paths)))
    text += c_array('path_offsets', 'int64_t', [sum(map(len, paths[:index])) for index in range(len(paths))])
    return text + f'#define PATH_ARGUMENTS {arity}\n'


def observation_repetitions(spec):
    basis = spec.get('observation_basis', 'canonical-count')
    if basis == 'whole-run':
        return 1
    if basis == 'canonical-count':
        return max(0, spec['count'])
    raise ValueError(f'unknown observation basis: {basis}')


def native_expectations(spec, expected_size):
    result = 1 if isinstance(spec['expected'], list) else spec['expected']
    floating = spec['name'] in ('fibfp', 'sumfp', 'fft')
    values = dict(configured_count=spec['count'], expected_size=expected_size,
                  expected_setup=spec.get('setup_barriers', -1),
                  expected_barriers=spec.get('barriers_per_iteration', spec.get('worker_barriers', 0)) * observation_repetitions(spec))
    reader = spec.get('runtime') == 'scalar-datum-reader'
    values.update(expected_setup_closed=1 if reader else -1,
                  expected_worker_closed=len(spec.get('pathnames', [])) * observation_repetitions(spec) if reader else -1)
    if spec.get('runtime') == 'scalar-io':
        values.update(expected_setup_closed=0, expected_worker_closed=(2 if spec['name'] == 'tail' else 1) * spec['count'])
    text = ''.join(f'static const int64_t {key} = {value};\n' for key, value in values.items())
    text += f'static const {"double" if floating else "int64_t"} expected_result = {result};\n'
    return (text + f'static const double expected_tolerance = {spec.get("tolerance", 0)};\n#define FLOAT_RESULT {int(floating)}\n'
            + f'#define CONFIGURED_COUNT {int("configured-count" in spec.get("additional_exports", []))}\n')


def native_diagnostics(spec):
    sizes = spec.get('diagnostic_sizes', [])
    return (c_strings('diagnostic_text', spec.get('diagnostic_text', []))
            + c_strings('diagnostic_prefix', [row[0] for row in sizes])
            + c_strings('diagnostic_suffix', [row[1] for row in sizes]))


def native_sources(directory, source, target):
    for name in ('scalar-provider.c', 'scalar-provider.h', 'scalar-entry.c'):
        shutil.copy2(directory / 'source/benchmarks/sfir/support' / name, target / name)
    (target / 'case-config.h').write_text(native_configuration(load(source / 'spec.json')))
    if source.name in ('slatex', 'dynamic', 'scheme', 'compiler'):
        shutil.copy2(source / 'native-entry.c', target / 'scalar-entry.c')


def native_validation(directory, source, target, manifest, environment):
    try:
        native_sources(directory, source, target)
    except ValueError as error:
        save(target / 'native-unavailable.json', dict(reason=str(error)))
        return 'unsupported-configuration'
    command = [manifest['tools']['PYTHON']['path'], directory / 'source/scripts/build-native', '--wasm',
               '--entry-c', target / 'scalar-entry.c', '--c-provider', 'benchmark',
               target / 'scalar-provider.h', target / 'scalar-provider.c', target / 'program.wasm.raw.wasm', target / 'program.native']
    if source.name == 'fft':
        fft_provider(directory, target, manifest, environment, False)
        command[2:2] = ['--c-provider', 'math', directory / 'source/benchmarks/sfir/support/fft-math.h', target / 'math-provider.o']
    built = record(target, 'native-build', command, environment, target, manifest['config']['compile_timeout'])
    parity = native_build_status(target, built, load(target / 'status.json'))
    if parity != 'passed':
        return parity
    return native_execution(directory, source, target, manifest, environment)


def native_execution(directory, source, target, manifest, environment):
    working = workload_execution_directory(directory, source, target, 'sfir-native')
    active = dict(environment)
    spec = load(source / 'spec.json')
    if 'native_heap_bytes' in spec:
        active['SNAIL_GC_HEAP_BYTES'] = str(spec['native_heap_bytes'])
    result = record(target, 'sfir-native', [target / 'program.native'], active, working, manifest['config']['run_timeout'])
    if source.name == 'compiler':
        return compiler_native_result(directory, source, target, manifest, environment, result)
    return 'passed' if succeeded(result) and output_files_match(source, working, target, 'sfir-native') else 'failed'


def output_files_match(source, working, target, route):
    if source.name == 'slatex':
        return numbered_outputs_match(source, working, target, route)
    if source.name not in ('cat', 'tail', 'ray'):
        return True
    spec = load(source / 'spec.json')
    path = spec['pathname'] if source.name == 'ray' else spec['pathnames'][1]
    expected = expected_file_digest(source.name, working, spec)
    observed = dict(path=path, actual=digest(working / path) if (working / path).is_file() else None, expected=expected)
    save(target / (route + '-outputs.json'), observed)
    return observed['actual'] == expected


def numbered_output_path(pattern, iteration):
    if isinstance(pattern, str):
        return relative_path(pattern)
    index = pattern['index_offset'] + pattern['index_step'] * iteration
    return relative_path(f'{pattern["prefix"]}{index}{pattern["suffix"]}')


def numbered_outputs_match(source, working, target, route):
    manifest = load(source / 'output-manifest.json')
    expected = {numbered_output_path(row['path'], iteration): row
                for iteration in range(manifest['iterations']) for row in manifest['files']}
    actual = {path.relative_to(working) for path in (working / 'outputs').rglob('*') if path.is_file()}
    bad = [str(path) for path, row in expected.items() if path not in actual
           or (working / path).stat().st_size != row['bytes'] or digest(working / path) != row['sha256']]
    passed = len(expected) == manifest['total_files'] and actual == set(expected) and not bad
    save(target / (route + '-outputs.json'), dict(passed=passed, expected_files=len(expected),
         actual_files=len(actual), mismatched=bad, extra=sorted(map(str, actual - set(expected)))))
    return passed


def expected_file_digest(name, working, spec):
    if name == 'ray':
        return spec['image_sha256']
    data = (working / spec['pathnames'][0]).read_bytes()
    if name == 'tail':
        if b'\r' in data:
            raise ValueError('canonical Tail byte oracle requires its pinned LF-only input')
        lines = data.split(b'\n')
        if lines[-1] == b'':
            lines.pop()
        data = b''.join(line + b'\n' for line in reversed(lines))
    return hashlib.sha256(data).hexdigest()


def compile_chez_control(source, target, manifest, environment, mode):
    program = source / f'chez-{mode}.scm'
    artifact = target / f'chez-{mode}.so'
    script = target / f'compile-chez-{mode}.scm'
    script.write_text('(import (chezscheme))\n(parameterize ((optimize-level 2)) (compile-program '
                      + json.dumps(str(program)) + ' ' + json.dumps(str(artifact)) + '))\n')
    return record(target, f'chez-{mode}-build', [manifest['tools']['CHEZ']['path'], '--script', script], environment, target, manifest['config']['compile_timeout'])


def chez_validation(directory, source, target, manifest, environment, mode):
    if not (source / f'chez-{mode}.scm').exists():
        return 'unavailable'
    built = compile_chez_control(source, target, manifest, environment, mode)
    if not succeeded(built):
        return 'failed-build'
    working = execution_directory(directory, target, f'chez-{mode}')
    result = record(target, f'chez-{mode}', [manifest['tools']['CHEZ']['path'], '--program', target / f'chez-{mode}.so'], environment,
                    working, manifest['config']['run_timeout'], (target / 'input.txt').read_text())
    passed = succeeded(result) and chez_result_matches(source, result['stdout'])
    return 'passed' if passed and output_files_match(source, working, target, f'chez-{mode}') else 'failed'


def chez_result_matches(source, output):
    if source.name in ('pi', 'chudnovsky'):
        return output == load(source / 'spec.json')['output']
    return '+!CSVLINE!+' in output and 'INCORRECT' not in output


def rust_validation(directory, case, target, manifest, environment, wasm):
    route = 'rust-wasm' if wasm else 'rust-native'
    artifact_root = directory / 'rust-target'
    command = [manifest['tools']['CARGO']['path'], 'build', '--offline', '--locked', '--release',
               '--manifest-path', directory / 'source/benchmarks/wasm-reference/Cargo.toml',
               '--target-dir', artifact_root, '--bin', case['name']]
    if wasm:
        command += ['--target', 'wasm32-wasip1']
    built = record(target, route + '-build', command, environment, directory / 'source', manifest['config']['compile_timeout'])
    return rust_execution(directory, case, target, manifest, environment, wasm) if succeeded(built) else 'failed-build'


def rust_execution(directory, case, target, manifest, environment, wasm):
    route = 'rust-wasm' if wasm else 'rust-native'
    binary = directory / 'rust-target' / ('wasm32-wasip1/release' if wasm else 'release') / (case['name'] + ('.wasm' if wasm else ''))
    command = ([manifest['tools']['NODE']['path'], '--no-warnings',
                directory / 'source/benchmarks/wasm-reference/run-wasi.mjs', binary] if wasm else [binary])
    working = execution_directory(directory, target, route)
    result = record(target, route, command, environment, working, manifest['config']['run_timeout'], (target / 'input.txt').read_text())
    save(target / (route + '-artifact.json'), dict(sha256=digest(binary), path=str(binary)))
    source = directory / 'source/benchmarks/sfir' / case['name']
    passed = succeeded(result) and '+!CSVLINE!+' in result['stdout'] and 'INCORRECT' not in result['stdout']
    return 'passed' if passed and output_files_match(source, working, target, route) else 'failed'


def rust_toolchain_evidence(directory, manifest, environment):
    for name, arguments in [('RUSTC', ['--version', '--verbose']), ('RUSTC', ['--print', 'sysroot']), ('CARGO', ['--version'])]:
        label = name.lower() + '-' + arguments[0].removeprefix('--')
        record(directory, label, [manifest['tools'][name]['path'], *arguments], environment,
               directory / 'source', manifest['config']['compile_timeout'])


def stage_result(target, status, key, value):
    status[key] = value
    save(target / 'status.json', status)


def sfir_artifacts(directory, case, source, target, manifest, environment, status):
    if not (directory / 'source/scripts/build-sfir').exists():
        stage_result(target, status, 'unavailable', 'frozen compiler lacks scripts/build-sfir')
        return False
    result = sfir_build(directory, case, source, target, manifest, environment)
    stage_result(target, status, 'build', 'passed' if succeeded(result) else 'failed')
    if not succeeded(result):
        return False
    if not (target / 'program.wasm.raw.wasm').is_file():
        stage_result(target, status, 'unavailable', 'build did not retain the mandatory raw/Binaryen artifact pair')
        return False
    status.update(optimized='passed', optimized_sha256=digest(target / 'program.wasm'),
                  raw_sha256=digest(target / 'program.wasm.raw.wasm'))
    save(target / 'status.json', status)
    return True


def wasm_validation(directory, case, target, manifest, environment):
    try:
        if case['host'] == 'slatex':
            return slatex_validation(directory, target, manifest, environment)
        if case['host'] == 'compiler':
            return compiler_validation(directory, case, target, manifest, environment)
        if case['host'] in ('dynamic', 'scheme'):
            return workload_validation(directory, case, target, manifest, environment)
        if case['host'] == 'datum-io':
            return datum_validation(directory, target, manifest, environment)
        if case['host'] in ('tail', 'ray', 'nucleic'):
            return specialized_validation(directory, case, target, manifest, environment)
        if case['host'] == 'integer':
            source = directory / 'source/benchmarks/sfir' / case['name']
            return integer_validation(directory, source, target, manifest, environment, False)
        return scalar_validation(directory, target, manifest, environment)
    except (OSError, RuntimeError, ValueError) as error:
        save(target / 'wasm-failure.json', dict(reason=str(error)))
        return 'failed'


def sfir_validation(directory, case, source, target, manifest, environment, status):
    if case['source'] != 'present':
        stage_result(target, status, 'unavailable', 'complete SFIR source has not been ported')
        return
    if not sfir_artifacts(directory, case, source, target, manifest, environment, status):
        return
    if case['host'] not in ('scalar', 'datum-io', 'tail', 'ray', 'nucleic', 'integer', 'slatex', 'dynamic', 'scheme', 'compiler'):
        stage_result(target, status, 'unavailable', f'{case["host"]} execution route has not been integrated')
        return
    stage_result(target, status, 'wasm_validation', wasm_validation(directory, case, target, manifest, environment))
    native = (integer_validation(directory, source, target, manifest, environment, True) if case['host'] == 'integer'
              else native_validation(directory, source, target, manifest, environment))
    stage_result(target, status, 'native_validation', native)


def comparison_validation(directory, case, source, target, manifest, environment, status):
    for mode in ('original', 'adapted'):
        key = 'chez_validation' if mode == 'original' else 'chez_adapted_validation'
        stage_result(target, status, key, chez_validation(directory, source, target, manifest, environment, mode))
    stage_result(target, status, 'rust_wasm_validation', rust_validation(directory, case, target, manifest, environment, True))
    stage_result(target, status, 'rust_native_validation', rust_validation(directory, case, target, manifest, environment, False))


def validate_case(directory, case, manifest, environment):
    status = dict(name=case['name'], source=case['source'], build='not-attempted', optimized='not-established',
                  wasm_validation='pending', native_validation='pending', chez_validation='pending',
                  rust_wasm_validation='pending', rust_native_validation='pending', measurement='not-measured',
                  adapted_control_required=case.get('chez_adapted') is not None)
    source, target = case_directory(directory, case)
    try:
        sfir_validation(directory, case, source, target, manifest, environment, status)
    except (OSError, RuntimeError, ValueError) as error:
        stage_result(target, status, 'sfir_failure', str(error))
    comparison_validation(directory, case, source, target, manifest, environment, status)
    return status


def validate(directory):
    manifest = verify_preparation(directory)
    environment = frozen_environment(manifest)
    rust_toolchain_evidence(directory, manifest, environment)
    report = dict(kind='sfir-target-validation', performance_samples=False, cases=[])
    for case in manifest['cases']:
        verify_preparation(directory)
        report['cases'].append(validate_case(directory, case, manifest, environment))
        save(directory / 'validation.json', report)
    return report


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('inventory', 'prepare', 'verify', 'validate'))
    parser.add_argument('--output', type=Path)
    parser.add_argument('--benchmarks', nargs='+', default=['all'])
    parser.add_argument('--compile-timeout', type=positive_timeout, default=DEFAULT_COMPILE_TIMEOUT)
    parser.add_argument('--run-timeout', type=positive_timeout, default=1200)
    args = parser.parse_args()
    if args.action != 'inventory' and args.output is None:
        parser.error('--output is required')
    return args


def all_routes_passed(report):
    required = ('wasm_validation', 'native_validation', 'chez_validation', 'rust_wasm_validation', 'rust_native_validation')
    return all(all(case.get(key) == 'passed' for key in required)
               and (not case['adapted_control_required'] or case.get('chez_adapted_validation') == 'passed')
               for case in report['cases'])


def main():
    args = arguments()
    if args.action == 'inventory':
        print(json.dumps(selected_cases(load(CORPUS / 'corpus.json'), args.benchmarks), indent=2))
        return
    directory = args.output.resolve()
    if args.action in ('verify', 'validate'):
        enter_frozen_driver(directory, args.action)
    if args.action == 'prepare':
        prepare(ROOT, directory, args.benchmarks, args.compile_timeout, args.run_timeout)
    elif args.action == 'verify':
        verify_preparation(directory)
    else:
        report = validate(directory)
        print(json.dumps(report, indent=2))
        if not all_routes_passed(report):
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

    def test_native_configuration_rejects_values_outside_the_host_abi(self):
        for values in ([2 ** 63], [-(2 ** 63) - 1], [float('nan')], [[1, 2]], ['answer']):
            with self.assertRaises(ValueError):
                numeric_arrays('input', values)

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

    def test_execution_routes_cannot_reuse_an_earlier_output_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'data/inputs').mkdir(parents=True)
            (root / 'input.txt').write_text('canonical input')
            first = execution_directory(root, root, 'first')
            (first / 'outputs/stale').write_text('incorrect old answer')
            second = execution_directory(root, root, 'second')
            self.assertEqual(list((second / 'outputs').iterdir()), [])
            self.assertEqual((second / 'input.txt').read_text(), 'canonical input')
            with self.assertRaises(FileExistsError):
                execution_directory(root, root, 'first')

    def test_workload_fixtures_are_explicit_and_cannot_escape_the_case(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'case'
            source.mkdir()
            (root / 'data/inputs').mkdir(parents=True)
            (root / 'input.txt').write_text('canonical input')
            (source / 'probes.scm').write_text('semantic probes')
            (source / 'private.txt').write_text('undeclared fixture')
            save(source / 'spec.json', dict(execution_files=['probes.scm']))
            working = workload_execution_directory(root, source, root, 'valid')
            self.assertEqual((working / 'probes.scm').read_text(), 'semantic probes')
            self.assertFalse((working / 'private.txt').exists())
            for index, name in enumerate(('../private.txt', '/private.txt')):
                save(source / 'spec.json', dict(execution_files=[name]))
                with self.assertRaises(ValueError):
                    workload_execution_directory(root, source, root, f'invalid-{index}')

    def test_compiler_fatal_requires_expected_exit_and_diagnostic(self):
        result = dict(status='finished', returncode=1, timeout=False,
                      stdout='(#f "Internal error, no exception handler at this point" #f)\n',
                      stderr='snail-sfir: benchmark primitive error\n')
        self.assertTrue(compiler_fatal_matches(result))
        for change in (dict(returncode=0), dict(returncode=-11), dict(timeout=True), dict(stdout=''),
                       dict(stderr='unrelated failure'), dict(executing_descendants=[42]),
                       dict(stderr=result['stderr'] + 'fatal compiler handler returned')):
            self.assertFalse(compiler_fatal_matches(dict(result, **change)))

    def test_failed_adapted_control_prevents_complete_validation(self):
        case = dict(wasm_validation='passed', native_validation='passed', chez_validation='passed',
                    rust_wasm_validation='passed', rust_native_validation='passed',
                    adapted_control_required=True, chez_adapted_validation='failed-build')
        self.assertFalse(all_routes_passed(dict(cases=[case])))
        case['chez_adapted_validation'] = 'passed'
        self.assertTrue(all_routes_passed(dict(cases=[case])))

    def test_exited_parent_does_not_leave_a_child_holding_the_output_pipe(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            code = 'import subprocess; subprocess.Popen(["sleep","30"]); print("parent exited",flush=True)'
            result = record(root, 'orphan-pipe', [sys.executable, '-c', code], os.environ, root, 0.2)
            self.assertEqual(result['returncode'], 0)
            self.assertTrue(result['timeout'])
            self.assertEqual(result['executing_descendants'], [])
            self.assertFalse(succeeded(result))

    def test_provider_export_edit_is_exactly_reversible_and_requires_every_name(self):
        text = '(module\n (export "keep" (func $f))\n (export "drop" (func $f))\n)\n'
        selected, edits = select_runtime_exports(text, {'keep', 'drop'}, {'keep'})
        self.assertNotIn('"drop"', selected)
        self.assertTrue(edits['complete_reverse_verified'])
        with self.assertRaises(ValueError):
            select_runtime_exports(text, {'keep', 'drop'}, {'absent'})


class NumberedOutputTests(unittest.TestCase):
    def test_every_numbered_file_and_no_extra_path_is_required(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'outputs').mkdir()
            payload = b'canonical output\n'
            save(root / 'output-manifest.json', dict(iterations=2, total_files=2, files=[dict(
                path=dict(prefix='outputs/z', index_offset=3, index_step=57, suffix='.tex'),
                bytes=len(payload), sha256=hashlib.sha256(payload).hexdigest())]))
            for name in ('z3.tex', 'z60.tex'):
                (root / 'outputs' / name).write_bytes(payload)
            self.assertTrue(numbered_outputs_match(root, root, root, 'complete'))
            (root / 'outputs/z60.tex').write_bytes(b'incorrect output\n')
            self.assertFalse(numbered_outputs_match(root, root, root, 'changed'))
            (root / 'outputs/z60.tex').unlink()
            self.assertFalse(numbered_outputs_match(root, root, root, 'missing'))
            (root / 'outputs/z60.tex').write_bytes(payload)
            (root / 'outputs/z117.tex').write_bytes(payload)
            self.assertFalse(numbered_outputs_match(root, root, root, 'extra'))

    def test_number_collisions_cannot_reduce_the_expected_file_count(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'outputs').mkdir()
            (root / 'outputs/z0.tex').write_bytes(b'')
            save(root / 'output-manifest.json', dict(iterations=2, total_files=2, files=[dict(
                path=dict(prefix='outputs/z', index_offset=0, index_step=0, suffix='.tex'),
                bytes=0, sha256=hashlib.sha256(b'').hexdigest())]))
            self.assertFalse(numbered_outputs_match(root, root, root, 'collision'))


class NativeParityTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.target = Path(temporary.name)
        self.attempt = self.target / 'program.native.native-test'
        self.attempt.mkdir()
        for path, contents in ((self.target / 'program.wasm.raw.wasm', b'raw'), (self.target / 'program.wasm', b'optimized'),
                               (self.target / 'program.native', b'executable'), (self.attempt / 'optimized.wasm', b'optimized'),
                               (self.attempt / 'module.ll', b'LLVM'), (self.attempt / 'build.scm', b'configuration')):
            path.write_bytes(contents)
        self.expected = dict(raw_sha256=digest(self.target / 'program.wasm.raw.wasm'), optimized_sha256=digest(self.target / 'program.wasm'))
        self.built = dict(returncode=0, command=['native-builder', 'program.wasm.raw.wasm'])
        self.record_build_artifacts()

    def record_build_artifacts(self):
        paths = [self.target / 'program.wasm.raw.wasm', self.target / 'program.native',
                 self.attempt / 'optimized.wasm', self.attempt / 'module.ll']
        save(self.attempt / 'build.json', dict(sha256={str(path): digest(path) for path in paths}))

    def test_matching_native_program_records_exact_inputs_and_output(self):
        self.assertEqual(native_build_status(self.target, self.built, self.expected), 'passed')
        report = load(self.target / 'native-parity.json')
        self.assertEqual(report['files']['program.wasm'], report['files']['program.native.native-test/optimized.wasm'])
        self.assertEqual(report['files']['program.wasm.raw.wasm'], self.expected['raw_sha256'])
        verify_files(self.target, report['files'])

    def test_missing_raw_input_never_substitutes_the_optimized_program(self):
        (self.target / 'program.wasm.raw.wasm').unlink()
        self.assertEqual(native_build_status(self.target, self.built, self.expected), 'failed-parity')
        self.assertIn('program.wasm.raw.wasm', load(self.target / 'native-parity.json')['reason'])

    def test_successful_native_build_with_different_optimized_bytes_is_rejected(self):
        (self.attempt / 'optimized.wasm').write_bytes(b'optimized-again')
        self.record_build_artifacts()
        self.assertEqual(native_build_status(self.target, self.built, self.expected), 'failed-parity')
        self.assertIn('differs from the V8 program', load(self.target / 'native-parity.json')['reason'])

    def test_replaced_executable_or_multiple_builds_cannot_reuse_success_evidence(self):
        (self.target / 'program.native').write_bytes(b'replaced executable')
        self.assertEqual(native_build_status(self.target, self.built, self.expected), 'failed-parity')
        self.record_build_artifacts()
        (self.target / 'program.native.native-other').mkdir()
        self.assertEqual(native_build_status(self.target, self.built, self.expected), 'failed-parity')
        self.assertIn('exactly one', load(self.target / 'native-parity.json')['reason'])

    def test_failed_build_is_retained_even_if_old_matching_files_exist(self):
        self.built['returncode'] = 1
        self.assertEqual(native_build_status(self.target, self.built, self.expected), 'failed-build')
        self.assertIn('program.wasm.raw.wasm', load(self.target / 'native-parity.json')['files'])


if __name__ == '__main__':
    main()
