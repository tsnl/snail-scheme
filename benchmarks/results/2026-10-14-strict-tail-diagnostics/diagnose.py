"""Profile the frozen complete Tail guest, outside clean timing samples."""

import datetime
from collections import Counter, defaultdict
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import time


# ---- Exact original programs and complete file contract ----

ROOT = Path('/tmp/snail-tail-diagnostics-20261014')
BUILD = ROOT / 'build/tail-diagnostics'
PREPARATION = Path('/tmp/snail-strict-tail-20261014/build/strict-tail-final')
CASE = PREPARATION / 'tail'
EVIDENCE = Path('/tmp/snail-strict-tail-20261014/build/tail-evidence')
NODE = '/nix/store/lfaydgacdyngci7p60s8wwvgdm74fjkx-nodejs-24.19.0/bin/node'
TASKSET = '/run/current-system/sw/bin/taskset'
REMOVED = ['NODE_OPTIONS', 'NODE_V8_COVERAGE', 'NODE_DEBUG', 'NODE_DEBUG_NATIVE']


def load(path):
    return json.loads(Path(path).read_text())


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n')


def identity(path):
    return dict(path=str(path), sha256=hashlib.sha256(Path(path).read_bytes()).hexdigest())


def original_files():
    prepared = load(PREPARATION / 'prepared.json')
    paths = [PREPARATION / 'prepared.json', PREPARATION / 'tail-host.mjs', NODE, TASKSET]
    paths += [CASE / leaf for leaf in prepared['cases'][0]['hashes']]
    paths += [PREPARATION / 'compiler-source' / leaf for leaf in prepared['compiler_files']]
    return [identity(path) for path in paths]


def require_original_files():
    prepared = load(PREPARATION / 'prepared.json')
    for directory, hashes in [(CASE, prepared['cases'][0]['hashes']),
                              (PREPARATION / 'compiler-source', prepared['compiler_files'])]:
        for leaf, expected in hashes.items():
            assert identity(directory / leaf)['sha256'] == expected, leaf
    assert identity(CASE / 'strict.wasm')['sha256'] == '23de40d54791743841fe3e9e93336872bd34ef6a8858607b136eb4cb92d2e33d'
    assert identity(PREPARATION / 'tail-host.mjs')['sha256'] == prepared['tail_host_sha256']


# ---- Sampling brackets the benchmark after initialization ----

PROFILE_HEADER = '''import inspector from 'node:inspector';
const diagnosticsSession = new inspector.Session();
diagnosticsSession.connect();
const diagnosticsMarkers = {clock_domain: 'Node process.hrtime.bigint nanoseconds', sampling_interval_us: 1000};
let diagnosticsStarted = false, diagnosticsProfile;
const profiler = (method, parameters = {}) => new Promise((resolve, reject) => {
  diagnosticsSession.post(method, parameters, (error, value) => error ? reject(error) : resolve(value));
});
'''

PROFILE_START = '''  await profiler('Profiler.enable');
  await profiler('Profiler.setSamplingInterval', {interval: 1000});
  diagnosticsMarkers.start_submission_ns = process.hrtime.bigint().toString();
  await profiler('Profiler.start');
  diagnosticsStarted = true;
  diagnosticsMarkers.start_acknowledgement_ns = process.hrtime.bigint().toString();
'''

PROFILE_STOP = '''  const diagnosticsClockStop = process.hrtime.bigint();
  const seconds = Number(diagnosticsClockStop - start) / 1e9;
  diagnosticsMarkers.clock_start_ns = start.toString();
  diagnosticsMarkers.clock_stop_ns = diagnosticsClockStop.toString();
  diagnosticsMarkers.stop_submission_ns = process.hrtime.bigint().toString();
  diagnosticsProfile = (await profiler('Profiler.stop')).profile;
  diagnosticsMarkers.stop_completion_ns = process.hrtime.bigint().toString();
  diagnosticsStarted = false;'''

PROFILE_SAVE = '''if (diagnosticsStarted) {
  try { diagnosticsProfile = (await profiler('Profiler.stop')).profile; }
  catch (error) { diagnosticsMarkers.failure = String(error); }
  diagnosticsMarkers.failed_window_may_include_cleanup = true;
}
diagnosticsSession.disconnect();
if (diagnosticsProfile) fs.writeFileSync(process.argv[5] + '/profile.cpuprofile', JSON.stringify(diagnosticsProfile));
fs.writeFileSync(process.argv[5] + '/profile-window.json', JSON.stringify(diagnosticsMarkers));
'''


