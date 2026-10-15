"""Measure the frozen full Ray task in four fresh-process implementations."""

import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time


# ---- Frozen artifacts and source contracts ----

OUTPUT = Path(__file__).resolve().parent / 'matched-measurements'
HANDOFF = Path('/tmp/snail-rust-ray-handoff-20261014/build/rust-ray-timing-handoff/handoff.json')
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
    rust = next(case for case in load(HANDOFF)['cases'] if case['name'] == 'ray')
    prepared, spec = load(preparation / 'prepared.json'), load(preparation / 'ray/spec.json')
    assert prepared['cases'][0]['status'] == 'ready' and spec['count'] == rust['count'] == 50
    assert spec['pathname'] == rust['output']['relative_path'] == 'outputs/ray.output'
    assert spec['inputs'] == [1, 1] and spec['expected'] == 1 and not spec.get('trace')
    assert (preparation / 'ray/input.txt').read_bytes() == Path(rust['stdin']).read_bytes()
    for field, hash_field in [('artifact', 'wasm_sha256'), ('host', 'host_sha256'), ('stdin', 'input_sha256'), ('module_source', 'module_source_sha256')]:
        assert identity(rust[field])['sha256'] == rust[hash_field]
    verify_files(rust['exact_source_bundle'], rust['source_bundle_hashes'])
    verify_files(preparation / 'compiler-source', prepared['compiler_files'])
    verify_files(preparation / 'ray', prepared['cases'][0]['hashes'])
    assert identity(rust['correctness']['expected_image'])['sha256'] == spec['image_sha256'] == rust['output']['sha256']
    return dict(name='ray', preparation=str(preparation), spec=spec, rust=rust)


def identities(case):
    preparation, rust = Path(case['preparation']), case['rust']
    prepared = load(preparation / 'prepared.json')
    paths = [__file__, HANDOFF, HANDOFF.parent / 'build-provenance.json', NODE, CHEZ, TASKSET,
             preparation / 'ray-host.mjs', preparation / 'prepared.json', rust['correctness']['expected_image']]
    paths += [preparation / 'ray' / leaf for leaf in prepared['cases'][0]['hashes']]
    paths += [preparation / 'compiler-source' / leaf for leaf in prepared['compiler_files']]
    paths += [Path(rust[key]) for key in ('artifact', 'host', 'stdin', 'module_source')]
    paths += [Path(rust['exact_source_bundle']) / leaf for leaf in rust['source_bundle_hashes']]
    return [identity(path) for path in dict.fromkeys(paths)]


def commands(case):
    preparation = Path(case['preparation'])
    directory = preparation / 'ray'
    return {'strict': [NODE, '--no-warnings', str(preparation / 'ray-host.mjs'), str(directory / 'strict.wasm'), str(directory / 'spec.json')],
            'original-chez': [CHEZ, '--program', str(directory / 'program.so')],
            'adapted-chez': [CHEZ, '--program', str(directory / 'same-source-chez/program.so')],
            'rust-wasm': case['rust']['command']}


# ---- Each fresh process owns its output directory ----

def execute(command, cwd, data):
    try:
        process = subprocess.run(command, cwd=cwd, env=ENVIRONMENT, input=data,
                                 capture_output=True, text=True, timeout=900)
        return dict(returncode=process.returncode, stdout=process.stdout, stderr=process.stderr)
    except subprocess.TimeoutExpired as error:
        return dict(returncode=None, timeout=True, stdout=(error.stdout or b'').decode(),
                    stderr=(error.stderr or b'').decode())


def observe(case, variant, arguments, round_index, position):
    cwd = OUTPUT / 'trials' / f'round-{round_index}' / variant
    cwd.mkdir(parents=True, exist_ok=False)
    (cwd / 'outputs').mkdir()
    assert not (cwd / case['rust']['output']['relative_path']).exists()
    arguments = [TASKSET, '-c', '5', *arguments]
    data = None if variant == 'strict' else Path(case['rust']['stdin']).read_text()
    started = time.monotonic()
    return dict(execute(arguments, cwd, data), variant=variant, command=arguments,
                cwd=str(cwd), stdin=data, process_seconds=time.monotonic() - started,
                round=round_index, position=position, retained=round_index >= 0)


def csv_seconds(case, variant, output):
    rows = [line.removeprefix('+!CSVLINE!+').split(',') for line in output.splitlines() if line.startswith('+!CSVLINE!+')]
    assert len(rows) == 1 and len(rows[0]) == 3
    expected = case['rust']['correctness']
    label = expected['csv_case'] if variant == 'rust-wasm' else expected['original_chez_csv_case']
    assert rows[0][:2] == [('rust-wasm' if variant == 'rust-wasm' else 'chez'), label]
    if variant == 'rust-wasm':
        results = [line for line in output.splitlines() if line.startswith('Result:')]
        assert results == [expected['expected_stdout_result']]
    return float(rows[0][2])


def checked_seconds(case, observation):
    assert observation['returncode'] == 0 and not observation['stderr'], observation
    assert 'INCORRECT' not in observation['stdout']
    if observation['variant'] == 'strict':
        result = json.loads(observation['stdout'])
        assert result['result'] == str(case['spec']['expected'])
        assert result['barriers'] is None and result['setup_barriers'] is None
        seconds = result['seconds']
    else:
        seconds = csv_seconds(case, observation['variant'], observation['stdout'])
    assert math.isfinite(seconds) and seconds > 0
    return seconds


def check_image(case, observation):
    output = case['rust']['output']
    path = Path(observation['cwd']) / output['relative_path']
    data = path.read_bytes()
    observation['image'] = dict(identity(path), bytes=len(data))
    assert len(data) == output['bytes'] == 29517
    assert observation['image']['sha256'] == output['sha256']
    assert data == Path(case['rust']['correctness']['expected_image']).read_bytes()


# ---- Preserve every trial before validation; never replace failed trials ----

def run_rounds(case, variants, record, output):
    names = list(variants)
    for round_index in range(-1, len(names)):
        offset = max(round_index, 0)
        for position, variant in enumerate(names[offset:] + names[:offset]):
            item = observe(case, variant, variants[variant], round_index, position)
            record['observations'].append(item)
            save(output, record)
            item['workload_seconds'] = checked_seconds(case, item)
            check_image(case, item)
            item['valid'] = True
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
    frozen = load(OUTPUT / 'ray-freeze.json')
    case, before = frozen['case'], frozen['identities']
    assert identities(case) == before and commands(case) == frozen['commands']
    record = dict(name='ray', started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), cpu=5,
                  scope='50 full renders; fresh processes; default V8 tiering; setup excluded and final predicate included.',
                  case=case, order=list(frozen['commands']), removed_environment=REMOVED_ENVIRONMENT,
                  identities_before=before, observations=[], complete=False)
    output = OUTPUT / 'ray.json'
    assert not output.exists(), 'Preserve prior observations; use a new directory.'
    campaign(case, frozen, record, output)


def main():
    action, *arguments = sys.argv[1:]
    OUTPUT.mkdir(exist_ok=True)
    if action == 'prepare' and len(arguments) == 1:
        case = contract(Path(arguments[0]).resolve())
        save(OUTPUT / 'ray-freeze.json', dict(case=case, identities=identities(case), commands=commands(case)))
        print('frozen ray', flush=True)
    elif action == 'measure' and not arguments:
        measure()
    else:
        raise SystemExit('usage: measure-matched.py prepare DIRECTORY | measure')


if __name__ == '__main__':
    main()
