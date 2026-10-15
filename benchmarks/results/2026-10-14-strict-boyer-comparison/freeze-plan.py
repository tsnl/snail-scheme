#!/usr/bin/env python3
"""Freeze both full Boyer workloads and current default-policy controls without timing."""

import importlib.util
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
spec = importlib.util.spec_from_file_location('boyer_measurement',REPORT/'measure-seven.py')
measurement = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = measurement
spec.loader.exec_module(measurement)


# ---- Full default-policy preparation and exact native lowering inputs ----

def read(path):
    return json.loads(path.read_text())


def check_preparation():
    prepared = read(PREPARED/'prepared.json')
    measurement.require(prepared['status']=='ready' and prepared['compiler_commit']==measurement.BASIS,'current basis differs')
    for name,expected in prepared['artifacts'].items():
        measurement.require(measurement.digest(PREPARED/name)==expected,'prepared bytes changed: '+name)
    for name in measurement.BENCHMARKS:
        check_workload(name)
    records = [read(path) for path in PREPARED.glob('commands/*/record.json')]
    measurement.require(all(row['returncode']==0 and row['capture_complete'] and not row['timeout'] and not row['executing_descendants'] for row in records),'preparation has failed/unclosed child')
    measurement.require(read(PREPARED/'protocols.json')['complete_frames']==14,'full protocol population differs')
    return prepared


def check_workload(name):
    directory = PREPARED/name
    build, = (directory/'native').glob('native.native-*')
    measurement.require(measurement.digest(build/'optimized.wasm')==measurement.digest(directory/'native/native-final.wasm'),'V8 native-final control differs from LLVM input')
    measurement.require(measurement.digest(directory/'input.txt')==measurement.INPUT_SHA256[name],'full input bytes changed')
    measurement.require(read(directory/'current-predicate-controls.json')['total']==20,'fresh predicate/reset controls incomplete')
    retention = read(directory/'native/retention.json')
    measurement.require(retention['llvm_sha256']==measurement.digest(build/'module.ll'),'retention LLVM differs from clean input')
    measurement.require(retention['module_sha256']==measurement.digest(build/'optimized.wasm'),'retention optimized Wasm differs')
    for row in retention['observations'].values():
        measurement.require(row['statistics']['heap_limit']==0 and row['statistics']['initial_heap_bytes']==256*1024**2 and row['statistics']['collections']>=2,'default growing GC differs')
    links = read(directory/'optimized.wasm.link.json')
    measurement.require(all(row['status']==0 and not row['stderr'] for row in links),'production linkage failed')
    measurement.require(any(Path(row['command'][0]).name=='wasm-opt' and '-O3' in row['command'] and '--converge' in row['command'] for row in links),'mandatory production Binaryen stage absent')
    original = read(build/'build.json')['commands'][-1]['command']
    expected = [str(directory/'native/retention-entry.c') if item==str(directory/'native/native-entry.c') else item for item in original]
    expected[expected.index('-o')+1] = str(directory/'native/retention-native')
    actual = read(PREPARED/'commands'/(name+'-retention-link-exact-llvm')/'record.json')['command']
    measurement.require(actual==expected,'retention link changed inputs besides entry/output')


def check_native_sources():
    for name,expected in read(PREPARED/'source.json')['files'].items():
        measurement.require(measurement.digest(PREPARED/'compiler-source'/name)==expected and measurement.digest(ROOT/name)==expected,'compiler/GC source changed: '+name)
    for name in measurement.BENCHMARKS:
        build, = (PREPARED/name/'native').glob('native.native-*')
        for original,expected in read(build/'build.json')['sha256'].items():
            source = Path(original)
            frozen = PREPARED/'native-runtime.a' if source==ROOT/'build/native-runtime/release/libsnail_runtime.a' else source
            measurement.require(measurement.digest(frozen)==expected,'native build provenance changed: '+original)
        measurement.require(any(row.get('name')=='build.optimize-scheme' for row in read(build/'compile.trace.json')),'mandatory native Binaryen stage absent')


