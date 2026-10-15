"""Keep Ray profiling and additive diagnostics separate from clean timings."""

import argparse
import datetime
import difflib
import hashlib
import json
import math
import os
from pathlib import Path
import re
import statistics
import subprocess
import tarfile
import time

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
BUILD = ROOT / 'build/native-ray-diagnostics'
ORIGINAL_COMPARISON = Path('/tmp/snail-native64-ray-comparison-20261014')
COMPARISON = ORIGINAL_COMPARISON
FROZEN = COMPARISON / 'build/native-ray'
GENERATION = FROZEN / 'ray-native.native-qttgjtjm'
PERF = '/nix/store/apffmxq24i2xf89m4llsz4yc2sc1bv94-perf-linux-7.2.3/bin/perf'
NODE = '/nix/store/lfaydgacdyngci7p60s8wwvgdm74fjkx-nodejs-24.19.0/bin/node'
TASKSET = '/run/current-system/sw/bin/taskset'
CLANG = '/run/current-system/sw/bin/clang'
LLD = '/run/current-system/sw/bin/ld.lld'
ENVIRONMENT = {key: value for key, value in os.environ.items()
               if not key.startswith(('SNAIL_GC_', 'SNAIL_NATIVE_'))
               and key not in ('NODE_OPTIONS', 'NODE_V8_COVERAGE', 'NODE_DEBUG',
                               'NODE_DEBUG_NATIVE', 'SNAIL_ARTIFACT_ROOT')}


# ---- Frozen inputs and retained process outcomes ----


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n')


def identity(path):
    return dict(path=str(path), sha256=hashlib.sha256(Path(path).read_bytes()).hexdigest())


def verify_frozen():
    freeze = json.loads((FROZEN / 'measurements/freeze.json').read_text())
    for expected in freeze['identities']:
        path = Path(expected['path'])
        if path.is_relative_to(ORIGINAL_COMPARISON):
            path = COMPARISON / path.relative_to(ORIGINAL_COMPARISON)
        assert identity(path)['sha256'] == expected['sha256'], str(path)
    assert freeze['spec']['count'] == 50 and freeze['spec']['inputs'] == [1, 1]
    assert freeze['spec']['expected'] == 1
    assert len((FROZEN / 'input/expected-ray.pgm').read_bytes()) == 29517
    assert not ENVIRONMENT.get('LD_PRELOAD')
    return freeze


def record_process(command, directory, overrides=None, timeout=900):
    directory.mkdir(parents=True, exist_ok=False)
    (directory / 'outputs').mkdir()
    record = dict(command=command, cwd=str(directory), overrides=overrides or {},
                  scope='whole process', timing_claim=False, complete=False)
    save(directory / 'outcome.json', record)
    start = time.monotonic()
    try:
        with (directory / 'stdout.txt').open('w') as stdout, (directory / 'stderr.txt').open('w') as stderr:
            process = subprocess.run(command, cwd=directory, env=ENVIRONMENT | (overrides or {}),
                                     stdout=stdout, stderr=stderr, timeout=timeout)
        record.update(returncode=process.returncode, complete=True)
    except (subprocess.TimeoutExpired, OSError) as error:
        record['failure'] = repr(error)
    record['process_seconds'] = time.monotonic() - start
    save(directory / 'outcome.json', record)
    return record


def validate_ray(record):
    directory = Path(record['cwd'])
    try:
        assert record.get('returncode') == 0 and record['complete'], record
        lines = (directory / 'stdout.txt').read_text().splitlines()
        result = json.loads(next(line for line in reversed(lines) if line.startswith('{"seconds"')))
        assert result['result'] == '1' and math.isfinite(result['seconds']) and result['seconds'] > 0, result
        image = directory / 'outputs/ray.output'
        record.update(workload_seconds=result['seconds'], image=identity(image), image_bytes=image.stat().st_size)
        assert image.read_bytes() == (FROZEN / 'input/expected-ray.pgm').read_bytes()
        record['valid'] = True
    except Exception as error:
        record['validation_failure'] = repr(error)
        raise
    finally:
        save(directory / 'outcome.json', record)


# ---- Exact executable sampling and V8 machine code ----


def profiles():
    verify_frozen()
    campaign = BUILD / 'profiles'
    campaign.mkdir(exist_ok=False)
    for index in range(8):
        directory = campaign / f'native-{index}'
        command = [PERF, 'record', '-F', '4999', '-e', 'cycles:u', '--call-graph', 'dwarf',
                   '-o', str(directory / 'perf.data'), '--', TASKSET, '-c', '5', str(FROZEN / 'ray-native')]
        record = record_process(command, directory)
        validate_ray(record)
        for name, arguments in [('report', ['report', '--stdio', '--no-children', '-g', 'none']),
                                ('samples', ['script', '-G', '-F', 'comm,pid,event,period,ip,sym,symoff,dso'])]:
            analysis = record_process([PERF, *arguments, '-i', str(directory / 'perf.data')], directory / name)
            assert analysis.get('returncode') == 0, analysis
    verify_frozen()


