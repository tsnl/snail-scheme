"""Measure the frozen full Mazefun task in four fresh-process implementations."""

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
HANDOFF = Path('/tmp/snail-rust-mazefun-handoff-20261014/build/rust-mazefun-timing-handoff/handoff.json')
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
    rust = next(case for case in load(HANDOFF)['cases'] if case['name'] == 'mazefun')
    prepared, spec = load(preparation / 'prepared.json'), load(preparation / 'mazefun/spec.json')
    assert prepared['cases'][0]['status'] == 'ready' and spec['count'] == rust['count'] == 10000
    assert spec['name'] == 'mazefun' and spec['inputs'] == [11, 11] and not spec.get('trace')
    assert spec['result_kind'] == 'i64-list-values' and spec.get('export', 'bench') == 'bench'
    data = Path(rust['stdin']).read_bytes()
    assert (preparation / 'mazefun/input.txt').read_bytes() == data == spec['input_decoder']['stdin'].encode()
    assert spec['expected'] == encoded_grid(rust['correctness']['expected_stdout_result'][8:])
    assert spec['input_decoder']['stdout'].splitlines() == [str(x) for x in [10000, 11, 11, *spec['expected']]]
    for field, hash_field in [('artifact', 'artifact_sha256'), ('host', 'host_sha256'), ('stdin', 'input_sha256'), ('source', 'source_sha256')]:
        assert identity(rust[field])['sha256'] == rust[hash_field]
    verify_files(rust['frozen_source_root'], rust['frozen_source_hashes'])
    verify_files(preparation / 'compiler-source', prepared['compiler_files'])
    verify_files(preparation / 'mazefun', prepared['cases'][0]['hashes'])
    assert identity(preparation / 'host.mjs')['sha256'] == prepared['host_sha256']
    assert identity(rust['correctness']['complete_result_path'])['sha256'] == rust['correctness']['complete_result_sha256']
    for tool in [*prepared['tools'].values(), *load(HANDOFF.parent / 'tools.json').values()]:
        assert identity(tool['path'])['sha256'] == tool['sha256']
    return dict(name='mazefun', preparation=str(preparation), spec=spec, rust=rust)


def encoded_grid(text):
    rows = [row.split() for row in re.findall(r'\(([_* ]+)\)', text)]
    assert len(rows) == 11 and all(len(row) == 11 for row in rows)
    encoded = [2, len(rows)]
    for row in rows:
        encoded.extend([len(row), *[int(mark == '_') for mark in row]])
    return encoded


def identities(case):
    preparation, rust = Path(case['preparation']), case['rust']
    prepared = load(preparation / 'prepared.json')
    rust_manifest = load(Path(__file__).resolve().parent.parent / '2026-10-14-rust-mazefun-handoff/manifest.json')
    verify_files(HANDOFF.parent, rust_manifest['files'])
    paths = [__file__, HANDOFF, HANDOFF.parent / 'build-provenance.json', NODE, CHEZ, TASKSET,
             preparation / 'host.mjs', preparation / 'prepared.json', rust['correctness']['complete_result_path']]
    paths += [preparation / 'mazefun' / leaf for leaf in prepared['cases'][0]['hashes']]
    paths += [preparation / 'compiler-source' / leaf for leaf in prepared['compiler_files']]
    paths += [HANDOFF.parent / leaf for leaf in rust_manifest['files']]
    paths += [Path(tool['path']) for tool in prepared['tools'].values()]
    paths += [Path(tool['path']) for tool in load(HANDOFF.parent / 'tools.json').values()]
    paths += [Path(tool['path']) for tool in load(HANDOFF.parent / 'build-provenance.json')['actual_rustup_tools'].values()]
    return [identity(path) for path in dict.fromkeys(paths)]


