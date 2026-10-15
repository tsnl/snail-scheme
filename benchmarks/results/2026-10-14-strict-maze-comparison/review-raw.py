#!/usr/bin/env python3
"""Independently audit complete Maze captures; never import the runner or run guests."""

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
BASIS = 'da8519f83f54dabb9cbfef1297bb46a29d7683b7'
INPUT_SHA256 = '90874004ae477b9a77164e83459454490a6da66a29cca6cb5d1f71e2b04bb1a9'
PLAN_SHA256 = '09f16e4cded8ee975a7426dfca357d102bb45bea4beaecff5550f052501da7e9'
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

def character_list(text):
    require(text.startswith('('), 'canonical character list missing')
    result, position = [], 1
    while True:
        while position < len(text) and text[position].isspace():
            position += 1
        require(position < len(text), 'unterminated canonical list')
        if text[position] == ')':
            require(not text[position+1:].strip(), 'extra canonical input')
            return result
        require(text.startswith('#\\', position), 'character token missing')
        if text.startswith('#\\newline', position):
            result.append(10)
            position += len('#\\newline')
        else:
            require(position+2 < len(text), 'truncated character token')
            result.append(ord(text[position+2]))
            position += 3
        require(position < len(text) and (text[position].isspace() or text[position] == ')'), 'character delimiter missing')


def expectation(plan):
    config = plan['configurations']['chez']
    data = capture(Path(config['stdin']))
    require(sha(data) == INPUT_SHA256 == plan['input_sha256'], 'canonical input identity differs')
    header = data.decode('ascii').split('\n', 3)
    require(header[:3] == ['10000', '20', '7'], 'complete count/dimensions differ')
    characters = character_list(header[3])
    require(len(characters) == 668 and characters.count(10) == 42, 'full character expectation differs')
    require(characters == plan['expected_characters'], 'frozen expectation differs from input')
    tokens = ['#\\newline' if code == 10 else '#\\space' if code == 32 else '#\\'+chr(code) for code in characters]
    rendered = 'Result: ('+' '.join(tokens)+')'
    require(rendered == plan['expected_rust_output'], 'frozen Rust expectation differs from input')
    return rendered.encode('ascii')


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


def chez_frame(output):
    lines = output.splitlines(keepends=True)
    name = b'maze:20:7:10000'
    require(len(lines) == 3 and lines[0] == b'Running '+name+b'\n', 'Chez opening frame differs')
    clocks = re.fullmatch(rb'Elapsed time: ([0-9.eE+\-]+) seconds \(([0-9.eE+\-]+)\) for '+name+rb'\n', lines[1])
    require(clocks is not None and lines[2].startswith(b'+!CSVLINE!+chez,'+name+b','), 'Chez complete frame differs')
    csv = re.fullmatch(rb'\+!CSVLINE!\+chez,'+name+rb',([0-9.eE+\-]+)\n', lines[2])
    require(csv is not None, 'Chez timing suffix differs')
    seconds, rounded = map(float, clocks.groups())
    require(math.isfinite(rounded) and rounded >= 0 and seconds == float(csv[1]), 'Chez clocks disagree')
    return positive(seconds)


def frame(system, output, expected_rust):
    if system.startswith('snail-'):
        return json_frame(system, output)
    if system.startswith('chez'):
        return chez_frame(output)
    lines = output.splitlines(keepends=True)
    require(len(lines) == 2 and lines[0] == expected_rust+b'\n', 'full Rust result differs')
    clock = re.fullmatch(rb'\+!CSVLINE!\+rust-wasm,maze:10000,([0-9.eE+\-]+)\n', lines[1])
    require(clock is not None, 'Rust complete timing frame differs')
    return positive(float(clock[1]))


# ---- Count observed rotations and frozen dependencies without runner helpers ----

def check_schedule(plan):
    rows = plan['schedule']
    require(plan['systems'] == list(SYSTEMS) and len(rows) == 56, 'seven-system population differs')
    require([row['index'] for row in rows] == list(range(56)), 'row identities differ')
    warmups = [dict(index=i, system=system, phase='discarded-warmup', round=-1, position=i)
               for i, system in enumerate(SYSTEMS)]
    require(rows[:7] == warmups, 'fixed discarded warmups differ')
    for index, row in enumerate(rows[7:]):
        round_number, position = divmod(index, 7)
        require(row == dict(index=index+7, system=SYSTEMS[(round_number+position) % 7],
                            phase='measurement', round=round_number, position=position), 'cyclic row differs')
    positions = [Counter(row['system'] for row in rows[7:] if row['position'] == position) for position in range(7)]
    require(all(counts == Counter(SYSTEMS) for counts in positions), 'retained position balance differs')
    return rows


