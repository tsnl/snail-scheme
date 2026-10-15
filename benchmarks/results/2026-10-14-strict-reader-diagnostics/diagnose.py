#!/usr/bin/env python3
"""Add bounded diagnostics to the frozen reader hosts; never collect clean timings."""

import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
BUILD = ROOT / 'build/strict-reader-diagnostics'
OWNER = Path('/tmp/snail-strict-reader-20261014')
PLAN = OWNER / 'benchmarks/results/2026-10-14-strict-reader-timing-correction/timing-plan.json'
PLAN_HASH = 'f23d33d0620bc56698f4519aa4b2e03e9e11e5440d1c9fd4e1417e6a5eaf90f3'
REMOVED = ('NODE_OPTIONS', 'NODE_V8_COVERAGE', 'NODE_DEBUG', 'NODE_DEBUG_NATIVE',
           'LD_PRELOAD', 'SNAIL_NATIVE_GC_INTERVAL', 'SNAIL_GC_STATS',
           'SNAIL_GC_HEAP_BYTES', 'SNAIL_GC_MIN_BYTES')


# ---- Frozen inputs remain authoritative before and after each process ----

def load(path):
    return json.loads(path.read_text())


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def identity(path):
    return dict(path=str(path), bytes=path.stat().st_size,
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def verify_inputs():
    assert identity(PLAN)['sha256'] == PLAN_HASH, 'frozen timing plan changed'
    plan = load(PLAN)
    for name, digest in plan['identities'].items():
        assert identity(Path(name))['sha256'] == digest, 'frozen identity changed: ' + name
    assert plan['cpu'] in os.sched_getaffinity(0), 'frozen CPU unavailable'
    return dict(plan_sha256=PLAN_HASH, verified_identities=len(plan['identities']))


# ---- Sampling and GC observation start after setup and stop after bench ----

PROFILE_HEADER = '''import inspector from 'node:inspector';
const session = new inspector.Session();
session.connect();
const markers = {clock_domain: 'process.hrtime.bigint nanoseconds', sampling_interval_us: 1000};
const post = (method, parameters = {}) => new Promise((resolve, reject) => {
  session.post(method, parameters, (error, value) => error ? reject(error) : resolve(value));
});
'''
PROFILE_START = '''await post('Profiler.enable');
await post('Profiler.setSamplingInterval', {interval: 1000});
markers.start_submission_ns = process.hrtime.bigint().toString();
await post('Profiler.start');
markers.start_acknowledgement_ns = process.hrtime.bigint().toString();
'''
PROFILE_STOP = '''markers.clock_start_ns = start.toString();
markers.clock_stop_ns = process.hrtime.bigint().toString();
markers.stop_submission_ns = process.hrtime.bigint().toString();
const profile = (await post('Profiler.stop')).profile;
markers.stop_completion_ns = process.hrtime.bigint().toString();
session.disconnect();
fs.writeFileSync(process.env.SNAIL_DIAGNOSTIC_OUTPUT + '/profile.cpuprofile', JSON.stringify(profile));
fs.writeFileSync(process.env.SNAIL_DIAGNOSTIC_OUTPUT + '/profile-window.json', JSON.stringify(markers));
'''
GC_HEADER = '''import {PerformanceObserver, performance, constants} from 'node:perf_hooks';
const events = [], markers = {clock_domain: 'performance.now milliseconds'};
const collect = entries => {
  const delivered_at_ms = performance.now();
  for (const entry of entries) events.push({start_ms: entry.startTime, duration_ms: entry.duration,
                                          detail: entry.detail, delivered_at_ms});
};
const observer = new PerformanceObserver(list => collect(list.getEntries()));
'''
GC_START = '''observer.observe({entryTypes: ['gc']});
markers.observer_started_ms = performance.now();
markers.clock_start_ms = performance.now();
'''
GC_STOP = '''markers.clock_stop_ms = performance.now();
await new Promise(resolve => setImmediate(resolve));
await new Promise(resolve => setImmediate(resolve));
collect(observer.takeRecords());
observer.disconnect();
fs.writeFileSync(process.env.SNAIL_DIAGNOSTIC_OUTPUT + '/gc-events.json', JSON.stringify({markers, events, constants}));
'''


# ---- Counters expose scalar services and complete per-worker file cycles ----

COUNTER_HEADER = '''const counts = {initialization: {}, setup: {}, workload: {}, cleanup: {}}, files = [], tokens = {};
let phase = 'initialization', pathText = '', currentFile;
const count = name => { counts[phase][name] = (counts[phase][name] ?? 0) + 1; };
const tokenUse = (kind, handle) => {
  const length = tokens[handle];
  assert(Number.isSafeInteger(length));
  const key = 'token-characters-for-' + kind;
  counts[phase][key] = (counts[phase][key] ?? 0) + length;
};
const scalarImports = exports => Object.fromEntries(Object.entries(exports).map(([name, value]) => [name,
  typeof value !== 'function' ? value : (...args) => {
    count(name);
    const result = value(...args);
    if (name === 'snail:io/path-begin') pathText = '';
    if (name === 'snail:io/path-character') pathText += String.fromCodePoint(args[0]);
    if (name === 'snail:io/open-input-file') {
      assert(!currentFile);
      currentFile = {phase, path: pathText, handle: result, reads: 0, peeks: 0, read_eof: 0, peek_eof: 0, closed: false};
      files.push(currentFile);
    }
    if (name === 'snail:io/read-character' || name === 'snail:io/peek-character') {
      assert(currentFile && currentFile.handle === args[0]);
      const key = name === 'snail:io/read-character' ? 'reads' : 'peeks';
      currentFile[key]++;
      if (result === -1) currentFile[key === 'reads' ? 'read_eof' : 'peek_eof']++;
    }
    if (name === 'snail:io/close') {
      assert(currentFile && currentFile.handle === args[0]);
      currentFile.closed = true;
      currentFile = undefined;
    }
    if (name === 'snail:datum/token-open') tokens[result] = 0;
    if (name === 'snail:datum/token-character') tokens[args[0]]++;
    if (name === 'snail:datum/token-parse') tokenUse('parse', args[0]);
    if (name === 'snail:datum/token-identifier') tokenUse('identifier', args[0]);
    if (name === 'snail:datum/token-intern') { tokenUse('intern', args[0]); delete tokens[args[0]]; }
    if (name === 'snail:datum/token-close') delete tokens[args[0]];
    return result;
  }]));
'''
COUNTER_WASI = '''const wasiImports = Object.fromEntries(Object.entries(wasi.wasiImport).map(([name, value]) => [name,
  (...args) => { count('wasi:' + name); return value(...args); }]));
'''
COUNTER_STOP = '''assert(!currentFile && Object.keys(tokens).length === 0);
fs.writeFileSync(process.env.SNAIL_DIAGNOSTIC_OUTPUT + '/counts.json', JSON.stringify({counts, files}));
'''


# ---- Diagnostic additions have an exact erasure back to the measured host ----

def host_changes(mode):
    if mode == 'counters':
        return [('import assert', COUNTER_HEADER + 'import assert'),
                ('let provider;', COUNTER_WASI + 'let provider;'),
                ('wasi_snapshot_preview1: wasi.wasiImport', 'wasi_snapshot_preview1: wasiImports'),
                ("'snail.library': provider?.exports", "'snail.library': scalarImports(provider.exports)"),
                ('instance.exports.main();', "phase = 'setup';\n  instance.exports.main();"),
                ('const start = process.hrtime.bigint();', "phase = 'workload';\n  const start = process.hrtime.bigint();"),
                ('try { assert.equal(close(), 0); }', "phase = 'cleanup';\n  try { assert.equal(close(), 0); }"),
                ('if (failure) throw failure;', 'if (failure) throw failure;\n' + COUNTER_STOP)]
    header, start, stop = (PROFILE_HEADER, PROFILE_START, PROFILE_STOP) if mode == 'profile' else (GC_HEADER, GC_START, GC_STOP)
    return [('import assert', header + 'import assert'),
            ('instance.exports.main();', 'instance.exports.main();\n  markers.main_return_ns = process.hrtime.bigint().toString();'),
            ('const start = process.hrtime.bigint();', start + '  const start = process.hrtime.bigint();'),
            ('seconds = Number(process.hrtime.bigint() - start) / 1e9;',
             'seconds = Number(process.hrtime.bigint() - start) / 1e9;\n' + stop)]


def make_host(mode, original):
    source, text = original.read_text(), original.read_text()
    changes = host_changes(mode)
    for before, after in changes:
        assert text.count(before) == (2 if before.startswith('wasi_snapshot') else 1), before
        text = text.replace(before, after)
    restored = text
    for before, after in reversed(changes):
        restored = restored.replace(after, before)
    assert restored == source, 'diagnostic host does not erase exactly'
    target = BUILD / (mode + '-host.mjs')
    target.write_text(text)
    save(target.with_suffix('.proof.json'), dict(original=identity(original), derived=identity(target),
         exact_source_erasure=True, guest_changes=False, replacements=changes))
    return target


# ---- One owned process group retains raw output and receives bounded cleanup ----

def stop_child(child):
    try:
        os.killpg(child.pid, signal.SIGKILL)
        signalled = True
    except ProcessLookupError:
        signalled = False
    child.wait(timeout=10)
    return dict(process_group=child.pid, group_signal_sent=signalled, child_reaped=True, returncode=child.returncode)


def execute(command, cwd, directory, environment):
    env = {key: value for key, value in os.environ.items() if key not in REMOVED}
    env.update(BINARYEN_CORES='1', SNAIL_DIAGNOSTIC_OUTPUT=str(directory), **environment)
    record = dict(command=command, cwd=str(cwd), clean_timing=False, host_activity='other agents may build/probe concurrently',
                  started_utc=datetime.now(timezone.utc).isoformat(), status='prepared',
                  driver=identity(Path(__file__)),
                  host=next((identity(Path(part)) for part in command if part.endswith('.mjs')), None),
                  inherited_environment={key: env.get(key) for key in (*REMOVED, 'LANG', 'LC_ALL', 'TZ')})
    child, started = None, time.monotonic()
    try:
        record['identities_before'] = verify_inputs()
        with (directory / 'stdout.bin').open('wb') as out, (directory / 'stderr.bin').open('wb') as err:
            child = subprocess.Popen(command, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=out, stderr=err, start_new_session=True)
            record.update(pid=child.pid, process_group=child.pid, status='running')
            save(directory / 'attempt.json', record)
            child.wait(timeout=120)
            record['status'] = 'exited'
    except subprocess.TimeoutExpired as error:
        record.update(status='timeout', error=repr(error))
    except BaseException as error:
        record.update(status='failed', error=repr(error))
    finally:
        if child is not None:
            try:
                record.update(cleanup=stop_child(child), returncode=child.returncode)
            except BaseException as error:
                record['cleanup_error'] = repr(error)
        try:
            record['identities_after'] = verify_inputs()
        except BaseException as error:
            record['identity_error'] = repr(error)
        record.update(diagnostic_process_seconds=time.monotonic() - started,
                      stdout=identity(directory / 'stdout.bin') if (directory / 'stdout.bin').exists() else None,
                      stderr=identity(directory / 'stderr.bin') if (directory / 'stderr.bin').exists() else None)
        save(directory / 'attempt.json', record)
    assert record['status'] == 'exited' and not any(key in record for key in ('cleanup_error', 'identity_error')), record
    assert record['returncode'] == 0, (directory / 'stderr.bin').read_text()
    result = json.loads((directory / 'stdout.bin').read_text())
    assert result['result'] == 1, 'full predicate failed'
    if environment.get('SNAIL_GC_STATS'):
        assert set(result) == {'result', 'seconds', 'barriers', 'setup_closed', 'worker_closed', 'closed'}
        assert result['barriers'] == 0 and result['setup_closed'] == 1
        assert result['closed'] == result['worker_closed'] + 1
    else:
        assert set(result) == {'result', 'seconds'}, 'unexpected output fields'
    record.update(valid_full_result=True, diagnostic_workload_seconds=result['seconds'], status='valid')
    save(directory / 'attempt.json', record)
    return record


def run(mode, name):
    plan = load(PLAN)
    system = 'strict-native' if mode == 'native-stats' else 'strict-v8-native-module' if mode == 'counters' else 'strict-v8'
    case = plan['systems'][name][system]
    command = list(case['argv'])
    directory = BUILD / name / mode
    directory.mkdir(parents=True, exist_ok=False)
    if mode != 'native-stats':
        command[2] = str(make_host(mode, Path(command[2])))
    record = execute([plan['taskset'], '-c', str(plan['cpu']), *command], Path(case['cwd']), directory,
                     {'SNAIL_GC_STATS': '1'} if mode == 'native-stats' else {})
    record.update(full_count=plan['workloads'][name]['count'], source_system=system, mode=mode)
    if mode == 'native-stats':
        result = json.loads((directory / 'stdout.bin').read_text())
        assert result['worker_closed'] == record['full_count'], 'native worker count differs'
    save(directory / 'attempt.json', record)
    print(name, mode, 'PASS full count', record['full_count'], flush=True)


if __name__ == '__main__':
    assert len(sys.argv) == 3 and sys.argv[1] in ('profile', 'gc', 'counters', 'native-stats')
    assert sys.argv[2] in ('sum1', 'read1')
    run(*sys.argv[1:])