# ---- Actual Python imports, tool libraries and Chez heaps join artifact identities ----

def imports():
    output = subprocess.check_output([sys.executable,REPORT/'measure-seven.py','--dependency-files'])
    return set(map(Path,json.loads(output)))


def linked_files(executables):
    files,records = set(),[]
    ldd = Path(shutil.which('ldd'))
    for executable in sorted(executables):
        row = subprocess.run([ldd,executable],capture_output=True,timeout=30)
        measurement.require(row.returncode==0,'dynamic-library discovery failed: '+str(executable))
        records.append(dict(command=[str(ldd),str(executable)],returncode=row.returncode,stdout=row.stdout.decode(),stderr=row.stderr.decode()))
        files.update(Path(name) for name in re.findall(r'(/[^\s()]+)',row.stdout.decode()) if Path(name).is_file())
    measurement.save(PREPARED/'linked-dependencies.json',records)
    return files|{ldd,PREPARED/'linked-dependencies.json'}


def selected_rust_toolchain(tools):
    directory = PREPARED/'toolchain-selection'
    directory.mkdir(exist_ok=False)
    shutil.copy2(ROOT/'rust-toolchain.toml',directory/'rust-toolchain.toml')
    command = [tools['RUSTC']['path'],'--print','sysroot']
    row = subprocess.run(command,cwd=ROOT,capture_output=True,timeout=30)
    measurement.require(row.returncode==0 and not row.stderr,'Rust toolchain selection failed')
    executables = {Path(row.stdout.decode().strip())/'bin'/name for name in ('rustc','cargo')}
    measurement.save(directory/'selection.json',dict(command=command,returncode=row.returncode,stdout=row.stdout.decode(),stderr=row.stderr.decode(),
        selected={str(path):measurement.digest(path) for path in sorted(executables)},scope='Actual stable toolchain behind the recorded rustup shims; source selector and binary/library identities retained as build provenance.'))
    return executables


def frozen_identities(tools):
    selected = selected_rust_toolchain(tools)
    imported = imports()|set(map(Path,measurement.dependency_files()))
    files = imported|{path for path in PREPARED.rglob('*') if path.is_file()}
    files.update(REPORT.glob('*.py'))
    files.update(Path(row['path']) for row in tools.values())
    executables = {Path(tools[name]['path']) for name in ('NODE','CHEZ','TASKSET','PYTHON')}
    executables |= {PREPARED/name/'native/native' for name in measurement.BENCHMARKS}
    executables |= {PREPARED/name/'rust'/(name+'.native') for name in measurement.BENCHMARKS}
    executables |= selected
    executables.update(path for path in imported if path.suffix=='.so')
    files |= linked_files(executables)
    files |= selected|{ROOT/'rust-toolchain.toml'}
    files.update(Path(tools['CHEZ']['path']).resolve().parents[1].glob('lib/**/*.boot'))
    for row in tools.values():
        measurement.require(measurement.digest(row['path'])==row['sha256'],'actual tool changed')
    return {str(path):measurement.digest(path) for path in sorted(files)}


def execution_dependencies(configurations,identities):
    external = [path for path in identities if not Path(path).is_relative_to(ROOT)]
    for systems in configurations.values():
        for config in systems.values():
            config['dependencies'] = list(dict.fromkeys([*config['dependencies'],*external]))
    return configurations


# ---- Fixed warmups and seven rotations balance positions within each workload ----

