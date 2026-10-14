"""Measure the frozen full Tail task in four fresh-process implementations."""

import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import statistics
import re
import subprocess
import sys
import time


# ---- Frozen artifacts and source contracts ----

OUTPUT = Path(__file__).resolve().parent / 'matched-measurements'
RUST = Path('/tmp/snail-tail-comparison-20261014/build/rust-tail-frozen')
NODE = '/nix/store/lfaydgacdyngci7p60s8wwvgdm74fjkx-nodejs-24.19.0/bin/node'
CHEZ = '/nix/store/bzqpmy5kmvf0xn4xh5ixzkw00w9srh07-chez-scheme-10.4.1/bin/scheme'
TASKSET = '/run/current-system/sw/bin/taskset'
REMOVED_ENVIRONMENT = ['NODE_OPTIONS', 'NODE_V8_COVERAGE', 'NODE_DEBUG', 'NODE_DEBUG_NATIVE']
ENVIRONMENT = {key: value for key, value in os.environ.items() if key not in REMOVED_ENVIRONMENT}


def load(path):
    return json.loads(Path(path).read_text())


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n')


def identity(path):
    return dict(path=str(path), sha256=hashlib.sha256(Path(path).read_bytes()).hexdigest())


def verify_files(directory, hashes):
    for leaf, expected in hashes.items():
        assert identity(Path(directory) / leaf)['sha256'] == expected, leaf


def contract(preparation):
    prepared, spec = load(preparation / 'prepared.json'), load(preparation / 'tail/spec.json')
    assert prepared['cases'][0]['status'] == 'ready' and spec == prepared['cases'][0]['spec']
    assert spec == dict(name='tail', count=50, inputs=[], pathnames=['inputs/bib', 'outputs/tail.output'],
                        expected=1, barriers_per_iteration=2, setup_barriers=0, runtime='scalar-io')
    verify_files(preparation / 'compiler-source', prepared['compiler_files'])
    verify_files(preparation / 'tail', prepared['cases'][0]['hashes'])
    verify_files(RUST, load(RUST / 'manifest.json')['files'])
    assert identity(preparation / 'tail-host.mjs')['sha256'] == prepared['tail_host_sha256']
    data = (RUST / 'bibliography.bin').read_bytes()
    assert data == (preparation / 'tail/upstream-input.bin').read_bytes()
    assert len(data) == 4460056 and data.count(b'\n') == 31102 and data.endswith(b'\n') and b'\r' not in data
    data.decode('utf8')
    oracle = b'\n'.join(reversed(data[:-1].split(b'\n'))) + b'\n'
    assert oracle == (RUST / 'expected-output.bin').read_bytes() == (preparation / 'tail/canonical-output.bin').read_bytes()
    stdin = (RUST / 'input.txt').read_bytes()
    assert stdin == (preparation / 'tail/input.txt').read_bytes() == b'50\n"inputs/bib"\n"outputs/tail.output"\nignored\n'
    for tool in prepared['tools'].values():
        assert identity(tool['path'])['sha256'] == tool['sha256']
    assert load(RUST / 'checks.json')['all_accepted_checks_pass']
    assert load(RUST / 'build-provenance.json')['optimized_artifact']['sha256'] == identity(RUST / 'program.wasm')['sha256']
    decode_input(preparation, stdin, spec)
    rust = dict(count=50, artifact=str(RUST / 'program.wasm'), host=str(RUST / 'reference-source/run-wasi.mjs'),
                stdin=str(RUST / 'input.txt'), input_sha256=identity(RUST / 'input.txt')['sha256'],
                bibliography=str(RUST / 'bibliography.bin'), bibliography_sha256=identity(RUST / 'bibliography.bin')['sha256'],
                expected_output=str(RUST / 'expected-output.bin'), output=dict(relative_path=spec['pathnames'][1], bytes=4460056,
                sha256=identity(RUST / 'expected-output.bin')['sha256']),
                correctness=dict(expected_stdout_result='Result: ignored', csv_case='tail:50', original_chez_csv_case='tail:50'))
    return dict(name='tail', preparation=str(preparation), spec=spec, rust=rust)


