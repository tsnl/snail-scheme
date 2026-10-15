#!/usr/bin/env python3
"""Audit the saved bigint loop ablation and separate diagnostics without guests."""

import argparse
from collections import Counter
from datetime import datetime
import hashlib
from importlib.machinery import PathFinder
import json
import math
from pathlib import Path
import re
import statistics

WORKLOADS = ('pi', 'chudnovsky')
VARIANTS = ('original', 'original-roundtrip', 'original-roundtrip-optimized',
            'backedge', 'backedge-optimized')
PLAN_SHA = 'c7f8235eb8e0f0e3697cf891a6b87a9f5fc60cbd0f2895bffa61849bf3da5b1a'
RUNNER_SHA = 'f239876433e5c9db33a7901e527a0931ebe3b65a8995fc3c00d6b135fc01c99d'
DRIVER_SHA = '1607e9f88521fe88ee707ffceaf8e1554a3cd4154251c28bcb0b5811a20df4ea'
INTEGER_SHA = '6954e2b5414e3baf093f6bb11f9a2ebe42d60bff0c1fd2900a979f15395da8cc'
NUMBER = r'[0-9]+(?:\.[0-9]+)?(?:[eE][+\-]?[0-9]+)?'


# ---- Frozen artifacts and the complete predeclared rotation ----

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
    return [dict(benchmark=name, system=VARIANTS[(position + max(round_number, 0)) % 5],
                 position=position, round=round_number, retained=round_number >= 0)
            for name in WORKLOADS for round_number in range(-1, 10) for position in range(5)]


def verify_supervision(preparation, plan):
    require(digest(preparation / 'integer-measure.py') == DRIVER_SHA, 'integer measurement driver differs')
    directory = (preparation / 'supervisor').resolve()
    require(sorted(path.stem for path in directory.glob('*.py')) == ['data_ports', 'matrix_port'],
            'supervision inventory differs')
    for name in ('data_ports', 'matrix_port'):
        path = directory / (name + '.py')
        spec = PathFinder.find_spec(name, [str(directory)])
        require(spec is not None and Path(spec.origin).resolve() == path, 'supervision import origin differs')
        require(digest(path) == plan['identities'][str(Path(plan['supervisor']) / path.name)],
                'supervision module differs')


def verify_preparation(preparation):
    require(digest(preparation / 'timing-plan.json') == PLAN_SHA
            and digest(preparation / 'measure.py') == RUNNER_SHA, 'frozen plan or runner differs')
    plan = read(preparation / 'timing-plan.json')
    require(len(plan['identities']) == 35 and plan['cpu'] == 5 and plan['timeout_seconds'] == 60,
            'identity count or execution policy differs')
    original = Path(plan['systems']['pi']['original']['command'][2]).parents[1]
    for name, expected in plan['identities'].items():
        path = Path(name)
        if path.is_relative_to(original):
            require(digest(preparation / path.relative_to(original)) == expected, 'archived frozen artifact differs')
    verify_supervision(preparation, plan)
    require(digest(preparation / 'integer.sld') == INTEGER_SHA, 'frozen arithmetic source differs')
    for name in WORKLOADS:
        require(read(preparation / 'specifications' / name / 'full.json') == plan['workloads'][name],
                'full workload specification differs')
    host = plan['systems']['pi']['original']['command'][1]
    require(digest(preparation / 'integer-control-host.mjs') == plan['identities'][host], 'frozen timing host differs')
    return plan


# ---- Exact complete output and recorded process ownership ----

def validate_invocation(plan, row, scheduled, diagnostic):
    require(all(type(row[key]) is type(value) and row[key] == value
                for key, value in scheduled.items()), 'sample schedule differs')
    config = plan['systems'][row['benchmark']][row['system']]
    require(row['command'] == [plan['taskset'], '-c', '5', *config['command']], 'command differs')
    require(row['cwd'] == config['cwd'] and row['environment'] == plan['environment'], 'execution context differs')
    require(row['inherited_environment'] == plan['inherited_environment'], 'inherited environment differs')
    require(row['diagnostic_only'] is diagnostic, 'diagnostic classification differs')


def validate_process(row):
    require(row['status'] == 'valid' and type(row['returncode']) is int and row['returncode'] == 0,
            'unsuccessful process')
    require(row['stderr'] == '' and row['timeout'] is False and row['executing_descendants'] == [],
            'invalid process evidence')
    require(not {'error', 'stop_signal'} & row.keys(), 'failed or interrupted sample')
    require(type(row['pid']) is int and row['pid'] > 0, 'invalid process identity')
    expected = dict(process_group=row['pid'], live_members=[], leader_reaped=True,
                    capture_handles_closed=True, zombies_count_as_stopped=True)
    require(row['cleanup'] == expected and row['process_group'] == row['pid'], 'ownership cleanup differs')
    require(positive_duration(row['workload_seconds']) <= positive_duration(row['process_seconds']),
            'workload clock exceeds process clock')


