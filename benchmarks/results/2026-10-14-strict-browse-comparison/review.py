#!/usr/bin/env python3
"""Independently audit the saved complete Browse campaign; never run guests."""

import argparse
from datetime import datetime
import hashlib
from importlib.machinery import PathFinder
import json
import math
from pathlib import Path
import re
import statistics

SYSTEMS = ('strict-v8', 'strict-v8-native-module', 'strict-native',
           'chez-original', 'chez-adapted', 'rust-wasm', 'rust-native')
SUPERVISOR = ('data_ports', 'matrix_port')
PLAN_SHA = 'f74417c18517306a366802ec012148c975fcadd51f5cc8274eedd124f3d64a12'
RUNNER_SHA = '807c1c1b9c3aae498faf2af4c47a5de99c4995b880a5d60a777c30d106b22731'
NUMBER = r'[0-9]+(?:\.[0-9]+)?(?:[eE][+\-]?[0-9]+)?'


# ---- Frozen preparation and complete predeclared schedule ----

def read(path):
    return json.loads(path.read_text())


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def positive_duration(value):
    require(type(value) in (int, float) and math.isfinite(value) and value > 0,
            'duration is not a finite positive number')
    return value


def expected_schedule():
    return [dict(benchmark='browse', system=SYSTEMS[(position + max(round_number, 0)) % 7],
                 round=round_number, retained=round_number >= 0)
            for round_number in range(-1, 7) for position in range(7)]


def verify_supervisor(preparation, plan):
    directory = (preparation / 'supervisor').resolve()
    require(sorted(path.stem for path in directory.glob('*.py')) == list(SUPERVISOR),
            'archived supervision inventory differs')
    for name in SUPERVISOR:
        path = directory / (name + '.py')
        spec = PathFinder.find_spec(name, [str(directory)])
        require(spec is not None and Path(spec.origin).resolve() == path, 'supervision import origin differs')
        original = str(Path(plan['preparation']) / path.name)
        require(digest(path) == plan['identities'][original], 'archived supervision module differs')


def verify_preparation(preparation):
    plan_path, runner = preparation / 'timing-plan.json', preparation / 'measure-seven.py'
    require(digest(plan_path) == PLAN_SHA and digest(runner) == RUNNER_SHA,
            'frozen plan or runner differs')
    plan = read(plan_path)
    require(plan['compiler_commit'] == '15d2c64' and len(plan['identities']) == 330,
            'frozen source basis or identity count differs')
    require(plan['cpu'] == 5 and plan['timeout_seconds'] == 120, 'execution limits differ')
    require(plan['workloads']['browse']['count'] == 2000, 'canonical invocation count differs')
    verify_supervisor(preparation, plan)
    return plan


# ---- Exact invocation, recorded process ownership and complete output ----

def validate_invocation(plan, row, scheduled):
    require(all(type(row[key]) is type(value) and row[key] == value
                for key, value in scheduled.items()), 'sample schedule differs')
    config = plan['systems']['browse'][row['system']]
    require(row['command'] == [plan['taskset'], '-c', '5', *config['argv']], 'command differs')
    require(row['cwd'] == config['cwd'] and row['environment'] == plan['environment'],
            'sample execution context differs')
    require(row['inherited_environment'] == plan['inherited_environment'], 'inherited environment differs')


def validate_process(row):
    require(row['status'] == 'valid' and type(row['returncode']) is int and row['returncode'] == 0,
            'unsuccessful process')
    require(row['stderr'] == '' and row['timeout'] is False and row['executing_descendants'] == [],
            'invalid process evidence')
    require(not {'error', 'stop_signal', 'diagnostic_only'} & row.keys(), 'failed or diagnostic sample')
    require(type(row['pid']) is int and row['pid'] > 0, 'invalid process identity')
    expected = dict(process_group=row['pid'], live_members=[], zombies_count_as_stopped=True)
    require(row['cleanup'] == expected and row['process_group'] == row['pid'], 'owned group cleanup differs')
    work, process = positive_duration(row['workload_seconds']), positive_duration(row['process_seconds'])
    capture = positive_duration(row['capture_and_cleanup_seconds'])
    require(work <= capture <= process, 'recorded clock ordering differs')


def output_frame(system, result_line):
    seconds = '(?P<seconds>' + NUMBER + ')'
    if system in SYSTEMS[:2]:
        return r'\{"result":1,"seconds":' + seconds + r'\}\n'
    if system == 'strict-native':
        return (r'\{"seconds":' + seconds + r',"result":1,"barriers":0,"setup_closed":1,'
                + r'"worker_closed":0,"closed":1\}\n')
    if system in ('chez-original', 'chez-adapted'):
        return (r'Running browse:2000\nElapsed time: ' + seconds + r' seconds \('
                + '(?P<rounded>' + NUMBER + r')\) for browse:2000\n'
                + r'\+!CSVLINE!\+chez,browse:2000,(?P=seconds)\n')
    require(system in ('rust-wasm', 'rust-native'), 'unknown output protocol')
    return re.escape(result_line) + r'\n\+!CSVLINE!\+rust-wasm,browse:2000,' + seconds + r'\n'


