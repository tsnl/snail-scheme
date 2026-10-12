#!/usr/bin/env python3
"""Restore checked archived inputs, then optionally repeat one observer mode."""
import argparse
import copy
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

REPORT=Path(__file__).resolve().parent.parent

# ---- Checked content-addressed restoration ----


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def restore_blobs(archive_path,manifest,output):
    if digest(archive_path)!=manifest['archive_sha256']:raise ValueError('archive checksum differs')
    directory=output/'blobs';directory.mkdir()
    seen=set()
    with tarfile.open(archive_path,'r|xz') as archive:
        for member in archive:
            if not member.isfile() or not re.fullmatch(r'blobs/[0-9a-f]{64}',member.name):
                raise ValueError('unexpected archive entry')
            checksum=member.name.split('/')[1];data=archive.extractfile(member).read()
            if hashlib.sha256(data).hexdigest()!=checksum:raise ValueError('blob checksum differs')
            if checksum in seen:raise ValueError('duplicate blob')
            path=directory/checksum;path.write_bytes(data);path.chmod(0o444);seen.add(checksum)
    if len(seen)!=manifest['blob_count'] or seen!=set(manifest['logical_files'].values()):
        raise ValueError('archive manifest coverage differs')


def restore_files(manifest,output):
    for name,checksum in manifest['logical_files'].items():
        relative=Path(name)
        if relative.is_absolute() or '..' in relative.parts:raise ValueError('unsafe logical path')
        path=output/'files'/relative;path.parent.mkdir(parents=True,exist_ok=True)
        os.link(output/'blobs'/checksum,path)


def environment(manifest):
    env=dict(os.environ)
    for name,value in manifest['experiment_environment'].items():
        if value is None:env.pop(name,None)
        else:env[name]=value
    tools=manifest['tools']
    directories=[str(Path(info['path']).parent) for info in tools.values() if info and info.get('path')]
    env['PATH']=os.pathsep.join(dict.fromkeys(directories))+os.pathsep+env.get('PATH','')
    return env


# ---- Relocated reports preserve original source and artifact hashes ----


def restore_report(label,manifest,output):
    name='d277-chez-reference' if label=='d277' else 'd4-prepared'
    source_path=output/'files'/manifest['reports'][name]['logical']
    report=json.loads(source_path.read_text());directory=output/('prepared-'+label);directory.mkdir()
    host=output/'files/host'
    inputs=output/'files/inputs';(directory/'inputs').symlink_to(inputs)
    (directory/'host').symlink_to(host)
    cases=[]
    for key,entry in manifest['cases'].items():
        case=copy.deepcopy(entry['case'])
        if not (key.startswith(label+'-') or label=='d277' and key.startswith('chez-')):continue
        case_directory=output/'files'/entry['prefix'];(case_directory/'outputs').mkdir(exist_ok=True)
        case.update(directory=str(case_directory),samples=[],status='ready')
        case.pop('preliminary',None)
        if key.startswith('chez-'):
            case['system']='chez';case['command']=[case['command'][0],'--program',str(case_directory/'program.so')]
        else:
            case['system']='snail-wasm';case['command']=[case['command'][0],'--no-warnings',str(host/'scripts/run-wasi.mjs'),str(case_directory/'program.wasm')]
        cases.append(case)
    report.update(cases=cases,output=str(directory),systems=['snail-wasm','chez'] if label=='d277' else ['snail-wasm'])
    report['input_sha256']={k:v for k,v in report['input_sha256'].items() if not k.startswith('inputs/') or k in manifest['inputs']}
    report['relocated_source']={'original_sha256':digest(source_path),'original_output':json.loads(source_path.read_text())['output']}
    path=directory/'results.json';path.write_text(json.dumps(report,indent=2)+'\n');return path


def runner(output):
    root=output/'runner';build=root/'build';build.mkdir(parents=True)
    (root/'benchmarks').mkdir()
    for path in (REPORT/'repro').iterdir():
        if path.is_file():shutil.copyfile(path,build/path.name)
    shutil.copyfile(REPORT/'repro/r7rs.py',root/'benchmarks/r7rs.py')
    return root


