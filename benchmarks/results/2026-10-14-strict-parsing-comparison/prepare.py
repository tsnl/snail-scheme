#!/usr/bin/env python3
"""Prepare the complete current Parsing controls; never start clean sampling."""

import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
PREPARED = ROOT/'build/parsing-measurement-prepared-8930aaa'
AUTHOR = Path('/tmp/snail-strict-parsing-20261014/build/parsing-preparation-1')
INTEGRATION = Path('/tmp/snail-general-specialization-20261012/build/parsing-integration-review/current/parsing')
sys.path.insert(0, str(ROOT/'benchmarks/strict-suite'))
import measure as driver
import parsing_port
import reader_ports

spec = importlib.util.spec_from_file_location('parsing_measurement', REPORT/'measure-seven.py')
measurement = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = measurement
spec.loader.exec_module(measurement)


# ---- Preserve historical provenance while generating the current complete sources ----

def read(path):
    return json.loads(path.read_text())


def save(path, value):
    measurement.save(path, value)


def digest(path):
    return measurement.digest(path)


def retained(path):
    return {str(file.relative_to(path)):digest(file) for file in path.rglob('*') if file.is_file()}


def reusable_sources():
    PREPARED.mkdir(parents=True, exist_ok=False)
    commitments = read(AUTHOR/'archive-files.json')
    for name, expected in commitments.items():
        measurement.require(digest(AUTHOR/name) == expected['sha256'], 'historical author bytes changed: '+name)
    shutil.copytree(INTEGRATION, PREPARED/'reviewed-integration')
    shutil.copytree(AUTHOR/'parsing/rust-control', PREPARED/'rust', ignore=shutil.ignore_patterns('target','__pycache__'))
    for name in ('completed.json','continuation.json','archive-files.json'):
        shutil.copy2(AUTHOR/name, PREPARED/('author-'+name))
    return read(AUTHOR/'completed.json')['tools']


def current_sources():
    runner = driver.upstream_runner()
    files = runner.suite_sources()
    directory = parsing_port.prepare_sources(files, PREPARED, runner, driver)
    names = ('upstream.scm','upstream-kernel.scm','adapted-kernel.scm','strict.scm',
             'chez/program.scm','chez-adapted/program.scm','input.txt','inputs/parsing.data')
    hashes = {name:digest(directory/name) for name in names}
    measurement.require(all(hashes[name] == digest(INTEGRATION/name) for name in names), 'current regeneration differs from reviewed integration')
    measurement.require(hashes['input.txt'] == measurement.INPUT_SHA256 and hashes['inputs/parsing.data'] == measurement.DATA_SHA256, 'full inputs differ')
    shutil.copy2(INTEGRATION/'runtime.wasm',directory/'runtime.wasm')
    for name in ('reader-timing.mjs','reader-host.mjs'):
        shutil.copy2(ROOT/'benchmarks/strict-suite'/name, PREPARED/name)
    save(PREPARED/'source-regeneration.json',dict(compiler_commit=measurement.BASIS, integration_preparation_basis='4c191323d08272591fc1346fdb1cbd53fa464b70', hashes=hashes,
        scope='All eight current complete source/input files match reviewed integration bytes. Historical author basis45214e3 remains separate.'))
    return runner


def snapshot_source():
    paths = [*ROOT.glob('src/**/*'),*ROOT.glob('scripts/**/*'),*ROOT.glob('benchmarks/strict-suite/*.py'),
             *ROOT.glob('benchmarks/strict-suite/*.mjs'),ROOT/'benchmarks/r7rs.py',ROOT/'Cargo.toml',ROOT/'Cargo.lock',ROOT/'build.rs']
    directory = PREPARED/'compiler-source'
    for source in sorted(path for path in paths if path.is_file()):
        target = directory/source.relative_to(ROOT)
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(source,target)
    patch = subprocess.check_output(['git','diff','--','benchmarks/strict-suite/reader-timing.mjs'],cwd=ROOT)
    (PREPARED/'reader-timing-host.patch').write_bytes(patch)
    save(PREPARED/'source.json',dict(commit=measurement.BASIS, files=retained(directory),
        host_change='Uncommitted narrow benchmark.write_character UTF-8 import is retained explicitly; compiler/GC source basis is unchanged.',
        gc_basis='Current growing precise native collector at8930aaa; complete compiler/host/adapter bytes retained.'))


# ---- Each diagnostic owns a group and exact byte captures through terminal state ----