def make_profile_host():
    original = (EVIDENCE / 'retention-host.mjs').read_text()
    changes = [('import fs', PROFILE_HEADER + 'import fs'),
               ('  const start = process.hrtime.bigint();', PROFILE_START + '  const start = process.hrtime.bigint();'),
               ('  const seconds = Number(process.hrtime.bigint() - start) / 1e9;', PROFILE_STOP),
               ('if (failure) throw failure;', PROFILE_SAVE + 'if (failure) throw failure;'),
               ('if (status === 0) readBytes +=', "if (status === 0 && live.get(args[0]) === config.pathnames[0]) readBytes +=")]
    text = original
    for before, after in changes:
        assert text.count(before) == 1
        text = text.replace(before, after)
    erased = text
    for before, after in reversed(changes):
        assert erased.count(after) == 1
        erased = erased.replace(after, before)
    assert erased == original
    (BUILD / 'profile-host.mjs').write_text(text)
    save(BUILD / 'profile-host-proof.json', dict(exact_erasure=True, original=identity(EVIDENCE / 'retention-host.mjs'),
         canonical_host=identity(PREPARATION / 'tail-host.mjs'), inherited_erasure=load(EVIDENCE / 'retained-work.json'), changes=changes))


# ---- Raw attempts precede all parsing and complete byte checks ----

def seed_files(directory):
    (directory / 'inputs').mkdir(parents=True, exist_ok=False)
    (directory / 'outputs').mkdir()
    (directory / 'inputs/bib').write_bytes((CASE / 'upstream-input.bin').read_bytes())
    assert not (directory / 'outputs/tail.output').exists()


def execute(command, directory, output):
    environment = {k: v for k, v in os.environ.items() if k not in REMOVED}
    assert not environment.get('LD_PRELOAD')
    record = dict(command=command, cwd=str(directory), status='started', performance_samples=False,
                  started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), identities_before=original_files())
    save(output, record)
    started = time.monotonic()
    try:
        process = subprocess.run(command, cwd=directory, env=environment, input=(CASE / 'input.txt').read_bytes(),
                                 capture_output=True, timeout=900)
        outcome, stdout, stderr = dict(status='exited', returncode=process.returncode), process.stdout, process.stderr
    except subprocess.TimeoutExpired as error:
        outcome, stdout, stderr = dict(status='timeout', returncode=None), error.stdout or b'', error.stderr or b''
    except OSError as error:
        outcome, stdout, stderr = dict(status='launch-failed', returncode=None, error=repr(error)), b'', b''
    (directory / 'stdout.bin').write_bytes(stdout)
    (directory / 'stderr.bin').write_bytes(stderr)
    record.update(outcome, diagnostic_process_seconds=time.monotonic() - started,
                  stdout_raw=identity(directory / 'stdout.bin'), stderr_raw=identity(directory / 'stderr.bin'))
    save(output, record)
    record.update(stdout=stdout.decode(), stderr=stderr.decode())
    save(output, record)
    return record


def validate_files_and_lifecycle(record):
    assert record['returncode'] == 0 and not record['stderr'], record
    assert record['stdout'].endswith('\n') and len(record['stdout'].splitlines()) == 1
    result = json.loads(record['stdout'])
    assert result['result'] == '1' and result['barriers'] == 100
    assert math.isfinite(result['seconds']) and result['seconds'] >= 0
    assert result['read_bytes'] == result['written_bytes'] == 223002800
    ordinary = [['open', 'inputs/bib', 0], ['delete', 0], ['open', 'outputs/tail.output', 0],
                ['close', 'outputs/tail.output', 0], ['close', 'inputs/bib', 0]]
    first = [ordinary[index] for index in (0, 2, 3, 4)]
    assert [event for event in result['events'] if event[0] != 'eof'] == first + ordinary * 49
    directory = Path(record['cwd'])
    assert (directory / 'inputs/bib').read_bytes() == (CASE / 'upstream-input.bin').read_bytes()
    actual = directory / 'outputs/tail.output'
    assert actual.read_bytes() == (CASE / 'canonical-output.bin').read_bytes()
    record.update(valid=True, output=dict(identity(actual), bytes=actual.stat().st_size), lifecycle_complete=True,
                  diagnostic_workload_seconds=result['seconds'], identities_after=original_files())
    assert record['identities_before'] == record['identities_after']
    return result


