#!/usr/bin/env python3
"""Prepare current Maze timing artifacts and diagnostics without clean sampling."""

import argparse
import hashlib
import difflib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
PREPARED = ROOT/'build/maze-measurement-prepared-da8519f'
AUTHOR = Path('/tmp/snail-maze-preparation-20261014')
INTEGRATION = Path('/tmp/snail-general-specialization-20261012/build/maze-integration-review/current')
sys.path.insert(0, str(ROOT/'benchmarks/strict-suite'))
import measure as driver
import maze_port

spec = importlib.util.spec_from_file_location('maze_measurement', REPORT/'measure-seven.py')
measurement = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = measurement
spec.loader.exec_module(measurement)


# ---- Current source and reviewed reusable artifacts are identified before builds ----

def read(path):
    return json.loads(path.read_text())


def save(path, value):
    measurement.save(path, value)


def digest(path):
    return measurement.digest(path)


def retained(path):
    return {str(file.relative_to(path)): digest(file) for file in path.rglob('*') if file.is_file()}


def copy_reusable():
    PREPARED.mkdir(parents=True, exist_ok=False)
    metadata = read(AUTHOR/'prepared.json')
    for name, expected in metadata['artifacts'].items():
        measurement.require(digest(AUTHOR/name) == expected, 'author artifact changed: '+name)
    for name in ('raw.wasm', 'optimized.wasm', 'strict-native.wasm', 'strict-native.wasm.raw.wasm', 'runtime.wasm'):
        measurement.require(digest(AUTHOR/'maze'/name) == digest(INTEGRATION/name), 'author/current module differs: '+name)
    shutil.copytree(AUTHOR/'maze/controls/rust', PREPARED/'rust', ignore=shutil.ignore_patterns('target', '__pycache__'))
    shutil.copytree(INTEGRATION, PREPARED/'reviewed-integration')
    shutil.copy2(AUTHOR/'prepared.json', PREPARED/'author-prepared.json')
    shutil.copy2(AUTHOR/'author-audit.json', PREPARED/'author-audit.json')
    return metadata


def current_sources():
    directory = PREPARED/'maze'
    directory.mkdir()
    runner = driver.upstream_runner()
    files = runner.suite_sources()
    maze_port.write_sources(files, directory, runner, driver)
    spec = maze_port.write_input(directory, files['inputs/maze.input'], driver)
    names = ('upstream.scm', 'upstream-kernel.scm', 'adapted-kernel.scm', 'strict.scm', 'chez/program.scm')
    measurement.require(all((directory/name).read_bytes() == (AUTHOR/'maze'/name).read_bytes() for name in names), 'current source regeneration differs from reviewed author source')
    adapted = (directory/'adapted-kernel.scm').read_text()
    current, author = (directory/'chez-adapted/program.scm').read_text(), (AUTHOR/'maze/chez-adapted/program.scm').read_text()
    measurement.require(current.count(adapted) == author.count(adapted) == 1 and maze_port.chez_prelude() in current,
                        'adapted Chez must retain exact current prelude and shared kernel')
    (PREPARED/'current-chez-prelude.patch').write_text(''.join(difflib.unified_diff(author.splitlines(True),current.splitlines(True),fromfile='author-chez-adapted',tofile='current-chez-adapted')))
    save(PREPARED/'source-regeneration.json', dict(compiler_commit=measurement.BASIS, matched_author_files=list(names), hashes={name:digest(directory/name) for name in names},
        adapted_chez='Uses exact current CHEZ_TYPES including wrapping-word adapters and the identical concrete Maze definitions/kernel. Full source differs from the author only in this current prelude; retained patch records that difference. No Datum/read library bodies are injected.'))
    shutil.copy2(INTEGRATION/'runtime.wasm', directory/'runtime.wasm')
    shutil.copy2(ROOT/'benchmarks/strict-suite/reader-timing.mjs', PREPARED/'reader-timing.mjs')
    return runner, spec


def snapshot_current_source():
    directory = PREPARED/'compiler-source'
    directory.mkdir()
    paths = sorted([*ROOT.glob('src/**/*'), *ROOT.glob('scripts/**/*'), ROOT/'Cargo.toml', ROOT/'Cargo.lock', ROOT/'build.rs'])
    for source in paths:
        if source.is_file():
            target = directory/source.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    save(PREPARED/'source.json', dict(commit=measurement.BASIS, files=retained(directory),
        gc_basis='Current growing precise native collector at da8519f; source is frozen with this preparation.'))


# ---- Diagnostic commands own groups and byte files through actual terminal state ----

