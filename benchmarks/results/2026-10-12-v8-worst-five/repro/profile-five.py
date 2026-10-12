#!/usr/bin/env python3
"""Retain raw V8 profiles/GC logs and separately counted Wasm diagnostic runs."""

import hashlib
import importlib.util
import json
import os
import statistics
import subprocess
import time
from collections import Counter
from pathlib import Path


# ---- Frozen report inputs ----


ROOT = next(parent for parent in Path(__file__).resolve().parents
            if (parent / 'benchmarks/r7rs.py').is_file())
OUTPUT = ROOT / 'build/v8-worst-five'
CPU = 5
spec = importlib.util.spec_from_file_location('r7rs', ROOT / 'benchmarks/r7rs.py')
r7rs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r7rs)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def cat_check(case):
    original = Path(case['directory']) / 'inputs/bib'
    copied = Path(case['directory']) / 'outputs/cat.output'
    result = {'bytes': original.stat().st_size, 'input_sha256': digest(original),
              'output_sha256': digest(copied)}
    if result['input_sha256'] != result['output_sha256']:
        raise ValueError('cat output differs from input')
    return result


# ---- Raw diagnostic invocations ----


def runner():
    original = OUTPUT / 'host/scripts/run-wasi.mjs'
    instrumented = original.with_name('run-instrumented.mjs')
    text = original.read_text().replace('try { process.exitCode = wasi.start(instance); }',
                                      'const invocationStarted = performance.now();\n'
                                      'try { process.exitCode = wasi.start(instance); }')
    text += '\nconsole.error("+!PROBES!+" + JSON.stringify({invocationMilliseconds: '
    text += 'performance.now() - invocationStarted, counters: Object.fromEntries('
    text += 'Object.entries(instance.exports).filter(([name]) => name.startsWith("__snail_probe_"))'
    text += '.map(([name, global]) => [name, String(global.value)]))}));\n'
    instrumented.write_text(text)
    return instrumented


