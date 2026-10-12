#!/usr/bin/env python3
"""Collect paired whole-process CPU samples and GC traces after clean runs."""
import hashlib
import importlib.util
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('profiles',ROOT/'build/profile-utils.py')
profiles=importlib.util.module_from_spec(spec);spec.loader.exec_module(profiles)
r7rs=profiles.r7rs
REPORTS={
    'd277':Path('/tmp/snail-v8-candidate-d2770ab-20261012/build/v8-worst-five/results.json'),
    'd4':ROOT/'build/final-five-prepared/results.json',
}
OUTPUT=ROOT/'build/paired-sampling'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def invoke(label, report, case):
    directory=OUTPUT/label/case['benchmark']
    directory.mkdir(parents=True)
    artifact=Path(case['directory'])/'program.wasm'
    host=Path(report['output'])/'host/scripts/run-wasi.mjs'
    r7rs.check_hashes(Path(case['directory']),case['artifact_sha256'])
    r7rs.check_hashes(Path(report['output'])/'host',report['host_sha256'])
    command=['taskset','-c','5',case['command'][0],'--no-warnings','--trace-gc-nvp','--cpu-prof',
             '--cpu-prof-dir='+str(directory),'--cpu-prof-name=profile.cpuprofile',str(host),str(artifact)]
    result=r7rs.execute(command,case['directory'],600,(Path(case['directory'])/'input.txt').read_bytes())
    stdout,stderr=result.pop('stdout'),result.pop('stderr')
    (directory/'stdout.txt').write_text(stdout);(directory/'stderr.txt').write_text(stderr)
    result.update(command=command,artifact_sha256=digest(artifact),runner_sha256=digest(host),
                  label=label,benchmark=case['benchmark'],recorded_at_utc=datetime.now(timezone.utc).isoformat(),
                  scope='Complete fresh Node process including initialization, checks, and output. Original immutable Wasm module with CPU sampling and GC tracing only; observer timings are excluded from clean comparisons.')
    if result['status']=='ok':
        result.update(r7rs.parse_result(stdout,'snail-scheme',case['benchmark']))
        if case['benchmark']=='cat': result['cat_bytes_check']=profiles.cat_check(case)
    (directory/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    if result['status']!='ok': raise ValueError('profile correctness failed: '+str(directory))
    compact={'execution':result,'gc':profiles.gc_summary(stdout),'cpu_profile':profiles.profile_summary(directory/'profile.cpuprofile')}
    (directory/'summary.json').write_text(json.dumps(compact,indent=2)+'\n')
    print(label,case['benchmark'],'sampling passed',compact['gc']['allocated_bytes_reported_at_gc'],flush=True)
    return compact


def main():
    if not json.loads((ROOT/'build/final-five-clean/results.json').read_text())['complete']:
        raise ValueError('clean final matrix must finish first')
    reports={label:json.loads(path.read_text()) for label,path in REPORTS.items()}
    cases={label:{c['benchmark']:c for c in report['cases'] if c['system']=='snail-wasm'} for label,report in reports.items()}
    labels=list(reports);summary={}
    for index,benchmark in enumerate(['cat','lattice','wc','graphs','deriv']):
        summary[benchmark]={}
        for label in labels[index%2:]+labels[:index%2]:
            summary[benchmark][label]=invoke(label,reports[label],cases[label][benchmark])
        (OUTPUT/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')


if __name__=='__main__':
    main()
