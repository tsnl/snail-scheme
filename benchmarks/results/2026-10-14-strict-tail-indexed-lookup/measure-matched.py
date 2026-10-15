"""Measure a frozen diagnostic Tail lookup pair in fresh processes."""

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

from prepare import finish_group, kill_group


# ---- Frozen artifacts and source contracts ----

OUTPUT = Path(__file__).resolve().parent / 'matched-measurements'
ORIGINAL = Path('/tmp/snail-strict-tail-20261014/build/strict-tail-final')
CASE = ORIGINAL / 'tail'
PRIOR = Path(__file__).resolve().parent.parent / '2026-10-14-strict-tail-comparison'
NODE = '/nix/store/lfaydgacdyngci7p60s8wwvgdm74fjkx-nodejs-24.19.0/bin/node'
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
    ready = load(preparation / 'prepared.json')
    assert ready['ready'] and not ready['performance_samples']
    assert ready['changed_source_files'] == ['src/strict_io.rs'] and ready['baseline_reproduces_original']
    for value in ready['identities']:
        assert identity(value['path'])['sha256'] == value['sha256'], value['path']
    original = load(ORIGINAL / 'prepared.json')
    for tool in ready['tools'].values():
        assert identity(tool['path'])['sha256'] == tool['sha256']
    for path, expected in load(CASE / 'runtime-toolchain.json')['toolchain_files'].items():
        assert identity(path)['sha256'] == expected
    verify_files(ORIGINAL / 'compiler-source', original['compiler_files'])
    verify_files(CASE, original['cases'][0]['hashes'])
    spec = load(CASE / 'spec.json')
    assert spec == dict(name='tail', count=50, inputs=[], pathnames=['inputs/bib', 'outputs/tail.output'],
                        expected=1, barriers_per_iteration=2, setup_barriers=0, runtime='scalar-io')
    assert identity(ORIGINAL / 'tail-host.mjs')['sha256'] == original['tail_host_sha256']
    data = (CASE / 'upstream-input.bin').read_bytes()
    assert len(data) == 4460056 and data.count(b'\n') == 31102 and data.endswith(b'\n') and b'\r' not in data
    assert data.isascii()
    oracle = b'\n'.join(reversed(data[:-1].split(b'\n'))) + b'\n'
    assert oracle == (CASE / 'canonical-output.bin').read_bytes()
    stdin = (CASE / 'input.txt').read_bytes()
    assert stdin == b'50\n"inputs/bib"\n"outputs/tail.output"\nignored\n'
    decoder = load(PRIOR / 'matched-measurements/input-decoder.json')
    assert decoder['returncode'] == 0 and not decoder['stderr'] and decoder['stdin'].encode() == stdin
    lines = decoder['stdout'].splitlines()
    assert len(lines) == 3 and int(lines[0]) == spec['count']
    assert [[int(x) for x in line.split()] for line in lines[1:]] == [[ord(x) for x in name] for name in spec['pathnames']]
    for name in ['baseline', 'indexed']:
        full = load(preparation / name / 'full-count.json')
        assert full['valid'] and full['lifecycle_complete'] and full['complete_output_checks'] == 50
        probes = load(preparation / name / 'scalar-probes/results.json')
        assert len(probes) == 10 and all(probe['valid'] for probe in probes)
    files = dict(stdin=str(CASE / 'input.txt'), input_sha256=identity(CASE / 'input.txt')['sha256'],
                 bibliography=str(CASE / 'upstream-input.bin'), bibliography_sha256=identity(CASE / 'upstream-input.bin')['sha256'],
                 expected_output=str(CASE / 'canonical-output.bin'), output=dict(relative_path=spec['pathnames'][1],
                 bytes=4460056, sha256=identity(CASE / 'canonical-output.bin')['sha256']))
    return dict(name='tail', preparation=str(preparation), spec=spec, files=files)