def v8_code():
    verify_frozen()
    wat = (FROZEN / 'current-v8.wasm.wat').read_text().splitlines()
    names = re.findall(r'^ \(import.*\(func (\$\S+)', '\n'.join(wat), re.M)
    names += re.findall(r'^ \(func (\$\S+)', '\n'.join(wat), re.M)
    for name in ['$function66', '$function70']:
        directory = BUILD / ('v8-code-' + name[1:])
        command = [TASKSET, '-c', '5', NODE, '--no-warnings', '--print-wasm-code',
                   f'--print-wasm-code-function-index={names.index(name)}',
                   str(FROZEN / 'input/ray-host.mjs'), str(FROZEN / 'current-v8.wasm'),
                   str(FROZEN / 'input/spec.json')]
        record = record_process(command, directory)
        validate_ray(record)
    verify_frozen()


# ---- Additive counters, copied sources and explicit phase boundaries ----


def instrument_constructors(text):
    lines, sites = text.splitlines(keepends=True), []
    for index, line in enumerate(lines):
        match = re.search(r'(%\w+) = call i64 @native_alloc\(i64 (\d+)\)', line)
        if match:
            following = ''.join(lines[index + 1:index + 30])
            tag = int(re.search(r'store i64 (\d+), ptr %\w+, align 1', following).group(1))
            size = int(match[2])
            lines[index] += f'  call void @native_diagnostic_constructor(i64 {tag}, i64 {size})\n'
            sites.append(dict(line=index + 1, tag=tag, size=size))
    declaration = 'declare void @native_diagnostic_constructor(i64, i64)\n'
    return ''.join(lines).replace('declare void @native_gc_collect()',
                                  declaration + 'declare void @native_gc_collect()', 1), sites


def copy_with_diff(source, destination, modified):
    original = source.read_text()
    destination.write_text(modified)
    difference = ''.join(difflib.unified_diff(original.splitlines(keepends=True), modified.splitlines(keepends=True),
                                             fromfile=str(source), tofile=str(destination)))
    (destination.with_suffix(destination.suffix + '.patch')).write_text(difference)


def prepare_counter_sources(directory):
    directory.mkdir(exist_ok=False)
    native = (COMPARISON / 'src/native.c').read_text()
    native = native.replace('frame->capacity = capacity;', 'native_diagnostic_enter(capacity);\n    frame->capacity = capacity;')
    native = native.replace('if (frame->capacity) {', 'native_diagnostic_leave(frame->capacity);\n    if (frame->capacity) {', 1)
    copy_with_diff(COMPARISON / 'src/native.c', directory / 'native.c', native)
    gc = (COMPARISON / 'src/precise-gc.c').read_text().replace('allocated_objects++;', 'allocated_objects++;\n    native_diagnostic_allocation(bytes);')
    gc += (REPORT / 'gc-snapshot.c').read_text()
    copy_with_diff(COMPARISON / 'src/precise-gc.c', directory / 'precise-gc.c', gc)
    header = (COMPARISON / 'src/precise-gc.h').read_text().replace('#endif', (REPORT / 'diagnostic.h').read_text() + '\n#endif')
    copy_with_diff(COMPARISON / 'src/precise-gc.h', directory / 'precise-gc.h', header)
    llvm, sites = instrument_constructors((GENERATION / 'module.ll').read_text())
    copy_with_diff(GENERATION / 'module.ll', directory / 'module.ll', llvm)
    save(directory / 'constructor-sites.json', sites)


def counters():
    verify_frozen()
    directory = BUILD / 'counter-build'
    prepare_counter_sources(directory)
    command = [CLANG, '-O3', '-flto', '-ffunction-sections', '-fdata-sections', '-Wl,--gc-sections',
               '-fuse-ld=' + LLD, '-I', str(directory), str(directory / 'module.ll'),
               str(directory / 'native.c'), str(directory / 'precise-gc.c'),
               str(REPORT / 'counter.c'), str(REPORT / 'entry.c'), str(GENERATION / 'provider-0.o'),
               str(COMPARISON / 'build/native-runtime/release/libsnail_runtime.a'), '-ldl', '-lpthread', '-lm',
               '-o', str(directory / 'ray-counter')]
    record = record_process(command, directory / 'compile')
    assert record.get('returncode') == 0, record
    save(directory / 'identities.json', [identity(path) for path in directory.iterdir() if path.is_file()])
    for index in range(2):
        record = record_process([TASKSET, '-c', '5', str(directory / 'ray-counter')],
                                BUILD / f'counter-run-{index}', {'SNAIL_GC_STATS': '1'})
        validate_ray(record)
    verify_frozen()


