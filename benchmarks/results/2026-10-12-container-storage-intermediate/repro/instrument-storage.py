#!/usr/bin/env python3
"""Count reached container/capture access sites in copied frozen Wasm."""
import argparse
import hashlib
import importlib.util
import json
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('wat',ROOT/'instrument-wasm.py')
wat=importlib.util.module_from_spec(spec);spec.loader.exec_module(wat)
TOOLS='/nix/store/nd1279k2zlbp23gfqcl0qp5xk40xlxr8-binaryen-132/bin'


# ---- Access result types ----


class StorageInstrumentation(wat.Instrumentation):
    def composite(self,name):
        result=self.types[name]
        while wat.head(result)=='sub':result=result[-1]
        return result

    def field_type(self,node):
        value=node[-1] if wat.head(node)=='field' else node
        if wat.head(value)=='mut':value=value[1]
        return 'i32' if value in ['i8','i16'] else value

    def access_result(self,node):
        operation=wat.head(node);body=self.composite(node[1])
        if operation in ('array.get','array.get_s','array.get_u'):
            return [self.field_type(body[1])]
        if operation in ('struct.get','struct.get_s','struct.get_u'):
            fields=[n for n in body[1:] if wat.head(n)=='field']
            return [self.field_type(fields[int(node[2])])]
        return []

    def visit(self,node,function):
        rewritten=super().visit(node,function)
        if wat.head(node) not in ('array.get','array.get_s','array.get_u','array.set','array.copy','array.fill','struct.get','struct.get_s','struct.get_u','struct.set'):
            return rewritten
        discriminator=node[2] if wat.head(node) in ('struct.get','struct.get_s','struct.get_u','struct.set','array.copy') else '-'
        return self.wrap(rewritten,self.access_result(node),('storage-access',function,wat.head(node),node[1],discriminator))


# ---- Frozen diagnostic artifacts ----


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=False)
    original=args.output/'original.wat'
    subprocess.run([TOOLS+'/wasm-dis',str(args.input),'-o',str(original)],check=True)
    observer=StorageInstrumentation(wat.read_wat(original.read_text()))
    source=args.output/'instrumented.wat';source.write_text(wat.write_wat(observer.transform())+'\n')
    artifact=args.output/'instrumented.wasm'
    features=['--mvp-features','--enable-gc','--enable-reference-types','--enable-tail-call','--enable-mutable-globals','--enable-sign-ext','--enable-bulk-memory','--enable-nontrapping-float-to-int']
    subprocess.run([TOOLS+'/wasm-as',str(source),'-o',str(artifact),*features,'-g'],check=True)
    report={'input':str(args.input),'input_sha256':digest(args.input),'instrumented_sha256':digest(artifact),'counters':observer.metadata(),'types':observer.types,
            'scope':'Full invocation including initialization/checking, function bodies only; constant global initializers excluded.',
            'caveat':'Counts mark reached sites before operand evaluation, including possible failed/aborted operands. They are not completed operations or physical allocations. Scalar boxes do not establish concrete container/capture storage. Instrumentation changes optimization; timings are excluded.'}
    (args.output/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'input':str(args.input),'counters':len(report['counters'])}))


if __name__=='__main__':main()