def decode_input(preparation, stdin, spec):
    command = [CHEZ, '--script', str(preparation / 'tail/input-decoder.scm')]
    outcome, stdout, stderr = execute(command, preparation, stdin)
    (OUTPUT / 'decoder.stdout.bin').write_bytes(stdout)
    (OUTPUT / 'decoder.stderr.bin').write_bytes(stderr)
    save(OUTPUT / 'input-decoder.json', dict(outcome, command=command, stdin=stdin.decode(),
         stdout=stdout.decode(), stderr=stderr.decode(), performance_samples=False))
    assert outcome['returncode'] == 0 and not stderr
    lines = stdout.decode().splitlines()
    assert len(lines) == 3 and int(lines[0]) == spec['count']
    assert [[int(x) for x in line.split()] for line in lines[1:]] == [[ord(x) for x in path] for path in spec['pathnames']]


def identities(case):
    preparation = Path(case['preparation'])
    prepared = load(preparation / 'prepared.json')
    paths = [__file__, RUST / 'manifest.json', preparation / 'tail-host.mjs', preparation / 'prepared.json',
             OUTPUT / 'input-decoder.json', OUTPUT / 'decoder.stdout.bin', OUTPUT / 'decoder.stderr.bin']
    paths += [preparation / 'tail' / leaf for leaf in prepared['cases'][0]['hashes']]
    paths += [preparation / 'compiler-source' / leaf for leaf in prepared['compiler_files']]
    paths += [RUST / leaf for leaf in load(RUST / 'manifest.json')['files']]
    paths += [tool['path'] for tool in prepared['tools'].values()]
    paths += [Path(__file__).resolve().parent.parent / '2026-10-14-strict-tail' / leaf
              for leaf in ['manifest.json', 'artifacts.tar.xz', 'retained-work.json']]
    return [identity(path) for path in dict.fromkeys(str(path) for path in paths)]


def commands(case):
    preparation = Path(case['preparation'])
    directory = preparation / 'tail'
    return {'strict': [NODE, '--no-warnings', str(preparation / 'tail-host.mjs'), str(directory / 'strict.wasm'), str(directory / 'spec.json')],
            'original-chez': [CHEZ, '--program', str(directory / 'program.so')],
            'adapted-chez': [CHEZ, '--program', str(directory / 'same-source-chez/program.so')],
            'rust-wasm': [NODE, '--no-warnings', case['rust']['host'], case['rust']['artifact']]}


# ---- Each fresh process preserves its terminal raw bytes ----

def execute(command, cwd, data):
    try:
        process = subprocess.run(command, cwd=cwd, env=ENVIRONMENT, input=data,
                                 capture_output=True, timeout=900)
        return dict(returncode=process.returncode, status='exited'), process.stdout, process.stderr
    except subprocess.TimeoutExpired as error:
        return dict(returncode=None, status='timeout', timeout_seconds=900), error.stdout or b'', error.stderr or b''
    except OSError as error:
        return dict(returncode=None, status='launch-failed', launch_error=repr(error)), b'', b''


