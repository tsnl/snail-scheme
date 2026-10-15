#!/usr/bin/env python3
"""Freeze verified Browse artifacts and their seven-system timing schedule."""

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
CORE = ROOT / 'build/browse-attempt2'
FROZEN = CORE / 'frozen'
SYSTEMS = ('strict-v8', 'strict-v8-native-module', 'strict-native',
           'chez-original', 'chez-adapted', 'rust-wasm', 'rust-native')
sys.path.insert(0, str(ROOT / 'benchmarks/strict-suite'))
import browse_port
import measure
import reader_ports


# ---- Reproduce generated sources before adopting the completed preparation ----

def load(path):
    return json.loads(path.read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_generated_sources():
    runner = measure.upstream_runner()
    files = runner.suite_sources()
    with tempfile.TemporaryDirectory(prefix='browse-sources-', dir=ROOT / 'build') as temporary:
        target = Path(temporary)
        browse_port.write_sources(files, target, runner, measure)
        for path in target.rglob('*'):
            if path.is_file() and path.read_bytes() != (CORE / path.relative_to(target)).read_bytes():
                raise ValueError('generated source changed: ' + str(path.relative_to(target)))
    verify_observer_sources(files['src/browse.scm'].decode())


def verify_observer_sources(source):
    if browse_port.strict_probe(source, ROOT, measure) != (CORE / 'observation/strict.scm').read_text():
        raise ValueError('observed strict source changed')
    for adapted, name in ((False, 'chez'), (True, 'chez-adapted')):
        if browse_port.chez_probe(source, ROOT, measure, adapted) != (CORE / f'observation/{name}.scm').read_text():
            raise ValueError('observed Chez source changed')
    tokens = lambda text: re.findall(r'"(?:[^"\\]|\\.)*"|;[^\n]*|[^\s()]+|[()]', text)
    if tokens(browse_port.datum_unit_program(ROOT)) != tokens((CORE / 'datum-tests/strict.scm').read_text()):
        raise ValueError('module tests changed beyond formatting')


def verify_correctness():
    for count in (1, 2, 2000):
        values = load(CORE / f'validation-{count}.json')['observations']
        if len(values) != 5 or any(not value.get('correct', value.get('result') == 1) for value in values.values()):
            raise ValueError('canonical correctness is incomplete')
    for path in (CORE / 'observation').glob('*/comparison.json'):
        comparisons = load(path)
        if len(comparisons) != 5 or len({value['sha256'] for value in comparisons.values()}) != 1:
            raise ValueError('ordered internal observations disagree')
        for system, value in comparisons.items():
            if digest(path.with_name(system + '.trace')) != value['sha256']:
                raise ValueError('recorded trace changed')
    browse_port.validate_trace_counts(CORE, measure)
    for label, data, expected in browse_port.fixtures((CORE / 'input.txt').read_bytes()):
        values = load(CORE / 'predicates' / label / 'validation.json')
        if len(values) != 5 or any(value.get('correct', value.get('result')) != expected for value in values.values()):
            raise ValueError('predicate or changed-input check failed: ' + label)
    if any(value['result'] != 42 for value in load(CORE / 'datum-tests/validation.json').values()):
        raise ValueError('datum module tests failed')


# ---- Retain sources, tool identities and runtime dependencies before timing ----

def retain_sources():
    FROZEN.mkdir(exist_ok=True)
    sources = [*ROOT.glob('src/**/*'), *ROOT.glob('benchmarks/strict-suite/*.py'),
               *ROOT.glob('benchmarks/strict-suite/*.mjs'), *ROOT.glob('scripts/build-*'),
               ROOT / 'scripts/link-strict-runtime', *ROOT.glob('tests/strict-reader/*'),
               *ROOT.glob('tests/strict-browse/*'), ROOT / 'tests/build-strict-program.scm',
               *(ROOT / name for name in ('Cargo.toml', 'Cargo.lock', 'rust-toolchain.toml', 'benchmarks/r7rs.py'))]
    for source in sources:
        if source.is_file():
            target = FROZEN / 'source' / source.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    for name in ('matrix_port.py', 'data_ports.py', 'reader-timing.mjs'):
        shutil.copy2(ROOT / 'benchmarks/strict-suite' / name, FROZEN / name)


def tools_from_records():
    paths = {name: record['path'] for name, record in load(CORE / 'controls/toolchain.json')['tools'].items()}
    paths.update(CHEZ=load(CORE / 'commands/count-2000-chez/record.json')['command'][0],
                 TASKSET=shutil.which('taskset'), PYTHON=sys.executable)
    return paths


def external_dependencies(tools):
    files = {Path(tools[name]) for name in ('NODE', 'CHEZ', 'TASKSET', 'PYTHON')}
    executables = [*sorted(files), CORE / 'controls/native/native', CORE / 'controls/rust/browse.native']
    for index, executable in enumerate(executables):
        log = CORE / f'commands/dependencies-{index}/record.json'
        run = load(log) if log.exists() else reader_ports.record(CORE, 'dependencies-' + str(index),
                          ['ldd', executable], dict(os.environ))
        files.update(Path(path) for path in re.findall(r'(/[^\s()]+)', run['stdout']) if Path(path).is_file())
    files.update(Path(tools['CHEZ']).resolve().parents[1].glob('lib/**/*.boot'))
    files.update(Path(module.__file__) for module in list(sys.modules.values())
                 if getattr(module, '__file__', None) and str(module.__file__).startswith('/nix/store/')
                 and Path(module.__file__).is_file())
    return files


def configuration(argv, cwd, stdin=None):
    return dict(argv=list(map(str, argv)), cwd=str(cwd), stdin=str(stdin) if stdin else None)


def systems(tools):
    native, rust = CORE / 'controls/native', CORE / 'controls/rust'
    node = [tools['NODE'], '--disable-warning=ExperimentalWarning']
    return {
        'strict-v8': configuration([*node, FROZEN / 'reader-timing.mjs', CORE / 'optimized.wasm', CORE / 'spec.json'], CORE),
        'strict-v8-native-module': configuration([*node, FROZEN / 'reader-timing.mjs', native / 'native-final.wasm',
                                                  native / 'spec.json', native / 'provider.wasm'], native),
        'strict-native': configuration([native / 'native'], native),
        'chez-original': configuration([tools['CHEZ'], '--program', CORE / 'chez/program.so'], CORE / 'chez', CORE / 'input.txt'),
        'chez-adapted': configuration([tools['CHEZ'], '--program', CORE / 'chez-adapted/program.so'], CORE / 'chez-adapted', CORE / 'input.txt'),
        'rust-wasm': configuration([*node, rust / 'run-wasi.mjs', rust / 'browse.wasm'], rust, CORE / 'input.txt'),
        'rust-native': configuration([rust / 'browse.native'], rust, CORE / 'input.txt'),
    }


def identity_files(tools):
    native, rust = CORE / 'controls/native', CORE / 'controls/rust'
    files = [CORE / name for name in ('strict.scm', 'upstream.scm', 'input.txt', 'spec.json', 'optimized.wasm',
             'raw.wasm', 'strict-native.wasm', 'runtime.wasm', 'chez/program.so', 'chez-adapted/program.so', 'prepared.json')]
    files += [native / name for name in ('native', 'native-final.wasm', 'provider.wasm', 'spec.json', 'input.txt',
              'native-provider.c', 'native-provider.h', 'native-entry.c')]
    files += [rust / name for name in ('browse.native', 'browse.wasm', 'run-wasi.mjs', 'src/bin/browse.rs', 'src/lib.rs')]
    files += [path for path in FROZEN.rglob('*') if path.is_file() and '__pycache__' not in path.parts]
    files += [REPORT / name for name in ('measure-seven.py', 'freeze-plan.py', 'retained-work.json')]
    return sorted(set(files) | external_dependencies(tools))


# ---- Fixed full-count rotation; validation records are never clean samples ----

def protocol_records():
    return {system: CORE / path / 'record.json' for system, path in [
        ('strict-v8', 'commands/final-timing-host-production'),
        ('strict-v8-native-module', 'commands/final-timing-host-native-module'),
        ('strict-native', 'controls/native/commands/full-count-validation'),
        ('chez-original', 'commands/count-2000-chez'), ('chez-adapted', 'commands/count-2000-chez-adapted'),
        ('rust-wasm', 'controls/rust/commands/count-2000-optimized-wasm'),
        ('rust-native', 'controls/rust/commands/count-2000-native')]}


def verify_protocols(runner, plan):
    paths = protocol_records()
    for system, path in paths.items():
        runner.workload_seconds(plan, dict(system=system, benchmark='browse'), load(path))
    return {system: dict(path=str(path), sha256=digest(path)) for system, path in paths.items()}


def main():
    verify_generated_sources()
    verify_correctness()
    retain_sources()
    measure.save(CORE / 'prepared.json', dict(name='browse', status='ready', measured=False,
        compiler_commit='15d2c64', canonical_counts=[1, 2, 2000], ordered_trace_counts=[1, 2],
        predicate_cases=8, scheme_executors=5, rust_executors=3,
        clean_retention=digest(REPORT / 'retained-work.json'),
        controls=digest(CORE / 'controls/prepared.json')))
    spec = importlib.util.spec_from_file_location('browse_timing', REPORT / 'measure-seven.py')
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    tools = tools_from_records()
    schedule = [dict(benchmark='browse', system=system, round=round_number, retained=round_number >= 0)
                for round_number in range(-1, 7)
                for system in SYSTEMS[max(0, round_number):] + SYSTEMS[:max(0, round_number)]]
    result = load(CORE / 'controls/rust/commands/count-2000-native/record.json')['stdout'].splitlines()[0]
    plan = dict(compiler_commit='15d2c64', upstream_commit='85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1',
                cpu=5, timeout_seconds=120, preparation=str(FROZEN), taskset=tools['TASKSET'],
                environment={'BINARYEN_CORES': '1'},
                inherited_environment={name: os.environ.get(name) for name in runner.RECORDED_ENVIRONMENT},
                workloads={'browse': dict(count=2000, rust_result_line=result)},
                systems={'browse': systems(tools)}, schedule=schedule,
                identities={str(path): digest(path) for path in identity_files(tools)},
                scope='Full canonical Browse; setup precedes every workload clock; complete final predicate is timed.',
                exclusions='Exactly the first seven processes are discarded; no replacement samples.',
                module_control='Native and its V8 control share the exact final Scheme Wasm; scalar provider target/linkage differ.',
                process_clock='Popen through capture, leader reap and bounded process-group cleanup.')
    protocols = verify_protocols(runner, plan)
    # Preparation already imported these from the checkout. Exercise the exact
    # frozen import paths that a new measurement process will use instead.
    for name in ('matrix_port', 'data_ports'):
        sys.modules.pop(name, None)
    runner.verify(plan)
    measure.save(REPORT / 'timing-plan.json', plan)
    measure.save(REPORT / 'checks.json', dict(protocol_records=protocols, dry_import_and_identity_verification=True,
        canonical_counts=[1, 2, 2000], five_scheme_edge_checks=40, ordered_trace_counts=[1, 2],
        full_count_internal_trace=False, measured=False, compiler_commit='15d2c64'))
    print('Frozen', len(schedule), 'fresh processes and', len(plan['identities']), 'identities; no timings run')


if __name__ == '__main__':
    main()