def profile():
    require_original_files()
    make_profile_host()
    directory = BUILD / 'profile'
    seed_files(directory)
    save(BUILD / 'profile-spec.json', dict(load(CASE / 'spec.json'), trace=True))
    command = [TASKSET, '-c', '5', NODE, '--no-warnings', str(BUILD / 'profile-host.mjs'),
               str(CASE / 'strict.wasm'), str(BUILD / 'profile-spec.json'), '--validate', str(directory)]
    output = BUILD / 'profile-run.json'
    record = execute(command, directory, output)
    try:
        validate_files_and_lifecycle(record)
        record['profile'] = identity(directory / 'profile.cpuprofile')
        record['profile_window'] = load(directory / 'profile-window.json')
    except Exception as error:
        record['validation_failure'] = repr(error)
        raise
    finally:
        save(output, record)
    print('PASS exact guest profile: full50, complete bytes and file lifecycles')


# ---- Separate counters preserve evaluated operands and original declarations ----

class CounterText:
    def __init__(self, original):
        self.original, self.text, self.changes, self.counters = original, original, [], {}

    def replace(self, before, after):
        assert self.text.count(before) == 1, before[:100]
        self.text = self.text.replace(before, after)
        self.changes.append([before, after])

    def increment(self, name, amount='(i64.const 1)'):
        self.counters[name] = 'i64; reset after main; request or completed-site boundary stated by name'
        return f'(global.set $tail_{name} (i64.add (global.get $tail_{name}) {amount}))'

    def entry(self, name, statements, local=None):
        before = expression(self.text, self.text.index('\n (func ' + name + ' ') + 2)
        lines, index = before.splitlines(keepends=True), 1
        while lines[index].startswith('  (local '):
            index += 1
        additions = ([f'  (local {local} i32)\n'] if local else []) + ['  ' + x + '\n' for x in statements]
        after = ''.join(lines[:index] + additions + lines[index:])
        self.replace(before, after)


def expression(text, start):
    depth = 0
    for index in range(start, len(text)):
        if text[index] == '(':
            depth += 1
        elif text[index] == ')':
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
    raise ValueError('unclosed instruction')


def completed_constructor(counter, prefix, name, result_type):
    before = expression(counter.text, counter.text.index(prefix))
    after = f'(block (result (ref {result_type}))\n{before}\n{counter.increment(name)})'
    counter.replace(before, after)


def completed_array(counter, before, name, result_type):
    start = before.index('(')
    length_start = before.index('\n', start) + 1
    length = before[length_start:before.rfind(')')].strip()
    captured = before.replace(length, f'(local.tee $tail_length {length})')
    statements = [counter.increment(name), counter.increment(name + '_cells', '(i64.extend_i32_u (local.get $tail_length))')]
    after = f'(block (result (ref {result_type}))\n{captured}\n' + '\n'.join(statements) + ')'
    counter.replace(before, after)


def completed_copy(counter):
    before = expression(counter.text, counter.text.index('(array.copy $type15 $type15'))
    assert before.rstrip().endswith('(local.get $3)\n     )')
    captured = before.replace('(local.get $3)\n     )', '(local.tee $tail_length (local.get $3))\n     )')
    statements = [counter.increment('array_copy_completed'),
                  counter.increment('array_copy_cells', '(i64.extend_i32_u (local.get $tail_length))')]
    counter.replace(before, '(block\n' + captured + '\n' + '\n'.join(statements) + ')')


