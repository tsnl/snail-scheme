"""Throwaway, checked native/V8 ablations over identical frozen Wasm datums."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
BUILD = Path(__file__).resolve().parent
INPUT = Path('/tmp/snail-compiler-cull-20261010/build/cull-kept-prepared/source')
REFERENCE = '658af1403c7313bef3efde25c7383e8bcf68fec34d758c0fdbed6911a27bdb0a'
WORKLOADS = ('compiler', 'fibonacci', 'tail')

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def run(command, **options):
    return subprocess.run(list(map(str, command)), check=True, text=True,
                          capture_output=True, timeout=600, **options)

def host_variant(name):
    text = (ROOT / 'src/native.c').read_text()
    if name in ('no-poll', 'combined'):
        text = text.replace('    GC_invoke_finalizers();\n    GC_reachable_here(object);',
                            '    GC_reachable_here(object);')
    if name in ('freelist', 'combined'):
        text = text.replace('#include <gc/gc.h>', '#include <gc/gc.h>\n#define NDEBUG\n#include <gc/gc_inline.h>\nstatic void *small_free[GC_TINY_FREELISTS];')
        text = text.replace('    void *object = GC_malloc(size);',
                            '    void *object;\n    GC_MALLOC_WORDS(object, (size + sizeof(void *)) / sizeof(void *), small_free);')
    if name == 'no-gc':
        text = text.replace('    GC_INIT();', '    GC_INIT();\n    GC_disable();')
    return text

def llvm_variant(workload, name):
    text = (BUILD / f'{workload}.ll').read_text()
    wat = (BUILD / f'{workload}.wat').read_text()
    names = re.findall(r'^\((?:import[^\n]*?\(func|func) (\$[^\s()]+)', wat, re.M)
    single = names.index('$single')
    pattern = rf'(define internal tailcc i64 @f\.{single}\(i64 (%[^)]+)\))[^{{]*{{.*?\n}}'
    match = re.search(pattern, text, re.S)
    assert match, (workload, single)
    if name in ('inline-single', 'combined'):
        text = text[:match.start()] + match[0].replace(') {', ') alwaysinline {', 1) + text[match.end():]
        assert 'alwaysinline' in text
    if name == 'no-single':
        text = text[:match.start()] + match[1] + ' {\nentry:\n ret i64 ' + match[2] + '\n}' + text[match.end():]
    return text

def prepare(names):
    report = {'commands': [], 'base': run(['git','rev-parse','HEAD'], cwd=ROOT).stdout.strip(),
              'tools': {tool:run([tool,'--version']).stdout.splitlines()[0] for tool in ('clang','node')},
              'inputs': {path.name:digest(path) for path in BUILD.glob('*.wat')},
              'runtime_sha256':digest(BUILD/'runtime.a')}
    flags = ['-lgc','-lm','-ldl','-lpthread','-I',os.environ['BDWGC_INCLUDE'],
             '-L',os.environ['BDWGC_LIB'],'-Wl,-rpath,'+os.environ['BDWGC_LIB']]
    for name in names:
        host = BUILD/f'{name}.c'
        host.write_text(host_variant(name))
        for workload in WORKLOADS:
            llvm, binary = BUILD/f'{workload}-{name}.ll', BUILD/f'{workload}-{name}'
            llvm.write_text(llvm_variant(workload,name))
            extra = ['-mllvm','-inline-threshold=1000'] if name == 'inline-budget' else []
            command = ['clang','-O3','-flto','-fuse-ld=lld',*extra,llvm,host,BUILD/'runtime.a',*flags,'-o',binary]
            result = run(command)
            report['commands'].append({'command':list(map(str,command)), 'stderr':result.stderr,
                                      'llvm_sha256':digest(llvm),'host_sha256':digest(host),'binary_sha256':digest(binary)})
            (BUILD/'builds.json').write_text(json.dumps(report,indent=2)+'\n')
            print('built', workload, name, flush=True)

def command(workload, variant):
    if variant.startswith('gc-divisor-'):
        return ['env','GC_FREE_SPACE_DIVISOR='+variant.rsplit('-',1)[1],str(BUILD/f'{workload}-baseline')]
    if variant.startswith('v8'):
        if variant.startswith('v8-no-binaryen'):
            flags = ['--no-wasm-tier-up'] if variant.endswith('-liftoff') else []
            return ['node',*flags,'--no-warnings',str(ROOT/'scripts/run-wasi.mjs'),str(BUILD/f'{workload}-no-binaryen.wasm')]
        flags = {'v8':[], 'v8-no-inline':['--no-wasm-inlining'], 'v8-no-opt':['--no-wasm-opt'],
                 'v8-liftoff':['--no-wasm-tier-up'], 'v8-no-liftoff':['--no-liftoff']}[variant]
        return ['node',*flags,'--no-warnings',str(ROOT/'scripts/run-wasi.mjs'),str(BUILD/f'{workload}.wasm')]
    return [str(BUILD/f'{workload}-{variant}')]

def sample(workload, variant):
    cmd = command(workload,variant)
    output = BUILD / 'output.wat'
    if workload == 'compiler':
        cmd += [str(INPUT),str(INPUT/'benchmarks/compile-self.scm'),str(output),variant]
        output.unlink(missing_ok=True)
    else:
        repetitions = 256 if workload == 'fibonacci' else 1048576
        cmd += [str(repetitions)]
    start = time.monotonic()
    result = run(['taskset','-c','2',*cmd],cwd='/tmp')
    wall = time.monotonic()-start
    if workload == 'compiler':
        checksum = digest(output)
        assert checksum == REFERENCE, (variant,checksum)
        seconds = float(re.search(r'\+!CSVLINE!+[^\n]*,([\d.]+)',result.stdout)[1])
    else:
        checksum = int(re.search(r'checksum: (\d+)',result.stdout)[1])
        assert checksum == 4204971*repetitions, (variant,checksum)
        seconds = float(re.search(r'elapsed: ([\d.]+) s',result.stdout)[1])
    assert seconds > 0, (variant, result.stdout)
    return {'seconds':seconds,'wall_seconds':wall,'checksum':checksum,'stdout':result.stdout,
            'stderr':result.stderr, 'command':['taskset','-c','2',*cmd]}

def measure(names,args):
    report = {'cpu':2,'rounds':args.rounds,'complete':False,'order':[], 'variants':{},
              'scope':'Internal timers exclude AOT preparation and process startup. JIT tiering may occur inside. Fresh processes; tail has equal in-process warmup.',
              'environment':{k:v for k,v in os.environ.items() if k.startswith(('GC_','SNAIL_NATIVE'))}}
    assert not report['environment'], report['environment']
    for workload in args.workloads.split(','):
        active = [name for name in names if workload != 'compiler' or name != 'no-gc']
        report['variants'][workload] = {name:{'command':command(workload,name),'samples':[]} for name in active}
        for index in range(args.rounds+1):
            order = active[index%len(active):]+active[:index%len(active)]
            for name in order:
                record = sample(workload,name)
                case = report['variants'][workload][name]
                if index: case['samples'].append(record)
                else: case['discarded'] = record
                report['order'].append([workload,index,name])
                args.output.write_text(json.dumps(report,indent=2)+'\n')
                print(workload,index,name,record['seconds'],flush=True)
        for name,case in report['variants'][workload].items():
            case['median_seconds'] = statistics.median(s['seconds'] for s in case['samples'])
    report['complete']=True
    args.output.write_text(json.dumps(report,indent=2)+'\n')

if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('mode', choices=('prepare','measure'))
    parser.add_argument('--variants',default='baseline,no-poll,inline-single,inline-budget,no-single,freelist,combined,no-gc')
    parser.add_argument('--rounds',type=int,default=3)
    parser.add_argument('--workloads',default='compiler,fibonacci,tail')
    parser.add_argument('--output',type=Path,default=BUILD/'results.json')
    args=parser.parse_args()
    names=args.variants.split(',')
    prepare(names) if args.mode=='prepare' else measure(names,args)
