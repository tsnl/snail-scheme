#!/usr/bin/env python3
"""Run exact module-final datum tests using the established reader builder/hosts."""

import json
import os
from pathlib import Path
import shutil
import sys


def main():
    root = Path(sys.argv[1]).resolve()
    sys.path.insert(0, str(root / 'benchmarks/strict-suite'))
    import measure as driver
    import reader_ports
    from data_ports import form
    output = root / 'build/reader-ablation-units'
    target = output / 'datum-tests'
    target.mkdir(parents=True, exist_ok=False)
    shutil.copy2(root / 'benchmarks/strict-suite/reader-host.mjs', output / 'reader-host.mjs')
    source = (root / 'src/snail/datum.sld').read_text()
    tests = form(source, '(begin\n      (define (test-pair-identity)')
    program = ('(import (snail strict) (snail datum) (snail bytes))\n' + tests
               + '\n(: configured-count (-> I64))\n(define (configured-count) 1)\n'
               + '(: bench (-> I64 I64))\n(define (bench count) (test-datum))\n(unit)\n')
    (target / 'strict.scm').write_text(program)
    driver.save(target / 'spec.json', dict(name='datum-tests', count=1, inputs=[], expected=42))
    tools = driver.tool_paths(reader_ports.NAMES)
    environment = {**os.environ, **tools, 'BINARYEN_CORES': '1'}
    reader_ports.build(target, tools, environment, driver)
    results = {}
    for kind, command in [('raw', [tools['NODE'], '--disable-warning=ExperimentalWarning', output / 'reader-host.mjs', target / 'raw.wasm', target / 'spec.json']),
                          ('optimized', [tools['NODE'], '--disable-warning=ExperimentalWarning', output / 'reader-host.mjs', target / 'optimized.wasm', target / 'spec.json']),
                          ('native', [target / 'native'])]:
        run = reader_ports.record(target, kind, command, environment, target)
        result = json.loads(run['stdout'])
        assert result['result'] == 42, 'module tests failed: ' + kind
        results[kind] = result
    driver.save(target / 'validation.json', results)
    print('PASS exact datum tests on raw/optimized linked Wasm and native')


if __name__ == '__main__':
    main()