def output_seconds(plan, name, text):
    workload = plan['workloads'][name]
    prefix = workload['output'] + f'+!CSVLINE!+snail-integer,{name}:{workload["count"]},'
    match = re.fullmatch(re.escape(prefix) + '(' + NUMBER + r')\n', text)
    require(match is not None, 'complete numerical output or clock framing differs')
    return positive_duration(float(match[1]))


def validate_samples(directory, plan, diagnostic):
    campaign = read(directory / 'campaign.json')
    schedule = [row for row in expected_schedule() if row['round'] == -1] if diagnostic else expected_schedule()
    require(campaign['plan'] == plan and campaign['complete'] is True
            and campaign['diagnostic_only'] is diagnostic, 'incomplete or different campaign')
    require(not {'pending_sample', 'error'} & campaign.keys(), 'campaign failed')
    require(len(campaign['samples']) == len(schedule) and {path.name for path in directory.glob('sample-*.json')}
            == {f'sample-{index:03}.json' for index in range(len(schedule))}, 'sample inventory differs')
    for index, (row, scheduled) in enumerate(zip(campaign['samples'], schedule)):
        require(row == read(directory / f'sample-{index:03}.json'), 'separate sample differs')
        validate_invocation(plan, row, scheduled, diagnostic)
        validate_process(row)
        require(output_seconds(plan, row['benchmark'], row['stdout']) == row['workload_seconds'],
                'saved workload duration differs')
    return campaign


# ---- Balanced retained medians and the coordinator's independent evidence ----

def summarize(rows):
    summary = {}
    for name in WORKLOADS:
        summary[name] = {}
        for variant in VARIANTS:
            chosen = [row for row in rows if row['benchmark'] == name and row['system'] == variant and row['retained']]
            require(len(chosen) == 10 and Counter(row['position'] for row in chosen) == dict.fromkeys(range(5), 2),
                    'retained positions are not balanced')
            work = [row['workload_seconds'] for row in chosen]
            summary[name][variant] = dict(samples=10, median=statistics.median(work), range=[min(work), max(work)])
    return summary


def ratios(summary):
    result = {}
    for name, values in summary.items():
        times = {variant: row['median'] for variant, row in values.items()}
        result[name] = dict(backedge_over_roundtrip=times['backedge'] / times['original-roundtrip'],
            optimized_backedge_over_optimized_roundtrip=times['backedge-optimized'] / times['original-roundtrip-optimized'],
            optimized_backedge_over_frozen_original=times['backedge-optimized'] / times['original'],
            roundtrip_over_original=times['original-roundtrip'] / times['original'],
            extra_optimization_over_roundtrip=times['original-roundtrip-optimized'] / times['original-roundtrip'])
    return result


def fixed_policy(host):
    return {name: value for name, value in host['policy'].items()
            if not name.endswith('/scaling_cur_freq')}


def host_evidence(directory, plan, rows):
    before, after = read(directory / 'host-before.json'), read(directory / 'host-after.json')
    require(all(host['cpu'] == 5 and 5 in host['affinity']
                and host['inherited_environment'] == plan['inherited_environment'] for host in (before, after)),
            'host execution context differs')
    start, end = datetime.fromisoformat(before['date']), datetime.fromisoformat(after['date'])
    started = [datetime.fromisoformat(row['started']) for row in rows]
    require(start <= started[0] <= started[-1] <= end and started == sorted(started), 'host window differs')
    return dict(started=before['date'], ended=after['date'], elapsed_seconds=(end - start).total_seconds(),
                fixed_policy_equal=fixed_policy(before) == fixed_policy(after), affinity_equal=before['affinity'] == after['affinity'])


def verify_coordinator(directory, summary, comparison_ratios, evidence):
    parent = read(directory / 'parent-independent-review.json')
    require(parent['valid'] is True and parent['actual_owned_session'] == 61576
            and parent['actual_terminal_exit_code'] == 0, 'coordinator terminal evidence differs')
    require((parent['processes'], parent['retained'], parent['predetermined_discards'], parent['identities'])
            == (110, 100, 10, 35), 'coordinator population differs')
    require(parent['plan_sha256'] == PLAN_SHA and parent['campaign_sha256'] == digest(directory / 'campaign.json'),
            'coordinator campaign differs')
    require(parent['summary'] == summary and parent['ratios'] == comparison_ratios, 'coordinator statistics differ')
    require(all(parent[name] == value for name, value in evidence.items()), 'coordinator host evidence differs')