def command(label, arguments, environment, cwd=ROOT, stdin=None, timeout=1200):
    directory = PREPARED/'commands'/label
    directory.mkdir(parents=True, exist_ok=False)
    config = dict(command=list(map(str, arguments)), cwd=str(cwd), stdin=str(stdin) if stdin else None)
    record = dict(**config, status='starting', diagnostic_only=True, clean_sample=False,
                  environment={'BINARYEN_CORES':'1'}, inherited_environment={name:os.environ.get(name) for name in measurement.RECORDED_ENVIRONMENT})
    save(directory/'record.json', record)
    print(label, 'starting', flush=True)
    try:
        measurement.run_owned(config, environment, timeout, record, directory)
        measurement.capture_identities(directory, record)
        measurement.require(record['returncode'] == 0 and not record['timeout'] and not record['executing_descendants']
            and record['capture_complete'] and not (directory/'stderr.bin').read_bytes(), 'diagnostic command failed: '+label)
        record['status'] = 'valid'
    except BaseException as error:
        record.update(status='failed', error=repr(error))
        raise
    finally:
        measurement.capture_identities(directory, record)
        save(directory/'record.json', record)
    print(label, 'terminal', record['returncode'], flush=True)
    return directory


def compile_current_wasm(tools, environment):
    directory = PREPARED/'maze'
    command('strict-compile-current', [ROOT/'scripts/build-strict', '--export', 'bench', '--export', 'configured-count', directory/'strict.scm', directory/'strict-native.wasm'], environment)
    for raw in (True, False):
        target = directory/('raw.wasm' if raw else 'optimized.wasm')
        source = directory/('strict-native.wasm.raw.wasm' if raw else 'strict-native.wasm')
        options = ['--diagnostic-prune-only'] if raw else []
        command('raw-link-current' if raw else 'optimized-link-current', [ROOT/'scripts/link-strict-runtime', '--runtime', directory/'runtime.wasm', *options, source, target], environment)
    names = ('strict-native.wasm', 'strict-native.wasm.raw.wasm', 'raw.wasm', 'optimized.wasm')
    same = {name:digest(directory/name) == digest(INTEGRATION/name) for name in names}
    save(PREPARED/'current-wasm-comparison.json', dict(author_and_integration_bytes_identical=same, hashes={name:digest(directory/name) for name in names}))
    # Fresh current controls establish readiness when library signatures change
    # executable bytes. Historical correctness remains separate source evidence.


def current_native(tools, environment):
    directory = PREPARED/'native'
    directory.mkdir()
    for name in ('native-entry.c', 'native-provider.c', 'native-provider.h', 'provider.wasm'):
        shutil.copy2(AUTHOR/'maze/controls/native'/name, directory/name)
    for name in ('strict-native.wasm', 'input.txt', 'spec.json'):
        shutil.copy2(PREPARED/'maze'/name, directory/name)
    measurement.require('count++' not in (directory/'native-provider.c').read_text(), 'opacity counting remains enabled')
    command('native-current-counter-free-build', [ROOT/'scripts/build-native', '--wasm', '--c-provider', 'benchmark', directory/'native-provider.h', directory/'native-provider.c',
        '--entry-c', directory/'native-entry.c', directory/'strict-native.wasm', directory/'native'], environment)
    build, = directory.glob('native.native-*')
    shutil.copy2(build/'optimized.wasm', directory/'native-final.wasm')
    shutil.copy2(ROOT/'build/native-runtime/release/libsnail_runtime.a', PREPARED/'native-runtime.a')
    save(directory/'final-module.json', dict(native_final_sha256=digest(directory/'native-final.wasm'), input_sha256=digest(directory/'strict-native.wasm'),
        executable_sha256=digest(directory/'native'), current_gc_source_sha256=digest(ROOT/'src/precise-gc.c'), compiler_commit=measurement.BASIS))


def compile_chez(runner, tools, environment):
    for name in ('chez', 'chez-adapted'):
        directory = PREPARED/'maze'/name
        compile_command, _ = runner.chez_commands(directory, str(directory/'program.scm'))
        command(name+'-compile-current-source', compile_command, environment, directory)


# ---- Full result expectation is derived from canonical input, never observed output ----

def canonical_expectation(spec):
    tokens = maze_port.character_tokens(spec['expected_datum'])
    characters = [10 if token == r'#\newline' else 32 if token in (r'#\space', '#\\ ') else ord(token[2:]) for token in tokens]
    measurement.require(len(characters) == 668 and characters.count(10) == 42, 'canonical character expectation differs')
    rendered = ['#\\newline' if code == 10 else '#\\space' if code == 32 else '#\\'+chr(code) for code in characters]
    return dict(expected_characters=characters, expected_rust_output='Result: ('+' '.join(rendered)+')')


