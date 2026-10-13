#!/usr/bin/env python3
"""Check actual on/off storage shapes and reached sites, without timing claims."""
import importlib.util
import json
import subprocess
from collections import defaultdict
from pathlib import Path

ROOT=Path(__file__).resolve().parent


def library(name,filename):
    spec=importlib.util.spec_from_file_location(name,ROOT/filename)
    result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result)
    return result


inspect=library('inspect_storage','inspect-storage.py')
observe=library('observe_storage','observe-storage.py')
prep=library('prepare_candidate','prepare-candidate.py')


def summarize(case,shapes,run):
    counts=json.loads((run/'counts.json').read_text());operations=[]
    for row in counts['operation_totals']:
        if row['key'][0] not in ['constructor','storage-access'] or not row['requests']:continue
        descriptor=shapes['types'][row['key'][2]]
        operations.append({**row,'actual_shape':descriptor})
    return {'mode':case['mode'],'fixture':case['fixture'],'input':counts['input'],
            'module_sha256':shapes['program_sha256'],'counter_mode':counts['mode'],'scope_caveat':counts['caveat'],
            'constructor_and_access_requests':operations,'full_counter_result':str(run/'counts.json')}


def check(case):
    directory=Path(case['directory']);shapes=inspect.inspect(directory/'program.wasm',directory/'shapes')
    observer=directory/'observer';command=['python3',str(ROOT/'instrument-storage.py'),str(directory/'program.wasm'),str(observer)]
    subprocess.run(command,check=True)
    sources=[source for source in prep.inputs(case['fixture']) if '#f' not in source]
    summaries=[]
    for index,source in enumerate(sources):
        name=f'check-{index}';observe.run(observer,source,name)
        output=(observer/name/'stdout.txt').read_text();prep.verify_stdout(case['fixture'],source,output)
        summaries.append(summarize(case,shapes,observer/name))
    return summaries


def main():
    prepared=json.loads((ROOT/'candidate-preparation.json').read_text())
    report={'revision':prepared['revision'],'scope':prepared['scope'],
            'mode':'Counter-only correctness under concurrent preparation/test jobs; all elapsed values excluded.',
            'proof_policy':'Actual type definitions plus nonzero reached constructor/access requests. Scalar $float/$integer payloads excluded from container/capture proof; names alone are insufficient.',
            'cases':[]}
    path=ROOT/'reached-storage-summary.json'
    for case in prepared['cases']:
        report['cases'].extend(check(case));path.write_text(json.dumps(report,indent=2)+'\n')
        print(case['mode'],case['fixture'],'reached-shape checks passed',flush=True)


if __name__=='__main__':main()
