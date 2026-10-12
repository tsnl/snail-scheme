#!/usr/bin/env python3
"""Retain forced optimizing-tier disassembly; never measure compilation time."""
import hashlib
import json
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parent.parent
NODE='/nix/store/lfaydgacdyngci7p60s8wwvgdm74fjkx-nodejs-24.19.0/bin/node'
TARGETS=[('cat','$function171'),('lattice','$function31'),('wc','$function420'),('graphs','$function217'),('deriv','$function38')]
SOURCE='const fs=require("node:fs"); new WebAssembly.Module(fs.readFileSync(process.argv[1]));'


def target(benchmark,name):
    mapping=json.loads((ROOT/'build/diagnostics'/benchmark/'source-mapping.json').read_text())
    entry=next(row for row in mapping['functions'] if row['wasm_name']==name)
    module=ROOT/'build/final-five-prepared/cases'/benchmark/'snail-wasm/program.wasm'
    return module,entry['wasm_index']


def capture(label,name,module,index):
    directory=ROOT/'build/final-machine-code'/label
    directory.mkdir(parents=True,exist_ok=True)
    command=[NODE,'--no-warnings','--no-liftoff','--no-wasm-lazy-compilation',
             '--print-wasm-code-function-index='+str(index),'--no-wasm-async-compilation','-e',SOURCE,str(module)]
    completed=subprocess.run(command,text=True,capture_output=True,timeout=60)
    path=directory/(name[1:]+'.txt');path.write_text(completed.stdout)
    path.with_suffix('.stderr.txt').write_text(completed.stderr)
    if completed.returncode or not completed.stdout:raise ValueError('machine-code capture failed')
    return {'label':label,'wasm_name':name,'wasm_index':index,'command':command,'returncode':completed.returncode,
            'module_sha256':hashlib.sha256(module.read_bytes()).hexdigest(),'output':str(path),
            'output_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'scope':'Forced eager optimizing-tier compilation of immutable original linked binary, no instantiation/workload or compilation timing. Documents one tier; no claim this exact native code ran throughout sampled processes.'}


def main():
    rows=[]
    for benchmark,name in TARGETS:
        module,index=target(benchmark,name);rows.append(capture(benchmark,name,module,index))
    vector=ROOT/'build/vector-append/public/program.wasm'
    for name,index in [('$specialized349',214),('$function58',159)]:
        rows.append(capture('vector-public',name,vector,index))
    (ROOT/'build/final-machine-code/commands.json').write_text(json.dumps(rows,indent=2)+'\n')
    print('captured',len(rows),'forced-tier functions; no timing evidence')


if __name__=='__main__':
    main()