def command(label, arguments, environment, cwd=ROOT, stdin=None, timeout=1200):
    directory = PREPARED/'commands'/label
    directory.mkdir(parents=True,exist_ok=False)
    config = dict(command=list(map(str,arguments)),cwd=str(cwd),stdin=str(stdin) if stdin else None)
    record = dict(**config,status='starting',diagnostic_only=True,clean_sample=False,
                  environment={'BINARYEN_CORES':'1'},inherited_environment={name:os.environ.get(name) for name in measurement.RECORDED_ENVIRONMENT})
    save(directory/'record.json',record)
    print(label,'starting',flush=True)
    try:
        measurement.run_owned(config,environment,timeout,record,directory)
        measurement.capture_identities(directory,record)
        measurement.require(record['returncode']==0 and not record['timeout'] and not record['executing_descendants']
            and record['capture_complete'] and not (directory/'stderr.bin').read_bytes(), 'diagnostic command failed: '+label)
        record['status']='valid'
    except BaseException as error:
        record.update(status='failed',error=repr(error))
        raise
    finally:
        measurement.capture_identities(directory,record)
        save(directory/'record.json',record)
    print(label,'terminal',record['returncode'],flush=True)
    return directory


# ---- Current Wasm, growing-GC native and Chez artifacts are freshly built ----

def compile_wasm(environment):
    directory = PREPARED/'parsing'
    command('strict-compile-current',[ROOT/'scripts/build-strict','--export','bench','--export','configured-count',directory/'strict.scm',directory/'strict-native.wasm'],environment)
    for raw in (True,False):
        source = directory/('strict-native.wasm.raw.wasm' if raw else 'strict-native.wasm')
        flags = ['--diagnostic-prune-only'] if raw else []
        command('raw-link-current' if raw else 'optimized-link-current',[ROOT/'scripts/link-strict-runtime','--runtime',directory/'runtime.wasm',*flags,source,directory/('raw.wasm' if raw else 'optimized.wasm')],environment)
    names = ('strict-native.wasm','strict-native.wasm.raw.wasm','raw.wasm','optimized.wasm','runtime.wasm')
    save(PREPARED/'current-wasm-comparison.json',{name:dict(sha256=digest(directory/name),equals_reviewed_integration=digest(directory/name)==digest(INTEGRATION/name)) for name in names})


def compile_native(environment):
    directory = PREPARED/'native'
    directory.mkdir()
    for name in ('strict-native.wasm','input.txt','spec.json'):
        shutil.copy2(PREPARED/'parsing'/name,directory/name)
    shutil.copytree(PREPARED/'parsing/inputs',directory/'inputs')
    provider = parsing_port.NATIVE_PROVIDER.replace('count++; return 1;','return 1;')
    measurement.require('count++' not in provider,'opacity counting remains')
    sources = {'native-provider.h':reader_ports.NATIVE_HEADER+'void write_character(uint32_t);\n',
               'native-provider.c':provider,'native-entry.c':reader_ports.TIMING_ENTRY}
    for name,text in sources.items():
        (directory/name).write_text(text)
    command('native-current-counter-free-build',[ROOT/'scripts/build-native','--wasm','--c-provider','benchmark',directory/'native-provider.h',directory/'native-provider.c','--entry-c',directory/'native-entry.c',directory/'strict-native.wasm',directory/'native'],environment)
    build, = directory.glob('native.native-*')
    shutil.copy2(build/'optimized.wasm',directory/'native-final.wasm')
    shutil.copy2(ROOT/'build/native-runtime/release/libsnail_runtime.a',PREPARED/'native-runtime.a')
    shutil.copy2(INTEGRATION/'native-module/provider.wasm',directory/'provider.wasm')
    save(directory/'final-module.json',dict(native_final_sha256=digest(directory/'native-final.wasm'),input_sha256=digest(directory/'strict-native.wasm'),executable_sha256=digest(directory/'native'),current_gc_source_sha256=digest(ROOT/'src/precise-gc.c'),compiler_commit=measurement.BASIS))


