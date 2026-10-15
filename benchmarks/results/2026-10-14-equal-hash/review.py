#!/usr/bin/env python3
"""Independently reparse Equal captures and recompute results; never run guests."""

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import statistics

REPORT = Path(__file__).resolve().parent
ROOT = REPORT.parents[2]
PREPARED = ROOT/'build/equal-hash-matched-20261014'
MODES = ('production-v8', 'native-final-v8', 'native64')
SYSTEMS = [revision+'-'+mode for mode in MODES for revision in ('baseline', 'candidate')]
CAPTURED = {}


# ---- The review consumes bytes directly and binds every read to its hash ----

def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def capture(path):
    data = path.read_bytes()
    CAPTURED[str(path)] = sha(data)
    return data


def distinct(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate JSON key: ' + key)
        result[key] = value
    return result


def read(path):
    return json.loads(capture(path), object_pairs_hook=distinct)


def positive(value):
    require(type(value) in (int, float) and math.isfinite(value) and value > 0, 'invalid workload seconds')
    return value


def frame(system, output):
    require(output.count(b'\n') == 1 and output.endswith(b'\n'), 'extra, missing or malformed output framing')
    value = json.loads(output.decode('utf-8'), object_pairs_hook=distinct)
    expected = {'result': 1}
    if system.endswith('-native64'):
        expected.update(barriers=0, setup_closed=1, worker_closed=0, closed=1)
    require(type(value) is dict and set(value) == set(expected) | {'seconds'}, 'unknown or missing full frame fields')
    for key, amount in expected.items():
        require(type(value[key]) is int and value[key] == amount, 'full predicate or file lifecycle differs: ' + key)
    return positive(value['seconds'])


# ---- Balance is checked by counting the observed schedule, independently ----

def check_schedule(plan):
    rows = plan['schedule']
    require(len(rows) == 78 and plan['systems'] == SYSTEMS, 'six-system campaign size differs')
    require([row['index'] for row in rows] == list(range(78)), 'sample identities differ')
    require([row['system'] for row in rows[:6]] == SYSTEMS, 'one warmup per system required')
    require(all(row['phase'] == 'discarded-warmup' and row['round'] == -1 for row in rows[:6]), 'warmup retention changed')
    retained = rows[6:]
    require(all(row['phase'] == 'measurement' and row['round'] == index//6
                and row['position'] == index%6 for index, row in enumerate(retained)), 'retained round/position differs')
    orders = [[row['system'] for row in retained[number*6:(number+1)*6]] for number in range(12)]
    require(all(set(order) == set(SYSTEMS) for order in orders), 'round missing or duplicates a system')
    check_cycle_balance(orders)
    return rows


def check_cycle_balance(orders):
    for cycle in (orders[:6], orders[6:]):
        require(all(Counter(order[position] for order in cycle) == Counter(SYSTEMS)
                    for position in range(6)), 'Williams position balance differs')
        require(Counter((order[i], order[i+1]) for order in cycle for i in range(5)) ==
                Counter({(a, b): 1 for a in SYSTEMS for b in SYSTEMS if a != b}), 'Williams directed adjacency differs')
    for mode in MODES:
        require(sum(order.index('candidate-'+mode) < order.index('baseline-'+mode) for order in orders) == 6,
                'revision order is not six before/six after')


def verify_manifest(plan):
    for path, expected in plan['identities'].items():
        require(sha(capture(Path(path))) == expected, 'frozen dependency changed: ' + path)
    require(plan['cpu'] == 5 and plan['rounds'] == 12 and plan['timeout_seconds'] == 60, 'control settings differ')
    require(plan['environment'] == {'BINARYEN_CORES': '1'}, 'explicit runtime environment differs')
    require(plan['input_parameters'] == [100, 100, 8, 1000, 2000, 5000], 'full canonical parameters differ')
    require(plan['candidate_uncommitted_at_freeze'] is True, 'candidate provenance misrepresented')


# ---- Raw process and capture records must agree before clocks are admitted ----

def check_invocation(record, expected, plan):
    for key, value in expected.items():
        require(type(record[key]) is type(value) and record[key] == value, 'scheduled row differs: ' + key)
    config = plan['configurations'][record['system']]
    for key in ('command', 'cwd', 'dependencies'):
        require(record[key] == config[key], 'actual invocation differs: ' + key)
    for key, value in plan['environment'].items():
        require(record['environment'].get(key) == value, 'explicit execution environment differs')
    require(record['environment'] == plan['environment'], 'unplanned environment metadata')
    require(record['inherited_environment'] == plan['inherited_environment'], 'inherited execution settings differ')
    require(record['diagnostic_only'] is False, 'instrumented or diagnostic run entered clean data')


def check_terminal(record):
    require(record['status'] == 'valid' and type(record['returncode']) is int and record['returncode'] == 0, 'process unsuccessful')
    require(record['termination'] == {'exit_status': 0, 'signal': None}, 'terminal status differs')
    require(record['timeout'] is False and record['interrupted'] is False and record['stop_signal'] is None, 'process stopped')
    require(type(record['pid']) is int and record['pid'] > 0 and record['pid'] == record['process_group'], 'owned process identity differs')
    cleanup = record['cleanup']
    require(cleanup['process_group'] == record['process_group'] and cleanup['leader_reaped'] is True, 'leader/group cleanup differs')
    require(cleanup['live_members'] == [] and record['executing_descendants'] == [], 'owned descendants not quiescent')
    require(record['capture_complete'] is True and record['capture_handles_closed'] is True, 'byte capture incomplete')
    positive(record['process_seconds'])


def check_raw_captures(directory, record):
    data = {}
    require(set(record['captures']) == {'stdout', 'stderr'}, 'capture inventory differs')
    for name in ('stdout', 'stderr'):
        path = directory/(name+'.bin')
        require(record['captures'][name]['path'] == str(path), 'actual byte capture path differs')
        data[name] = capture(path)
        require(record['captures'][name]['bytes'] == len(data[name])
                and record['captures'][name]['sha256'] == sha(data[name]), 'raw byte identity differs')
    require(data['stderr'] == b'', 'stderr is not empty')
    seconds = frame(record['system'], data['stdout'])
    require(seconds == record['workload_seconds'], 'runner interpretation differs from raw frame')
    return seconds


def read_samples(campaign, report, plan, scheduled):
    require(len(report['samples']) == 78, 'campaign raw record count differs')
    actual = sorted(path.name for path in campaign.glob('sample-*'))
    require(actual == [f'sample-{index:03}' for index in range(78)], 'sample directory inventory differs')
    rows = []
    for expected, recorded in zip(scheduled, report['samples']):
        directory = campaign/f'sample-{expected["index"]:03}'
        row = read(directory/'record.json')
        require(row == recorded, 'campaign record differs from individually preserved capture')
        check_invocation(row, expected, plan)
        check_terminal(row)
        rows.append(dict(**expected, seconds=check_raw_captures(directory, row)))
    return rows


# ---- The review computes both ratio formulas from the twelve matched rounds ----

def recompute(rows):
    systems, values = {}, {}
    for system in SYSTEMS:
        selected = [row for row in rows if row['system'] == system and row['phase'] == 'measurement']
        require([row['round'] for row in selected] == list(range(12)), 'retained population differs')
        values[system] = [row['seconds'] for row in selected]
        systems[system] = dict(samples=12, median=statistics.median(values[system]),
                              range=[min(values[system]), max(values[system])])
    return dict(systems=systems, comparisons=compare_revisions(values, systems))


def compare_revisions(values, systems):
    comparisons = {}
    for mode in MODES:
        before, after = 'baseline-'+mode, 'candidate-'+mode
        ratios = [values[after][number]/values[before][number] for number in range(12)]
        ratio = systems[after]['median']/systems[before]['median']
        comparisons[mode] = dict(candidate_over_baseline=ratio, percent_less_time=100*(1-ratio),
            paired_round_ratios=ratios, paired_median=statistics.median(ratios))
    return comparisons


def audit(campaign):
    plan = read(REPORT/'timing-plan.json')
    report = read(campaign/'campaign.json')
    require(report['complete'] is True and report['diagnostic_only'] is False, 'completed clean campaign required')
    require(report['plan_sha256'] == CAPTURED[str(REPORT/'timing-plan.json')], 'campaign plan differs')
    require(report['coordinated_release'], 'coordinated quiet-window record absent')
    verify_manifest(plan)
    rows = read_samples(campaign, report, plan, check_schedule(plan))
    summary = recompute(rows)
    require(summary == report['summary'], 'independent statistical recomputation differs')
    before, after = read(campaign/'host-before.json'), read(campaign/'host-after.json')
    return dict(passed=True, guests_started=False, warmups=6, retained=72, processes=78,
        plan_sha256=report['plan_sha256'], summary=summary, host_cpu=[before['cpu'], after['cpu']],
        capture_sha256=dict(CAPTURED), review_code_sha256=sha(Path(__file__).read_bytes()))


# ---- Tests ----

def protocol_self_test():
    checked = 0
    for revision in ('baseline', 'candidate'):
        for label, mode in [('complete-correctness', 'native64'), ('production-v8-correctness', 'production-v8'),
                            ('identical-wasm-v8-correctness', 'native-final-v8')]:
            record = read(PREPARED/revision/'native/commands'/label/'record.json')
            positive(frame(revision+'-'+mode, record['stdout'].encode()))
            checked += 1
    original = b'{"result":1,"seconds":0.5}\n'
    malformed = [original+b'\n', original.replace(b'1,', b'true,'), original.replace(b'1,', b'1.0,'),
        original.replace(b'0.5', b'NaN'), original.replace(b'0.5', b'0'), original[:-1], b'\xff\n',
        original.replace(b'"result":1', b'"result":1,"result":1')]
    for output in malformed:
        try:
            frame('baseline-production-v8', output)
        except (ValueError, UnicodeError):
            continue
        raise AssertionError('independent parser accepted malformed output')
    print('PASS independent raw-frame replay:', checked, 'existing complete frames and', len(malformed), 'corruptions; no guest started')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--campaign', type=Path)
    parser.add_argument('--protocol-self-test', action='store_true')
    parser.add_argument('--output', type=Path, default=REPORT/'independent-review.json')
    arguments = parser.parse_args()
    if arguments.protocol_self_test:
        protocol_self_test()
        return
    if not arguments.campaign:
        parser.error('--campaign is required for completed evidence review')
    result = audit(arguments.campaign.resolve())
    with arguments.output.open('x') as target:
        target.write(json.dumps(result, indent=2, allow_nan=False)+'\n')
    print('PASS independently reparsed all 78 raw captures and reproduced six medians/ranges and 36 matched ratios')


if __name__ == '__main__':
    main()