def build_counters():
    require_original_files()
    counter = CounterText((CASE / 'strict.wasm.wat').read_text())
    counter.entry('$snail:io/read-character', [counter.increment('scalar_read_requests')])
    counter.entry('$snail:io/write-character', [counter.increment('scalar_write_requests')])
    counter.entry('$function61', [counter.increment('line_reader_entries')])
    counter.entry('$function57', [counter.increment('output_loop_entries')])
    counter.entry('$string-new', [counter.increment('string_requests'),
                  counter.increment('requested_i32_cells', '(i64.extend_i32_u (local.get $0))')], '$tail_length')
    counter.entry('$string-copy-forward', [counter.increment('copy_service_requests'),
                  counter.increment('copy_service_cells', '(i64.extend_i32_u (local.get $2))')], '$tail_length')
    for register, name in [('$3', 'trim_requests'), ('$11', 'growth_requests')]:
        owner = expression(counter.text, counter.text.index('\n (func $function52 ') + 2)
        calls = [expression(owner, match.start()) for match in re.finditer(r'\(call \$string-new\b', owner)]
        matches = [call for call in calls if f'(local.get {register})' in call]
        assert len(matches) == 1
        before = matches[0]
        counter.replace(before, '(block (result (ref $type14))\n' + counter.increment(name) + '\n' + before + ')')
    for prefix, name, type_name in [('(struct.new $type42', 'line_values_completed', '$type42'),
                                   ('(struct.new_default $type41)', 'eof_values_completed', '$type41'),
                                   ('(struct.new $type23', 'list_nodes_completed', '$type23')]:
        completed_constructor(counter, prefix, name, type_name)
    for prefix, name, type_name in [('(array.new_default $type16', 'directory_arrays_completed', '$type16'),
                                   ('(array.new_default $type15\n       (local.tee $4', 'secondary_arrays_completed', '$type15'),
                                   ('(array.new_default $type15\n    (local.get $3)', 'primary_arrays_completed', '$type15')]:
        completed_array(counter, expression(counter.text, counter.text.index(prefix)), name, type_name)
    completed_copy(counter)
    definitions = ''.join(f' (global $tail_{name} (mut i64) (i64.const 0))\n'
                  f' (export "tail-counter.{name}" (global $tail_{name}))\n' for name in counter.counters)
    closing = counter.text.rfind(')')
    counter.replace(counter.text[closing:], definitions + counter.text[closing:])
    erased = counter.text
    for before, after in reversed(counter.changes):
        assert erased.count(after) == 1
        erased = erased.replace(after, before)
    assert erased == counter.original
    (BUILD / 'counter.wat').write_text(counter.text)
    save(BUILD / 'counter-proof.json', dict(exact_erasure=True, original=identity(CASE / 'strict.wasm.wat'),
         sites=counter.counters, changes=counter.changes, no_reoptimization=True, appended_scalar_locals_and_globals=True))
    optimizer = load(CASE / 'strict.wasm.link.json')[-2]['command']
    features = [x for x in optimizer if x == '--mvp-features' or x.startswith('--enable-')]
    assembler = load(PREPARATION / 'prepared.json')['tools']['WASM_AS']['path']
    command = [assembler, '-g', *features, str(BUILD / 'counter.wat'), '-o', str(BUILD / 'counter.wasm')]
    process = subprocess.run(command, capture_output=True)
    save(BUILD / 'counter-build.json', dict(command=command, returncode=process.returncode,
         stdout=process.stdout.decode(), stderr=process.stderr.decode(), tool=identity(assembler), performance_samples=False))
    assert process.returncode == 0 and not process.stderr


def counters():
    build_counters()
    source = (EVIDENCE / 'retention-host.mjs').read_text()
    changes = [('  const start = process.hrtime.bigint();',
                "  const counters = Object.entries(instance.exports).filter(([name]) => name.startsWith('tail-counter.'));\n"
                "  for (const [name, value] of counters) value.value = 0n;\n  const start = process.hrtime.bigint();"),
               ('  observation = {seconds, result:', '  const workCounts = Object.fromEntries(counters.map(([name, value]) => [name, value.value.toString()]));\n  observation = {workCounts, seconds, result:')]
    text = source
    for before, after in changes:
        assert text.count(before) == 1
        text = text.replace(before, after)
    erased = text
    for before, after in reversed(changes):
        erased = erased.replace(after, before)
    assert erased == source
    (BUILD / 'counter-host.mjs').write_text(text)
    save(BUILD / 'counter-host-proof.json', dict(exact_erasure=True, changes=changes))
    directory = BUILD / 'counters'
    seed_files(directory)
    save(BUILD / 'counter-spec.json', dict(load(CASE / 'spec.json'), trace=True))
    command = [TASKSET, '-c', '5', NODE, '--no-warnings', str(BUILD / 'counter-host.mjs'),
               str(BUILD / 'counter.wasm'), str(BUILD / 'counter-spec.json'), '--validate']
    output = BUILD / 'counter-run.json'
    record = execute(command, directory, output)
    try:
        result = validate_files_and_lifecycle(record)
        record['counts'] = {name.removeprefix('tail-counter.'): int(value) for name, value in result['workCounts'].items()}
    except Exception as error:
        record['validation_failure'] = repr(error)
        raise
    finally:
        save(output, record)
    print('PASS erased-counter guest: full50, complete bytes and file lifecycles')


# ---- Weighted profile intervals and independently predicted work ----

def frame_key(node):
    frame = node['callFrame']
    return (frame['functionName'], frame['url'], frame['lineNumber'], frame['columnNumber'])


