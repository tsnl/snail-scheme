#!/usr/bin/env python3
"""Independently check saved exact-integer measurements; never launch guests."""

import argparse
from datetime import datetime
import hashlib
import json
import math
from pathlib import Path
import re
import statistics

SYSTEMS = ('production-v8', 'native-final-v8', 'native64', 'chez-original',
           'chez-adapted', 'chez-limbs', 'rust-native', 'rust-wasm')
WORKLOADS = ('pi', 'chudnovsky')
PLAN_SHA = 'd0946c397d52f674abb5d9019afcd28f68d6e44d358a90c3e9aba89e2ad319c3'
RUNNER_SHA = '1607e9f88521fe88ee707ffceaf8e1554a3cd4154251c28bcb0b5811a20df4ea'


# ---- Complete output and fixed process schedule ----

def read(path):
    return json.loads(path.read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def expected_schedule():
    rows = []
    for name in WORKLOADS:
        for round_number in range(-1, 8):
            for position in range(8):
                system = SYSTEMS[(position + max(round_number, 0)) % 8]
                rows.append(dict(benchmark=name, system=system, round=round_number,
                                 position=position, retained=round_number >= 0))
    return rows


def output_prefix(plan, row):
    name, system = row['benchmark'], row['system']
    workload = plan['workloads'][name]
    family = ('chez-integer' if system.startswith('chez-') else
              'rust-wasm' if system.startswith('rust-') else 'snail-integer')
    label = 'native' if system == 'native64' else name
    result = ('Result: ' if system.startswith('rust-') else '') + workload['output']
    return result + f'+!CSVLINE!+{family},{label}:{workload["count"]},'


def validate_output(plan, row):
    prefix, text = output_prefix(plan, row), row['stdout']
    require(text.startswith(prefix), 'complete numerical result changed')
    suffix = text[len(prefix):]
    require(re.fullmatch(r'[0-9.eE+\-]+\n', suffix), 'unexpected clock framing')
    seconds = float(suffix)
    require(math.isfinite(seconds) and seconds >= 0, 'invalid workload clock')
    require(seconds == row['workload_seconds'], 'parsed workload clock differs')


def validate_sample(plan, row, scheduled):
    require(all(row[key] == value for key, value in scheduled.items()), 'schedule differs')
    config = plan['systems'][row['benchmark']][row['system']]
    command = [plan['taskset'], '-c', '5', *config['command']]
    require(row['command'] == command and row['cwd'] == config['cwd'], 'command differs')
    require(row['environment'] == {**plan['environment'], **config.get('environment', {})},
            'sample environment differs')
    require(row['status'] == 'valid' and row['returncode'] == 0, 'unsuccessful process')
    require(not any(row[key] for key in ('stderr', 'timeout', 'executing_descendants',
                                        'diagnostic_only', 'stop_signal')), 'invalid process evidence')
    cleanup = row['cleanup']
    require(cleanup['live_members'] == [] and cleanup['leader_reaped']
            and cleanup['capture_handles_closed'], 'incomplete process cleanup')
    require(cleanup['process_group'] == row['process_group'] == row['pid'], 'group differs')
    require(math.isfinite(row['process_seconds']) and row['process_seconds'] > 0,
            'invalid process duration')
    validate_output(plan, row)


# ---- Medians, source identities and review result ----

def summarize(rows):
    summary = {}
    for name in WORKLOADS:
        summary[name] = {}
        for system in SYSTEMS:
            selected = [r for r in rows if r['benchmark'] == name and r['system'] == system and r['retained']]
            require(len(selected) == 8 and {r['position'] for r in selected} == set(range(8)),
                    'retained positions are not balanced')
            work = [r['workload_seconds'] for r in selected]
            process = [r['process_seconds'] for r in selected]
            summary[name][system] = dict(samples=8, workload_median=statistics.median(work),
                workload_range=[min(work), max(work)], process_median=statistics.median(process),
                process_range=[min(process), max(process)])
    return summary


def ratios(summary):
    return {name: {system: {f'over_{control}': values['workload_median'] / systems[control]['workload_median']
                           for control in ('chez-original', 'chez-adapted', 'chez-limbs',
                                           'native-final-v8', 'rust-native', 'rust-wasm')}
                   for system, values in systems.items()} for name, systems in summary.items()}


def fixed_policy(host):
    return {name: value for name, value in host['policy'].items()
            if not name.endswith('/scaling_cur_freq')}


def review(directory, preparation, check_live_identities):
    plan_path, runner = preparation / 'timing-plan.json', preparation / 'measure.py'
    require(digest(plan_path) == PLAN_SHA and digest(runner) == RUNNER_SHA, 'frozen preparation changed')
    plan, campaign = read(plan_path), read(directory / 'campaign.json')
    require(campaign['plan'] == plan and plan['schedule'] == expected_schedule(), 'plan differs')
    require(plan['cpu'] == 5 and plan['timeout_seconds'] == 300, 'execution limits differ')
    require(campaign['complete'] and not campaign['diagnostic_only'], 'campaign is not complete')
    require('pending_sample' not in campaign and 'error' not in campaign, 'unfinished campaign')
    rows = campaign['samples']
    require(len(rows) == 144 and len(list(directory.glob('sample-*.json'))) == 144, 'sample count differs')
    for index, (row, scheduled) in enumerate(zip(rows, expected_schedule())):
        require(row == read(directory / f'sample-{index:03}.json'), 'separate sample differs')
        validate_sample(plan, row, scheduled)
    if check_live_identities:
        for path, expected in plan['identities'].items():
            require(digest(Path(path)) == expected, 'live artifact identity changed: ' + path)
    summary = summarize(rows)
    require(summary == campaign['summary'], 'independent medians differ')
    before, after = read(directory / 'host-before.json'), read(directory / 'host-after.json')
    for host in (before, after):
        require(host['cpu'] == 5 and host['inherited_environment'] == plan['inherited_environment'],
                'host environment differs')
    start, end = datetime.fromisoformat(before['date']), datetime.fromisoformat(after['date'])
    require(end >= start, 'host clock moved backwards')
    return dict(valid=True, process_count=144, predetermined_discards=16, retained_count=128,
                identity_count=len(plan['identities']), live_identities_checked=check_live_identities,
                started=before['date'], ended=after['date'], elapsed_seconds=(end - start).total_seconds(),
                fixed_cpu_policy_equal=fixed_policy(before) == fixed_policy(after),
                affinity_equal=before['affinity'] == after['affinity'],
                campaign_sha256=digest(directory / 'campaign.json'), summary=summary, ratios=ratios(summary))


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