# ---- Existing heap-policy controls, frozen before a quiet campaign ----


def freeze_heap_controls():
    freeze = verify_frozen()
    plan = dict(executable=identity(FROZEN / 'ray-native'), spec=freeze['spec'], cpu=5,
                phase='bench(50)', design='one excluded cycle, four retained rotated cycles',
                variants=[dict(name='default', overrides={}),
                          dict(name='min-1m', overrides={'SNAIL_GC_MIN_BYTES': str(1024 * 1024)}),
                          dict(name='min-64m', overrides={'SNAIL_GC_MIN_BYTES': str(64 * 1024 * 1024)})])
    path = BUILD / 'heap-plan.json'
    assert not path.exists(), 'Do not replace a frozen plan.'
    save(path, plan)


def heap_controls():
    verify_frozen()
    quiet = json.loads((BUILD / 'heap-quiet-window.json').read_text())
    assert quiet['agents_holding_builds'] is True, quiet
    plan = json.loads((BUILD / 'heap-plan.json').read_text())
    assert identity(FROZEN / 'ray-native') == plan['executable']
    campaign = BUILD / 'heap-controls'
    campaign.mkdir(exist_ok=False)
    observations = []
    for cycle in range(-1, 4):
        rotation = max(cycle, 0) % len(plan['variants'])
        order = plan['variants'][rotation:] + plan['variants'][:rotation]
        for position, variant in enumerate(order):
            directory = campaign / f'cycle-{cycle}' / variant['name']
            record = record_process([TASKSET, '-c', '5', str(FROZEN / 'ray-native')], directory, variant['overrides'])
            record.update(cycle=cycle, position=position, variant=variant['name'], retained=cycle >= 0)
            save(directory / 'outcome.json', record)
            validate_ray(record)
            observations.append(record)
            save(campaign / 'observations.json', observations)
    save(campaign / 'summary.json', {variant['name']: statistics.median([item['workload_seconds'] for item in observations
                                                                       if item['retained'] and item['variant'] == variant['name']])
                                   for variant in plan['variants']})
    verify_frozen()


# ---- Reproducible analysis of retained samples and phase snapshots ----


def read_profile_samples(path):
    samples = []
    for line in path.read_text().splitlines():
        columns = line.split()
        if columns[0] == 'ray-native' and columns[3] == 'cpu_core/cycles/u:':
            name, separator, offset = columns[5].rpartition('+0x')
            samples.append((name if separator else columns[5], int(offset, 16) if separator else 0, int(columns[2])))
    return samples


def profile_summary():
    periods, counts, offsets, per_run = {}, {}, {}, []
    for path in sorted((BUILD / 'profiles').glob('native-*/samples/stdout.txt')):
        current = {}
        for name, offset, period in read_profile_samples(path):
            periods[name] = periods.get(name, 0) + period
            counts[name] = counts.get(name, 0) + 1
            current[name] = current.get(name, 0) + period
            if name == 'f.20':
                offsets[offset] = offsets.get(offset, 0) + period
        per_run.append(dict(path=str(path), periods=current, total=sum(current.values())))
    assert len(per_run) == 8
    return dict(total_period=sum(periods.values()), total_samples=sum(counts.values()), per_run=per_run,
                symbols=[dict(symbol=name, period=period, samples=counts[name], percent=period / sum(periods.values()) * 100)
                         for name, period in sorted(periods.items(), key=lambda item: -item[1])],
                f20_offsets={hex(offset): period for offset, period in offsets.items()})


def selected_regions(profile):
    ranges = [('no-root allocation', 0x4f726, 0x4f827), ('no-point allocation', 0x4fd90, 0x4fe91),
              ('outer frame entry', 0x4f1f0, 0x4f26f), ('first-hit frame entry', 0x4f460, 0x4f4da),
              ('first-hit frame exit', 0x500d3, 0x500fc)]
    observations = []
    for name, first, stop in ranges:
        period = sum(value for offset, value in profile['f20_offsets'].items() if first <= 0x4f1a0 + int(offset, 16) < stop)
        observations.append(dict(name=name, first=hex(first), stop_exclusive=hex(stop), period=period,
                                 percent=period / profile['total_period'] * 100))
    return observations


