"""Compare heap setup outside the Scheme timer; validate every program output."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[3]
BUILD = ROOT / 'build/prefault-heap'
FROZEN = Path('/tmp/snail-native-ablation-20261011/build/ablation')
SOURCE = Path('/tmp/snail-precise-gc-20261011/build/precise-gc/reproduction-smoke/source')
CPU = 3
REFERENCE = '658af1403c7313bef3efde25c7383e8bcf68fec34d758c0fdbed6911a27bdb0a'


def command(workload, variant):
    environment = dict(os.environ, GC_MARKERS='1')
    if variant.endswith('-128'):
        environment['SNAIL_GC_MIN_BYTES'] = str(128 << 20)
        variant = variant[:-4]
    if variant == 'v8':
        return ['node', '--no-warnings', str(ROOT / 'scripts/run-wasi.mjs'), str(FROZEN / f'{workload}.wasm')], environment
    if variant.startswith('bump'):
        environment.update(SNAIL_BUMP_BYTES=str((16 if workload == 'compiler' else 1) << 30), SNAIL_BUMP_REPORT='1')
        if variant == 'bump-prefault':
            environment['SNAIL_PREFAULT_HEAP'] = '1'
        return [str(BUILD / f'{workload}-bump')], environment
    if variant in ('precise300', 'nursery8', 'nursery32'):
        environment.update(SNAIL_GC_HEAP_BYTES='314572800', SNAIL_GC_PREFAULT='1')
        if variant.startswith('nursery'):
            environment.update(SNAIL_GC_GENERATIONAL='1', SNAIL_GC_NURSERY_BYTES=str(int(variant[7:]) << 20))
        return [f'/tmp/snail-generational-gc-20261011/build/generational-gc/{workload}-generational'], environment
    if variant in ('immix', 'immix-tuned'):
        environment['SNAIL_GC_HEAP_BYTES'] = '314572800'
        return [f'/tmp/snail-immix-gc-20261011/build/immix-gc/{workload}-{variant}'], environment
    environment['SNAIL_BDW_MODE'] = 'incremental' if variant == 'incremental300' else 'baseline'
    if variant != 'baseline':
        environment['SNAIL_PREFAULT_HEAP'] = '1'
    return [str(BUILD / f'{workload}-bdw')], environment


def sample(workload, variant):
    invocation, environment = command(workload, variant)
    output = BUILD / 'output.wat'
    if workload == 'compiler':
        output.unlink(missing_ok=True)
        invocation += [str(SOURCE), str(SOURCE / 'benchmarks/compile-self.scm'), str(output), variant]
    else:
        invocation += ['1048576']
    invocation = ['taskset', '-c', str(CPU), *invocation]
    start = time.monotonic()
    result = subprocess.run(invocation, env=environment, cwd='/tmp', text=True, capture_output=True, timeout=180)
    if result.returncode:
        failure = dict(command=invocation, status=result.returncode, stdout=result.stdout, stderr=result.stderr)
        (BUILD / 'failed-sample.json').write_text(json.dumps(failure, indent=2) + '\n')
        raise RuntimeError(failure)
    wall = time.monotonic() - start
    if workload == 'compiler':
        checksum = hashlib.sha256(output.read_bytes()).hexdigest()
        assert checksum == REFERENCE, (variant, checksum)
        seconds = float(re.search(r'\+!CSVLINE!+[^\n]*,([\d.]+)', result.stdout)[1])
    else:
        checksum = int(re.search(r'checksum: (\d+)', result.stdout)[1])
        assert checksum == 4409231671296, (variant, checksum)
        seconds = float(re.search(r'elapsed: ([\d.]+) s', result.stdout)[1])
    return dict(seconds=seconds, wall_seconds=wall, checksum=checksum, stdout=result.stdout, stderr=result.stderr, command=invocation)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--variants', default='nursery8,immix,v8,bump-prefault,bump-lazy,bdw300,precise300,nursery32')
    parser.add_argument('--workloads', default='compiler,tail')
    parser.add_argument('--output', type=Path, default=BUILD / 'results.json')
    args = parser.parse_args()
    variants = args.variants.split(',')
    report = dict(complete=False, cpu=CPU, variants={}, order=[])
    for workload in args.workloads.split(','):
        cases = report['variants'][workload] = {v: dict(samples=[]) for v in variants}
        for index in range(4 if workload == 'compiler' else 6):
            for variant in variants[index % len(variants):] + variants[:index % len(variants)]:
                value = sample(workload, variant)
                if index:
                    cases[variant]['samples'].append(value)
                    cases[variant]['median_seconds'] = statistics.median(s['seconds'] for s in cases[variant]['samples'])
                else:
                    cases[variant]['discarded'] = value
                report['order'].append([workload, index, variant])
                args.output.write_text(json.dumps(report, indent=2) + '\n')
                print(workload, index, variant, value['seconds'], value['stderr'].strip().replace('\n', ' | '), flush=True)
    report['complete'] = True
    args.output.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
