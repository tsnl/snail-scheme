"""Contrast mechanical LLVM lowering choices without changing Scheme IR."""
import json
import os
from pathlib import Path
import re
import experiment as e

source=e.BUILD/'direct-src'
for path in (e.ROOT/'src').rglob('*.sld'):
    target=source/path.relative_to(e.ROOT/'src')
    target.parent.mkdir(parents=True,exist_ok=True)
    target.write_bytes(path.read_bytes())
llvm=source/'snail-scheme/llvm.sld'
text=llvm.read_text()
old='''             (reference (new-array name (constant "i32" length) (constant "i64" 0))))
        (for-each (lambda (value index)
                    (store (cast "trunc" value type)
                           (array-slot reference (constant "i32" index) type)))'''
new='''             (reference (call-native "native_alloc" "i64"
                                     (list (constant "i64" (+ 16 (* 8 length)))))))
        (store (constant "i64" (type-id name)) (field-pointer reference 0 "i64"))
        (store (constant "i64" length) (field-pointer reference 1 "i64"))
        (for-each (lambda (value index)
                    (store (cast "trunc" value type)
                           (field-pointer reference (+ index 2) type)))'''
assert old in text
llvm.write_text(text.replace(old,new))
flags=['-lgc','-lm','-ldl','-lpthread','-I',os.environ['BDWGC_INCLUDE'],
       '-L',os.environ['BDWGC_LIB'],'-Wl,-rpath,'+os.environ['BDWGC_LIB']]
records=[]
for workload in e.WORKLOADS:
    output=e.BUILD/f'{workload}-fixed'
    output.with_suffix('.wat').write_bytes((e.BUILD/f'{workload}.wat').read_bytes())
    e.run(['chibi-scheme','-h512M','-I',source,e.BUILD/'translate.scm',output])
    for variant in ('fixed','fastcc','align','inbounds'):
        original=e.BUILD/f'{workload}.ll'
        contents=output.with_suffix('.ll').read_text() if variant=='fixed' else original.read_text()
        if variant=='fastcc': contents=contents.replace('tailcc','fastcc')
        if variant=='align':
            def align(m):
                width={'i8':1,'i16':2,'i32':4,'float':4,'i64':8,'double':8,'ptr':8}.get(m[2],1)
                return m[1]+', align '+str(width)
            contents=re.sub(r'((?:store|load) (i\d+|float|double|ptr) [^\n]*), align 1',align,contents)
        if variant=='inbounds':contents=contents.replace('getelementptr i64','getelementptr inbounds i64')
        ll=e.BUILD/f'{workload}-{variant}.ll'
        ll.write_text(contents)
        command=['clang','-O3','-flto','-fuse-ld=lld',ll,e.ROOT/'src/native.c',e.BUILD/'runtime.a',*flags,'-o',e.BUILD/f'{workload}-{variant}']
        result=e.run(command)
        records.append({'variant':variant,'workload':workload,'command':list(map(str,command)),
                        'llvm_sha256':e.digest(ll),'stderr':result.stderr})
        (e.BUILD/'lowering-builds.json').write_text(json.dumps(records,indent=2)+'\n')
        print('prepared lowering',workload,variant,flush=True)
