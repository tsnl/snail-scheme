#!/usr/bin/env python3
"""Prepare both full Boyer controls with the current default growing collector."""

import importlib.util
import difflib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
PREPARED = ROOT/'build/boyer-measurement-prepared-a707974'
AUTHOR_ROOT = Path('/tmp/snail-strict-boyer-20261014')
AUTHOR = AUTHOR_ROOT/'build/boyer-prepared-combined'
sys.path.insert(0,str(ROOT/'benchmarks/strict-suite'))
import measure as driver
import boyer_port
import equal_port
import reader_ports

spec = importlib.util.spec_from_file_location('boyer_measurement',REPORT/'measure-seven.py')
measurement = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = measurement
spec.loader.exec_module(measurement)


# ---- Full original sources and historical evidence remain separate ----

def read(path):
    return json.loads(path.read_text())


def save(path,value):
    measurement.save(path,value)


def digest(path):
    return measurement.digest(path)


def retained(directory):
    return {str(path.relative_to(directory)):digest(path) for path in directory.rglob('*') if path.is_file()}


def historical_sources():
    PREPARED.mkdir(parents=True,exist_ok=False)
    historical = read(AUTHOR/'prepared.json')
    for case in historical['cases']:
        for name,expected in case['hashes'].items():
            measurement.require(digest(AUTHOR/case['name']/name)==expected,'historical artifact changed: '+name)
        shutil.copytree(AUTHOR/case['name']/'rust-control',PREPARED/case['name']/'rust',ignore=shutil.ignore_patterns('target','__pycache__'))
    shutil.copy2(AUTHOR/'prepared.json',PREPARED/'historical-prepared.json')
    shutil.copy2('/tmp/snail-boyer-parent-audit-20261014.json',PREPARED/'historical-parent-audit.json')
    return historical['tools']


def specification(name,data,accepted=1):
    value = boyer_port.specification(name,data)
    value.pop('native_heap_bytes')
    return dict(value,expected=accepted,native_policy='default growing collector; no policy override')


def current_sources():
    runner = driver.upstream_runner()
    files = runner.suite_sources()
    proofs = {}
    for name in measurement.BENCHMARKS:
        directory = PREPARED/name
        boyer_port.write_sources(name,files,directory,runner,driver)
        data = files['inputs/'+name+'.input']
        (directory/'input.txt').write_bytes(data)
        save(directory/'spec.json',specification(name,data))
        names = ('upstream.scm','upstream-kernel.scm','adapted-kernel.scm','strict.scm','chez/program.scm','input.txt')
        proofs[name] = {item:dict(sha256=digest(directory/item),equals_historical=digest(directory/item)==digest(AUTHOR/name/item)) for item in names}
        measurement.require(all(row['equals_historical'] for row in proofs[name].values()),'original/kernel/strict/input bytes changed')
        measurement.require(digest(directory/'input.txt')==measurement.INPUT_SHA256[name],'full original input changed')
        adapted = (directory/'adapted-kernel.scm').read_text()
        measurement.require((directory/'chez-adapted/program.scm').read_text().count(adapted)==1,'adapted Chez kernel differs')
        (directory/'historical-current-chez-library.patch').write_text(''.join(difflib.unified_diff(
            (AUTHOR/name/'chez-adapted/program.scm').read_text().splitlines(True),
            (directory/'chez-adapted/program.scm').read_text().splitlines(True),fromfile='historical-adapted-chez',tofile='current-adapted-chez')))
    save(PREPARED/'source-regeneration.json',dict(compiler_commit=measurement.BASIS,workloads=proofs,
        evidence_scope='Reviewed source/work/alias/reset evidence remains historical6fd5ca4; exact kernels/strict programs/original controls/inputs match. Current adapted Chez retains exact current library prefix.'))
    for name in ('reader-timing.mjs','reader-host.mjs'):
        shutil.copy2(ROOT/'benchmarks/strict-suite'/name,PREPARED/name)
    return runner