def validate_output(plan, row):
    result_line = plan['workloads']['browse']['rust_result_line']
    match = re.fullmatch(output_frame(row['system'], result_line), row['stdout'])
    require(match is not None, 'complete output differs')
    seconds = positive_duration(float(match['seconds']))
    require(seconds == row['workload_seconds'], 'saved workload duration differs')
    if row['system'] in ('chez-original', 'chez-adapted'):
        positive_duration(float(match['rounded']))


# ---- Recompute statistics without changing the retained population ----

def summarize(rows):
    summary = {}
    for system in SYSTEMS:
        selected = [(index % 7, row) for index, row in enumerate(rows)
                    if row['system'] == system and row['retained']]
        require(len(selected) == 7 and {position for position, _ in selected} == set(range(7)),
                'retained positions are not balanced')
        work = [row['workload_seconds'] for _, row in selected]
        process = [row['process_seconds'] for _, row in selected]
        summary[system] = dict(samples=7, workload_median=statistics.median(work),
            workload_range=[min(work), max(work)], process_median=statistics.median(process),
            process_range=[min(process), max(process)])
    return summary


def ratios(summary):
    controls = dict(original_chez='chez-original', adapted_chez='chez-adapted',
                    common_v8='strict-v8-native-module', rust_wasm='rust-wasm')
    return {system: {f'over_{name}': values['workload_median'] / summary[control]['workload_median']
                     for name, control in controls.items()} for system, values in summary.items()}


def fixed_policy(host):
    return {name: value for name, value in host['policy'].items()
            if not name.endswith('/scaling_cur_freq')}


def host_evidence(directory, rows):
    before, after = read(directory / 'host-before.json'), read(directory / 'host-after.json')
    require(all(host['cpu'] == 5 and 5 in host['affinity'] for host in (before, after)), 'host CPU differs')
    start, end = datetime.fromisoformat(before['date']), datetime.fromisoformat(after['date'])
    started = [datetime.fromisoformat(row['started']) for row in rows]
    require(start <= started[0] <= started[-1] <= end and started == sorted(started),
            'sample timestamps disagree with the host window')
    return dict(started=before['date'], ended=after['date'], elapsed_seconds=(end - start).total_seconds(),
                fixed_cpu_policy_equal=fixed_policy(before) == fixed_policy(after),
                affinity_equal=before['affinity'] == after['affinity'])


def verify_coordinator(directory, summary, comparison_ratios, evidence):
    parent = read(directory / 'parent-independent-review.json')
    require(parent['valid'] is True and parent['actual_owned_session'] == 49220
            and parent['actual_terminal_exit_code'] == 0, 'coordinator terminal evidence differs')
    require((parent['processes'], parent['retained'], parent['discarded'], parent['identities'])
            == (56, 49, 7, 330), 'coordinator population differs')
    require(parent['campaign_sha256'] == digest(directory / 'campaign.json'), 'coordinator campaign differs')
    require(parent['summary'] == summary and parent['ratios'] == comparison_ratios, 'coordinator statistics differ')
    for name in ('started', 'ended', 'elapsed_seconds'):
        require(parent[name] == evidence[name], 'coordinator host window differs')
    require(parent['fixed_policy_equal'] == evidence['fixed_cpu_policy_equal']
            and parent['affinity_equal'] == evidence['affinity_equal'], 'coordinator host policy differs')


def review(directory, preparation, check_live_identities):
    plan, campaign = verify_preparation(preparation), read(directory / 'campaign.json')
    require(campaign['plan'] == plan and plan['schedule'] == expected_schedule(), 'plan differs')
    require(campaign['complete'] is True and campaign['inherited_environment'] == plan['inherited_environment'],
            'incomplete campaign or changed inherited environment')
    require(not {'pending_sample', 'error', 'diagnostic_only'} & campaign.keys(), 'campaign failed')
    rows = campaign['samples']
    require(len(rows) == 56 and {path.name for path in directory.glob('sample-*.json')}
            == {f'sample-{index:02}.json' for index in range(56)}, 'sample inventory differs')
    for index, (row, scheduled) in enumerate(zip(rows, expected_schedule())):
        require(row == read(directory / f'sample-{index:02}.json'), 'separate sample differs')
        validate_invocation(plan, row, scheduled)
        validate_process(row)
        validate_output(plan, row)
    if check_live_identities:
        for path, expected in plan['identities'].items():
            require(digest(Path(path)) == expected, 'live identity changed: ' + path)
    summary, evidence = summarize(rows), host_evidence(directory, rows)
    require(campaign['summary'] == {'browse': summary}, 'independent medians differ')
    comparison_ratios = ratios(summary)
    verify_coordinator(directory, summary, comparison_ratios, evidence)
    return dict(valid=True, process_count=56, predetermined_discards=7, retained_count=49,
                identity_count=len(plan['identities']), live_identities_checked=check_live_identities,
                supervisor_modules=list(SUPERVISOR), archived_import_origins_checked=True,
                campaign_sha256=digest(directory / 'campaign.json'), **evidence,
                summary=summary, ratios=comparison_ratios)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('campaign', type=Path)
    parser.add_argument('preparation', type=Path)
    parser.add_argument('--check-live-identities', action='store_true')
    parser.add_argument('--output', type=Path)
    options = parser.parse_args()
    result = review(options.campaign, options.preparation, options.check_live_identities)
    payload = json.dumps(result, indent=2) + '\n'
    if options.output:
        options.output.write_text(payload)
    else:
        print(payload, end='')


if __name__ == '__main__':
    main()