def frame_weights(profile):
    nodes = {node['id']: node for node in profile['nodes']}
    parents = {child: node['id'] for node in profile['nodes'] for child in node.get('children', [])}
    exclusive, inclusive = defaultdict(int), defaultdict(int)
    for node, interval in zip(profile['samples'], profile['timeDeltas'], strict=True):
        assert interval >= 0
        exclusive[frame_key(nodes[node])] += interval
        ancestors = set()
        while node in nodes:
            ancestors.add(frame_key(nodes[node]))
            node = parents.get(node)
        for frame in ancestors:
            inclusive[frame] += interval
    return exclusive, inclusive


def rows(weights, denominator):
    return [dict(function=frame[0], url=frame[1], line=frame[2], column=frame[3],
                 weighted_interval_us=value, percent=100 * value / denominator)
            for frame, value in sorted(weights.items(), key=lambda pair: -pair[1])]


def work_checks(counts, predictions):
    pairs = [('scalar_read_requests', 'scalar_read_calls'), ('scalar_write_requests', 'scalar_write_calls'),
             ('line_values_completed', 'line_results'), ('eof_values_completed', 'eof_results'),
             ('list_nodes_completed', 'retained_list_nodes'), ('growth_requests', 'growth_allocations'),
             ('trim_requests', 'trim_allocations'), ('string_requests', 'string_new_calls'),
             ('requested_i32_cells', 'requested_i32_character_cells'), ('copy_service_cells', 'copy_i32_cells'),
             ('primary_arrays_completed', 'string_new_calls'), ('primary_arrays_completed_cells', 'requested_i32_character_cells'),
             ('array_copy_cells', 'copy_i32_cells')]
    result = {name: dict(actual=counts[name], predicted=predictions[predicted]) for name, predicted in pairs}
    assert all(value['actual'] == value['predicted'] for value in result.values())
    assert counts['directory_arrays_completed'] == counts['secondary_arrays_completed'] == 0
    return result


def predict_line(length):
    capacity, capacities = 0, []
    while capacity < length:
        capacity = max(64, capacity * 2)
        capacities.append(capacity)
    trim = length if length != capacity else 0
    return capacities, trim, sum(capacities[:-1]) + trim


def verify_predictions(predictions):
    data = (CASE / 'upstream-input.bin').read_bytes()
    assert data.endswith(b'\n') and b'\r' not in data and data.isascii()
    lengths = [len(line) for line in data.split(b'\n')[:-1]]
    lines = [predict_line(length) for length in lengths]
    growth = Counter(capacity for capacities, _, _ in lines for capacity in capacities)
    trims = Counter(length for _, length, _ in lines if length)
    assert {str(k): v for k, v in sorted(growth.items())} == predictions['growth_capacities_per_iteration']
    assert {str(k): v for k, v in sorted(trims.items())} == predictions['trimmed_lengths_per_iteration']
    assert dict(Counter(lengths)) == {int(k): v for k, v in predictions['line_length_histogram'].items()}
    assert 50 * (sum(k * v for k, v in growth.items()) + sum(k * v for k, v in trims.items())) == predictions['requested_i32_character_cells']
    assert 50 * sum(copied for _, _, copied in lines) == predictions['copy_i32_cells']


def summarize():
    profile = load(BUILD / 'profile/profile.cpuprofile')
    exclusive, inclusive = frame_weights(profile)
    denominator = sum(profile['timeDeltas'])
    assert sum(exclusive.values()) == denominator <= profile['endTime'] - profile['startTime']
    verify_predictions(load(BUILD / 'predictions.json'))
    result = dict(kind='Separate diagnostics; no clean timing samples', interval_us=1000,
                  observed_samples=len(profile['samples']), weighted_intervals_us=denominator,
                  profile_span_us=profile['endTime'] - profile['startTime'],
                  unsampled_tail_us=profile['endTime'] - profile['startTime'] - denominator,
                  exclusive_frames=rows(exclusive, denominator), inclusive_frames=rows(inclusive, denominator),
                  inclusive_warning='Overlapping ancestors; do not sum as separate costs',
                  work_checks=work_checks(load(BUILD / 'counter-run.json')['counts'], load(BUILD / 'predictions.json')))
    save(BUILD / 'findings.json', result)
    print('PASS weighted exclusive partition and 13 independent work predictions')


if __name__ == '__main__':
    BUILD.mkdir(parents=True, exist_ok=True)
    if sys.argv[1:] == ['profile']:
        profile()
    elif sys.argv[1:] == ['counters']:
        counters()
    elif sys.argv[1:] == ['summarize']:
        summarize()
    else:
        raise SystemExit('usage: diagnose.py profile | counters | summarize')
