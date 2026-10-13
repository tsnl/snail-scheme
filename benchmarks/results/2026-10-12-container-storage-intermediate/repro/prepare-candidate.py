#!/usr/bin/env python3
"""Freeze on/off linked fixtures and correctness results, without clean timing."""
import hashlib
import json
import os
import shutil
import subprocess
from decimal import Decimal
from pathlib import Path

ROOT=Path(__file__).resolve().parent.parent
CHIBI='/nix/store/rymbc3gyix886hxf3ns6cr7smmc9swy2-chibi-scheme-0.12/bin/chibi-scheme'
NODE='/nix/store/lfaydgacdyngci7p60s8wwvgdm74fjkx-nodejs-24.19.0/bin/node'
BINARYEN='/nix/store/nd1279k2zlbp23gfqcl0qp5xk40xlxr8-binaryen-132/bin'
ENV={**os.environ,'PATH':os.pathsep.join([str(Path(CHIBI).parent),BINARYEN,'/run/current-system/sw/bin'])+os.pathsep+os.environ['PATH'],
     'BINARYEN_CORES':'1','WASM_MERGE':str(ROOT/'build/tools/capture-wasm-merge'),
     'SNAIL_REAL_WASM_MERGE':BINARYEN+'/wasm-merge','SNAIL_CAPTURE_SHARED_DIRECTORY':str(ROOT/'build/captured-inputs')}
NAMES=['representation-coverage','vector-f64','vector-i64','managed-pair-vector','shared-cell','update-f64','update-i64']


# ---- Immutable prepared artifacts ----


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(mode,name):
    directory=ROOT/'build/prepared'/mode/name;directory.mkdir(parents=True,exist_ok=False)
    shutil.copyfile(ROOT/'build/fixtures'/(name+'.scm'),directory/'program.scm')
    command=[CHIBI,'-I','src','tests/build-storage-program.scm',str(ROOT),str(directory/'program.scm'),str(directory/'program'),mode]
    with (directory/'build.stdout.txt').open('w') as out,(directory/'build.stderr.txt').open('w') as err:
        subprocess.run(command,cwd=ROOT,env={**ENV,'SNAIL_CAPTURE_DIRECTORY':str(directory)},stdout=out,stderr=err,check=True,timeout=900)
    return {'mode':mode,'fixture':name,'directory':str(directory),'build_command':command,
            'files':{p.name:{'sha256':digest(p),'bytes':p.stat().st_size} for p in sorted(directory.iterdir()) if p.is_file()},'build_status':'passed'}


# ---- Observable correctness, independent of printed elapsed ----


def inputs(name):
    if name=='representation-coverage':return ['#t\n','#f\n']
    if name=='shared-cell':return ['3\n']
    if name in ['managed-pair-vector','update-f64','update-i64']:return ['8\n3\n']
    return [f'{operation}\n8\n3\n{choice}\n' for choice,operations in [('#t',['update','append-direct','append-opaque','append-apply']),('#f',['append-opaque','append-apply'])] for operation in operations]


def checksum(name,source):
    base=Decimal('0.25') if 'f64' in name else Decimal(1099511627776)
    if name=='shared-cell':return Decimal('1.75')
    if name=='managed-pair-vector':return Decimal(8*(1099511627776+3)+28)
    if name.startswith('update-') or source.startswith('update\n'):
        return 8*(base+3*(Decimal('0.5') if 'f64' in name else 1))+28
    return 16*base+8*1024+56+2


def verify_stdout(name,source,stdout):
    if name=='representation-coverage':
        if stdout.strip()!='+!REPRESENTATION_COVERAGE!+#t':raise ValueError('coverage output mismatch')
        return {'coverage':True}
    fields=next(line.removeprefix('+!STORAGE!+') for line in stdout.splitlines() if line.startswith('+!STORAGE!+')).split(',')
    position=4 if name.startswith('vector-') else 3 if name!='shared-cell' else 2
    actual=Decimal(fields[position]);expected=checksum(name,source)
    if actual!=expected:raise ValueError('external checksum mismatch: '+str((name,actual,expected)))
    return {'checksum':str(actual),'expected':str(expected),'printed_elapsed_excluded':True}


def check(case,source,index):
    directory=Path(case['directory']);output=directory/f'check-{index}';output.mkdir(exist_ok=False)
    (output/'input.txt').write_text(source);command=[NODE,'--no-warnings',str(ROOT/'scripts/run-wasi.mjs'),str(directory/'program.wasm')]
    result=subprocess.run(command,cwd=directory,input=source,text=True,capture_output=True,timeout=180)
    (output/'stdout.txt').write_text(result.stdout);(output/'stderr.txt').write_text(result.stderr)
    if result.returncode:raise ValueError('linked correctness failed: '+str(output))
    observed=verify_stdout(case['fixture'],source,result.stdout)
    return {'input':source,'input_sha256':digest(output/'input.txt'),'returncode':result.returncode,'passed':True,'command':command,
            'output':str(output),'observed':observed,'scope':'Concurrent preparation correctness only; emitted durations are not timing evidence.'}


# ---- Preparation record ----


def main():
    report={'revision':'3f2db1cc31f2e816572720a60c660364459d76e3','baseline':'f07d1eb12f7c7234463a606a09190325a3c906b5',
            'scope':'Intermediate fixed-vector and lexical binding/capture storage; pair/record and richer clone keys pending.',
            'environment':{key:ENV.get(key) for key in ['PATH','BINARYEN_CORES','WASM_MERGE','SNAIL_REAL_WASM_MERGE','SNAIL_CAPTURE_SHARED_DIRECTORY','NODE_OPTIONS','RUSTFLAGS']},
            'tools':{p:digest(Path(p)) for p in [CHIBI,NODE,BINARYEN+'/wasm-opt',BINARYEN+'/wasm-merge',str(ROOT/'build/tools/capture-wasm-merge')]},
            'host':{p:digest(ROOT/p) for p in ['scripts/run-wasi.mjs','src/runtime/host.mjs','src/runtime/build.mjs']},'cases':[]}
    path=ROOT/'build/candidate-preparation.json'
    for name in NAMES:
        for mode in ['off','on']:
            try:
                case=prepare(mode,name);case['checks']=[check(case,source,index) for index,source in enumerate(inputs(name))]
                report['cases'].append(case);path.write_text(json.dumps(report,indent=2)+'\n')
                print(mode,name,'prepared/checks passed',len(case['checks']),flush=True)
            except Exception as error:
                report['failure']={'mode':mode,'fixture':name,'error':str(error)};path.write_text(json.dumps(report,indent=2)+'\n');raise


if __name__=='__main__':main()
