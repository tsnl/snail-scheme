#!/usr/bin/env python3
"""Verify/restore archived modules; optionally repeat their frozen clean counts."""
import argparse
import hashlib
import importlib.util
import json
import os
import re
import sys
import tarfile
from pathlib import Path

REPORT=Path(__file__).resolve().parent.parent
sys.dont_write_bytecode=True


# ---- Content-addressed restoration ----


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def restore(manifest,output):
    archive_path=REPORT/'artifacts.tar.xz'
    if digest(archive_path)!=manifest['archive_sha256']:raise ValueError('archive checksum mismatch')
    directory=output/'blobs';directory.mkdir();seen=set()
    with tarfile.open(archive_path,'r|xz') as archive:
        for member in archive:
            if not member.isfile() or not re.fullmatch(r'blobs/[0-9a-f]{64}',member.name):raise ValueError('unexpected archive entry')
            checksum=member.name.split('/')[1];data=archive.extractfile(member).read()
            if hashlib.sha256(data).hexdigest()!=checksum or checksum in seen:raise ValueError('blob checksum/uniqueness mismatch')
            path=directory/checksum;path.write_bytes(data);path.chmod(0o444);seen.add(checksum)
    if seen!=set(manifest['logical_files'].values()) or len(seen)!=manifest['blob_count']:raise ValueError('manifest coverage mismatch')
    for name,checksum in manifest['logical_files'].items():
        relative=Path(name)
        if relative.is_absolute() or '..' in relative.parts:raise ValueError('unsafe logical path')
        path=output/'files'/relative;path.parent.mkdir(parents=True,exist_ok=True);os.link(directory/checksum,path)


# ---- Relocated original artifacts retain their recorded hashes ----


def helper(output):
    path=REPORT/'repro/run-clean-controls.py'
    spec=importlib.util.spec_from_file_location('clean',path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    module.ROOT=output/'files/trees/candidate';module.BASE=output/'files/trees/baseline'
    return module


def check_preflight(module,manifest):
    result=module.preflight();expected=manifest['clean_comparability']
    for key in ['tools','host']:
        if result[key]!=expected[key]:raise ValueError('runtime/host differs: '+key)
    old={(c['case'],c['variant']):c for c in expected['modules']}
    for row in result['modules']:
        reference=old[(row['case'],row['variant'])]
        if any(row[k]!=reference[k] for k in ['module_sha256','source_sha256','module_bytes']):raise ValueError('module differs')
    return len(result['modules'])


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--run-clean',action='store_true');args=parser.parse_args()
    manifest=json.loads((REPORT/'manifest.json').read_text());output=args.output.resolve();output.mkdir(exist_ok=False)
    restore(manifest,output);module=helper(output);case_count=check_preflight(module,manifest)
    check={'all_blob_hashes_valid':True,'blob_count':manifest['blob_count'],'logical_file_count':len(manifest['logical_files']),
           'clean_preflight_cases':case_count,'clean_comparability_passed':True}
    (output/'restoration.json').write_text(json.dumps(check,indent=2)+'\n');print(json.dumps(check),flush=True)
    if not args.run_clean:return
    frozen=json.loads((output/'files/reports/clean-controls.json').read_text())
    module.calibrate=lambda directory,records:frozen['configs']
    for key in ['NODE_OPTIONS','RUSTFLAGS']:os.environ.pop(key,None)
    sys.argv=['run-clean-controls.py','--execute'];module.main()
    result=module.ROOT/'build/clean-controls/results.json';record=json.loads(result.read_text())
    record['quiet_coordination']='Reproduction invocation; host quiet must be coordinated separately by its operator.'
    record['replayed_original_result_sha256']=digest(output/'files/reports/clean-controls.json')
    result.write_text(json.dumps(record,indent=2)+'\n')


if __name__=='__main__':main()