def observe(case, variant, arguments, round_index, position, record, output):
    cwd = OUTPUT / 'trials' / f'round-{round_index}' / variant
    cwd.mkdir(parents=True, exist_ok=False)
    (cwd / 'inputs').mkdir()
    (cwd / 'outputs').mkdir()
    bibliography = cwd / case['spec']['pathnames'][0]
    bibliography.write_bytes(Path(case['rust']['bibliography']).read_bytes())
    assert identity(bibliography)['sha256'] == case['rust']['bibliography_sha256']
    assert not (cwd / case['rust']['output']['relative_path']).exists()
    arguments = [TASKSET, '-c', '5', *arguments]
    data = Path(case['rust']['stdin']).read_bytes()
    (cwd / 'input.txt').write_bytes(data)
    item = dict(variant=variant, command=arguments, cwd=str(cwd), stdin=data.decode(),
                input_sha256=identity(cwd / 'input.txt')['sha256'], bibliography_before=identity(bibliography), round=round_index,
                position=position, retained=round_index >= 0, status='started',
                started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    record['observations'].append(item)
    save(output, record)
    started = time.monotonic()
    outcome, stdout, stderr = execute(arguments, cwd, data)
    item.update(outcome, process_seconds=time.monotonic() - started,
                finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    (cwd / 'stdout.bin').write_bytes(stdout)
    (cwd / 'stderr.bin').write_bytes(stderr)
    item.update(stdout_raw=dict(identity(cwd / 'stdout.bin'), bytes=len(stdout)),
                stderr_raw=dict(identity(cwd / 'stderr.bin'), bytes=len(stderr)))
    save(output, record)
    item.update(stdout=stdout.decode(), stderr=stderr.decode())
    return item


def csv_seconds(case, variant, output):
    assert output.endswith('\n') and '\r' not in output
    lines = output.splitlines()
    expected = case['rust']['correctness']
    label = expected['csv_case'] if variant == 'rust-wasm' else expected['original_chez_csv_case']
    if variant == 'rust-wasm':
        assert len(lines) == 2 and lines[0] == expected['expected_stdout_result']
    else:
        assert len(lines) == 3 and lines[0] == 'Running ' + label
        assert re.fullmatch(r'Elapsed time: ([^ ]+) seconds \(([^ ]+)\) for ' + re.escape(label), lines[1])
    row = lines[-1].removeprefix('+!CSVLINE!+').split(',')
    assert lines[-1].startswith('+!CSVLINE!+') and len(row) == 3
    assert row[:2] == [('rust-wasm' if variant == 'rust-wasm' else 'chez'), label]
    seconds = float(row[2])
    if variant != 'rust-wasm':
        assert float(lines[1].split()[2]) == seconds
        assert math.isfinite(float(lines[1].split()[4][1:-1]))
    return seconds


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        assert key not in result, 'duplicate JSON field'
        result[key] = value
    return result


def checked_seconds(case, observation):
    assert observation['returncode'] == 0 and not observation['stderr'], observation
    assert 'INCORRECT' not in observation['stdout']
    if observation['variant'] == 'strict':
        assert observation['stdout'].endswith('\n') and len(observation['stdout'].splitlines()) == 1
        result = json.loads(observation['stdout'], object_pairs_hook=unique_object)
        assert set(result) == {'seconds', 'result', 'barriers'}
        assert result['result'] == '1'
        assert result['barriers'] is None
        seconds = result['seconds']
        assert type(seconds) in (int, float)
    else:
        seconds = csv_seconds(case, observation['variant'], observation['stdout'])
    assert math.isfinite(seconds) and seconds >= 0
    return seconds


def check_file(case, observation):
    output = case['rust']['output']
    path = Path(observation['cwd']) / output['relative_path']
    data = path.read_bytes()
    observation['output_file'] = dict(identity(path), bytes=len(data))
    assert len(data) == output['bytes'] and observation['output_file']['sha256'] == output['sha256']
    assert data == Path(case['rust']['expected_output']).read_bytes()
    bibliography = Path(observation['cwd']) / case['spec']['pathnames'][0]
    observation['bibliography_after'] = identity(bibliography)
    assert observation['bibliography_after'] == observation['bibliography_before']


# ---- Preserve every trial before validation; never replace failed trials ----

def run_rounds(case, variants, record, output):
    names = list(variants)
    for round_index in range(-1, len(names)):
        offset = max(round_index, 0)
        for position, variant in enumerate(names[offset:] + names[:offset]):
            item = observe(case, variant, variants[variant], round_index, position, record, output)
            try:
                item['workload_seconds'] = checked_seconds(case, item)
                check_file(case, item)
                item['valid'] = True
            except Exception as error:
                item['validation_failure'] = repr(error)
                save(output, record)
                raise
            save(output, record)
            print(round_index, variant, item['workload_seconds'], flush=True)


def summarize(record):
    record['summary'] = {}
    for variant in record['order']:
        retained = [x for x in record['observations'] if x['variant'] == variant and x['retained']]
        record['summary'][variant] = {}
        for clock in ['workload_seconds', 'process_seconds']:
            samples = [x[clock] for x in retained]
            assert len(samples) == 4
            record['summary'][variant][clock] = dict(samples=samples, median=statistics.median(samples), min=min(samples), max=max(samples))
    print(json.dumps(record['summary']), flush=True)


def campaign(case, frozen, record, output):
    try:
        run_rounds(case, frozen['commands'], record, output)
        record['identities_after'] = identities(case)
        assert record['identities_after'] == record['identities_before']
        summarize(record)
        record['complete'] = True
    except Exception as error:
        record['failure'] = repr(error)
        raise
    finally:
        record['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        save(output, record)


def measure():
    assert load(OUTPUT / 'quiet-window.json')['agents_holding_builds'] is True
    assert not ENVIRONMENT.get('LD_PRELOAD'), 'An injected library would change the clean execution.'
    frozen = load(OUTPUT / 'tail-freeze.json')
    case, before = frozen['case'], frozen['identities']
    assert identities(case) == before and commands(case) == frozen['commands']
    record = dict(name='tail', started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), cpu=5,
                  scope='50 complete4460056-byte file reversals; fresh processes; default V8 tiering; setup excluded and original always-true predicate included; full output validation after each stopped clock.',
                  case=case, order=list(frozen['commands']), removed_environment=REMOVED_ENVIRONMENT,
                  quiet_window=load(OUTPUT / 'quiet-window.json'),
                  identities_before=before, observations=[], complete=False)
    output = OUTPUT / 'tail.json'
    assert not output.exists(), 'Preserve prior observations; use a new directory.'
    campaign(case, frozen, record, output)


def main():
    action, *arguments = sys.argv[1:]
    OUTPUT.mkdir(exist_ok=True)
    if action == 'prepare' and len(arguments) == 1:
        case = contract(Path(arguments[0]).resolve())
        assert not ENVIRONMENT.get('LD_PRELOAD'), 'An injected library would change the clean execution.'
        assert not (OUTPUT / 'tail-freeze.json').exists(), 'Preserve the existing freeze.'
        save(OUTPUT / 'tail-freeze.json', dict(case=case, identities=identities(case), commands=commands(case),
             protocol=dict(cpu=5, timeout_seconds=900, excluded_rounds=1, retained_cyclic_rounds=4,
                           cwd_pattern=str(OUTPUT / 'trials/round-{round}/{variant}'),
                           command_prefix=[TASKSET, '-c', '5'], stdin=case['rust']['stdin'],
                           input_sha256=case['rust']['input_sha256'], bibliography=case['rust']['bibliography'],
                           bibliography_sha256=case['rust']['bibliography_sha256'],
                           output_initial_state='absent', validation='Every4460056 output byte checked after every process and outside both clocks.',
                           removed_environment=REMOVED_ENVIRONMENT,
                           selected_effective_environment={key: ENVIRONMENT[key] for key in ['PATH', 'LANG', 'LC_ALL', 'TZ', 'LD_LIBRARY_PATH', 'LD_PRELOAD'] if key in ENVIRONMENT},
                           environment_limit='Remaining environment inherited; full values not archived.',
                           workload_clock='Program/host clock excludes input/setup and includes full repeated file work and original always-true predicate.',
                           process_clock='Parent monotonic launch-through-completion; distinct from workload clock.')))
        print('frozen tail', flush=True)
    elif action == 'measure' and not arguments:
        measure()
    else:
        raise SystemExit('usage: measure-matched.py prepare DIRECTORY | measure')


if __name__ == '__main__':
    main()
