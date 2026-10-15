#!/usr/bin/env python3
"""Independently audit complete Boyer captures; never import the runner or run guests."""

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import re
import statistics

REPORT = Path(__file__).resolve().parent
ROOT = REPORT.parents[2]
SYSTEMS = ('snail-production-v8', 'snail-native64', 'snail-identical-wasm-v8',
           'chez', 'chez-adapted', 'rust-native', 'rust-optimized-wasm')
BASIS = 'a7079746aa9c79c0cdcd10862a630fa7f2082134'
BENCHMARKS = ('nboyer','sboyer')
INPUT_SHA256 = {'nboyer':'b71987258638074bb13ede6d586e5764b0a6cbb742b97807aad15996132f4c88',
                'sboyer':'d6f1f85be211a2a8e6ad5b6216d1ed925b7be175d48cb8b6910de02435050be6'}
READS = {}
CAPTURE_OWNERS = set()


# ---- Every reviewed byte sequence is bound to its content identity ----

def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def capture(path):
    data = path.read_bytes()
    READS[str(path)] = sha(data)
    return data


def distinct(pairs):
    value = {}
    for name, item in pairs:
        require(name not in value, 'duplicate JSON key: '+name)
        value[name] = item
    return value


def read(path):
    return json.loads(capture(path), object_pairs_hook=distinct)


def positive(value):
    require(type(value) in (int, float) and math.isfinite(value) and value > 0, 'invalid positive clock')
    return value


# ---- Derive the complete result from input, independently of recorded output ----

def expectation(plan):
    for name in BENCHMARKS:
        path = Path(plan['configurations'][name]['chez']['stdin'])
        data = capture(path)
        require(sha(data)==INPUT_SHA256[name]==plan['input_sha256'][name],'full original input differs')
        tokens = re.sub(r';[^\n]*','',data.decode('ascii')).split()
        require(list(map(int,tokens[:3]))==[1,5,51507739],'original repetition/size/rewrite predicate differs')
    require(plan['input_parameters']==dict(count=1,size=5,rewrites=51507739),'frozen predicate differs from canonical input')
    return b'Result: 51507739'


def json_frame(system, output):
    require(output.endswith(b'\n') and output.count(b'\n') == 1, 'complete JSON frame differs')
    value = json.loads(output.decode('utf-8'), object_pairs_hook=distinct)
    fields = dict(result=1)
    if system == 'snail-native64':
        fields.update(barriers=0, setup_closed=1, worker_closed=0, closed=1)
    require(type(value) is dict and set(value) == set(fields) | {'seconds'}, 'JSON fields differ')
    for key, amount in fields.items():
        require(type(value[key]) is int and value[key] == amount, 'full predicate or lifecycle differs: '+key)
    return positive(value['seconds'])


def chez_frame(benchmark,output):
    lines = output.splitlines(keepends=True)
    name = (benchmark+':5:1').encode()
    require(len(lines) == 3 and lines[0] == b'Running '+name+b'\n', 'Chez opening frame differs')
    clocks = re.fullmatch(rb'Elapsed time: ([0-9.eE+\-]+) seconds \(([0-9.eE+\-]+)\) for '+name+rb'\n', lines[1])
    require(clocks is not None and lines[2].startswith(b'+!CSVLINE!+chez,'+name+b','), 'Chez complete frame differs')
    csv = re.fullmatch(rb'\+!CSVLINE!\+chez,'+name+rb',([0-9.eE+\-]+)\n', lines[2])
    require(csv is not None, 'Chez timing suffix differs')
    seconds, rounded = map(float, clocks.groups())
    require(math.isfinite(rounded) and rounded >= 0 and seconds == float(csv[1]), 'Chez clocks disagree')
    return positive(seconds)


def frame(benchmark,system,output,expected_rust):
    if system.startswith('snail-'):
        return json_frame(system, output)
    if system.startswith('chez'):
        return chez_frame(benchmark,output)
    lines = output.splitlines(keepends=True)
    require(len(lines) == 2 and lines[0] == expected_rust+b'\n', 'full Rust result differs')
    clock = re.fullmatch(rb'\+!CSVLINE!\+rust-wasm,'+re.escape(benchmark.encode())+rb':1,([0-9.eE+\-]+)\n', lines[1])
    require(clock is not None, 'Rust complete timing frame differs')
    return positive(float(clock[1]))


# ---- Count observed rotations and frozen dependencies without runner helpers ----

def check_schedule(plan):
    rows = plan['schedule']
    require(plan['systems']==list(SYSTEMS) and plan['benchmarks']==list(BENCHMARKS) and len(rows)==112,'two-workload/seven-system population differs')
    require([row['index'] for row in rows]==list(range(112)),'row identities differ')
    expected = [dict(benchmark=name,system=system,phase='discarded-warmup',round=-1,position=position)
                for name in BENCHMARKS for position,system in enumerate(SYSTEMS)]
    for number in range(7):
        workload_order = BENCHMARKS if number%2==0 else tuple(reversed(BENCHMARKS))
        for name in workload_order:
            expected.extend(dict(benchmark=name,system=SYSTEMS[(number+position)%7],phase='measurement',round=number,position=position) for position in range(7))
    require(rows==[dict(index=index,**row) for index,row in enumerate(expected)],'fixed rotation differs')
    for name in BENCHMARKS:
        retained = [row for row in rows if row['benchmark']==name and row['phase']=='measurement']
        for position in range(7):
            require(Counter(row['system'] for row in retained if row['position']==position)==Counter(SYSTEMS),'retained position balance differs')
    return rows