# ---- Separate correctness and whole-process sampling diagnostics ----

def function85(text):
    start, depth = text.index('(func $function85 '), 0
    for end in range(start, len(text)):
        depth += (text[end] == '(') - (text[end] == ')')
        if depth == 0:
            return text[start:end + 1]
    raise ValueError('unterminated function85')


def probe_scope(preparation):
    for name in WORKLOADS:
        original = function85((preparation / name / 'original.wat').read_text())
        changed = function85((preparation / name / 'backedge.wat').read_text())
        proof = read(preparation / name / 'transformation.json')
        require(proof['function'] == 'function85' and proof['changed_calls'] == 1
                and hashlib.sha256(original.encode()).hexdigest() == proof['original_function_sha256'], 'target function differs')
        require(original.count('(return_call $function85') == 1 and '(return_call $function85' not in changed
                and '(local $next7 i64)' in changed and '(local $next8 i64)' in changed, 'scalar backedge replacement differs')
        operations = r'\((?:(?:i32|i64|array|struct)\.[^\s()]+|if|unreachable)\b'
        require(Counter(re.findall(operations, original)) == Counter(re.findall(operations, changed)),
                'arithmetic, storage or guard operation counts differ')
    return dict(function='function85', changed_self_tail_calls=1, scalar_update_temporaries=2,
                arithmetic_storage_guard_counts_equal=True)


def validate_preparation_runs(preparation, plan):
    checked = 0
    for name in WORKLOADS:
        workload = plan['workloads'][name]
        for variant in VARIANTS:
            for label in ('full', 'count-0', 'count-1', 'count-2', 'wrong-result', 'wrong-final'):
                row = read(preparation / name / (variant + '-' + label + '.json'))
                require(row['returncode'] == 0 and row['stderr'] == '' and row['timeout'] is False
                        and row['executing_descendants'] == [] and row['diagnostic_only'] is True, 'preparation guest failed')
                expected = '()\n' if label == 'count-0' else workload['output']
                require(row['stdout'] == expected, 'preparation complete output differs')
                if label != 'full':
                    validate_specification(row['specification'], workload, label)
                checked += 1
    return checked


def validate_specification(specification, workload, label):
    expected = dict(workload, count=int(label[-1]) if label.startswith('count-') else 1)
    if label == 'count-0':
        expected['output'] = '()\n'
    if label.startswith('wrong-'):
        expected['expected'] = list(workload['expected'])
        index = 0 if label == 'wrong-result' else -1
        expected['expected'][index] = str(int(expected['expected'][index]) + 1)
        expected['predicate'] = 0
    require(specification == expected, 'count or negative-predicate specification differs')


def profile_evidence(directory, plan):
    result = {}
    for name in WORKLOADS:
        profile = read(directory / name / 'full.cpuprofile')
        frames = {node['id']: node['callFrame'] for node in profile['nodes']}
        require(len(profile['samples']) == len(profile['timeDeltas']) and len(frames) == len(profile['nodes']),
                'profile sample framing differs')
        samples = [(frames[node]['functionName'], delta) for node, delta in zip(profile['samples'], profile['timeDeltas'])]
        require(all(type(delta) is int and delta > 0 for _, delta in samples), 'invalid profile sample weight')
        total = sum(delta for _, delta in samples)
        target = [delta for function, delta in samples if function == 'function85']
        row = next(row for row in read(directory / name / 'function-summary.json') if row['function'] == 'function85')
        require(row['samples'] == len(target) and row['weight_us'] == sum(target)
                and math.isclose(row['weight_percent'], sum(target) / total * 100, abs_tol=1e-12), 'profile summary differs')
        record = read(directory / name / 'record.json')
        require(record['diagnostic_only'] is True and record['returncode'] == 0 and record['stderr'] == '', 'profile guest failed')
        output_seconds(plan, name, record['stdout'])
        result[name] = dict(scope='whole process, not clipped to workload clock', samples=len(samples),
            total_weight_us=total, function85_samples=len(target), function85_weight_us=sum(target),
            function85_weight_percent=sum(target) / total * 100)
    return result


