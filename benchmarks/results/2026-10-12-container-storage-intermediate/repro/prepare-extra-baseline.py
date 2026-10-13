#!/usr/bin/env python3
"""Append independent fixture artifacts without changing the frozen first set."""
import importlib.util
import json
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('prep',ROOT/'prepare-baseline.py')
prep=importlib.util.module_from_spec(spec);spec.loader.exec_module(prep)
prep.ENV.update({'WASM_MERGE':str(ROOT/'tools/capture-wasm-merge'),
                 'SNAIL_CAPTURE_SHARED_DIRECTORY':str(ROOT/'captured-inputs')})


def main():
    path=ROOT/'extra-baseline-preparation.json'
    report=json.loads(path.read_text()) if path.exists() else {'revision':'f07d1eb12f7c7234463a606a09190325a3c906b5','production_code_revision':'d4f0d4203a8adc9cd1f1f338d991da31794ae725','cases':[]}
    for name in sys.argv[1:]:
        case=prep.prepare(name)
        case['checks']=[prep.check(case,'8\n3\n',0)]
        case['environment']={key:prep.ENV.get(key) for key in ['PATH','BINARYEN_CORES','WASM_MERGE','SNAIL_REAL_WASM_MERGE','SNAIL_CAPTURE_SHARED_DIRECTORY','NODE_OPTIONS','RUSTFLAGS']}
        report['cases'].append(case);path.write_text(json.dumps(report,indent=2)+'\n')
        print(name,'prepared and checked',flush=True)


if __name__=='__main__':main()