def verify_manifest(plan):
    require(plan['cpu'] == 5 and plan['rounds'] == 7 and plan['timeout_seconds'] == 120, 'control settings differ')
    require(plan['compiler_commit'] == BASIS and plan['gc_policy'] == 'current growing precise collector', 'source/GC basis differs')
    require(plan['environment'] == {'BINARYEN_CORES':'1'}, 'explicit environment differs')
    require(plan['input_count'] == 10000 and plan['dimensions'] == [20, 7], 'canonical configuration differs')
    require(plan['warmup_processes'] == 7 and plan['measured_processes'] == 49, 'retained counts differ')
    for name, expected in plan['identities'].items():
        require(sha(capture(Path(name))) == expected, 'frozen dependency changed: '+name)


# ---- Admit clocks only after invocation, terminal status and raw captures agree ----

def check_invocation(record, expected, plan):
    for key, value in expected.items():
        require(type(record[key]) is type(value) and record[key] == value, 'scheduled row differs: '+key)
    for key, value in plan['configurations'][expected['system']].items():
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
    seconds = frame(record['system'], data['stdout'], expected_rust)
    require(seconds == record['workload_seconds'], 'runner interpreted raw frame differently')
    return seconds


def read_samples(campaign, report, plan, expected_rust):
    scheduled = check_schedule(plan)
    require(len(report['samples']) == 56, 'campaign sample record count differs')
    inventory = sorted(path.name for path in campaign.glob('sample-*'))
    require(inventory == [f'sample-{index:03}' for index in range(56)], 'sample directory inventory differs')
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


# ---- Recompute seven medians and ranges; ratios describe this one workload ----

def recompute(rows):
    systems = {}
    for system in SYSTEMS:
        retained = [row for row in rows if row['system'] == system and row['phase'] == 'measurement']
        require([row['round'] for row in retained] == list(range(7)), 'retained population differs')
        seconds = [row['seconds'] for row in retained]
        systems[system] = dict(samples=7, median=statistics.median(seconds), range=[min(seconds), max(seconds)])
    original = systems['chez']['median']
    ratio = systems['snail-native64']['median']/systems['snail-identical-wasm-v8']['median']
    comparisons = dict(system_over_original_chez={name: values['median']/original for name, values in systems.items()},
                       native_over_identical_wasm_v8=ratio, native_percent_less_time=100*(1-ratio))
    return dict(systems=systems, comparisons=comparisons)


def audit(campaign):
    plan = read(REPORT/'timing-plan.json')
    require(READS[str(REPORT/'timing-plan.json')] == PLAN_SHA256, 'reviewed plan digest differs')
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
    return dict(passed=True, guests_started=False, processes=56, warmups=7, retained=49,
        plan_sha256=report['plan_sha256'], summary=summary, host_cpu=[before['cpu'],after['cpu']],
        rows=rows, capture_sha256=dict(READS), review_code_sha256=sha(Path(__file__).read_bytes()))


# ---- Tests ----

def reject_corruptions(system, original, expected_rust):
    broken = [original+b'\n', original[:-1], b'\xff\n', original.replace(b'seconds', b'unexpected', 1)]
    if system.startswith('rust-'):
        broken[-1] = original.replace(b'#\\space', b'#\\_', 1)
    if system.startswith('snail-'):
        broken += [original.replace(b'"result":1', b'"result":true'),
                   original.replace(b'"result":1', b'"result":1.0'),
                   original.replace(b'"result":1', b'"result":1,"result":1'),
                   b'{"result":1,"seconds":NaN}\n', b'{"result":1,"seconds":0}\n']
    for output in broken:
        try:
            frame(system, output, expected_rust)
        except (ValueError, UnicodeError):
            continue
        raise AssertionError('independent parser accepted corrupt complete frame: '+system)
    return len(broken)


def protocol_self_test():
    plan = read(REPORT/'timing-plan.json')
    expected_rust = expectation(plan)
    check_schedule(plan)
    frames, corruptions = {}, 0
    for system, record_path in plan['protocol_records'].items():
        directory = Path(record_path).parent
        require(capture(directory/'stderr.bin') == b'', 'preparation stderr differs')
        output = capture(directory/'stdout.bin')
        frames[system] = positive(frame(system, output, expected_rust))
        corruptions += reject_corruptions(system, output, expected_rust)
    require(set(frames) == set(SYSTEMS), 'full replay population differs')
    return dict(passed=True, guests_started=False, complete_frames=7, corruptions=corruptions,
                canonical_characters=668, canonical_newlines=42, capture_sha256=dict(READS),
                review_code_sha256=sha(Path(__file__).read_bytes()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--campaign', type=Path)
    parser.add_argument('--protocol-self-test', action='store_true')
    parser.add_argument('--output', type=Path, default=REPORT/'independent-review.json')
    arguments = parser.parse_args()
    if arguments.protocol_self_test:
        result = protocol_self_test()
    elif arguments.campaign:
        result = audit(arguments.campaign.resolve())
    else:
        parser.error('--campaign or --protocol-self-test is required')
    with arguments.output.open('x') as target:
        target.write(json.dumps(result, indent=2, allow_nan=False)+'\n')
    print('PASS independent canonical-input/frame/schedule review; no guest started')


if __name__ == '__main__':
    main()