def snapshot_source():
    paths = [*ROOT.glob('src/**/*'),*ROOT.glob('scripts/**/*'),*ROOT.glob('benchmarks/strict-suite/*.py'),
             *ROOT.glob('benchmarks/strict-suite/*.mjs'),ROOT/'benchmarks/r7rs.py',ROOT/'Cargo.toml',ROOT/'Cargo.lock',ROOT/'build.rs']
    directory = PREPARED/'compiler-source'
    for source in sorted(path for path in paths if path.is_file()):
        target = directory/source.relative_to(ROOT)
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(source,target)
    revision = subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    changed = subprocess.check_output(['git','diff','--name-only','HEAD','--','src','scripts','Cargo.toml','Cargo.lock','build.rs','benchmarks/strict-suite','benchmarks/r7rs.py'],cwd=ROOT,text=True)
    measurement.require(revision==measurement.BASIS and changed=='','compiler/runtime tree differs from declared commit')
    save(PREPARED/'source.json',dict(commit=measurement.BASIS,files=retained(directory),
        native_policy='Default current growing precise collector: all source policy environment knobs must be unset. Historical caps are not selected.'))


# ---- Every diagnostic owns its process group and exact captures until terminal ----

def command(label,arguments,environment,cwd=ROOT,stdin=None,overrides=None,allow_stderr=False):
    directory = PREPARED/'commands'/label
    directory.mkdir(parents=True,exist_ok=False)
    config = dict(command=list(map(str,arguments)),cwd=str(cwd),stdin=str(stdin) if stdin else None)
    record = dict(**config,status='starting',diagnostic_only=True,clean_sample=False,
        environment={'BINARYEN_CORES':'1',**(overrides or {})},inherited_environment={name:os.environ.get(name) for name in measurement.RECORDED_ENVIRONMENT})
    save(directory/'record.json',record)
    print(label,'starting',flush=True)
    try:
        measurement.run_owned(config,{**environment,**(overrides or {})},1200,record,directory)
        measurement.capture_identities(directory,record)
        measurement.require(record['returncode']==0 and not record['timeout'] and not record['executing_descendants'] and record['capture_complete'],'diagnostic command failed: '+label)
        measurement.require(allow_stderr or not (directory/'stderr.bin').read_bytes(),'unexpected diagnostic stderr: '+label)
        record['status']='valid'
    except BaseException as error:
        record.update(status='failed',error=repr(error))
        raise
    finally:
        measurement.capture_identities(directory,record)
        save(directory/'record.json',record)
    print(label,'terminal',record['returncode'],flush=True)
    return directory


# ---- Fresh mandatory-Binaryen runtime, Wasm and default-policy native builds ----

def build_runtime(tools,environment):
    command('current-wasm-runtime-build',[tools['CARGO']['path'],'rustc','--crate-type=cdylib','--quiet','--offline','--release','--target','wasm32-wasip1','--target-dir',ROOT/'build/wasm-runtime'],environment)
    source = ROOT/'build/wasm-runtime/wasm32-wasip1/release/snail_runtime.wasm'
    shutil.copy2(source,PREPARED/'runtime.wasm')
    for name in measurement.BENCHMARKS:
        shutil.copy2(source,PREPARED/name/'runtime.wasm')


def build_wasm(name,environment):
    directory = PREPARED/name
    command(name+'-strict-build',[ROOT/'scripts/build-strict','--export','bench','--export','configured-count',directory/'strict.scm',directory/'strict-native.wasm'],environment)
    for raw in (True,False):
        artifact = directory/('strict-native.wasm.raw.wasm' if raw else 'strict-native.wasm')
        flags = ['--diagnostic-prune-only'] if raw else []
        command(name+('-raw-link' if raw else '-optimized-link'),[ROOT/'scripts/link-strict-runtime','--runtime',directory/'runtime.wasm',*flags,artifact,directory/('raw.wasm' if raw else 'optimized.wasm')],environment)