def verify_manifest(plan):
    require(plan['cpu'] == 5 and plan['rounds'] == 7 and plan['timeout_seconds'] == 1200, 'control settings differ')
    require(plan['compiler_commit'] == BASIS and plan['gc_policy'] == 'current growing precise collector; all policy knobs unset', 'source/GC basis differs')
    require(plan['environment'] == {'BINARYEN_CORES':'1'}, 'explicit environment differs')
    require(plan['input_parameters']==dict(count=1,size=5,rewrites=51507739),'canonical configuration differs')
    require(all(plan['inherited_environment'][name] is None for name in ('SNAIL_GC_HEAP_BYTES','SNAIL_GC_INITIAL_BYTES','SNAIL_GC_MIN_BYTES','SNAIL_GC_STATS','SNAIL_NATIVE_GC_INTERVAL')),'default GC knobs differ')
    require(plan['warmup_processes'] == 14 and plan['measured_processes'] == 98, 'retained counts differ')
    for name, expected in plan['identities'].items():
        require(sha(capture(Path(name))) == expected, 'frozen dependency changed: '+name)


# ---- Admit clocks only after invocation, terminal status and raw captures agree ----

def check_invocation(record, expected, plan):
    for key, value in expected.items():
        require(type(record[key]) is type(value) and record[key] == value, 'scheduled row differs: '+key)
    for key, value in plan['configurations'][expected['benchmark']][expected['system']].items():
        require(record[key] == value, 'actual invocation differs: '+key)
    require(record['environment'] == plan['environment'], 'explicit settings differ')
    require(record['inherited_environment'] == plan['inherited_environment'], 'recorded inherited settings differ')
    require(record['diagnostic_only'] is False, 'diagnostic data entered clean campaign')


def check_terminal(record):
    require(record['status'] == 'valid' and type(record['returncode']) is int and record['returncode'] == 0, 'unsuccessful process')
    require(record['termination'] == dict(exit_status=0, signal=None), 'actual terminal status differs')
    require(record['timeout'] is False and record['interrupted'] is False and record['stop_signal'] is None, 'stopped process')
    require(type(record['pid']) is int and record['pid'] > 0 and record['pid'] == record['process_group'], 'owned process identity differs')
    cleanup = record['cleanup']
    require(cleanup['process_group'] == record['process_group'] and cleanup['leader_reaped'] is True, 'leader/group cleanup differs')
    require(cleanup['live_members'] == [] and record['executing_descendants'] == [], 'original-group descendants were not quiescent')
    require(record['capture_complete'] is True and record['capture_handles_closed'] is True, 'incomplete captures')
    positive(record['process_seconds'])


def check_captures(directory, record, expected_rust):
    require(set(record['captures']) == {'stdout', 'stderr'}, 'capture inventory differs')
    data = {}
    for name in ('stdout', 'stderr'):
        path = directory/(name+'.bin')
        identity = (path.stat().st_dev, path.stat().st_ino)
        require(identity not in CAPTURE_OWNERS, 'two captures alias the same file')
        CAPTURE_OWNERS.add(identity)
        data[name] = capture(path)
        expected = record['captures'][name]
        recorded_path = Path(expected['path'])
        actual_path = recorded_path if recorded_path.is_absolute() else ROOT/recorded_path
        require(actual_path == path, 'capture location differs from actual launch directory')
        require(expected['bytes'] == len(data[name]) and expected['sha256'] == sha(data[name]), 'capture identity differs')
    require(data['stderr'] == b'', 'guest wrote stderr')
    seconds = frame(record['benchmark'],record['system'],data['stdout'],expected_rust)
    require(seconds == record['workload_seconds'], 'runner interpreted raw frame differently')
    return seconds


def read_samples(campaign, report, plan, expected_rust):
    scheduled = check_schedule(plan)
    require(len(report['samples']) == 112, 'campaign sample record count differs')
    inventory = sorted(path.name for path in campaign.glob('sample-*'))
    require(inventory == [f'sample-{index:03}' for index in range(112)], 'sample directory inventory differs')
    rows = []
    for expected, recorded in zip(scheduled, report['samples']):
        directory = campaign/f'sample-{expected["index"]:03}'
        require(directory.is_dir() and not directory.is_symlink(), 'sample directory alias')
        require(all((directory/name).is_file() and not (directory/name).is_symlink()
                    for name in ('record.json', 'stdout.bin', 'stderr.bin')), 'capture/record alias or nonregular file')
        record = read(directory/'record.json')
        require(record == recorded, 'individual and campaign process records disagree')
        check_invocation(record, expected, plan)
        check_terminal(record)
        rows.append(dict(**expected, seconds=check_captures(directory, record, expected_rust)))
    return rows


