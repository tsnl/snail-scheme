#!/usr/bin/env python3
"""Run frozen intermediate storage controls in a coordinated quiet window."""
import argparse
import hashlib
import json
import math
import os
import statistics
import subprocess
import time
from datetime import datetime,timezone
from decimal import Decimal
from pathlib import Path

ROOT=Path(__file__).resolve().parent.parent
BASE=Path('/tmp/snail-container-storage-measurement-20261012')
NODE='/nix/store/lfaydgacdyngci7p60s8wwvgdm74fjkx-nodejs-24.19.0/bin/node'
TASKSET='/run/current-system/sw/bin/taskset'
VARIANTS=['baseline','off','on']
CASES=['update-i64','shared-cell','update-f64','managed-pair-vector']
HOSTS=['scripts/run-wasi.mjs','src/runtime/host.mjs','src/runtime/build.mjs']


# ---- Frozen comparability ----


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def artifact(case,variant):
    tree=BASE if variant=='baseline' else ROOT
    directory=tree/'build/baseline'/case if variant=='baseline' else tree/'build/prepared'/variant/case
    return tree,directory/'program.wasm',directory/'program.scm'


def preflight():
    modules=[]
    for case in CASES:
        source_hash=digest(artifact(case,'baseline')[2])
        for variant in VARIANTS:
            tree,module,source=artifact(case,variant)
            if digest(source)!=source_hash:raise ValueError('source mismatch '+case)
            if any(digest(tree/p)!=digest(BASE/p) for p in HOSTS):raise ValueError('host mismatch')
            modules.append({'case':case,'variant':variant,'module':str(module),'module_sha256':digest(module),
                            'module_bytes':module.stat().st_size,'source_sha256':source_hash})
    return {'modules':modules,'tools':{p:digest(Path(p)) for p in [NODE,TASKSET]},'host':{p:digest(BASE/p) for p in HOSTS}}


# ---- One uninstrumented execution and complete observable checks ----


def expected_checksum(case,size,rounds):
    if case=='shared-cell':return Decimal('0.25')+rounds*Decimal('0.5')
    base=Decimal('0.25') if case=='update-f64' else Decimal(1099511627776)
    step=Decimal('0.5') if case=='update-f64' else 1
    return size*(base+rounds*step)+size*(size-1)//2


def verify(case,size,rounds,stdout):
    fields=next(line.removeprefix('+!STORAGE!+') for line in stdout.splitlines() if line.startswith('+!STORAGE!+')).split(',')
    actual=Decimal(fields[2 if case=='shared-cell' else 3]);expected=expected_checksum(case,size,rounds)
    elapsed=float(fields[3 if case=='shared-cell' else 4])
    if actual!=expected or not math.isfinite(elapsed) or elapsed<0:raise ValueError('output mismatch')
    return {'actual_checksum':str(actual),'expected_checksum':str(expected),'kernel_seconds':elapsed}


def execute(case,variant,size,rounds,phase,index,directory):
    output=directory/f'{index:03d}-{phase}-{case}-{variant}';output.mkdir(exist_ok=False)
    tree,module,_=artifact(case,variant);source=f'{rounds}\n' if case=='shared-cell' else f'{size}\n{rounds}\n'
    (output/'input.txt').write_text(source);command=[TASKSET,'-c','5',NODE,'--no-warnings',str(tree/'scripts/run-wasi.mjs'),str(module)]
    started=datetime.now(timezone.utc).isoformat();begin=time.monotonic_ns()
    result=subprocess.run(command,input=source,text=True,capture_output=True,cwd=module.parent,timeout=180)
    process_seconds=(time.monotonic_ns()-begin)/1e9
    (output/'stdout.txt').write_text(result.stdout);(output/'stderr.txt').write_text(result.stderr)
    if result.returncode:raise ValueError('clean execution failed: '+str(output))
    observed=verify(case,size,rounds,result.stdout)
    record={'case':case,'variant':variant,'phase':phase,'size':size,'rounds':rounds,'input':source,
            'input_sha256':digest(output/'input.txt'),'command':command,'started_utc':started,'returncode':result.returncode,
            'passed':True,'process_seconds':process_seconds,'output':str(output),**observed}
    (output/'run.json').write_text(json.dumps(record,indent=2)+'\n')
    return record


