#!/usr/bin/env python3
"""Prepare immutable ordinary fixtures and check outputs under concurrent builds."""
import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parent.parent
CHIBI='/nix/store/rymbc3gyix886hxf3ns6cr7smmc9swy2-chibi-scheme-0.12/bin/chibi-scheme'
NODE='/nix/store/lfaydgacdyngci7p60s8wwvgdm74fjkx-nodejs-24.19.0/bin/node'
BINARYEN='/nix/store/nd1279k2zlbp23gfqcl0qp5xk40xlxr8-binaryen-132/bin'
PREFIX=[str(Path(CHIBI).parent),BINARYEN,'/run/current-system/sw/bin']
ENV={**os.environ,'PATH':os.pathsep.join(PREFIX)+os.pathsep+os.environ['PATH'],
     'BINARYEN_CORES':'1','WASM_MERGE':'/tmp/snail-v8-gc-20261012/build/tools/capture-wasm-merge',
     'SNAIL_REAL_WASM_MERGE':BINARYEN+'/wasm-merge'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(name):
    directory=ROOT/'build/baseline'/name;directory.mkdir(parents=True)
    shutil.copyfile(ROOT/'build/fixtures'/(name+'.scm'),directory/'program.scm')
    script='(import (scheme base) (snail-scheme build) (snail-scheme chromium-trace))\n'
    script+=f'(with-chromium-trace-to "{directory}/build.trace.json" (lambda () (build-wasm "{ROOT}" "{directory}/program.scm" "{directory}/program.wasm")))\n'
    (directory/'build.scm').write_text(script)
    command=[CHIBI,'-I','src',str(directory/'build.scm')]
    env={**ENV,'SNAIL_CAPTURE_DIRECTORY':str(directory)}
    with (directory/'build.stdout.txt').open('w') as out,(directory/'build.stderr.txt').open('w') as err:
        subprocess.run(command,cwd=ROOT,env=env,stdout=out,stderr=err,check=True,timeout=900)
    return {'fixture':name,'directory':str(directory),'build_command':command,
            'files':{p.name:digest(p) for p in sorted(directory.iterdir()) if p.is_file()},'build_status':'passed'}


def check(case,source,index):
    directory=Path(case['directory']);output=directory/f'check-{index}';output.mkdir()
    (output/'input.txt').write_text(source)
    command=[NODE,'--no-warnings',str(ROOT/'scripts/run-wasi.mjs'),str(directory/'program.wasm')]
    result=subprocess.run(command,cwd=directory,input=source,text=True,capture_output=True,timeout=60)
    (output/'stdout.txt').write_text(result.stdout);(output/'stderr.txt').write_text(result.stderr)
    if result.returncode or not any(x.startswith('+!STORAGE!+') or x.startswith('+!REPRESENTATION_COVERAGE!+') for x in result.stdout.splitlines()):
        raise ValueError('linked baseline correctness failed: '+str(output))
    return {'input':source,'returncode':result.returncode,'passed':True,'command':command,
            'output':str(output),'scope':'Preparation correctness smoke under concurrent agent builds; emitted durations are not comparative timing evidence.'}


def inputs(name):
    if name=='representation-coverage':return ['#t\n','#f\n']
    if name=='shared-cell':return ['3\n']
    if name=='managed-pair-vector':return ['8\n3\n']
    return [f'{mode}\n8\n3\n#t\n' for mode in ['update','append-direct','append-opaque','append-apply']]


def main():
    cases=[]
    for name in ['representation-coverage','vector-f64','vector-i64','managed-pair-vector','shared-cell']:
        case=prepare(name);case['checks']=[check(case,text,index) for index,text in enumerate(inputs(name))]
        cases.append(case)
        (ROOT/'build/baseline-preparation.json').write_text(json.dumps({'revision':'f07d1eb12f7c7234463a606a09190325a3c906b5','production_code_revision':'d4f0d4203a8adc9cd1f1f338d991da31794ae725','environment':{key:ENV.get(key) for key in ['PATH','BINARYEN_CORES','WASM_MERGE','SNAIL_REAL_WASM_MERGE','NODE_OPTIONS','RUSTFLAGS']},'cases':cases},indent=2)+'\n')
        print(name,'prepared and checked',flush=True)


if __name__=='__main__':main()
