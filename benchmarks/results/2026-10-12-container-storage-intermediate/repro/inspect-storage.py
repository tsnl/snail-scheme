#!/usr/bin/env python3
"""Retain actual GC data definitions and mapped operation sites from Wasm."""
import argparse
import hashlib
import importlib.util
import json
import subprocess
from collections import Counter
from pathlib import Path

ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('wat',ROOT/'instrument-wasm.py')
wat=importlib.util.module_from_spec(spec);spec.loader.exec_module(wat)
DIS='/nix/store/nd1279k2zlbp23gfqcl0qp5xk40xlxr8-binaryen-132/bin/wasm-dis'


def walk(node):
    if isinstance(node,list):
        yield node
        for child in node:yield from walk(child)


def field(node):
    value=node[-1] if wat.head(node)=='field' else node
    mutable=wat.head(value)=='mut'
    return {'mutable':mutable,'storage_type':wat.write_wat(value[1] if mutable else value)}


def descriptor(body):
    if wat.head(body)=='sub':
        result=descriptor(body[-1]);result['supertypes']=[n for n in body[1:-1] if isinstance(n,str) and n.startswith('$')];return result
    if wat.head(body)=='struct':return {'kind':'struct','fields':[field(n) for n in body[1:] if wat.head(n)=='field']}
    if wat.head(body)=='array':return {'kind':'array','element':field(body[1])}
    return {'kind':wat.head(body),'definition':body}


def operation_sites(function):
    sites=Counter()
    for node in walk(function):
        operation=wat.head(node)
        if operation in ['array.new','array.new_fixed','array.new_default','array.new_data','array.new_elem','struct.new','struct.new_default','array.get','array.get_u','array.get_s','array.set','array.copy','array.fill','struct.get','struct.get_s','struct.get_u','struct.set']:
            key=(operation,node[1],node[2] if operation in ['struct.get','struct.get_s','struct.get_u','struct.set','array.copy'] else None)
            sites[key]+=1
    return [{'operation':k[0],'type':k[1],'field_or_source_type':k[2],'static_sites':v} for k,v in sites.items()]


def inspect(program,output):
    output.mkdir(parents=True,exist_ok=True);text=output/'original.wat'
    command=[DIS,str(program),'-o',str(text)];subprocess.run(command,check=True)
    module=wat.read_wat(text.read_text());types={name:descriptor(body) for name,body in wat.definitions(module).items()}
    imports=[n for n in module if wat.head(n)=='import' and wat.head(n[3])=='func']
    functions=[]
    for index,node in enumerate([n for n in module if wat.head(n)=='func'],len(imports)):
        sites=operation_sites(node)
        functions.append({'wasm_index':index,'name':node[1],'parameters':[n for n in node if wat.head(n)=='param'],
                          'result':[n for n in node if wat.head(n)=='result'],'storage_sites':sites})
    result={'program':str(program),'program_sha256':hashlib.sha256(program.read_bytes()).hexdigest(),'disassembly_command':command,
            'imported_function_count':len(imports),'types':types,'functions':functions,
            'proof_caveat':'Definitions/sites are static evidence only. Map source roles and pair with reached-site counts; boxed scalar payload types do not prove specialized user-container/capture storage.'}
    (output/'storage-shapes.json').write_text(json.dumps(result,indent=2)+'\n')
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('program',type=Path);parser.add_argument('output',type=Path)
    args=parser.parse_args();result=inspect(args.program,args.output)
    print([(name,value) for name,value in result['types'].items() if value['kind']=='array'])


if __name__=='__main__':main()
