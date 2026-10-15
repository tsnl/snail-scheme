#!/usr/bin/env python3
"""Independently audit captured Equal timings without executing any guest."""

import hashlib
import json
import math
from pathlib import Path
import re
import statistics

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
PREPARED = ROOT / 'build/equal-prepared-6fd5ca4'
CAMPAIGN = PREPARED / 'clean-campaign'
SYSTEMS = ('strict-v8', 'strict-v8-native-module', 'strict-native',
           'chez-original', 'chez-adapted', 'rust-wasm', 'rust-native')
CAPTURED = {}


# ---- Parsed records and their hashes share the same captured bytes ----

def sha(data):
    return hashlib.sha256(data).hexdigest()


def distinct_fields(pairs):
    result = {}
    for name, value in pairs:
        if name in result:
            raise ValueError('duplicate JSON field: ' + name)
        result[name] = value
    return result


def read(path):
    data = path.read_bytes()
    CAPTURED[str(path.relative_to(ROOT))] = sha(data)
    return json.loads(data, object_pairs_hook=distinct_fields)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def positive(value):
    return type(value) in (int, float) and math.isfinite(value) and value > 0


# ---- Independent complete-output parsing includes the original predicate ----

def strict_seconds(system, output):
    value = json.loads(output, object_pairs_hook=distinct_fields)
    flags = dict(result=1)
    if system == 'strict-native':
        flags.update(barriers=0, setup_closed=1, worker_closed=0, closed=1)
    require(output.endswith('\n') and output.count('\n') == 1, 'strict output frame')
    require(set(value) == set(flags) | {'seconds'}, 'strict output fields')
    require(all(type(value[key]) is int and value[key] == number for key, number in flags.items()), 'strict predicate/lifecycle')
    return value['seconds']


def chez_seconds(output):
    title = 'equal:100:100:8:1000:2000:5000'
    number = r'([0-9.eE+\-]+)'
    pattern = (re.escape('Running ' + title + '\nElapsed time: ') + number
               + r' seconds \(' + number + r'\) for '
               + re.escape(title + '\n+!CSVLINE!+chez,' + title + ',') + number + '\n')
    matched = re.fullmatch(pattern, output)
    require(matched is not None, 'complete canonical Chez frame')
    first, rounded, last = map(float, matched.groups())
    require(first == last and math.isfinite(rounded) and rounded >= 0, 'Chez clock fields')
    return first


def result_seconds(system, output):
    if system.startswith('strict-'):
        return strict_seconds(system, output)
    if system.startswith('chez-'):
        return chez_seconds(output)
    matched = re.fullmatch(r'Result: #t\n\+!CSVLINE!\+rust-wasm,equal:1,([0-9.eE+\-]+)\n', output)
    require(matched is not None, 'complete Rust result frame')
    return float(matched[1])


# ---- The fixed rotation, actual captures and owned cleanup must all agree ----

def schedule():
    return [dict(system=system, round=round_number, retained=round_number >= 0)
            for round_number in range(-1, 7)
            for system in SYSTEMS[max(0, round_number):] + SYSTEMS[:max(0, round_number)]]


def check_capture(row, expected, plan):
    require(all(type(row[key]) is type(value) and row[key] == value for key, value in expected.items()), 'scheduled record')
    config = plan['systems'][row['system']]
    require(row['command'] == [plan['taskset'], '-c', '5', *config['argv']] and row['cwd'] == config['cwd'], 'actual command/cwd')
    require(row['status'] == 'valid' and row['returncode'] == 0 and not row['stderr'] and row['timeout'] is False, 'clean completion')
    closed = row['cleanup']
    require(closed['process_group'] == row['process_group'] == row['pid'], 'owned group identity')
    require(closed['leader_reaped'] is True and closed['capture_handles_closed'] is True and closed['live_members'] == [], 'owned cleanup')
    seconds = result_seconds(row['system'], row['stdout'])
    require(positive(seconds) and positive(row['process_seconds']) and row['workload_seconds'] == seconds, 'positive clocks')
    return seconds


def check_records(plan, report):
    expected = schedule()
    require(report['complete'] is True and len(report['samples']) == 56, 'complete 56-process campaign')
    require('error' not in report and 'pending_sample' not in report, 'unfinished or failed campaign')
    require(report['plan'] == plan and plan['schedule'] == expected, 'frozen plan/schedule')
    require(plan['cpu'] == 5 and plan['timeout_seconds'] == 120 and tuple(plan['systems']) == SYSTEMS, 'frozen execution policy')
    require(plan['input_parameters'] == [100, 100, 8, 1000, 2000, 5000]
            and plan['chez_workload_name'] == 'equal:100:100:8:1000:2000:5000', 'complete original workload')
    require(plan['environment'] == {'BINARYEN_CORES': '1'} and report['inherited_environment'] == plan['inherited_environment'], 'recorded environment')
    require({path.name for path in CAMPAIGN.glob('sample-*.json')} == {f'sample-{i:02}.json' for i in range(56)}, 'exact sample inventory')
    for index, scheduled in enumerate(expected):
        row = read(CAMPAIGN / f'sample-{index:02}.json')
        require(row == report['samples'][index], 'campaign/raw capture disagreement')
        check_capture(row, scheduled, plan)


def summaries(rows):
    result = {}
    for system in SYSTEMS:
        retained = [row for row in rows if row['system'] == system and row['retained']]
        work = [row['workload_seconds'] for row in retained]
        process = [row['process_seconds'] for row in retained]
        require(len(retained) == 7, 'seven retained observations per system')
        result[system] = dict(samples=7, workload_median=statistics.median(work), workload_range=[min(work), max(work)],
                             process_median=statistics.median(process), process_range=[min(process), max(process)])
    return result


# ---- Tool identities remain external; selected artifact bytes bind to the archive ----

def check_identities(plan):
    for name, expected in plan['identities'].items():
        path = Path(name)
        observed = sha(path.read_bytes())
        require(observed == expected, 'changed frozen identity: ' + name)
        retained = path.is_relative_to(PREPARED) or path.is_relative_to(REPORT)
        if retained and not {'target', '__pycache__'}.intersection(path.parts):
            CAPTURED[str(path.relative_to(ROOT))] = observed
    return len(plan['identities'])


def check_host():
    before, after = read(CAMPAIGN / 'host-before.json'), read(CAMPAIGN / 'host-after.json')
    require(before['cpu'] == after['cpu'] == 5 and before['affinity'] == after['affinity'], 'CPU/affinity changed')
    policy = lambda row: {key: value for key, value in row['policy'].items() if not key.endswith('/scaling_cur_freq')}
    require(policy(before) == policy(after), 'CPU policy changed')
    return dict(before=before, after=after, limitation='Snapshots do not establish fixed frequency, cold caches or absence of unrelated host activity.')


def main():
    destination = REPORT / 'independent-review.json'
    require(not destination.exists(), 'refusing to replace an existing independent audit')
    plan, report = read(REPORT / 'timing-plan.json'), read(CAMPAIGN / 'campaign.json')
    check_records(plan, report)
    summary = summaries(report['samples'])
    require(summary == report['summary'], 'reported medians/ranges differ from raw retained samples')
    identities, host = check_identities(plan), check_host()
    result = dict(complete=True, clean_processes=56, retained_processes=49, discarded_processes=7,
                  frozen_identities=identities, summary=summary, host_observations=host,
                  audited_files=CAPTURED, scope='Complete original enabled Equal aggregate; independent capture/frame/schedule/summary audit, no guest execution.')
    destination.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
