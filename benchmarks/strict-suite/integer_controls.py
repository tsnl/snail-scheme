#!/usr/bin/env python3
"""Build and validate exact-integer comparison controls; never start measurements."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil

import integer_ports as ports

ROOT, HERE = ports.ROOT, ports.HERE
RUST_FEATURES = ['--mvp-features', '--enable-mutable-globals',
    '--enable-nontrapping-float-to-int', '--enable-bulk-memory', '--enable-sign-ext',
    '--enable-reference-types', '--enable-multivalue', '--enable-extended-const',
    '--enable-bulk-memory-opt', '--enable-call-indirect-overlong']


# ---- One boundary: prepare input, compute and compare, then serialize ----

CHEZ_CLOCK = '''(define timed? (member "--time" (command-line)))
(define before (and timed? (current-time 'time-monotonic)))
'''
CHEZ_REPORT = '''(define after (and timed? (current-time 'time-monotonic)))
(write RENDER) (newline)
(when timed?
  (let ((elapsed (time-difference after before)))
    (display "+!CSVLINE!+chez-integer,NAME:") (display count) (display ",")
    (display (+ (time-second elapsed) (/ (time-nanosecond elapsed) 1e9))) (newline)))
'''
CHEZ_EQUALITY = '''(define (same-integers? left right)
  (if (null? left) (null? right)
      (and (not (null? right)) (integer=? (car left) (car right))
           (same-integers? (cdr left) (cdr right)))))
(define (same-rows? left right)
  (if (null? left) (null? right)
      (and (not (null? right)) (same-integers? (car left) (car right))
           (same-rows? (cdr left) (cdr right)))))
(define (lift-list values) (map (lambda (value) (integer-from-string (number->string value))) values))
'''


def chez_program(name, original, adapted, mode):
    source = ports.kernel(original if mode == 'original' else adapted)
    helpers = '(define (square value) (* value value))\n'
    lift, predicate, render = 'expected-input', 'equal?', 'result'
    if mode == 'adapted': helpers += ports.CHEZ_ADAPTER
    if mode == 'limbs':
        source = ports.rewrite_integer_operators(name, source)
        helpers, lift, predicate, render = limb_control(name)
    hide = ports.form((ports.CORPUS/'src/common.scm').read_text(), '(define (hide ')
    driver = f'''(define count (read)) (define first (read)) (define last (read)) (define step (read))
(define expected-input (read)) (define expected {lift})
{CHEZ_CLOCK}(define result
  (let loop ((index 0) (result '()))
    (if (< index count)
        (loop (+ index 1) (pies (hide count first) (hide count last) (hide count step))) result)))
(unless ({predicate} result expected) (error 'benchmark "complete result differs"))
'''
    imports = '(import (except (chezscheme) expt))\n' if mode == 'limbs' else '(import (chezscheme))\n'
    return imports+helpers+source+hide+'\n'+driver+CHEZ_REPORT.replace('RENDER',render).replace('NAME',name)


def limb_control(name):
    helpers = ports.chez_limb_body()+CHEZ_EQUALITY+'''(define (square value) (integer-multiply value value))
(define (expt base exponent)
  (if (integer-value? exponent) (integer-expt base exponent) (integer-power base exponent)))
(define (term-count digits) (integer-from-i64 (exact (floor (+ 2 (/ digits 14.181647462))))))
'''
    if name == 'pi':
        return helpers, '(map lift-list expected-input)', 'same-rows?', '(map (lambda (row) (map (lambda (value) (string->number (integer->string value))) row)) result)'
    return helpers, '(lift-list expected-input)', 'same-integers?', '(map (lambda (value) (string->number (integer->string value))) result)'


def retained_result_probe(source):
    before = '(loop (+ index 1) (pies (hide-i64 input0) (hide-i64 input1) (hide-i64 input2)))'
    after = '''(let ((value (pies (hide-i64 input0) (hide-i64 input1) (hide-i64 input2))))
              (ref-set! saved value) (observe) (loop (+ index 1) value))'''
    edits = []
    result = ports.edit(source, before, after, edits)
    assert ports.restore(result, edits) == source
    return result, edits


# ---- Frozen inputs and full-result negative controls ----

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_input(directory, name, spec):
    target = directory/(name+'.native-input')
    target.write_text(' '.join(map(str,[spec['count'],*spec['inputs'],len(spec['expected'])]))+'\n'+'\n'.join(spec['expected'])+'\n')
    return target


def control_specs(directory, spec):
    controls = [('full',spec)]
    controls += [(f'count-{count}',{**spec,'count':count,'output':spec['output'] if count else '()\n'}) for count in (0,1,2)]
    for label,index in [('wrong-result',0),('wrong-final',-1)]:
        wrong = {**spec,'count':1,'predicate':0,'expected':spec['expected'].copy()}
        wrong['expected'][index] = str(int(wrong['expected'][index])+1)
        controls.append((label,wrong))
    for label,control in controls:
        ports.save(directory/(label+'.spec.json'),control)
        write_input(directory,label,control)
    return controls


def text_inputs(name, data):
    values = ports.read_input(data)
    controls = [('full',data,False)]
    for count in (0,1,2):
        controls.append((f'count-{count}','\n'.join(map(ports.scheme,[count,*values[1:]]))+'\n',count == 0))
    for label,index in [('wrong-result',0),('wrong-final',-1)]:
        wrong = ports.read_input(data)
        if name == 'pi': wrong[4][index][index] += 1
        else: wrong[4][index] += 1
        controls.append((label,'\n'.join(map(ports.scheme,[1,*wrong[1:]]))+'\n',True))
    return controls


def freeze_sources(name,directory):
    original=(ports.CORPUS/'src'/f'{name}.scm').read_text()
    data=(ports.CORPUS/'inputs'/f'{name}.input').read_text()
    adapted,edits=ports.adaptation(name,original)
    assert ports.restore(adapted,edits)==original
    for label,source in [('original',original),('adapted',adapted),('strict',ports.strict_source(name,adapted))]:
        (directory/(label+'.scm')).write_text(source)
    (directory/'input').write_text(data);ports.save(directory/'edits.json',edits)
    return original,adapted,data,ports.specification(name,data)


# ---- Production Wasm and the native-final common module ----

def compile_native(directory,wasm,label,environment):
    executable=directory/label
    ports.execute([ROOT/'scripts/build-native','--wasm','--c-provider','benchmark',
        HERE/'integer-provider.h',HERE/'integer-provider.c','--entry-c',HERE/'integer-control-entry.c',wasm,executable],
        ROOT,directory/(label+'-build.json'),environment)
    build,=directory.glob(label+'.native-*')
    return executable,build/'optimized.wasm'


def validate_wasm(directory,label,module,controls,environment):
    for name,spec in controls:
        actual=ports.execute([environment['NODE'],HERE/'integer-control-host.mjs',module,directory/(name+'.spec.json')],
            directory,directory/(label+'-'+name+'.json'),environment)
        assert actual==spec['output'],(label,name)


def validate_native(directory,label,executable,controls,environment,probe=False):
    for name,spec in controls:
        mode='--probe' if probe else '--reject' if spec.get('predicate')==0 else '--validate'
        actual=ports.execute([executable,directory/(name+'.native-input'),mode],directory,
            directory/(label+'-'+name+'.json'),environment)
        assert actual==spec['output'],(label,name)


def prepare_scheme(directory,spec,environment):
    wasm=directory/'production.wasm'
    ports.execute([ROOT/'scripts/build-strict','--export','bench','--export','observe',directory/'strict.scm',wasm],
        ROOT,directory/'production-build.json',environment)
    native,common=compile_native(directory,wasm,'native',environment)
    shutil.copy2(common,directory/'native-final.wasm')
    controls=control_specs(directory,spec)
    for label,module in [('raw',Path(str(wasm)+'.raw.wasm')),('production',wasm),('native-final',directory/'native-final.wasm')]:
        validate_wasm(directory,label,module,controls,environment)
        ports.execute([environment['WASM_DIS'],module,'-o',directory/(label+'.wat')],directory,
            directory/(label+'-disassemble.json'),environment)
    validate_native(directory,'native',native,controls,environment)


def prepare_probe(directory,spec,environment):
    probe=directory/'retained-results';probe.mkdir()
    source,edits=retained_result_probe((directory/'strict.scm').read_text())
    (probe/'probe.scm').write_text(source);ports.save(probe/'edits.json',edits)
    controls=[]
    for count in (0,1,2,spec['count']):
        control={**spec,'count':count,'per_iteration':True,'output':spec['output']*count}
        label='count-'+str(count);ports.save(probe/(label+'.spec.json'),control)
        write_input(probe,label,control);controls.append((label,control))
    wasm=probe/'probe.wasm'
    ports.execute([ROOT/'scripts/build-strict','--export','bench','--export','observe',probe/'probe.scm',wasm],
        ROOT,probe/'build.json',environment)
    native,common=compile_native(probe,wasm,'native',environment)
    for label,module in [('raw',Path(str(wasm)+'.raw.wasm')),('optimized',wasm),('native-final',common)]:
        validate_wasm(probe,label,module,controls,environment)
    validate_native(probe,'native',native,controls,environment,probe=True)


# ---- Chez executes compiled original, adapted and identical-limb controls ----

def prepare_chez(name,directory,original,adapted,data,spec,environment):
    for mode in ('original','adapted','limbs'):
        source=directory/('chez-'+mode+'.sps');source.write_text(chez_program(name,original,adapted,mode))
        program=directory/('chez-'+mode+'.so');compile_script=directory/('chez-'+mode+'-compile.sps')
        compile_script.write_text('(import (chezscheme))\n(parameterize ((optimize-level 2)) (compile-program '+json.dumps(str(source))+' '+json.dumps(str(program))+'))\n')
        ports.execute([environment['CHEZ'],'--script',compile_script],directory,directory/('chez-'+mode+'-compile.json'),environment)
        for label,stdin,fails in text_inputs(name,data):
            record=directory/('chez-'+mode+'-'+label+'.json')
            actual=ports.execute([environment['CHEZ'],'--program',program],directory,record,environment,stdin,expected='error' if fails else 0)
            if fails: assert 'complete result differs' in json.loads(record.read_text())['stderr']
            else: assert actual==spec['output'],(mode,label)


# ---- Rust references preserve the numerical source and change only reporting ----

def rust_validation_source(source):
    edits=[]
    source=ports.edit(source,'let (start, mut result) = (Instant::now(), Vec::new());',
        'let start = std::env::var_os("SNAIL_INTEGER_TIME").map(|_| Instant::now());\n    let mut result = Vec::new();',edits)
    import re
    call,=re.findall(r'    report\("(?:pi|chudnovsky)", count, start, Pies\(&result\)\);',source)
    source=ports.edit(source,call,'    if let Some(start) = start {\n'+call+'\n    } else { println!("Result: {}", Pies(&result)); }',edits)
    return source,edits


def freeze_rust(output):
    target=output/'rust-reference';target.mkdir()
    original=ROOT/'benchmarks/wasm-reference'
    shutil.copytree(original/'src',target/'src')
    for name in ('Cargo.toml','Cargo.lock','run-wasi.mjs'):shutil.copy2(original/name,target/name)
    for name in ('pi','chudnovsky'):
        path=target/'src/bin'/f'{name}.rs';before=path.read_text();after,edits=rust_validation_source(before)
        assert ports.restore(after,edits)==before
        path.write_text(after);ports.save(target/(name+'-reporting-edits.json'),edits)
    return target


def prepare_rust(name,target,directory,data,spec,environment):
    environment={**environment,'CARGO_TARGET_DIR':str(target/'target')}
    for label,args in [('tests',['test','--offline','--bin',name]),
        ('native-build',['rustc','--offline','--release','--bin',name,'--','--emit=asm,llvm-ir']),
        ('wasm-build',['rustc','--offline','--release','--target','wasm32-wasip1','--bin',name,'--','--emit=llvm-ir'])]:
        ports.execute(['cargo',*args],target,target/(name+'-'+label+'.json'),environment)
    executable=target/(name+'-native');shutil.copy2(target/'target/release'/name,executable)
    raw=target/(name+'.raw.wasm');shutil.copy2(target/'target/wasm32-wasip1/release'/f'{name}.wasm',raw)
    optimized=target/(name+'.wasm')
    ports.execute([environment['WASM_OPT'],'-O3','-g',*RUST_FEATURES,raw,'-o',optimized],target,target/(name+'-optimize.json'),environment)
    commands=[('native',[executable]),('raw',[environment['NODE'],'--disable-warning=ExperimentalWarning',target/'run-wasi.mjs',raw]),
        ('optimized',[environment['NODE'],'--disable-warning=ExperimentalWarning',target/'run-wasi.mjs',optimized])]
    for kind,command in commands:
        for label,stdin,fails in text_inputs(name,data):
            record=target/(name+'-'+kind+'-'+label+'.json')
            actual=ports.execute(command,target,record,environment,stdin,expected='error' if fails else 0)
            if fails: assert 'assertion' in json.loads(record.read_text())['stderr']
            else: assert actual=='Result: '+spec['output'],(name,kind,label)
    ports.execute([environment['WASM_DIS'],optimized,'-o',target/(name+'.wat')],target,target/(name+'-disassemble.json'),environment)


# ---- Frozen preparation dependencies and explicit later timing commands ----

def preparation_sources():
    return [*sorted(path for path in HERE.glob('integer*') if path.is_file()),HERE/'data_ports.py',
        ROOT/'src/snail/integer.sld',ROOT/'src/native.c',ROOT/'src/precise-gc.c']


def freeze_preparation(output,environment):
    identities={}
    for source in preparation_sources():
        relative=source.relative_to(ROOT);target=output/'frozen'/relative
        target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
        identities[str(relative)]=digest(source)
    code='import sys; sys.path.insert(0, '+repr(str(output/'frozen/benchmarks/strict-suite'))+'); import integer_controls, integer_ports, data_ports; print("PASS frozen preparation imports")'
    ports.execute([os.sys.executable,'-I','-B','-c',code],output,output/'frozen-imports.json',environment)
    ports.save(output/'frozen-sources.json',identities)
    return identities


def record_tools(output,environment):
    tools={}
    for variable,default in [('NODE','node'),('CHEZ','scheme'),('CHIBI','chibi-scheme'),
        ('WASM_AS','wasm-as'),('WASM_OPT','wasm-opt'),('WASM_DIS','wasm-dis'),
        ('CLANG','clang'),('CARGO','cargo'),('RUSTC','rustc'),('LLD','ld.lld'),
        ('PYTHON',os.sys.executable),('OBJDUMP','objdump')]:
        path=Path(shutil.which(environment.get(variable,default)))
        version=ports.execute([path,'-V' if variable=='CHIBI' else '--version'],output,output/('tool-'+variable.lower()+'.json'),environment)
        stderr=json.loads((output/('tool-'+variable.lower()+'.json')).read_text())['stderr']
        tools[variable]=dict(path=str(path),realpath=str(path.resolve()),sha256=digest(path),version=(version+stderr).strip())
    versions=ports.execute([environment['NODE'],'-p','JSON.stringify(process.versions)'],output,output/'node-components.json',environment)
    tools['NODE']['components']=json.loads(versions)
    ports.save(output/'tools.json',tools)
    return tools


def timing_plan(output,environment):
    commands=[];host=output/'frozen/benchmarks/strict-suite/integer-control-host.mjs'
    for name in ('pi','chudnovsky'):
        directory=output/name;rust=output/'rust-reference'
        for kind,module in [('production-v8','production.wasm'),('native-final-v8','native-final.wasm')]:
            commands.append(dict(name=name,system=kind,command=[environment['NODE'],str(host),str(directory/module),str(directory/'full.spec.json'),'--time']))
        commands.append(dict(name=name,system='native64',command=[str(directory/'native'),str(directory/'full.native-input'),'--time']))
        for mode in ('original','adapted','limbs'):
            commands.append(dict(name=name,system='chez-'+mode,command=[environment['CHEZ'],'--program',str(directory/('chez-'+mode+'.so')),'--time'],stdin=str(directory/'input')))
        commands.append(dict(name=name,system='rust-native',command=[str(rust/(name+'-native'))],stdin=str(directory/'input'),environment={'SNAIL_INTEGER_TIME':'1'}))
        commands.append(dict(name=name,system='rust-wasm',command=[environment['NODE'],'--disable-warning=ExperimentalWarning',str(rust/'run-wasi.mjs'),str(rust/(name+'.wasm'))],stdin=str(directory/'input'),environment={'SNAIL_INTEGER_TIME':'1'}))
    return commands


def freeze_plan(output,environment):
    commands=timing_plan(output,environment);identities={}
    for row in commands:
        row['cwd']=str(output);row['artifact_sha256']={}
        for value in [*row['command'],row.get('stdin','')]:
            path=Path(value)
            if value and path.is_file():
                if value not in identities: identities[value]=digest(path)
                row['artifact_sha256'][value]=identities[value]
    for name in ('pi','chudnovsky'):
        build,=(output/name).glob('native.native-*')
        assert digest(build/'optimized.wasm')==digest(output/name/'native-final.wasm')
    ports.save(output/'timing-plan.json',dict(measurement_started=False,commands=commands,
        environment_guard={name:environment.get(name) for name in ['NODE_OPTIONS','SNAIL_NATIVE_GC_INTERVAL',
            'SNAIL_GC_HEAP_BYTES','SNAIL_GC_MIN_BYTES','SNAIL_GC_STATS','CHEZSCHEMELIBDIRS','SCHEMEHEAPDIRS']},
        clock_boundary='Input/expected parsing and module initialization precede the clock; computation and final complete numeric predicate are inside; serialization follows.',
        invocation_policy='Verify hashes and environment; coordinate a quiet window; run fresh processes serially. This plan does not launch timing.'))


# ---- Readiness is a result of this invocation, never a cached success ----

def prepare(name,output,rust,environment):
    directory=output/name;directory.mkdir()
    original,adapted,data,spec=freeze_sources(name,directory)
    prepare_scheme(directory,spec,environment);print('PASS '+name+': Scheme targets and negative controls',flush=True)
    prepare_probe(directory,spec,environment);print('PASS '+name+': complete result from every original repetition',flush=True)
    prepare_chez(name,directory,original,adapted,data,spec,environment)
    prepare_rust(name,rust,directory,data,spec,environment)
    ports.save(directory/'validated.json',dict(passed=True,count=spec['count'],input_sha256=hashlib.sha256(data.encode()).hexdigest(),
        output_sha256=hashlib.sha256(spec['output'].encode()).hexdigest(),diagnostic_only=True,no_clock_started=True))
    print('PASS '+name+': all eight requested controls; no measurement started',flush=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'build/strict-integer-controls')
    options=parser.parse_args();output=options.output.resolve();output.mkdir(parents=True)
    environment={**os.environ,'BINARYEN_CORES':'1'}
    environment.pop('SNAIL_INTEGER_TIME',None)
    for name,default in [('NODE','node'),('CHEZ','scheme'),('WASM_OPT','wasm-opt'),('WASM_DIS','wasm-dis')]:
        environment[name]=shutil.which(environment.get(name,default))
    assert ports.execute(['git','-C',ports.CORPUS,'rev-parse','HEAD'],ROOT,output/'corpus-revision.json',environment).strip()==ports.REVISION
    assert not ports.execute(['git','-C',ports.CORPUS,'status','--porcelain','--untracked-files=no'],ROOT,output/'corpus-status.json',environment)
    frozen=freeze_preparation(output,environment);record_tools(output,environment)
    rust=freeze_rust(output)
    for name in ('pi','chudnovsky'):prepare(name,output,rust,environment)
    assert all(digest(ROOT/path)==identity for path,identity in frozen.items())
    freeze_plan(output,environment)
    paths=['src/snail/integer.sld','src/native.c','src/precise-gc.c','scripts/build-native','scripts/build-strict']
    ports.save(output/'validated.json',dict(passed=True,diagnostic_only=True,no_clock_started=True,
        source_sha256={path:digest(ROOT/path) for path in paths},corpus_revision=ports.REVISION,
        control_source_sha256={path.name:digest(path) for path in HERE.glob('integer*') if path.is_file()}))


if __name__=='__main__':main()
