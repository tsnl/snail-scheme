#!/usr/bin/env python3
"""Compare literal delimiter inputs directly, independent of Chez spelling."""

import importlib.machinery
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
A = Path('/tmp/snail-reader-delimiter-ablation-20261014')


def reader_runner(root, name):
    loader = importlib.machinery.SourceFileLoader(name, str(root / 'scripts/test-strict-reader'))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def main():
    runner, candidate = reader_runner(ROOT, 'baseline_reader'), reader_runner(A, 'candidate_reader')
    runner.OUTPUT = ROOT / 'build/reader-direct-delimiters'
    runner.OUTPUT.mkdir(exist_ok=False)
    artifacts = {'baseline': ROOT / 'build/strict-reader-1792009125320519692',
                 'delimiters': A / 'build/strict-reader-1792008872589570629'}
    cases = {'literal-bars': 'a|b|', 'complete-adjacency': candidate.valid_cases()['delimiter-adjacency'][0]}
    results = {}
    for name, source in cases.items():
        directory = runner.prepare_case(name, source)
        outputs = {}
        for label, path in artifacts.items():
            runner.ARTIFACTS = path
            for kind, command in runner.commands(directory):
                outputs[label + '-' + kind] = runner.run(command, name + '-' + label + '-' + kind, directory)
        assert len(set(outputs.values())) == 1, 'unchanged literal source differs: ' + name
        if name == 'literal-bars':
            assert next(iter(outputs.values())) == 'i:4\ni:1\nc:97\ni:4\ni:1\nc:98\nresult:2\n'
        results[name] = dict(input=source, six_paths_identical=True, complete_trace=next(iter(outputs.values())))
    (runner.OUTPUT / 'validation.json').write_text(json.dumps(results, indent=2) + '\n')
    print('PASS baseline/A literal bars and complete unchanged adjacency on raw/optimized/native')


if __name__ == '__main__':
    main()
