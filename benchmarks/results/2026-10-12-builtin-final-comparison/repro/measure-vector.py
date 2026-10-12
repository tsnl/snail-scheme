#!/usr/bin/env python3
"""Pilot once, freeze common inputs, then compare fresh vector processes."""
import argparse
import hashlib
import itertools
import json
import math
import statistics
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NODE = Path('/nix/store/lfaydgacdyngci7p60s8wwvgdm74fjkx-nodejs-24.19.0/bin/node')
HOST = ROOT / 'build/final-five-prepared/host/scripts/run-wasi.mjs'
PROGRAMS = {
    'd277-reference': Path('/tmp/snail-vector-reference-d2770ab-20261012/build/vector-append/reference/program.wasm'),
    'd4-reference': ROOT / 'build/vector-append/reference/program.wasm',
    'd4-public': ROOT / 'build/vector-append/public/program.wasm',
}
OUTPUT = ROOT / 'build/vector-clean'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def score(kind, value):
    if kind == 'reference': return value + 7
    if kind == 'character': return 955 + value % 26
    return value


def expected_checksum(mode, kind, size, repetitions):
    sources = {'direct-one': 1, 'direct-two': 2}.get(mode, 3)
    base = sum(score(kind, offset + index) for offset in [0, 1000, 2000][:sources] for index in range(size))
    if not size: return 0
    whole, remainder = divmod(repetitions, 97)
    changes = whole * sum(score(kind, index) for index in range(97))
    changes += sum(score(kind, index) for index in range(remainder))
    return repetitions * (base - score(kind, 0)) + changes


