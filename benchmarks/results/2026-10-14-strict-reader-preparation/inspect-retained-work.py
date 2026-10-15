#!/usr/bin/env python3
"""Retain the actual repetition, file I/O, parser and predicate paths."""

import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
CORE = ROOT / 'build/strict-reader-ports-attempt6'
CONTROLS = ROOT / 'build/strict-reader-controls-attempt2'
sys.path.insert(0, str(ROOT / 'benchmarks/strict-suite'))
from data_ports import form


# ---- Static excerpts always name their complete source artifact ----

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def counted(items):
    return {item: items.count(item) for item in sorted(set(items))}


def retain(source, body, label, kind):
    target = REPORT / 'retained-work' / label
    target.write_text(body + '\n')
    pattern = r'\((?:return_)?call \$([^\s()]+)' if kind == 'wat' else r'\bcall[^\n]*?@("[^"\n]+"|[^ (]+)'
    return dict(source=str(source), source_sha256=digest(source), excerpt=label, excerpt_sha256=digest(target),
                lines=len(body.splitlines()), calls=counted(re.findall(pattern, body)),
                loops=body.count('(loop '), f64_adds=body.count('(f64.add'),
                opaque_asm=body.count('asm sideeffect'), allocations=body.count('(struct.new ') + body.count('@native_alloc('))


def llvm_function(text, name):
    matches = re.findall(r'^define[^\n]* @' + re.escape(name) + r'\([^\n]*\)[^\n]*\{\n.*?^}', text, re.M | re.S)
    if len(matches) != 1:
        raise ValueError('expected one LLVM function: ' + name)
    return matches[0]


# ---- Scheme retains the outer count and every worker's file lifecycle ----

def scheme(name):
    original = CORE / name / 'reused-case/optimized.wasm.wat'
    native = next((CONTROLS / name / 'native-timing').glob('native.native-*/optimized.wat'))
    records = {}
    selected = ('export0', 'function210', 'function198', 'function137', 'function135')
    selected += ('function201', 'function199') if name == 'sum1' else ('function203', 'function129')
    for layout, source in (('production', original), ('native-final', native)):
        text = source.read_text()
        for function in selected:
            body = form(text, '(func $' + function + ' ')
            label = f'{name}-{layout}-{function}.wat'
            records[layout + '-' + function] = retain(source, body, label, 'wat')
        calls = records[layout + '-function210']['calls']
        open_file, close_file = ('snail:io/open-input-file', 'snail:io/close') if layout == 'production' else ('foreign5', 'foreign6')
        if any(calls.get(symbol) != 1 for symbol in ('foreign26', open_file, close_file, 'function210')):
            raise ValueError('outer count/opacity/file lifecycle path changed')
        if 'i64.gt_s' not in form(text, '(func $function210 '):
            raise ValueError('outer count comparison disappeared')
    return records


def native(name):
    source = next((CONTROLS / name / 'native-timing').glob('native.native-*/module.ll'))
    text, records = source.read_text(), {}
    selected = ('"wasm.bench"', 'f.2', 'f.3')
    selected += ('f.62', 'f.61', 'f.60', 'f.19') if name == 'sum1' else ('f.66', 'f.65', 'f.64', 'f.63', 'f.20')
    for function in selected:
        label = name + '-native-' + function.replace('"', '').replace('.', '-') + '.ll'
        records[function] = retain(source, llvm_function(text, function), label, 'llvm')
    outer, barrier = ('f.61', 'f.19') if name == 'sum1' else ('f.65', 'f.20')
    if any(records[outer]['calls'].get(symbol) != 1 for symbol in (outer, barrier, 'f.2', 'f.3')):
        raise ValueError('native outer count/opacity/file lifecycle path changed')
    return records


# ---- Rust's distinct scanner and buffered reader remain inside their loops ----

def rust(name):
    target = CONTROLS / 'rust-reference'
    wasm, native = target / (name + '.wat'), next((target / 'target/release/deps').glob(name + '-*.ll'))
    text, records = wasm.read_text(), {}
    symbol = re.search(r'^ \(func (\$_ZN\d+' + name + r'4main[^\s()]*) ', text, re.M)[1]
    body = form(text, '(func ' + symbol + ' ')
    records['wasm-main'] = retain(wasm, body, name + '-rust-wasm-main.wat', 'wat')
    if not any('File4open' in call for call in records['wasm-main']['calls']) or records['wasm-main']['calls'].get('read', 0) == 0:
        raise ValueError('Rust main lost file-open/read operations')
    if name == 'sum1' and records['wasm-main']['f64_adds'] < 1:
        raise ValueError('Rust sum lost sequential binary64 accumulation')
    if name == 'read1' and not any('Reader5datum' in call for call in records['wasm-main']['calls']):
        raise ValueError('Rust buffered reader lost datum parsing')
    llvm = native.read_text()
    symbol = re.search(r'^define[^\n]* @(_ZN\d+' + name + r'4main[^ (]+)', llvm, re.M)[1]
    body = llvm_function(llvm, symbol)
    records['native-main'] = retain(native, body, name + '-rust-native-main.ll', 'llvm')
    if records['native-main']['opaque_asm'] < 2:
        raise ValueError('Rust count loop lost its black-box boundaries')
    return records


def main():
    (REPORT / 'retained-work').mkdir(exist_ok=True)
    records = {name: dict(scheme=scheme(name), native=native(name), rust=rust(name)) for name in ('sum1', 'read1')}
    records['scope'] = 'Static retained source paths plus dynamic full-count/file observations; no equal-allocation claim or full-count internal trace.'
    (REPORT / 'retained-work.json').write_text(json.dumps(records, indent=2) + '\n')
    print('Retained both complete repetition/file/parser/predicate paths and Rust control loops')


if __name__ == '__main__':
    main()
