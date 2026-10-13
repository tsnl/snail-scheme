#!/usr/bin/env python3
"""Retain counter-only correctness runs; discard observer elapsed times."""
import argparse
import hashlib
import json
import subprocess
from collections import defaultdict
from pathlib import Path

ROOT=Path(__file__).resolve().parent
NODE='/nix/store/lfaydgacdyngci7p60s8wwvgdm74fjkx-nodejs-24.19.0/bin/node'
HOST=ROOT/'counting-host/scripts/run-counted.mjs'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(observer,source,name):
    output=observer/name;output.mkdir(exist_ok=False)
    program=observer/'instrumented.wasm';manifest=json.loads((observer/'manifest.json').read_text())
    (output/'input.txt').write_text(source)
    command=[NODE,'--no-warnings',str(HOST),str(program.resolve())]
    result=subprocess.run(command,input=source,text=True,capture_output=True,cwd=output,timeout=180)
    (output/'stdout.txt').write_text(result.stdout);(output/'stderr.txt').write_text(result.stderr)
    if result.returncode or not any(line.startswith(('+!STORAGE!+','+!REPRESENTATION_COVERAGE!+')) for line in result.stdout.splitlines()):
        raise ValueError('counter correctness failed: '+str(output))
    counters=json.loads(next(line.removeprefix('+!PROBES!+') for line in result.stderr.splitlines() if line.startswith('+!PROBES!+')))['counters']
    rows=[{**item,'requests':int(counters[item['export']])} for item in manifest['counters']]
    totals=defaultdict(int)
    for row in rows:totals[tuple(row['key'][0:1]+row['key'][2:])]+=row['requests']
    report={'mode':'Counter-only full invocation under concurrent agent builds; emitted elapsed values are excluded as evidence.',
            'command':command,'node_sha256':digest(Path(NODE)),'host_sha256':digest(HOST),'program_sha256':digest(program),
            'input':source,'input_sha256':digest(output/'input.txt'),'returncode':result.returncode,'passed':True,
            'counters':rows,'operation_totals':[{'key':list(key),'requests':value} for key,value in sorted(totals.items())],
            'caveat':manifest['caveat']}
    (output/'counts.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'output':str(output),'passed':True,'nonzero_counter_rows':sum(row['requests']>0 for row in rows)}),flush=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('observer',type=Path);parser.add_argument('input',type=Path);parser.add_argument('--name',required=True)
    args=parser.parse_args();run(args.observer.resolve(),args.input.read_text(),args.name)


if __name__=='__main__':main()