def invoke(case, mode, host):
    directory = OUTPUT / 'diagnostics' / case['benchmark'] / mode
    directory.mkdir(parents=True, exist_ok=True)
    artifact = Path(case['directory']) / 'program.wasm'
    if mode == 'counters':
        artifact = directory.parent / 'instrumented.wasm'
    command = ['taskset', '-c', str(CPU), case['command'][0], '--no-warnings',
               '--trace-gc-nvp', '--cpu-prof', '--cpu-prof-dir=' + str(directory),
               '--cpu-prof-name=profile.cpuprofile', str(host), str(artifact)]
    result = r7rs.execute(command, case['directory'], 600,
                          (Path(case['directory']) / 'input.txt').read_bytes())
    (directory / 'stdout.txt').write_text(result.pop('stdout'))
    (directory / 'stderr.txt').write_text(result.pop('stderr'))
    result.update(command=command, artifact_sha256=digest(artifact), runner_sha256=digest(host),
                  scope='Complete fresh Node process, initialization and checks included',
                  mode=mode, benchmark=case['benchmark'])
    if result['status'] == 'ok':
        result.update(r7rs.parse_result((directory / 'stdout.txt').read_text(), 'snail-scheme', case['benchmark']))
        if case['benchmark'] == 'cat':
            result['cat_bytes_check'] = cat_check(case)
    (directory / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(case['benchmark'], mode, result['status'], flush=True)
    if result['status'] != 'ok':
        raise RuntimeError('diagnostic execution failed: ' + str(directory))


# ---- Compact summaries with explicit scope ----


def gc_summary(text):
    events = []
    for line in text.splitlines():
        if ' pause=' not in line or ' gc=' not in line:
            continue
        pairs = dict(word.split('=', 1) for word in line.split() if '=' in word)
        events.append(pairs)
    pauses = [float(e['pause']) for e in events]
    scavenges = [float(e['scavenge']) for e in events if 'scavenge' in e]
    return {'events': len(events), 'types': dict(Counter(e.get('gc') for e in events)),
            'pause_printed_sum_milliseconds': sum(pauses),
            'pause_rounding_interval_milliseconds': [sum(max(0, p - .05) for p in pauses),
                                                       sum(p + .05 for p in pauses)],
            'scavenge_phase_printed_sum_milliseconds': sum(scavenges),
            'scavenge_phase_rounding_interval_milliseconds': [sum(max(0, p - .005) for p in scavenges),
                                                              sum(p + .005 for p in scavenges)],
            'allocated_bytes_reported_at_gc': sum(int(e.get('allocated', '0')) for e in events),
            'last_live_object_bytes': int(events[-1]['end_object_size']) if events else None,
            'maximum_start_object_bytes': max(int(e['start_object_size']) for e in events) if events else None,
            'trace_semantics_source': 'https://github.com/nodejs/node/blob/v24.19.0/deps/v8/src/heap/gc-tracer.cc',
            'allocated_definition': 'current.start_object_size minus previous.end_object_size, summed at GC events. '
                                    'Includes V8 object allocations over the whole process, excludes final uncollected '
                                    'allocation and Rust allocations inside Wasm linear memory.',
            'scope': 'V8 GC events over the complete process. Final uncollected allocation is absent; '
                     'pause measures stop-the-world wall duration, rounded to 0.1 ms per event. '
                     'scavenge is an included phase, rounded to 0.01 ms; do not sum it with pause. '
                     'Neither duration includes all background/concurrent GC CPU time.'}


def profile_summary(path):
    profile = json.loads(path.read_text())
    nodes = {n['id']: n for n in profile['nodes']}
    counts = Counter(profile.get('samples', []))
    totals = Counter()
    for identifier, count in counts.items():
        frame = nodes[identifier]['callFrame']
        totals[frame['functionName'] or '(' + frame.get('url', 'anonymous') + ')'] += count
    denominator = sum(totals.values())
    return {'samples': denominator, 'duration_microseconds': profile['endTime'] - profile['startTime'],
            'self_sample_top_30': [{'function': name, 'samples': count,
                                   'sample_fraction': count / denominator} for name, count in totals.most_common(30)],
            'scope': 'Whole-process 1 ms sampling; percentages are sampled stacks, not exact cost fractions.'}


def counter_summary(directory):
    text = (directory / 'counters/stderr.txt').read_text()
    row = next(line.removeprefix('+!PROBES!+') for line in text.splitlines() if line.startswith('+!PROBES!+'))
    probes = json.loads(row)
    manifest = json.loads((directory / 'manifest.json').read_text())
    rows = [{**row, 'count': int(probes['counters'][row['export']])} for row in manifest['counters']]
    constructors = Counter()
    for row in rows:
        if row['key'][0] == 'constructor':
            constructors[(row['key'][2], row['key'][3])] += row['count']
    return {'constructor_operations': sum(constructors.values()),
            'constructor_types': [{'operation': key[0], 'type': key[1], 'count': count,
                                   'definition': manifest['types'][key[1]]} for key, count in constructors.most_common()],
            'top_function_entries': sorted([row for row in rows if row['key'][0] == 'function-entry'],
                                            key=lambda row: row['count'], reverse=True)[:40],
            'indirect_calls': sum(row['count'] for row in rows if row['key'][0] == 'indirect-call'),
            'host_imports': [row for row in rows if row['key'][0] == 'host-import' and row['count']],
            'counter_rows': rows, 'scope': manifest['scope'], 'caveat': manifest['caveat']}


def summarize(report):
    summaries = {}
    for case in report['cases']:
        if case['system'] != 'snail-wasm':
            continue
        directory = OUTPUT / 'diagnostics' / case['benchmark']
        summaries[case['benchmark']] = {'counters': counter_summary(directory), 'modes': {}}
        for mode in ('sampling', 'counters'):
            run = directory / mode
            summaries[case['benchmark']]['modes'][mode] = {
                'execution': json.loads((run / 'result.json').read_text()),
                'gc': gc_summary((run / 'stdout.txt').read_text()),
                'cpu_profile': profile_summary(run / 'profile.cpuprofile')}
    (OUTPUT / 'diagnostic-summary.json').write_text(json.dumps(summaries, indent=2) + '\n')


def main():
    global CPU
    report = json.loads((OUTPUT / 'results.json').read_text())
    CPU = report['cpu']
    if not report['complete'] or any(c['status'] != 'passed' for c in report['cases']):
        raise ValueError('complete clean baseline required first')
    host = runner()
    cases = [c for c in report['cases'] if c['system'] == 'snail-wasm']
    for case in cases:
        destination = OUTPUT / 'diagnostics' / case['benchmark']
        if not (destination / 'instrumented.wasm').exists():
            subprocess.run(['python3', str(ROOT / 'build/instrument-wasm.py'),
                            str(Path(case['directory']) / 'program.wasm'), str(destination)], check=True)
    for case in cases:
        for mode, selected_host in [('sampling', OUTPUT / 'host/scripts/run-wasi.mjs'), ('counters', host)]:
            saved = OUTPUT / 'diagnostics' / case['benchmark'] / mode / 'result.json'
            if saved.exists() and json.loads(saved.read_text())['status'] == 'ok':
                continue
            if saved.exists():
                saved.parent.rename(saved.parent.with_name(mode + '-failed-preflight'))
            invoke(case, mode, selected_host)
    summarize(report)


if __name__ == '__main__':
    main()