def configurations(tools):
    maze, native, rust = PREPARED/'maze', PREPARED/'native', PREPARED/'rust'
    node = [tools['NODE']['path'], '--disable-warning=ExperimentalWarning']
    systems = {
        'snail-production-v8': ([*node, PREPARED/'reader-timing.mjs', maze/'optimized.wasm', maze/'spec.json'], maze, None),
        'snail-native64': ([native/'native'], native, None),
        'snail-identical-wasm-v8': ([*node, PREPARED/'reader-timing.mjs', native/'native-final.wasm', native/'spec.json', native/'provider.wasm'], native, None),
        'chez': ([tools['CHEZ']['path'], '--program', maze/'chez/program.so'], maze, maze/'input.txt'),
        'chez-adapted': ([tools['CHEZ']['path'], '--program', maze/'chez-adapted/program.so'], maze, maze/'input.txt'),
        'rust-native': ([rust/'maze.native'], maze, maze/'input.txt'),
        'rust-optimized-wasm': ([*node, rust/'run-wasi.mjs', rust/'maze.wasm'], maze, maze/'input.txt'),
    }
    return {name:dict(command=[tools['TASKSET']['path'],'-c','5',*map(str,argv)], cwd=str(cwd), stdin=str(stdin) if stdin else None,
        dependencies=list(dict.fromkeys([str(Path(tools['TASKSET']['path'])), *[str(Path(item)) for item in argv if Path(item).is_file()], str(cwd/'input.txt'), *([str(stdin)] if stdin else [])])))
        for name,(argv,cwd,stdin) in systems.items()}


def validate_protocols(spec, tools, environment):
    configured = configurations(tools)
    expectation = canonical_expectation(spec)
    for system, config in configured.items():
        path = command('complete-frame-'+system, config['command'], environment, Path(config['cwd']), config['stdin'])
        output = (path/'stdout.bin').read_bytes()
        measurement.workload_seconds(expectation, system, output)
    save(PREPARED/'protocols.json', dict(complete_frames=7, diagnostic_only=True, expected_source='canonical input parsed independently', **expectation,
        configurations=configured, protocol_records={name:str(PREPARED/'commands'/('complete-frame-'+name)/'record.json') for name in configured}))


def current_predicate_controls(tools, environment):
    maze, native = PREPARED/'maze', PREPARED/'native'
    labels = {'once','twice','wrong-character','missing-character','extra-character','zero-false','zero-list','negative-false'}
    results = []
    for label, data, accepted in maze_port.fixtures((maze/'input.txt').read_bytes()):
        if label not in labels:
            continue
        target = PREPARED/'predicate-controls'/label
        spec = maze_port.write_input(target, data, driver, accepted)
        node = [tools['NODE']['path'],'--disable-warning=ExperimentalWarning',PREPARED/'reader-timing.mjs']
        commands = {'raw':[*node,maze/'raw.wasm',target/'spec.json'],
                    'optimized':[*node,maze/'optimized.wasm',target/'spec.json'], 'native':[native/'native']}
        for system, arguments in commands.items():
            path = command('predicate-'+label+'-'+system, arguments, environment, target)
            value = json.loads((path/'stdout.bin').read_bytes(), object_pairs_hook=measurement.distinct_fields)
            measurement.require(type(value['result']) is int and value['result'] == int(accepted), 'current predicate differs: '+label)
            if system == 'native':
                measurement.require(all(value[key] == amount for key,amount in dict(barriers=0,setup_closed=1,worker_closed=0,closed=1).items()), 'current native fixture lifetime differs')
            results.append(dict(label=label,system=system,accepted=accepted))
        path = command('predicate-'+label+'-chez-adapted', [tools['CHEZ']['path'],'--program',maze/'chez-adapted/program.so'], environment,target,target/'input.txt')
        maze_port.check_chez(dict(stdout=(path/'stdout.bin').read_text(),stderr=(path/'stderr.bin').read_text()),spec)
        results.append(dict(label=label,system='chez-adapted',accepted=accepted))
    save(PREPARED/'current-predicate-controls.json', dict(controls=results, total=len(results), diagnostic_only=True,
        scope='Fresh once/twice, wrong Unicode character, missing/extra tail and zero/negative-count predicates on current raw/optimized/native and exact current adapted Chez.'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resume-built-wasm', action='store_true')
    arguments = parser.parse_args()
    if arguments.resume_built_wasm:
        metadata = read(PREPARED/'author-prepared.json')
        runner, spec = driver.upstream_runner(), read(PREPARED/'maze/spec.json')
        expected = read(PREPARED/'current-wasm-comparison.json')['hashes']
        measurement.require(all(digest(PREPARED/'maze'/name) == value for name,value in expected.items()), 'retained fresh Wasm changed')
    else:
        metadata = copy_reusable()
        runner, spec = current_sources()
        snapshot_current_source()
    tools = metadata['tools']
    environment = {**os.environ, **{name:row['path'] for name,row in tools.items()}, 'BINARYEN_CORES':'1'}
    if not arguments.resume_built_wasm:
        compile_current_wasm(tools, environment)
    current_native(tools, environment)
    compile_chez(runner, tools, environment)
    validate_protocols(spec, tools, environment)
    current_predicate_controls(tools, environment)
    save(PREPARED/'prepared.json', dict(status='ready', clean_measurement_started=False, compiler_commit=measurement.BASIS,
        tools=tools, source_sha256=retained(PREPARED/'compiler-source'), artifacts=retained(PREPARED)))
    print('PASS current Maze source/Wasm/native/GC, two Chez sources and seven full frames; no clean schedule started', flush=True)


if __name__ == '__main__':
    main()