# ---- Common pilot counts and three retained rotations ----


def calibrate(directory,records):
    configs={}
    for case in CASES:
        size=0 if case=='shared-cell' else 65536
        rounds=1000000 if case=='shared-cell' else 16
        for attempt in range(3):
            run=execute(case,'baseline',size,rounds,'pilot',len(records),directory);records.append(run)
            if run['kernel_seconds']>=0.3:break
            scale=min(100,max(2,math.ceil(0.5/max(run['kernel_seconds'],0.001))))
            rounds*=scale
        configs[case]={'size':size,'rounds':rounds if records[-1]['rounds']==rounds else records[-1]['rounds']}
        print('frozen pilot count',case,configs[case],records[-1]['kernel_seconds'],flush=True)
    return configs


def summaries(records):
    result=[]
    for case in CASES:
        rows={variant:[r for r in records if r['case']==case and r['variant']==variant and r['phase']=='retained'] for variant in VARIANTS}
        statistics_by_variant={v:{metric:{'observations':[r[metric] for r in data],'median':statistics.median(r[metric] for r in data),
                                         'min':min(r[metric] for r in data),'max':max(r[metric] for r in data)}
                                 for metric in ['kernel_seconds','process_seconds']} for v,data in rows.items()}
        ratios={metric:{'baseline_over_on':statistics_by_variant['baseline'][metric]['median']/statistics_by_variant['on'][metric]['median'],
                         'off_over_on':statistics_by_variant['off'][metric]['median']/statistics_by_variant['on'][metric]['median']}
                for metric in ['kernel_seconds','process_seconds']}
        result.append({'case':case,'variants':statistics_by_variant,'ratios':ratios})
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--execute',action='store_true')
    args=parser.parse_args();frozen=preflight()
    if not args.execute:print(json.dumps({'preflight':'passed',**frozen},indent=2));return
    if os.environ.get('NODE_OPTIONS'):raise ValueError('NODE_OPTIONS must be unset')
    directory=ROOT/'build/clean-controls';directory.mkdir(exist_ok=False);records=[]
    report={'candidate':'3f2db1cc31f2e816572720a60c660364459d76e3','baseline':'f07d1eb12f7c7234463a606a09190325a3c906b5',
            'observer':'None: fresh default-tier Node processes, plain WASI host, no probes/profiler/GC flags. CPU5 affinity.',
            'scope':'Intermediate fixed arrays/bindings/captures only. Kernel timer excludes initialization and complete result checks; process timer includes them and compilation/startup.',
            'comparability':frozen,'quiet_coordination':'Parent and Astra explicitly confirmed no build/test jobs; both restrict to source edits/review until release.',
            'records':records,'caveat':'Three retained observations per variant; ranges are descriptive, without statistical confidence or full-suite extrapolation.'}
    configs=calibrate(directory,records);report['configs']=configs
    for phase,round_count in [('preliminary',1),('retained',3)]:
        for rotation in range(round_count):
            for case_index,case in enumerate(CASES):
                for offset in range(len(VARIANTS)):
                    variant=VARIANTS[(rotation+case_index+offset)%len(VARIANTS)];config=configs[case]
                    record=execute(case,variant,config['size'],config['rounds'],phase,len(records),directory);records.append(record)
                    (directory/'results.json').write_text(json.dumps(report,indent=2)+'\n')
                    print(phase,rotation,case,variant,record['kernel_seconds'],record['process_seconds'],flush=True)
    report['summaries']=summaries(records);(directory/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    print('complete',str(directory/'results.json'),digest(directory/'results.json'),flush=True)


if __name__=='__main__':main()