def check_tools(manifest):
    for name in ['NODE','CHEZ']:
        tool=manifest['tools'][name]
        if digest(Path(tool['path']))!=tool['sha256']:raise ValueError('tool binary differs: '+name)


def import_helper(path,name):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module);return module


# ---- Fresh observer executions use untouched restored binaries ----


def vector(output,root):
    module=import_helper(root/'build/measure-vector.py','vector')
    module.ROOT=root;module.HOST=output/'files/host/scripts/run-wasi.mjs'
    module.PROGRAMS={'d277-reference':output/'files/vector-append-d277/reference/program.wasm',
                     'd4-reference':output/'files/vector-append/reference/program.wasm',
                     'd4-public':output/'files/vector-append/public/program.wasm'}
    module.OUTPUT=output/'fresh-vector'
    source=output/'files/reports/vector-pilot.json';frozen=json.loads(source.read_text())
    frozen.update(module.provenance());frozen['relocated_source_sha256']=digest(source)
    pilot=root/'build/vector-pilot';pilot.mkdir()
    (pilot/'frozen-inputs.json').write_text(json.dumps(frozen,indent=2)+'\n');module.measure()


def counters(output,root,reports):
    module=import_helper(root/'build/count-five.py','counts')
    for label,path in reports.items():
        prepared=root/'build'/('counter-report-'+label);prepared.mkdir()
        report=json.loads(path.read_text());report['cases']=[c for c in report['cases'] if c['system']=='snail-wasm']
        (prepared/'host').symlink_to(path.parent/'host')
        (prepared/'results.json').write_text(json.dumps(report,indent=2)+'\n')
        module.ROOT=root;module.PREPARED=prepared;module.OUTPUT=output/'fresh-counters'/label;module.main()


def sampling(output,root,reports):
    previous=root/'build/final-five-clean';previous.mkdir()
    shutil.copyfile(output/'files/reports/final-five-clean.json',previous/'results.json')
    module=import_helper(root/'build/profile-paired.py','sampling')
    module.REPORTS=reports;module.OUTPUT=output/'fresh-sampling';module.main()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--experiment',choices=['five','vector','counters','sampling'],default='five')
    parser.add_argument('--restore-only',action='store_true')
    parser.add_argument('--cpu',type=int,default=5);parser.add_argument('--rounds',type=int,default=3)
    args=parser.parse_args();output=args.output.resolve();output.mkdir()
    manifest=json.loads((REPORT/'manifest.json').read_text());restore_blobs(REPORT/'artifacts.tar.xz',manifest,output)
    restore_files(manifest,output);check_tools(manifest)
    reports={label:restore_report(label,manifest,output) for label in ['d277','d4']};root=runner(output)
    command=[sys.executable,str(root/'build/compare-frozen.py'),str(reports['d277']),str(reports['d4']),
             '--output',str(output/'preflight'),'--cpu',str(args.cpu),'--rounds',str(args.rounds),'--prepare-only']
    env=environment(manifest);subprocess.run(command,cwd=root,env=env,check=True)
    (output/'restoration.json').write_text(json.dumps({'all_blob_hashes_valid':True,'blob_count':manifest['blob_count'],
        'logical_file_count':len(manifest['logical_files']),'case_count':15,'comparator_preflight_passed':True},indent=2)+'\n')
    if args.restore_only:return
    os.environ.clear();os.environ.update(env)
    if args.experiment=='five':
        command=command[:-1];command[command.index(str(output/'preflight'))]=str(output/'fresh-five')
        subprocess.run(command,cwd=root,env=env,check=True)
    else:
        if args.cpu!=5 or args.rounds!=3:raise ValueError('original vector/observer helpers retain CPU5 and their fixed observer protocol')
        if args.experiment=='vector':vector(output,root)
        elif args.experiment=='counters':counters(output,root,reports)
        else:sampling(output,root,reports)


if __name__=='__main__':
    main()