def plan(prepared):
    protocols = read(PREPARED/'protocols.json')
    identities = frozen_identities(prepared['tools'])
    return dict(measurement_started=False,coordinated_release_required=True,compiler_commit=measurement.BASIS,
        historical_compiler_commit='6fd5ca453cc58903cdb64f13abc3cdc656b06226',historical_driver_commit='6f4a30e3f342bac06d01be3e5228abe783a0bfab',
        upstream_commit='85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1',gc_policy='current growing precise collector; all policy knobs unset',
        cpu=5,timeout_seconds=1200,rounds=7,warmup_processes=14,measured_processes=98,
        benchmarks=list(measurement.BENCHMARKS),input_parameters=dict(count=1,size=5,rewrites=51507739),input_sha256=measurement.INPUT_SHA256,
        systems=list(measurement.SYSTEMS),configurations=execution_dependencies({name:row['configurations'] for name,row in protocols['workloads'].items()},identities),
        schedule=measurement.schedule(),environment={'BINARYEN_CORES':'1'},inherited_environment={name:os.environ.get(name) for name in measurement.RECORDED_ENVIRONMENT},
        fresh_processes=True,serial_execution=True,
        warmup_scope='Fresh processes discard guest/JIT state every time; discarded warmups may warm machine/file caches only.',
        diagnostic_scope='Forced-GC marked payload/object totals are aggregate snapshots in the diagnostic entry/forced-collection root context. Equal totals would not establish identical survivors or absence of leaks; the observed totals differ. Sampled diagnostic collection peaks are not clean-run peaks, RSS or GC cost.',
        balance='One discarded warmup per workload/system, then seven cyclic rotations per workload: each retained system occupies each position once. Alternate workload blocks between rounds (four/three first blocks). No workload-order or adjacency-balance claim.',
        clock_boundary='Original count1/size5 worker, including setup-boyer and original theorem-success/numeric51507739-rewrite predicate. Scheme quoted constants and three-datum configuration setup precede its clock; complete source kernel and original rewrite count remain. Host serialization/final cleanup follow the clock. Rust retains its separately documented indexed-storage/bit-operation representation.',
        analysis='Retain all seven samples per workload/system; report median/min/max and descriptive ratios to original Chez and native/exact-native-final V8. No trimming, replacement or adaptive stopping.',
        failure_policy='Stop before another row on failed exit, stderr, invalid complete frame/predicate, timeout/interruption, unexpected or surviving original-group descendants, changed executable dependencies/settings. Initial/final broader provenance discrepancies invalidate the campaign. Preserve every attempt.',
        capture_policy='Regular-file stdin/stdout/stderr; actual wait status, original-group inspection, bounded SIGKILL cleanup, closed/fsynced handles and raw bytes precede validation. Frozen guests are non-daemonizing; arbitrary escaped descendants are outside the group check.',
        source_scope='Fresh current Scheme/runtime/native/Chez artifacts. Exact kernels/strict programs/original Chez/full inputs match reviewed historical preparation; current adapted Chez includes exact current library prefix. Counter-free native provider retains original rewrite counter. Exact-native-final V8 shares actual optimized Wasm lowering bytes with scalar-provider import closure. Retention diagnostics use matching LLVM with separate C entry and forced collections, never clean data. Rust binaries/sources are retained author artifacts, freshly executed but not rebuilt. Historical fixed reservations and old diagnostics remain separately identified.',
        protocol_records={name:row['protocol_records'] for name,row in protocols['workloads'].items()},identities=identities)


def main():
    measurement.require(not (REPORT/'timing-plan.json').exists(),'refusing to replace frozen plan')
    prepared = check_preparation()
    check_native_sources()
    frozen = plan(prepared)
    measurement.verify(frozen)
    measurement.save(REPORT/'timing-plan.json',frozen)
    measurement.save(REPORT/'readiness-audit.json',dict(ready=True,clean_measurement_started=False,
        compiler_commit=measurement.BASIS,fresh_complete_frames=14,fresh_predicate_controls=40,
        fresh_retention_processes=4,processes_planned=112,native_gc_current_default=True,
        source_kernels_unchanged=True,native_provider_counter_free=True,
        plan_sha256=measurement.digest(REPORT/'timing-plan.json'),frozen_identities=len(frozen['identities'])))
    print('PASS frozen full Boyer plan;',len(frozen['identities']),'identities;112 processes planned,none launched')


if __name__=='__main__':
    main()