# ---- Independently recompute both workloads from their complete retained rows ----

def recompute(rows):
    return {name:recompute_workload(name,rows) for name in BENCHMARKS}


def recompute_workload(benchmark,rows):
    systems = {}
    for system in SYSTEMS:
        retained = [row for row in rows if row['benchmark']==benchmark and row['system'] == system and row['phase'] == 'measurement']
        require([row['round'] for row in retained] == list(range(7)), 'retained population differs')
        seconds = [row['seconds'] for row in retained]
        systems[system] = dict(samples=7, median=statistics.median(seconds), range=[min(seconds), max(seconds)])
    original = systems['chez']['median']
    ratio = systems['snail-native64']['median']/systems['snail-identical-wasm-v8']['median']
    comparisons = dict(system_over_original_chez={name: values['median']/original for name, values in systems.items()},
                       native_over_identical_wasm_v8=ratio, native_percent_less_time=100*(1-ratio))
    return dict(systems=systems, comparisons=comparisons)


def audit(campaign,expected_plan_sha256):
    plan = read(REPORT/'timing-plan.json')
    require(READS[str(REPORT/'timing-plan.json')] == expected_plan_sha256, 'reviewed plan digest differs')
    report = read(campaign/'campaign.json')
    require(report['complete'] is True and report['diagnostic_only'] is False, 'completed clean campaign required')
    require(report['plan_sha256'] == READS[str(REPORT/'timing-plan.json')], 'campaign plan identity differs')
    require(report['coordinated_release'], 'quiet-window release evidence missing')
    verify_manifest(plan)
    rows = read_samples(campaign, report, plan, expectation(plan))
    summary = recompute(rows)
    require(summary == report['summary'], 'independent summary differs')
    before, after = read(campaign/'host-before.json'), read(campaign/'host-after.json')
    require(before['cpu'] == after['cpu'] == 5, 'host CPU record differs')
    return dict(passed=True, guests_started=False, processes=112, warmups=14, retained=98,
        plan_sha256=report['plan_sha256'], summary=summary, host_cpu=[before['cpu'],after['cpu']],
        rows=rows, capture_sha256=dict(READS), review_code_sha256=sha(Path(__file__).read_bytes()))


# ---- Tests ----

def reject_corruptions(benchmark,system,original,expected_rust):
    broken = [original+b'\n', original[:-1], b'\xff\n', original.replace(b'seconds', b'unexpected', 1)]
    if system.startswith('rust-'):
        broken[-1] = original.replace(b'51507739',b'51507738',1)
    if system.startswith('snail-'):
        broken += [original.replace(b'"result":1', b'"result":true'),
                   original.replace(b'"result":1', b'"result":1.0'),
                   original.replace(b'"result":1', b'"result":1,"result":1'),
                   b'{"result":1,"seconds":NaN}\n', b'{"result":1,"seconds":0}\n']
    for output in broken:
        try:
            frame(benchmark,system,output,expected_rust)
        except (ValueError, UnicodeError):
            continue
        raise AssertionError('independent parser accepted corrupt complete frame: '+system)
    return len(broken)


def protocol_self_test(expected_plan_sha256):
    plan = read(REPORT/'timing-plan.json')
    require(READS[str(REPORT/'timing-plan.json')]==expected_plan_sha256,'reviewed plan digest differs')
    expected_rust = expectation(plan)
    check_schedule(plan)
    frames,corruptions = {},0
    for benchmark,records in plan['protocol_records'].items():
        frames[benchmark] = {}
        for system,record_path in records.items():
            directory = Path(record_path).parent
            require(capture(directory/'stderr.bin')==b'','preparation stderr differs')
            output = capture(directory/'stdout.bin')
            frames[benchmark][system] = positive(frame(benchmark,system,output,expected_rust))
            corruptions += reject_corruptions(benchmark,system,output,expected_rust)
        require(set(frames[benchmark])==set(SYSTEMS),'full replay population differs')
    require(set(frames)==set(BENCHMARKS),'full workload population differs')
    return dict(passed=True,guests_started=False,complete_frames=14,corruptions=corruptions,
        input_parameters=dict(count=1,size=5,rewrites=51507739),capture_sha256=dict(READS),
        review_code_sha256=sha(Path(__file__).read_bytes()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--campaign', type=Path)
    parser.add_argument('--expected-plan-sha256',required=True)
    parser.add_argument('--protocol-self-test', action='store_true')
    parser.add_argument('--output', type=Path, default=REPORT/'independent-review.json')
    arguments = parser.parse_args()
    if arguments.protocol_self_test:
        result = protocol_self_test(arguments.expected_plan_sha256)
    elif arguments.campaign:
        result = audit(arguments.campaign.resolve(),arguments.expected_plan_sha256)
    else:
        parser.error('--campaign or --protocol-self-test is required')
    with arguments.output.open('x') as target:
        target.write(json.dumps(result, indent=2, allow_nan=False)+'\n')
    print('PASS independent canonical-input/frame/schedule review; no guest started')


if __name__ == '__main__':
    main()
