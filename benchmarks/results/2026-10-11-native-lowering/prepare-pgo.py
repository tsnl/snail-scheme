"""Train and use native IR profiles; training timings are never benchmarks."""
import json
import os
from pathlib import Path
import experiment as e

profdata='/nix/store/m64szdzwmazkdagvsr9c124dypixsjxn-llvm-21.1.8/bin/llvm-profdata'
records=[]
for workload in e.WORKLOADS:
    directory=e.BUILD/f'{workload}-profile'
    directory.mkdir(exist_ok=True)
    common=['clang','-O3','-flto','-fuse-ld=lld',e.BUILD/f'{workload}.ll',e.ROOT/'src/native.c',e.BUILD/'runtime.a',
            '-lgc','-lm','-ldl','-lpthread','-I',os.environ['BDWGC_INCLUDE'],
            '-L',os.environ['BDWGC_LIB'],'-Wl,-rpath,'+os.environ['BDWGC_LIB']]
    instrumented=e.BUILD/f'{workload}-pgo-train'
    command=[*common,'-fprofile-generate='+str(directory),'-o',instrumented]
    result=e.run(command)
    records.append({'command':list(map(str,command)),'stderr':result.stderr})
    training=e.sample(workload,'pgo-train')
    records.append({'training':training,'workload':workload})
    profile=e.BUILD/f'{workload}.profdata'
    command=[profdata,'merge','-o',profile,*directory.glob('*.profraw')]
    e.run(command)
    records.append({'command':list(map(str,command))})
    command=[*common,'-fprofile-use='+str(profile),'-o',e.BUILD/f'{workload}-pgo']
    result=e.run(command)
    records.append({'command':list(map(str,command)),'stderr':result.stderr})
    (e.BUILD/'pgo-builds.json').write_text(json.dumps(records,indent=2)+'\n')
    print('prepared PGO',workload,flush=True)