def build_native(name,environment):
    directory = PREPARED/name/'native'
    directory.mkdir()
    for item in ('strict-native.wasm','input.txt','spec.json'):
        shutil.copy2(directory.parent/item,directory/item)
    provider = reader_ports.NATIVE_PROVIDER.replace('count++; return 1;','return 1;')
    measurement.require('count++' not in provider,'opacity counter remains')
    for item,text in {'native-provider.h':reader_ports.NATIVE_HEADER,'native-provider.c':provider,'native-entry.c':reader_ports.TIMING_ENTRY}.items():
        (directory/item).write_text(text)
    command(name+'-native-default-build',[ROOT/'scripts/build-native','--wasm','--c-provider','benchmark',directory/'native-provider.h',directory/'native-provider.c','--entry-c',directory/'native-entry.c',directory/'strict-native.wasm',directory/'native'],environment)
    build, = directory.glob('native.native-*')
    shutil.copy2(build/'optimized.wasm',directory/'native-final.wasm')
    shutil.copy2(ROOT/'build/native-runtime/release/libsnail_runtime.a',PREPARED/'native-runtime.a')
    save(directory/'final-module.json',dict(native_final_sha256=digest(directory/'native-final.wasm'),executable_sha256=digest(directory/'native'),input_sha256=digest(directory/'strict-native.wasm'),compiler_commit=measurement.BASIS,gc_source_sha256=digest(ROOT/'src/precise-gc.c')))


def interfaces(label,paths,tools,environment):
    script = "const fs=require('node:fs');console.log(JSON.stringify(process.argv.slice(1).map(path=>{const m=new WebAssembly.Module(fs.readFileSync(path));return {path,imports:WebAssembly.Module.imports(m),exports:WebAssembly.Module.exports(m)}})));"
    result = command(label,[tools['NODE']['path'],'-e',script,*paths],environment)
    return json.loads((result/'stdout.bin').read_bytes())


def scalar_provider(name,tools,environment):
    directory = PREPARED/name/'native'
    program,runtime = interfaces(name+'-provider-input-interfaces',[directory/'native-final.wasm',PREPARED/'runtime.wasm'],tools,environment)
    required = {row['name'] for row in program['imports'] if row['module']=='snail.library'}
    keep = required|{'memory','_initialize','snail:io/close-all','snail:report-error'}
    exports = {row['name'] for row in runtime['exports']}
    measurement.require(keep<=exports,'runtime lacks required scalar export')
    command(name+'-provider-disassemble',[tools['WASM_DIS']['path'],PREPARED/'runtime.wasm','-o',directory/'full-provider.wat'],environment)
    reader_ports.prune_export_table(directory,keep,exports,driver)
    features = reader_ports.matrix_port.RUST_WASM_FEATURES
    command(name+'-provider-assemble',[tools['WASM_AS']['path'],*features,directory/'selected-provider.wat','-o',directory/'selected-provider.wasm'],environment)
    command(name+'-provider-optimize',[tools['WASM_OPT']['path'],'-g',*features,'--remove-unused-module-elements','-O3',directory/'selected-provider.wasm','-o',directory/'provider.wasm'],environment)
    provider, = interfaces(name+'-provider-final-interface',[directory/'provider.wasm'],tools,environment)
    measurement.require({row['name'] for row in provider['exports']}==keep and all(row['module'] in ('wasi_snapshot_preview1','snail.platform') for row in provider['imports']),'scalar provider closure differs')
    save(directory/'provider-interface.json',dict(required=sorted(required),retained=sorted(keep),module_sha256=digest(directory/'native-final.wasm'),runtime_sha256=digest(PREPARED/'runtime.wasm'),provider_sha256=digest(directory/'provider.wasm'),interface=provider))


def build_chez(name,runner,environment):
    for system in ('chez','chez-adapted'):
        directory = PREPARED/name/system
        arguments,_ = runner.chez_commands(directory,str(directory/'program.scm'))
        command(name+'-'+system+'-compile',arguments,environment,directory)