def invoke(label, mode, kind, size, repetitions, directory):
    directory.mkdir(parents=True)
    source = f'{mode}\n{kind}\n{size}\n{repetitions}\n#t\n'
    (directory/'input.txt').write_text(source)
    program = PROGRAMS[label]
    command = ['taskset','-c','5',str(NODE),'--no-warnings',str(HOST),str(program)]
    started = time.monotonic()
    completed = subprocess.run(command,cwd=program.parent,input=source,text=True,capture_output=True,timeout=60)
    wall = time.monotonic() - started
    (directory/'stdout.txt').write_text(completed.stdout)
    (directory/'stderr.txt').write_text(completed.stderr)
    rows = [line.removeprefix('+!VECTOR_APPEND!+').split(',') for line in completed.stdout.splitlines() if line.startswith('+!VECTOR_APPEND!+')]
    passed = completed.returncode == 0 and len(rows) == 1 and rows[0][:4] == [mode,kind,str(size),str(repetitions)]
    expected = expected_checksum(mode,kind,size,repetitions)
    passed = passed and int(rows[0][4]) == expected
    result = {'label':label,'mode':mode,'kind':kind,'size':size,'repetitions':repetitions,'passed':passed,
              'workload_seconds':float(rows[0][5]) if passed else None,'process_wall_seconds':wall,
              'checksum':int(rows[0][4]) if passed else None,'expected_checksum':expected,
              'returncode':completed.returncode,'command':command,'cwd':str(program.parent),
              'input_sha256':digest(directory/'input.txt'),'directory':str(directory),
              'recorded_at_utc':datetime.now(timezone.utc).isoformat()}
    (directory/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    if not passed: raise ValueError('vector correctness failure: '+str(directory))
    return result


def provenance():
    return {'node':{'path':str(NODE),'sha256':digest(NODE)},'host':{'path':str(HOST),'sha256':digest(HOST)},
            'artifacts':{label:{'path':str(path),'module_sha256':digest(path),'source_sha256':digest(path.with_suffix('.scm'))}
                         for label,path in PROGRAMS.items()},
            'measurement_script_sha256':digest(Path(__file__))}


def pilot():
    directory = ROOT/'build/vector-pilot'
    if directory.exists(): raise ValueError('refusing to overwrite pilot')
    groups = [('integer',8,65536),('integer',1024,2048),('reference',8,65536)]
    observations = []
    counts = {}
    for kind,size,repetitions in groups:
        for label in ['d277-reference','d4-public']:
            out = directory/f'{label}-{kind}-{size}'
            record = invoke(label,'typed-three',kind,size,repetitions,out)
            observations.append(record)
            if label == 'd4-public':
                scale = min(16, max(.125,.3/max(record['workload_seconds'],.000001)))
                counts[f'{kind}-{size}'] = max(64, math.ceil(repetitions*scale/64)*64)
        print('pilot',kind,size,'frozen iterations',counts[f'{kind}-{size}'],flush=True)
    frozen = {**provenance(),'counts':counts,'pilot_observations':observations,
              'selection':'Shared repetitions aim at 0.3 s for public typed-three pilot; scale clamped to 1/8..16 and rounded to 64. Pilot is excluded from retained results.'}
    (directory/'frozen-inputs.json').write_text(json.dumps(frozen,indent=2)+'\n')


def workload_rows(frozen):
    small_modes = ['direct-one','direct-two','direct-three','typed-three','opaque-three','apply-three','checksum-three']
    large_modes = ['typed-three','opaque-three','apply-three','checksum-three']
    rows = [('integer',8,mode) for mode in small_modes] + [('integer',1024,mode) for mode in large_modes]
    rows += [('reference',8,mode) for mode in ['typed-three','opaque-three','apply-three']]
    return [{'kind':kind,'size':size,'mode':mode,'repetitions':frozen['counts'][f'{kind}-{size}']} for kind,size,mode in rows]


def retained_summary(records, rows):
    result=[]
    for row in rows:
        medians={}
        entries=[]
        for label in PROGRAMS:
            samples=[r['workload_seconds'] for r in records if r['phase']=='retained' and r['label']==label and all(r[k]==row[k] for k in row)]
            medians[label]=statistics.median(samples)
            entries.append({'label':label,'samples':samples,'median_seconds':medians[label],'min_seconds':min(samples),'max_seconds':max(samples)})
        result.append({**row,'systems':entries,'d277_reference_over_public':medians['d277-reference']/medians['d4-public'],
                       'd4_reference_over_public':medians['d4-reference']/medians['d4-public']})
    return result


def measure():
    frozen=json.loads((ROOT/'build/vector-pilot/frozen-inputs.json').read_text())
    if provenance()!= {k:frozen[k] for k in provenance()}: raise ValueError('frozen provenance changed')
    if OUTPUT.exists(): raise ValueError('refusing to overwrite clean vector results')
    OUTPUT.mkdir()
    rows=workload_rows(frozen); labels=list(PROGRAMS); records=[]
    for phase in ['preliminary','retained']:
        rounds=1 if phase=='preliminary' else 3
        for round_number in range(rounds):
            for index,row in enumerate(rows):
                shift=(round_number+index)%3
                for label in labels[shift:]+labels[:shift]:
                    directory=OUTPUT/phase/str(round_number)/f"{row['kind']}-{row['size']}-{row['mode']}-{label}"
                    record=invoke(label,**row,directory=directory)
                    record.update(phase=phase,round=round_number)
                    records.append(record)
                    payload={'complete':False,'frozen_inputs':frozen,'records':records,
                             'scope':'Fresh Node process, CPU 5, uninstrumented. Workload internal timer excludes setup and correctness; process wall also retained. Full-result checksum included; checksum control is not subtracted.'}
                    (OUTPUT/'results.json').write_text(json.dumps(payload,indent=2)+'\n')
                    print(phase,round_number,label,row['kind'],row['size'],row['mode'],record['workload_seconds'],flush=True)
    payload['complete']=True
    payload['summary']=retained_summary(records,rows)
    (OUTPUT/'results.json').write_text(json.dumps(payload,indent=2)+'\n')
    (OUTPUT/'summary.json').write_text(json.dumps(payload['summary'],indent=2)+'\n')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pilot',action='store_true')
    args=parser.parse_args()
    if args.pilot: pilot()
    else: measure()


if __name__=='__main__':
    main()