def identities(case):
    preparation = Path(case['preparation'])
    ready, original = load(preparation / 'prepared.json'), load(ORIGINAL / 'prepared.json')
    paths = [__file__, Path(__file__).with_name('prepare.py'), preparation / 'prepared.json',
             ORIGINAL / 'prepared.json', ORIGINAL / 'tail-host.mjs', PRIOR / 'freeze.json',
             PRIOR / 'matched-measurements/input-decoder.json', PRIOR / 'matched-measurements/decoder.stdout.bin',
             PRIOR / 'matched-measurements/decoder.stderr.bin']
    paths += [record['path'] for record in ready['identities']]
    paths += [preparation / name / 'scalar-probes/results.json' for name in ['baseline', 'indexed']]
    paths += [CASE / leaf for leaf in original['cases'][0]['hashes']]
    paths += [ORIGINAL / 'compiler-source' / leaf for leaf in original['compiler_files']]
    paths += [tool['path'] for tool in original['tools'].values()]
    paths += list(load(CASE / 'runtime-toolchain.json')['toolchain_files'])
    return [identity(path) for path in dict.fromkeys(str(path) for path in paths)]


def commands(case):
    preparation = Path(case['preparation'])
    return {name: [NODE, '--no-warnings', str(ORIGINAL / 'tail-host.mjs'), str(preparation / name / 'strict.wasm'), str(CASE / 'spec.json')]
            for name in ['baseline', 'indexed']}


# ---- Each fresh process preserves its terminal raw bytes ----