def code_evidence(directory, plan):
    selections = read(directory / 'selection.json')
    require({row['record'] for row in selections} == {name + '-' + variant + '.json'
            for name in WORKLOADS for variant in ('backedge', 'backedge-optimized')}, 'code capture inventory differs')
    for selection in selections:
        stem = Path(selection['record']).stem
        name, variant = stem.split('-', 1)
        row = read(directory / selection['record'])
        require(row['diagnostic_only'] is True and row['returncode'] == 0 and row['stderr'] == ''
                and row['timeout'] is False and row['executing_descendants'] == [], 'code capture guest failed')
        module = plan['systems'][name][variant]['command'][2]
        require(row['module_sha256'] == selection['module_sha256'] == plan['identities'][module], 'captured module differs')
        require(row['stdout'] == (directory / (stem + '.txt')).read_text()
                and row['stdout'].endswith(plan['workloads'][name]['output']), 'complete code capture output differs')
        expected = [('Liftoff', 1148), ('TurboFan', 892)] if variant == 'backedge' else [('Liftoff', 1760), ('TurboFan', 1960)]
        observed = [(item['compiler'], item['instruction_bytes']) for item in selection['observed']]
        body = (directory / (stem + '-selected.txt')).read_text()
        function = 'function85' if variant == 'backedge' else 'function88'
        require(row['function'] == selection['function'] == function
                and row['index'] == selection['index'], 'captured function identity differs')
        pattern = (rf'name: {function}\nindex: {row["index"]}\nkind: wasm function\n'
                   + r'compiler: (\w+)\n[^\n]*\nInstructions \(size = ([0-9]+)\)')
        decoded = [(compiler, int(size)) for compiler, size in re.findall(pattern, row['stdout'])]
        selected = [(compiler, int(size)) for compiler, size in re.findall(pattern, body)]
        require(observed == expected == decoded == selected, 'observed code tier or size differs')
    original_code_evidence(directory, plan)
    return dict(diagnostic_processes=4, raw_function='function85', raw_turbofan_bytes=892,
                original_turbofan_bytes=584, optimized_function='function88', optimized_turbofan_bytes=1960)


def original_code_evidence(directory, plan):
    sources = read(directory / 'original/sources.json')
    require(set(sources) == set(WORKLOADS), 'original capture inventory differs')
    for name, identity in sources.items():
        excerpt = directory / 'original' / identity['excerpt']
        require(digest(excerpt) == identity['excerpt_sha256'] and identity['verified_archive_member'] is True,
                'original excerpt identity differs')
        module = plan['systems'][name]['original']['command'][2]
        require(identity['module_sha256'] == plan['identities'][module], 'original captured module differs')
        body = excerpt.read_text()
        require(body.startswith('name: function85\n') and '\ncompiler: TurboFan\n' in body
                and 'Instructions (size = 584)\n' in body, 'original captured function differs')
        require(re.search(r'sarq [^\n]+, 30\b', body) and 'idiv' not in body,
                'original constant division lowering differs')


def review(campaign_directory, preparation, diagnostics, profiles, code, check_live_identities):
    plan = verify_preparation(preparation)
    require(plan['schedule'] == expected_schedule(), 'predeclared schedule differs')
    campaign = validate_samples(campaign_directory, plan, False)
    diagnostic = validate_samples(diagnostics, plan, True)
    summary = summarize(campaign['samples'])
    require(campaign['summary'] == summary, 'independent medians differ')
    comparison_ratios = ratios(summary)
    evidence = host_evidence(campaign_directory, plan, campaign['samples'])
    verify_coordinator(campaign_directory, summary, comparison_ratios, evidence)
    if check_live_identities:
        for path, expected in plan['identities'].items():
            require(digest(Path(path)) == expected, 'live identity changed: ' + path)
    return dict(valid=True, process_count=110, predetermined_discards=10, retained_count=100,
        identity_count=35, live_identities_checked=check_live_identities,
        campaign_sha256=digest(campaign_directory / 'campaign.json'), **evidence,
        summary=summary, ratios=comparison_ratios, correctness_processes=validate_preparation_runs(preparation, plan),
        diagnostic_processes=len(diagnostic['samples']), probe_scope=probe_scope(preparation),
        profiles=profile_evidence(profiles, plan), code=code_evidence(code, plan))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('campaign', type=Path)
    parser.add_argument('preparation', type=Path)
    parser.add_argument('diagnostics', type=Path)
    parser.add_argument('profiles', type=Path)
    parser.add_argument('code', type=Path)
    parser.add_argument('--check-live-identities', action='store_true')
    parser.add_argument('--output', type=Path)
    options = parser.parse_args()
    result = review(options.campaign, options.preparation, options.diagnostics, options.profiles, options.code,
                    options.check_live_identities)
    payload = json.dumps(result, indent=2) + '\n'
    if options.output:
        options.output.write_text(payload)
    else:
        print(payload, end='')


if __name__ == '__main__':
    main()