def commands(case):
    preparation = Path(case['preparation'])
    directory = preparation / 'mazefun'
    return {'strict': [NODE, '--no-warnings', str(preparation / 'host.mjs'), str(directory / 'strict.wasm'), str(directory / 'spec.json')],
            'original-chez': [CHEZ, '--program', str(directory / 'program.so')],
            'adapted-chez': [CHEZ, '--program', str(directory / 'same-source-chez/program.so')],
            'rust-wasm': case['rust']['command']}


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
    arguments = [TASKSET, '-c', '5', *arguments]
    data = Path(case['rust']['stdin']).read_bytes()
    (cwd / 'input.txt').write_bytes(data)
    item = dict(variant=variant, command=arguments, cwd=str(cwd), stdin=data.decode(),
                input_sha256=identity(cwd / 'input.txt')['sha256'], round=round_index,
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
        assert set(result) == {'seconds', 'result', 'barriers', 'setup_barriers'}
        assert result['result'] == '1'
        assert result['barriers'] is None and result['setup_barriers'] is None
        seconds = result['seconds']
        assert type(seconds) in (int, float)
    else:
        seconds = csv_seconds(case, observation['variant'], observation['stdout'])
    assert math.isfinite(seconds) and seconds >= 0
    return seconds


# ---- Preserve every trial before validation; never replace failed trials ----

def run_rounds(case, variants, record, output):
    names = list(variants)
    for round_index in range(-1, len(names)):
        offset = max(round_index, 0)
        for position, variant in enumerate(names[offset:] + names[:offset]):
            item = observe(case, variant, variants[variant], round_index, position, record, output)
            try:
                item['workload_seconds'] = checked_seconds(case, item)
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
    frozen = load(OUTPUT / 'mazefun-freeze.json')
    case, before = frozen['case'], frozen['identities']
    assert identities(case) == before and commands(case) == frozen['commands']
    record = dict(name='mazefun', started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), cpu=5,
                  scope='10000 full11x11 mazes; fresh processes; default V8 tiering; setup excluded and full final predicate included.',
                  case=case, order=list(frozen['commands']), removed_environment=REMOVED_ENVIRONMENT,
                  quiet_window=load(OUTPUT / 'quiet-window.json'),
                  identities_before=before, observations=[], complete=False)
    output = OUTPUT / 'mazefun.json'
    assert not output.exists(), 'Preserve prior observations; use a new directory.'
    campaign(case, frozen, record, output)


def main():
    action, *arguments = sys.argv[1:]
    OUTPUT.mkdir(exist_ok=True)
    if action == 'prepare' and len(arguments) == 1:
        case = contract(Path(arguments[0]).resolve())
        assert not ENVIRONMENT.get('LD_PRELOAD'), 'An injected library would change the clean execution.'
        assert not (OUTPUT / 'mazefun-freeze.json').exists(), 'Preserve the existing freeze.'
        save(OUTPUT / 'mazefun-freeze.json', dict(case=case, identities=identities(case), commands=commands(case),
             protocol=dict(cpu=5, timeout_seconds=900, excluded_rounds=1, retained_cyclic_rounds=4,
                           cwd_pattern=str(OUTPUT / 'trials/round-{round}/{variant}'),
                           command_prefix=[TASKSET, '-c', '5'], stdin=case['rust']['stdin'],
                           input_sha256=case['rust']['input_sha256'], removed_environment=REMOVED_ENVIRONMENT,
                           selected_effective_environment={key: ENVIRONMENT[key] for key in ['PATH', 'LANG', 'LC_ALL', 'TZ', 'LD_LIBRARY_PATH', 'LD_PRELOAD'] if key in ENVIRONMENT},
                           environment_limit='Remaining environment inherited; full values not archived.',
                           workload_clock='Program/host clock excludes setup and includes complete final predicate.',
                           process_clock='Parent monotonic launch-through-completion; distinct from workload clock.')))
        print('frozen mazefun', flush=True)
    elif action == 'measure' and not arguments:
        measure()
    else:
        raise SystemExit('usage: measure-matched.py prepare DIRECTORY | measure')


if __name__ == '__main__':
    main()