def execute(command, cwd, data, timeout=900):
    started, process = time.monotonic(), None
    try:
        process = subprocess.Popen(command, cwd=cwd, env=ENVIRONMENT, stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        stdout, stderr = process.communicate(data, timeout=timeout)
        outcome = dict(returncode=process.returncode, status='exited')
    except subprocess.TimeoutExpired:
        killed = kill_group(process.pid)
        stdout, stderr = process.communicate()
        outcome = dict(returncode=process.returncode, status='timeout', timeout_seconds=timeout, timeout_group_kill_sent=killed)
    except OSError as error:
        if process is not None:
            kill_group(process.pid)
            process.wait()
        outcome, stdout, stderr = dict(returncode=None, status='launch-failed', launch_error=repr(error)), b'', b''
    finally:
        finished = time.monotonic()
        group = finish_group(process) if process is not None else None
    outcome['process_seconds'] = finished - started
    if process is not None:
        outcome.update(owned_process_group=process.pid, group_cleanup=group)
    return outcome, stdout, stderr


def observe(case, variant, arguments, round_index, position, record, output):
    cwd = OUTPUT / 'trials' / f'round-{round_index}' / variant
    cwd.mkdir(parents=True, exist_ok=False)
    (cwd / 'inputs').mkdir()
    (cwd / 'outputs').mkdir()
    bibliography = cwd / case['spec']['pathnames'][0]
    bibliography.write_bytes(Path(case['files']['bibliography']).read_bytes())
    assert identity(bibliography)['sha256'] == case['files']['bibliography_sha256']
    assert not (cwd / case['files']['output']['relative_path']).exists()
    arguments = [TASKSET, '-c', '5', *arguments]
    data = Path(case['files']['stdin']).read_bytes()
    (cwd / 'input.txt').write_bytes(data)
    item = dict(variant=variant, command=arguments, cwd=str(cwd), stdin=data.decode(),
                input_sha256=identity(cwd / 'input.txt')['sha256'], bibliography_before=identity(bibliography), round=round_index,
                position=position, retained=round_index >= 0, status='started',
                started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    record['observations'].append(item)
    save(output, record)
    outcome, stdout, stderr = execute(arguments, cwd, data)
    item.update(outcome,
                finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    (cwd / 'stdout.bin').write_bytes(stdout)
    (cwd / 'stderr.bin').write_bytes(stderr)
    item.update(stdout_raw=dict(identity(cwd / 'stdout.bin'), bytes=len(stdout)),
                stderr_raw=dict(identity(cwd / 'stderr.bin'), bytes=len(stderr)))
    save(output, record)
    item.update(stdout=stdout.decode(), stderr=stderr.decode())
    return item

def unique_object(pairs):
    result = {}
    for key, value in pairs:
        assert key not in result, 'duplicate JSON field'
        result[key] = value
    return result


def checked_seconds(case, observation):
    assert observation['status'] == 'exited' and observation['returncode'] == 0 and not observation['stderr'], observation
    assert observation['group_cleanup']['no_executing_descendants'], observation
    assert observation['stdout'].endswith('\n') and len(observation['stdout'].splitlines()) == 1
    result = json.loads(observation['stdout'], object_pairs_hook=unique_object)
    assert set(result) == {'seconds', 'result', 'barriers'}
    assert result['result'] == '1' and result['barriers'] is None
    seconds = result['seconds']
    assert type(seconds) in (int, float) and math.isfinite(seconds) and seconds >= 0
    return seconds


def check_file(case, observation):
    output = case['files']['output']
    path = Path(observation['cwd']) / output['relative_path']
    data = path.read_bytes()
    observation['output_file'] = dict(identity(path), bytes=len(data))
    assert len(data) == output['bytes'] and observation['output_file']['sha256'] == output['sha256']
    assert data == Path(case['files']['expected_output']).read_bytes()
    bibliography = Path(observation['cwd']) / case['spec']['pathnames'][0]
    observation['bibliography_after'] = identity(bibliography)
    assert observation['bibliography_after'] == observation['bibliography_before']


# ---- Preserve every trial before validation; never replace failed trials ----

def run_rounds(case, variants, record, output):
    names = list(variants)
    for round_index in range(-1, 4):
        offset = max(round_index, 0) % len(names)
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
    record = dict(name='tail-indexed-lookup', started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), cpu=5,
                  scope='50 complete 4460056-byte file reversals; fresh processes; default V8 tiering; setup excluded and original always-true predicate included; full output validation after each stopped clock.',
                  case=case, order=list(frozen['commands']), removed_environment=REMOVED_ENVIRONMENT,
                  quiet_window=load(OUTPUT / 'quiet-window.json'),
                  identities_before=before, observations=[], complete=False)
    output = OUTPUT / 'tail-indexed-lookup.json'
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
             protocol=dict(cpu=5, timeout_seconds=900, excluded_rounds=1, retained_cyclic_rounds=4, variants=2, retained_order=['AB', 'BA', 'AB', 'BA'],
                           cwd_pattern=str(OUTPUT / 'trials/round-{round}/{variant}'),
                           command_prefix=[TASKSET, '-c', '5'], stdin=case['files']['stdin'],
                           input_sha256=case['files']['input_sha256'], bibliography=case['files']['bibliography'],
                           bibliography_sha256=case['files']['bibliography_sha256'],
                           output_initial_state='absent', validation='Every 4460056 output byte checked after every process and outside both clocks.',
                           removed_environment=REMOVED_ENVIRONMENT,
                           selected_effective_environment={key: ENVIRONMENT[key] for key in ['PATH', 'LANG', 'LC_ALL', 'TZ', 'LD_LIBRARY_PATH', 'LD_PRELOAD'] if key in ENVIRONMENT},
                           environment_limit='Remaining environment inherited; full values not archived.',
                           workload_clock='Program/host clock excludes input/setup and includes full repeated file work and original always-true predicate.',
                           process_clock='Parent monotonic launch-through-process-completion; excludes subsequent group inspection and file validation; distinct from workload clock.')))
        print('frozen tail', flush=True)
    elif action == 'measure' and not arguments:
        measure()
    else:
        raise SystemExit('usage: measure-matched.py prepare DIRECTORY | measure')


if __name__ == '__main__':
    main()