def validate_provider(tools,environment):
    script = "const fs=require('node:fs');console.log(JSON.stringify(process.argv.slice(1).map(p=>{const m=new WebAssembly.Module(fs.readFileSync(p));return {path:p,imports:WebAssembly.Module.imports(m),exports:WebAssembly.Module.exports(m)}})));"
    directory = PREPARED/'native'
    path = command('exact-native-provider-interfaces',[tools['NODE']['path'],'-e',script,directory/'native-final.wasm',directory/'provider.wasm'],environment)
    program,provider = json.loads((path/'stdout.bin').read_bytes())
    required = {row['name'] for row in program['imports'] if row['module']=='snail.library'}
    historical = read(INTEGRATION/'native-module/provider-interface.json')
    measurement.require(required==set(historical['required']),'current scalar import closure differs')
    measurement.require(digest(directory/'provider.wasm')==historical['provider_sha256'],'reviewed scalar provider changed')
    measurement.require({row['name'] for row in provider['exports']}==required|{'memory','_initialize','snail:io/close-all','snail:report-error'},'provider export closure differs')
    measurement.require(all(row['module'] in ('wasi_snapshot_preview1','snail.platform') for row in provider['imports']),'legacy root ABI retained')
    save(directory/'provider-identity.json',dict(required=sorted(required),module_sha256=digest(directory/'native-final.wasm'),provider_sha256=digest(directory/'provider.wasm'),runtime_sha256=digest(PREPARED/'parsing/runtime.wasm'),actual_interfaces=[program,provider]))


def compile_chez(runner,environment):
    for name in ('chez','chez-adapted'):
        directory = PREPARED/'parsing'/name
        arguments,_ = runner.chez_commands(directory,str(directory/'program.scm'))
        command(name+'-compile-current-source',arguments,environment,directory)


# ---- Execute the scalar UTF-8 host and the full canonical output contracts ----

def validate_utf8_host(tools,environment):
    directory = PREPARED/'utf8-host'
    directory.mkdir()
    scalars = [0,65,127,128,2047,2048,0x3bb,0xd7ff,0xe000,0xffff,0x10000,0x1f600,0x10ffff,10]
    calls = ''.join(f'(call $write (i32.const {value}))' for value in scalars)
    text = '(module (import "benchmark" "write_character" (func $write (param i32))) (memory (export "memory") 1) (func (export "main")) (func (export "configured-count") (result i64) (i64.const 1)) (func (export "close-resources") (result i32) (i32.const 0)) (func (export "bench") (param i64) (result i64) '+calls+' (i64.const 1)))'
    (directory/'characters.wat').write_text(text+'\n')
    save(directory/'spec.json',dict(count=1))
    command('utf8-host-assemble',[tools['WASM_AS']['path'],'--all-features',directory/'characters.wat','-o',directory/'characters.wasm'],environment)
    path = command('utf8-host-node-execution',[tools['NODE']['path'],'--disable-warning=ExperimentalWarning',PREPARED/'reader-timing.mjs',directory/'characters.wasm',directory/'spec.json'],environment,directory)
    expected = ''.join(map(chr,scalars)).encode('utf-8')
    output = (path/'stdout.bin').read_bytes()
    measurement.require(output.startswith(expected),'UTF-8 scalar bytes differ')
    measurement.json_seconds('snail-production-v8',output[len(expected):])
    save(directory/'validation.json',dict(passed=True,scalars=scalars,expected_utf8_hex=expected.hex(),actual_stdout_sha256=digest(path/'stdout.bin'),node_executed=True))


def configurations(tools):
    parsing,native,rust = PREPARED/'parsing',PREPARED/'native',PREPARED/'rust'
    node = [tools['NODE']['path'],'--disable-warning=ExperimentalWarning']
    systems = {
        'snail-production-v8':([*node,PREPARED/'reader-timing.mjs',parsing/'optimized.wasm',parsing/'spec.json'],parsing,None),
        'snail-native64':([native/'native'],native,None),
        'snail-identical-wasm-v8':([*node,PREPARED/'reader-timing.mjs',native/'native-final.wasm',native/'spec.json',native/'provider.wasm'],native,None),
        'chez':([tools['CHEZ']['path'],'--program',parsing/'chez/program.so'],parsing,parsing/'input.txt'),
        'chez-adapted':([tools['CHEZ']['path'],'--program',parsing/'chez-adapted/program.so'],parsing,parsing/'input.txt'),
        'rust-native':([rust/'parsing.native'],parsing,parsing/'input.txt'),
        'rust-optimized-wasm':([*node,rust/'run-wasi.mjs',rust/'parsing.wasm'],parsing,parsing/'input.txt')}
    return {name:dict(command=[tools['TASKSET']['path'],'-c','5',*map(str,arguments)],cwd=str(cwd),stdin=str(stdin) if stdin else None,
        dependencies=list(dict.fromkeys([tools['TASKSET']['path'],*[str(Path(item)) for item in arguments if Path(item).is_file()],str(cwd/'input.txt'),str(cwd/'inputs/parsing.data')]))) for name,(arguments,cwd,stdin) in systems.items()}