def read_counter_phases(path):
    phases = {}
    for line in path.read_text().splitlines():
        if not line.startswith(('gc phase=', 'roots phase=', 'constructors phase=', 'allocation_sizes phase=')):
            continue
        kind, phase, *values = line.split()
        phases.setdefault(phase.removeprefix('phase='), {})[kind] = {
            key: [int(part) for part in value.split(':')] if ':' in value else float(value) if key.endswith('_s') else int(value)
            for key, value in (item.split('=', 1) for item in values)}
    assert set(phases) == {'setup', 'workload-end', 'finish'}, path
    return phases


def counter_summary():
    observations = []
    for index in range(2):
        phases = read_counter_phases(BUILD / f'counter-run-{index}/stderr.txt')
        setup, end = phases['setup'], phases['workload-end']
        gc = {name: value - setup['gc'].get(name, 0) for name, value in end['gc'].items()}
        entries = {name: value - setup['roots'].get(name, 0) for name, value in end['roots'].items() if name.startswith('capacity_')}
        linked = sum(value for name, value in entries.items() if name != 'capacity_0')
        observations.append(dict(cumulative=phases, workload_gc_delta=gc, workload_entries=entries,
                                 workload_logical_entries=sum(entries.values()), workload_nonempty_links=linked))
    assert observations[0]['workload_entries'] == observations[1]['workload_entries']
    assert observations[0]['cumulative']['finish']['constructors'] == observations[1]['cumulative']['finish']['constructors']
    return observations


def summarize():
    verify_frozen()
    profile = profile_summary()
    profile['selected_regions'] = selected_regions(profile)
    profile['scope'] = 'Whole ray-native processes, excluding taskset; CPU core cycles weighted by perf period.'
    profile['limits'] = 'Regions describe sampled PCs, including allocation checks and root publication. Inlining and skid prevent exact operation-time attribution.'
    summary = dict(executable=identity(FROZEN / 'ray-native'), optimized_wasm=identity(GENERATION / 'optimized.wasm'),
                   profiles=profile, counters=counter_summary(),
                   heap=json.loads((BUILD / 'heap-controls/summary.json').read_text()))
    save(REPORT / 'summary.json', summary)


# ---- Archive integrity and explicit relocated replay paths ----


def archive():
    freeze = verify_frozen()
    paths = {path.resolve() for path in BUILD.rglob('*') if path.is_file()}
    paths |= {Path(item['path']) for item in freeze['identities'] if Path(item['path']).is_relative_to(COMPARISON)}
    paths |= {path.resolve() for path in REPORT.iterdir() if path.is_file() and path.suffix in ('.py', '.c', '.h', '.md')}
    paths |= {ROOT / 'benchmarks/strict-suite/replay.py', FROZEN / 'measurements/freeze.json',
              COMPARISON / 'build/native-runtime/release/libsnail_runtime.a', COMPARISON / 'src/precise-gc.h'}
    destination = REPORT / 'artifacts.tar.xz'
    assert not destination.exists(), 'Preserve the preceding archive.'
    names = {'files/' + str(path).lstrip('/'): path for path in sorted(paths)}
    with tarfile.open(destination, 'w:xz', preset=6) as output:
        for name, path in names.items():
            output.add(path, arcname=name, recursive=False)
    save(REPORT / 'manifest.json', dict(archive_sha256=identity(destination)['sha256'], archive_bytes=destination.stat().st_size,
                                      files={name: identity(path)['sha256'] for name, path in names.items()},
                                      source_paths={name: str(path) for name, path in names.items()},
                                      external_files=[item for item in freeze['identities'] if not Path(item['path']).is_relative_to(COMPARISON)]))


def main():
    global COMPARISON, FROZEN, GENERATION, BUILD
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['profiles', 'v8-code', 'counters', 'freeze-heap', 'heap-controls', 'summarize', 'archive'])
    parser.add_argument('--comparison', type=Path, default=COMPARISON)
    parser.add_argument('--build', type=Path, default=BUILD)
    options = parser.parse_args()
    COMPARISON, BUILD = options.comparison.resolve(), options.build.resolve()
    FROZEN, GENERATION = COMPARISON / 'build/native-ray', COMPARISON / 'build/native-ray/ray-native.native-qttgjtjm'
    operations = {'profiles': profiles, 'v8-code': v8_code, 'counters': counters,
                  'freeze-heap': freeze_heap_controls, 'heap-controls': heap_controls,
                  'summarize': summarize, 'archive': archive}
    operations[options.mode]()


if __name__ == '__main__':
    main()