# ---- Full frames and current boundary/reset predicates precede any clean plan ----

def configurations(name,tools):
    directory,native,rust = PREPARED/name,PREPARED/name/'native',PREPARED/name/'rust'
    node = [tools['NODE']['path'],'--disable-warning=ExperimentalWarning']
    systems = {
        'snail-production-v8':([*node,PREPARED/'reader-timing.mjs',directory/'optimized.wasm',directory/'spec.json'],directory,None),
        'snail-native64':([native/'native'],native,None),
        'snail-identical-wasm-v8':([*node,PREPARED/'reader-timing.mjs',native/'native-final.wasm',native/'spec.json',native/'provider.wasm'],native,None),
        'chez':([tools['CHEZ']['path'],'--program',directory/'chez/program.so'],directory,directory/'input.txt'),
        'chez-adapted':([tools['CHEZ']['path'],'--program',directory/'chez-adapted/program.so'],directory,directory/'input.txt'),
        'rust-native':([rust/(name+'.native')],directory,directory/'input.txt'),
        'rust-optimized-wasm':([*node,rust/'run-wasi.mjs',rust/(name+'.wasm')],directory,directory/'input.txt')}
    return {system:dict(command=[tools['TASKSET']['path'],'-c','5',*map(str,arguments)],cwd=str(cwd),stdin=str(stdin) if stdin else None,
        dependencies=list(dict.fromkeys([tools['TASKSET']['path'],*[str(Path(item)) for item in arguments if Path(item).is_file()],str(cwd/'input.txt')]))) for system,(arguments,cwd,stdin) in systems.items()}


def validate_protocols(name,tools,environment):
    configured = configurations(name,tools)
    for system,config in configured.items():
        path = command(name+'-complete-frame-'+system,config['command'],environment,Path(config['cwd']),config['stdin'])
        measurement.workload_seconds({},name,system,(path/'stdout.bin').read_bytes())
    path = command(name+'-complete-frame-raw-v8',[tools['NODE']['path'],'--disable-warning=ExperimentalWarning',PREPARED/'reader-timing.mjs',PREPARED/name/'raw.wasm',PREPARED/name/'spec.json'],environment,PREPARED/name)
    measurement.json_seconds('snail-production-v8',(path/'stdout.bin').read_bytes())
    return dict(configurations=configured,protocol_records={system:str(PREPARED/'commands'/(name+'-complete-frame-'+system)/'record.json') for system in configured})


def validate_predicates(name,tools,environment):
    directory = PREPARED/name
    results = []
    for label,data,accepted in boyer_port.fixtures((directory/'input.txt').read_bytes())[1:]:
        target = directory/'predicate-controls'/label
        target.mkdir(parents=True)
        (target/'input.txt').write_bytes(data)
        spec = specification(name,data,accepted)
        save(target/'spec.json',spec)
        for system in ('raw','optimized','native'):
            arguments = [directory/'native/native'] if system=='native' else [tools['NODE']['path'],'--disable-warning=ExperimentalWarning',PREPARED/'reader-timing.mjs',directory/(system+'.wasm'),target/'spec.json']
            path = command(name+'-predicate-'+label+'-'+system,arguments,environment,target)
            value = json.loads((path/'stdout.bin').read_bytes(),object_pairs_hook=measurement.distinct_fields)
            measurement.require(type(value['result']) is int and value['result']==accepted,'boundary/reset predicate differs')
            if system=='native':
                measurement.require(all(value[key]==amount for key,amount in dict(barriers=0,setup_closed=1,worker_closed=0,closed=1).items()),'native resource lifecycle differs')
            results.append(dict(label=label,system=system,accepted=accepted))
        for system in ('chez','chez-adapted'):
            path = command(name+'-predicate-'+label+'-'+system,[tools['CHEZ']['path'],'--program',directory/system/'program.so'],environment,target,target/'input.txt')
            boyer_port.chez_result(dict(stdout=(path/'stdout.bin').read_text(),stderr=(path/'stderr.bin').read_text()),spec)
            results.append(dict(label=label,system=system,accepted=accepted))
    save(directory/'current-predicate-controls.json',dict(total=len(results),diagnostic_only=True,controls=results))


