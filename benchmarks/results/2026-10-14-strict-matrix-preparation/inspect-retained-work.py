#!/usr/bin/env python3
"""Retain the frozen search and repetition paths without running a benchmark."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'benchmarks/strict-suite'))
from data_ports import form


# ---- Static excerpts retain their source identity ----

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def retain(output, label, source, body):
    target = output / label
    target.write_text(body + '\n')
    return dict(source=str(source), source_sha256=digest(source),
                excerpt=label, excerpt_sha256=digest(target), lines=len(body.splitlines()))


def llvm_function(source, pattern):
    matches = re.findall(r'^define[^\n]*' + pattern + r'[^\n]*\{\n.*?^}', source, re.M | re.S)
    if len(matches) != 1:
        raise ValueError('expected exactly one LLVM function: ' + pattern)
    return matches[0]


def counted(names):
    return {name: names.count(name) for name in sorted(set(names))}


def wat_operations(body):
    return dict(calls=counted(re.findall(r'\((?:return_)?call \$(\S+)', body)),
                indirect_calls=len(re.findall(r'\((?:return_)?call_ref\b', body)),
                struct_new=body.count('(struct.new '), struct_set=body.count('(struct.set '),
                array_new=body.count('(array.new_default '), array_set=body.count('(array.set '),
                loops=body.count('(loop '))


def llvm_operations(body):
    return dict(calls=counted(re.findall(r'\b(?:call|invoke)\b[^\n]*?@([^(]+)', body)),
                branches=len(re.findall(r'^\s+br ', body, re.M)),
                opaque_asm=body.count('asm sideeffect'))


# ---- The Scheme entry, loops, arithmetic, enumeration and full predicate ----

def scheme_paths(case, output):
    source = case / 'strict.optimized.wat'
    wat, records = source.read_text(), {}
    for name in ('export0', 'function179', 'function181', 'function156', 'function147',
                 'function150', 'function95', 'function165', 'function161',
                 'function169', 'function172', 'function91', 'function92',
                 'function152', 'function153', 'function54', 'function52'):
        body = form(wat, '(func $' + name + ' ')
        records[name] = dict(retain(output, 'scheme-' + name + '.wat', source, body), **wat_operations(body))
    for name in ('function179', 'function181'):
        if records[name]['calls'].get('foreign2') != 2 or records[name]['calls'].get('function156') != 1:
            raise ValueError('Scheme full-count opacity/worker path changed')
    if records['function181']['calls'].get('function181') != 1:
        raise ValueError('Scheme repetition tail call changed')
    return records


def native_paths(case, output):
    source = next((case / 'native-timing').glob('native.native-*/module.ll'))
    llvm, records = source.read_text(), {}
    for name in ('2', '69', '87', '89', '92'):
        body = llvm_function(llvm, r'@f\.' + name + r'\(')
        records['f' + name] = dict(retain(output, 'native-f' + name + '.ll', source, body), **llvm_operations(body))
    for name in ('f87', 'f89'):
        if records[name]['calls'].get('f.2') != 2 or records[name]['calls'].get('f.69') != 1:
            raise ValueError('native full-count opacity/worker path changed')
    if records['f89']['calls'].get('f.89') != 1:
        raise ValueError('native repetition tail call changed')
    return records


# ---- Rust keeps the search in both generated targets ----

def rust_paths(case, output):
    wasm = case / 'rust-reference/matrix.wat'
    native = next((case / 'rust-reference/target/release/deps').glob('matrix-*.ll'))
    wat, llvm, records = wasm.read_text(), native.read_text(), {}
    for name in ('10row_reduce', '13collect_tests', '4main', '5zebra', '6search'):
        symbol = re.search(r'\(func (\$_ZN6matrix' + name + r'\S+)', wat)[1]
        body = form(wat, '(func ' + symbol + ' ')
        records['wasm-' + name] = dict(retain(output, 'rust-wasm-' + name + '.wat', wasm, body), **wat_operations(body))
        body = llvm_function(llvm, '@_ZN6matrix' + name)
        records['native-' + name] = dict(retain(output, 'rust-native-' + name + '.ll', native, body), **llvm_operations(body))
    for target in ('wasm', 'native'):
        if not any('6search' in name for name in records[target + '-4main']['calls']):
            raise ValueError('Rust main lost its search call')
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preparation', type=Path, default=ROOT / 'build/matrix-attempt5')
    options = parser.parse_args()
    output, case = REPORT / 'retained-work', options.preparation / 'matrix'
    output.mkdir(exist_ok=True)
    records = dict(scheme=scheme_paths(case, output), native=native_paths(case, output), rust=rust_paths(case, output),
                   scope='Static source and generated paths; not dynamic allocation counters or full-count internal traces.')
    (REPORT / 'retained-work.json').write_text(json.dumps(records, indent=2) + '\n')
    print('Retained full-count Scheme loops and Scheme/Rust modular search paths')


if __name__ == '__main__':
    main()
