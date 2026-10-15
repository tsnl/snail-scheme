"""Compare frozen strict programs with both Chez controls and Rust/Wasm."""

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
HANDOFF = Path('/tmp/snail-rust-lattice-handoff-20261014/build/rust-lattice-timing-handoff/handoff.json')
NODE = '/nix/store/lfaydgacdyngci7p60s8wwvgdm74fjkx-nodejs-24.19.0/bin/node'
CHEZ = '/nix/store/bzqpmy5kmvf0xn4xh5ixzkw00w9srh07-chez-scheme-10.4.1/bin/scheme'
TASKSET = '/run/current-system/sw/bin/taskset'
ENVIRONMENT = os.environ.copy()
ENVIRONMENT.pop('NODE_OPTIONS', None)


def load(path):
    return json.loads(Path(path).read_text())


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n')


def identity(path):
    return dict(path=str(path), sha256=hashlib.sha256(Path(path).read_bytes()).hexdigest())


def contract(name, preparation):
    rust = next(case for case in load(HANDOFF)['cases'] if case['name'] == name)
    spec = load(preparation / name / 'spec.json')
    assert load(preparation / 'prepared.json')['cases'][0]['status'] == 'ready'
    assert spec['count'] == rust['count']
    assert (preparation / name / 'input.txt').read_bytes() == Path(rust['stdin']).read_bytes()
    for field, hash_field in [('artifact', 'wasm_sha256'), ('host', 'host_sha256'), ('stdin', 'input_sha256'), ('module_source', 'module_source_sha256')]:
        assert identity(rust[field])['sha256'] == rust[hash_field]
    for leaf, expected in rust['source_bundle_hashes'].items():
        assert identity(Path(rust['exact_source_bundle']) / leaf)['sha256'] == expected
    return dict(name=name, preparation=str(preparation), spec=spec, rust=rust)


def identities(case):
    preparation, rust = Path(case['preparation']), case['rust']
    directory = preparation / case['name']
    paths = [__file__, HANDOFF, HANDOFF.parent / 'build-provenance.json', NODE, CHEZ, TASKSET,
             preparation / 'host.mjs', preparation / 'prepared.json']
    paths += [directory / leaf for leaf in ('strict.scm', 'strict.wasm', 'spec.json', 'input.txt',
               'program.scm', 'program.so', 'same-source-chez/program.scm', 'same-source-chez/program.so')]
    paths += [preparation / 'compiler-source' / leaf for leaf in load(preparation / 'prepared.json')['compiler_files']]
    paths += [Path(rust[key]) for key in ('artifact', 'host', 'stdin', 'module_source')]
    paths += [Path(rust['exact_source_bundle']) / leaf for leaf in rust['source_bundle_hashes']]
    return [identity(path) for path in dict.fromkeys(paths)]


def commands(case):
    preparation = Path(case['preparation'])
    directory = preparation / case['name']
    return {'strict': [NODE, str(preparation / 'host.mjs'), str(directory / 'strict.wasm'), str(directory / 'spec.json')],
            'original-chez': [CHEZ, '--program', str(directory / 'program.so')],
            'adapted-chez': [CHEZ, '--program', str(directory / 'same-source-chez/program.so')],
            'rust-wasm': case['rust']['command']}


# ---- Fresh processes; retain failures before checking their results ----

def execute(command, cwd, data):
    try:
        process = subprocess.run(command, cwd=cwd, env=ENVIRONMENT, input=data,
                                 capture_output=True, text=True, timeout=900)
        return dict(returncode=process.returncode, stdout=process.stdout, stderr=process.stderr)
    except subprocess.TimeoutExpired as error:
        return dict(returncode=None, timeout=True, stdout=(error.stdout or b'').decode(),
                    stderr=(error.stderr or b'').decode())


def observe(case, variant, arguments):
    arguments = [TASKSET, '-c', '5', *arguments]
    directory = Path(case['preparation']) / case['name']
    data = None if variant == 'strict' else (directory / 'input.txt').read_text()
    cwd = case['rust']['cwd'] if variant == 'rust-wasm' else str(directory)
    started = time.monotonic()
    return dict(execute(arguments, cwd, data), variant=variant, command=arguments,
                cwd=cwd, stdin=data, process_seconds=time.monotonic() - started)


def csv_seconds(case, variant, output):
    rows = [line.removeprefix('+!CSVLINE!+').split(',') for line in output.splitlines() if line.startswith('+!CSVLINE!+')]
    assert len(rows) == 1 and len(rows[0]) == 3
    contract = case['rust']['correctness']
    expected_case = contract['csv_case'] if variant == 'rust-wasm' else contract.get('original_chez_csv_case', contract['csv_case'])
    assert rows[0][:2] == [('rust-wasm' if variant == 'rust-wasm' else 'chez'), expected_case]
    if variant == 'rust-wasm':
        results = [line for line in output.splitlines() if line.startswith('Result:')]
        assert results == [contract['expected_stdout_result']]
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


# ---- One discarded round and four retained cyclic rotations ----

def run_rounds(case, variants, record, output):
    names = list(variants)
    for round_index in range(-1, len(names)):
        offset = max(round_index, 0)
        for variant in names[offset:] + names[:offset]:
            item = dict(observe(case, variant, variants[variant]), round=round_index, retained=round_index >= 0)
            record['observations'].append(item)
            save(output, record)
            item['workload_seconds'] = checked_seconds(case, item)
            save(output, record)
            print(case['name'], round_index, variant, item['workload_seconds'], flush=True)


def finish(case, record, output):
    record['identities_after'] = identities(case)
    assert record['identities_after'] == record['identities_before']
    record['summary'] = {}
    for variant in record['order']:
        samples = [x['workload_seconds'] for x in record['observations'] if x['variant'] == variant and x['retained']]
        record['summary'][variant] = dict(samples=samples, median=statistics.median(samples), min=min(samples), max=max(samples))
    record['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    record['complete'] = True
    save(output, record)
    print(json.dumps(record['summary']), flush=True)


def measure(name):
    assert load(OUTPUT / 'quiet-window.json')['agents_holding_builds'] is True
    frozen = load(OUTPUT / (name + '-freeze.json'))
    case, before = frozen['case'], frozen['identities']
    assert identities(case) == before and commands(case) == frozen['commands']
    record = dict(name=name, started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), cpu=5,
                  scope='Original full workload, fresh processes, default V8 tiering; setup excluded and final predicate included.',
                  case=case, order=list(frozen['commands']), node_options=None,
                  identities_before=before, observations=[], complete=False)
    output = OUTPUT / (name + '.json')
    run_rounds(case, frozen['commands'], record, output)
    finish(case, record, output)


def main():
    action, name, *arguments = sys.argv[1:]
    OUTPUT.mkdir(exist_ok=True)
    if action == 'prepare' and len(arguments) == 1:
        case = contract(name, Path(arguments[0]).resolve())
        save(OUTPUT / (name + '-freeze.json'), dict(case=case, identities=identities(case), commands=commands(case)))
        print('frozen', name, flush=True)
    elif action == 'measure' and not arguments:
        measure(name)
    else:
        raise SystemExit('usage: measure-matched.py prepare NAME DIRECTORY | measure NAME')


if __name__ == '__main__':
    main()