# ---- A separate entry links the exact clean LLVM for default-policy retention ----

def retention_check(name,tools,environment):
    directory = PREPARED/name/'native'
    build, = directory.glob('native.native-*')
    entry = directory/'retention-entry.c'
    entry.write_text(equal_port.lifetime_entry())
    arguments = list(read(build/'build.json')['commands'][-1]['command'])
    arguments = [str(entry) if item==str(directory/'native-entry.c') else item for item in arguments]
    arguments[arguments.index('-o')+1] = str(directory/'retention-native')
    command(name+'-retention-link-exact-llvm',arguments,environment)
    rows = {}
    for label,flags in (('setup-only',['setup-only']),('full-original',[])):
        path = command(name+'-retention-'+label,[directory/'retention-native',*flags],environment,directory,overrides={'SNAIL_GC_STATS':'1'},allow_stderr=True)
        result = json.loads((path/'stdout.bin').read_bytes())
        expected = 0 if flags else 1
        measurement.require(all(result[key]==amount for key,amount in dict(result=expected,barriers=0,setup_closed=1,worker_closed=0,closed=1).items()),'retention result/lifecycle differs')
        stats = parse_statistics((path/'stderr.bin').read_bytes())
        measurement.require(stats['heap_limit']==0 and stats['initial_heap_bytes']==256*1024**2 and stats['collections']>=2,'default growing-GC policy differs')
        rows[label]=dict(result=result,statistics=stats)
    save(directory/'retention.json',dict(diagnostic_only=True,observations=rows,module_sha256=digest(directory/'native-final.wasm'),llvm_sha256=digest(build/'module.ll'),
        scope='Exact clean optimized Wasm/lowered LLVM/provider/runtime; only diagnostic entry/collection schedule differ. Last-live is marked payload after return, peak-live samples collections; no clean timing or isolated fragmentation/lifetime cause.'))


def parse_statistics(data):
    prefix = b'immix-gc allocation_search=tuned evacuation=0 '
    measurement.require(data.startswith(prefix) and data.endswith(b'\n') and data.count(b'\n')==1,'complete GC diagnostic frame differs')
    fields = {}
    for pair in data[len(prefix):-1].split(b' '):
        key,value = pair.decode('ascii').split('=')
        measurement.require(key not in fields and re.fullmatch(r'\d+(?:\.\d+)?',value),'GC field differs')
        fields[key] = float(value) if '.' in value else int(value)
    return fields


def main():
    for name in measurement.REJECTED_ENVIRONMENT:
        measurement.require(name not in os.environ,'preparation must unset '+name)
    tools = historical_sources()
    for name,row in tools.items():
        measurement.require(digest(row['path'])==row['sha256'],'tool changed: '+name)
    environment = {**os.environ,**{name:row['path'] for name,row in tools.items()},'BINARYEN_CORES':'1'}
    runner = current_sources()
    snapshot_source()
    build_runtime(tools,environment)
    protocols = {}
    for name in measurement.BENCHMARKS:
        build_wasm(name,environment)
        build_native(name,environment)
        scalar_provider(name,tools,environment)
        build_chez(name,runner,environment)
        protocols[name]=validate_protocols(name,tools,environment)
        validate_predicates(name,tools,environment)
        retention_check(name,tools,environment)
    save(PREPARED/'protocols.json',dict(workloads=protocols,complete_frames=14,diagnostic_only=True))
    save(PREPARED/'prepared.json',dict(status='ready',clean_measurement_started=False,compiler_commit=measurement.BASIS,tools=tools,artifacts=retained(PREPARED)))
    print('PASS both complete current Boyer preparations; clean timing not started',flush=True)


if __name__=='__main__':
    main()
