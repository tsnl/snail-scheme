#!/usr/bin/env python3
"""Check lexical class evidence and recursive groups with captured monotypes."""

import argparse
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent
LOADER = importlib.machinery.SourceFileLoader('sfir_integration', str(ROOT / 'scripts/test-sfir-integration'))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
SUPPORT = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(SUPPORT)
SUPPORT.FIXTURES = FIXTURES


# ---- Tests ----


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path, default=ROOT / 'build/sfir-conformance-audit')
    options = parser.parse_args()
    options.output.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix='attempt-', dir=options.output.resolve()))
    cases = json.loads((FIXTURES / 'cases.json').read_text())
    names = [case['name'] for case in cases]
    assert len(names) == len(set(names))
    assert set(names) == {source.stem for source in FIXTURES.glob('*.sfir')}
    results = []
    for case in cases:
        result = SUPPORT.check_case(case, options.compiler.resolve(), output)
        results.append(result)
        (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
        print(('PASS ' if result['passed'] else 'FAIL ') + case['name'], flush=True)
    print(f'Retained outcomes: {output}', flush=True)
    return int(any(not result['passed'] for result in results))


if __name__ == '__main__':
    raise SystemExit(main())
