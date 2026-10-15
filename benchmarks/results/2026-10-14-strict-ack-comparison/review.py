#!/usr/bin/env python3
"""Independently audit the saved complete Ackermann campaign; never run guests."""

import argparse
from datetime import datetime
import hashlib
import json
import math
from pathlib import Path
import re
import statistics

SYSTEMS = ('production-v8', 'native-final-v8', 'native64', 'chez-original',
           'rust-native-recursive', 'rust-native-heap', 'rust-wasm-heap')
PLAN_SHA = 'becf183a5d71651b924229cd1dc389c6f46cd1bcf01e907889f2bcd59ed69311'
RUNNER_SHA = '320bda3ba13d3c2916aa920f3b53fa064e5c102491164fb26161f04f88856171'
NUMBER = r'[0-9]+(?:\.[0-9]+)?(?:[eE][+\-]?[0-9]+)?'


# ---- Frozen preparation and complete predeclared schedule ----

def read(path):
    return json.loads(path.read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def positive_duration(value):
    require(type(value) in (int, float) and math.isfinite(value) and value > 0,
            'duration is not a finite positive number')
    return value


def expected_schedule():
    rows = []
    for round_number in range(-1, 7):
        for position in range(7):
            system = SYSTEMS[(position + max(round_number, 0)) % 7]
            rows.append(dict(benchmark='ack', system=system, round=round_number,
                             position=position, retained=round_number >= 0))
    return rows


def verify_preparation(preparation):
    plan_path, runner = preparation / 'timing-plan.json', preparation / 'measure.py'
    require(digest(plan_path) == PLAN_SHA and digest(runner) == RUNNER_SHA,
            'frozen plan or runner differs')
    plan = read(plan_path)
    modules = sorted((preparation / 'supervisor').glob('*.py'))
    require(len(modules) == 18 and [path.stem for path in modules] == plan['supervisor_modules'],
            'archived supervisor inventory differs')
    for path in modules:
        original = str(Path(plan['supervisor']) / path.name)
        require(digest(path) == plan['identities'][original], 'archived supervisor differs')
    return plan


# ---- Exact invocation, historical ownership evidence and complete output ----

def validate_invocation(plan, row, scheduled):
    require(all(type(row[key]) is type(value) and row[key] == value
                for key, value in scheduled.items()), 'sample schedule differs')
    config = plan['systems'][row['system']]
    require(row['command'] == [plan['taskset'], '-c', '5', *config['command']], 'command differs')
    require(row['cwd'] == config['cwd'] and row['stdin_path'] == config['stdin'], 'input context differs')
    require(row['environment'] == plan['environment'], 'sample environment differs')
    require(row['identities_before'] == row['identities_after'] == 'verified', 'identity check missing')


def validate_process(row):
    require(row['status'] == 'valid' and row['returncode'] == 0, 'unsuccessful process')
    require(not any(row[key] for key in ('stderr', 'timeout', 'executing_descendants',
                                        'diagnostic_only', 'stop_signal')), 'invalid process evidence')
    require(type(row['pid']) is int and row['pid'] > 0, 'invalid process identity')
    expected = dict(process_group=row['pid'], live_members=[], leader_reaped=True,
                    capture_handles_closed=True, zombies_count_as_stopped=True)
    require(row['cleanup'] == expected and row['process_group'] == row['pid'],
            'incomplete ownership evidence')
    positive_duration(row['process_seconds'])
    positive_duration(row['workload_seconds'])


def output_frame(system):
    seconds = '(?P<seconds>' + NUMBER + ')'
    if system in ('production-v8', 'native-final-v8'):
        return (r'\{"seconds":' + seconds
                + r',"result":"32765","barriers":null,"setup_barriers":null\}\n')
    if system == 'native64':
        return r'\{"result":"32765","barriers":0,"seconds":' + seconds + r'\}\n'
    if system == 'chez-original':
        return (r'Running ack:3:12:2\nElapsed time: ' + seconds + r' seconds \('
                + '(?P<rounded>' + NUMBER + r')\) for ack:3:12:2\n'
                + r'\+!CSVLINE!\+chez,ack:3:12:2,(?P=seconds)\n')
    require(system in SYSTEMS[4:], 'unknown output protocol')
    return r'Result: 32765\n\+!CSVLINE!\+rust-wasm,ack:2,' + seconds + r'\n'


def validate_output(row):
    match = re.fullmatch(output_frame(row['system']), row['stdout'])
    require(match is not None, 'complete output differs')
    seconds = positive_duration(float(match['seconds']))
    require(seconds == row['workload_seconds'], 'saved workload duration differs')
    if row['system'] == 'chez-original':
        require(math.isfinite(float(match['rounded'])), 'nonfinite rounded Chez clock')


# ---- Recompute statistics without changing the retained population ----

def summarize(rows):
    summary = {}
    for system in SYSTEMS:
        selected = [row for row in rows if row['system'] == system and row['retained']]
        require(len(selected) == 7 and {row['position'] for row in selected} == set(range(7)),
                'retained positions are not balanced')
        work = [row['workload_seconds'] for row in selected]
        process = [row['process_seconds'] for row in selected]
        summary[system] = dict(samples=7, workload_median=statistics.median(work),
            workload_range=[min(work), max(work)], process_median=statistics.median(process),
            process_range=[min(process), max(process)])
    return summary


def ratios(summary):
    controls = ('chez-original', 'native-final-v8', 'rust-native-recursive',
                'rust-native-heap', 'rust-wasm-heap')
    return {system: {f'over_{control}': values['workload_median'] / summary[control]['workload_median']
                     for control in controls} for system, values in summary.items()}


def fixed_policy(host):
    return {name: value for name, value in host['policy'].items()
            if not name.endswith('/scaling_cur_freq')}


def host_evidence(directory, plan):
    before, after = read(directory / 'host-before.json'), read(directory / 'host-after.json')
    for host in (before, after):
        require(host['cpu'] == 5 and host['inherited_environment'] == plan['inherited_environment'],
                'host environment differs')
    start, end = datetime.fromisoformat(before['date']), datetime.fromisoformat(after['date'])
    require(end >= start, 'host clock moved backwards')
    return dict(started=before['date'], ended=after['date'], elapsed_seconds=(end - start).total_seconds(),
                fixed_cpu_policy_equal=fixed_policy(before) == fixed_policy(after),
                affinity_equal=before['affinity'] == after['affinity'])


def review(directory, preparation, check_live_identities):
    plan, campaign = verify_preparation(preparation), read(directory / 'campaign.json')
    require(campaign['plan'] == plan and plan['schedule'] == expected_schedule(), 'plan differs')
    require(plan['cpu'] == 5 and plan['timeout_seconds'] == 120, 'execution limits differ')
    require(campaign['complete'] and not campaign['diagnostic_only'], 'incomplete clean campaign')
    require(campaign['identities_after'] == 'verified', 'final identity check missing')
    require(not {'pending_sample', 'error', 'identity_after_error'} & campaign.keys(), 'campaign failed')
    rows = campaign['samples']
    require(len(rows) == 56 and len(list(directory.glob('sample-*.json'))) == 56, 'sample count differs')
    for index, (row, scheduled) in enumerate(zip(rows, expected_schedule())):
        require(row == read(directory / f'sample-{index:03}.json'), 'separate sample differs')
        validate_invocation(plan, row, scheduled)
        validate_process(row)
        validate_output(row)
    if check_live_identities:
        for path, expected in plan['identities'].items():
            require(digest(Path(path)) == expected, 'live identity changed: ' + path)
    summary = summarize(rows)
    require(summary == campaign['summary'], 'independent medians differ')
    return dict(valid=True, process_count=56, predetermined_discards=7, retained_count=49,
                identity_count=len(plan['identities']), live_identities_checked=check_live_identities,
                campaign_sha256=digest(directory / 'campaign.json'), **host_evidence(directory, plan),
                summary=summary, ratios=ratios(summary))


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