def validate_protocols(tools,environment):
    configured = configurations(tools)
    expectation = dict(expected_datum='(should return this list)',expected_rust_output='Result: (should return this list)')
    for name,config in configured.items():
        path = command('complete-frame-'+name,config['command'],environment,Path(config['cwd']),config['stdin'])
        measurement.workload_seconds(expectation,name,(path/'stdout.bin').read_bytes())
    raw = PREPARED/'parsing/raw.wasm'
    path = command('complete-frame-raw-v8',[tools['NODE']['path'],'--disable-warning=ExperimentalWarning',PREPARED/'reader-timing.mjs',raw,PREPARED/'parsing/spec.json'],environment,PREPARED/'parsing')
    measurement.json_seconds('snail-production-v8',(path/'stdout.bin').read_bytes())
    save(PREPARED/'protocols.json',dict(complete_frames=7,diagnostic_only=True,**expectation,configurations=configured,
        protocol_records={name:str(PREPARED/'commands'/('complete-frame-'+name)/'record.json') for name in configured}))


def validate_predicates(tools,environment):
    parsing,native = PREPARED/'parsing',PREPARED/'native'
    labels = {'count-1','count-2','wrong-final-element','zero-parses','zero-wrong-predicate','nested','values'}
    data,text = (parsing/'input.txt').read_bytes(),(parsing/'inputs/parsing.data').read_bytes()
    cases = [case for case in parsing_port.fixtures(data,text) if case['label'] in labels]
    cases += [parsing_port.fixture('missing-final',text.decode(),'(should return this)',1,False),parsing_port.fixture('extra-final',text.decode(),'(should return this list extra)',1,False)]
    results = []
    for case in cases:
        target = PREPARED/'predicate-controls'/case['label']
        target.mkdir(parents=True)
        spec = parsing_port.specification(case['data'])
        reader_ports.seed_files(target,spec,case['data'],case['text'])
        save(target/'spec.json',spec)
        for system in ('raw','optimized','native'):
            arguments = [native/'native'] if system=='native' else [tools['NODE']['path'],'--disable-warning=ExperimentalWarning',PREPARED/'reader-timing.mjs',parsing/(system+'.wasm'),target/'spec.json']
            path = command('predicate-'+case['label']+'-'+system,arguments,environment,target)
            value = json.loads((path/'stdout.bin').read_bytes(),object_pairs_hook=measurement.distinct_fields)
            measurement.require(type(value['result']) is int and value['result']==int(case['accepted']),'predicate control differs')
            if system=='native':
                measurement.require(all(value[key]==amount for key,amount in dict(barriers=0,setup_closed=1,worker_closed=1,closed=2).items()),'native lifetime differs')
            results.append(dict(label=case['label'],system=system,accepted=case['accepted']))
        path = command('predicate-'+case['label']+'-chez-adapted',[tools['CHEZ']['path'],'--program',parsing/'chez-adapted/program.so'],environment,target,target/'input.txt')
        parsing_port.chez_result(dict(stdout=(path/'stdout.bin').read_text(),stderr=(path/'stderr.bin').read_text()),dict(spec,expected=int(case['accepted'])))
        results.append(dict(label=case['label'],system='chez-adapted',accepted=case['accepted']))
    save(PREPARED/'current-predicate-controls.json',dict(total=len(results),diagnostic_only=True,controls=results))


def main():
    tools = reusable_sources()
    for name,row in tools.items():
        measurement.require(digest(row['path'])==row['sha256'],'actual tool changed: '+name)
    environment = {**os.environ,**{name:row['path'] for name,row in tools.items()},'BINARYEN_CORES':'1'}
    runner = current_sources()
    snapshot_source()
    validate_utf8_host(tools,environment)
    compile_wasm(environment)
    compile_native(environment)
    validate_provider(tools,environment)
    compile_chez(runner,environment)
    validate_protocols(tools,environment)
    validate_predicates(tools,environment)
    save(PREPARED/'prepared.json',dict(status='ready',clean_measurement_started=False,compiler_commit=measurement.BASIS,tools=tools,artifacts=retained(PREPARED)))
    print('PASS complete current Parsing preparation; clean timing not started',flush=True)


if __name__=='__main__':
    main()
