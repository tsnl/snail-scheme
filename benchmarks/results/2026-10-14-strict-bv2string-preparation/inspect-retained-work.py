#!/usr/bin/env python3
"""Extract the frozen conversion/comparison paths without executing a benchmark."""

import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'benchmarks/strict-suite'))
from data_ports import form

REPORT = Path(__file__).resolve().parent
PLAN = json.loads((REPORT / 'timing-plan.json').read_text())
CASE = Path(PLAN['preparation']) / 'bv2string'
OUTPUT = REPORT / 'retained-work'
OUTPUT.mkdir(exist_ok=True)


def retain(label, source, body):
    target = OUTPUT / label
    target.write_text(body + '\n')
    return dict(source=str(source), source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                excerpt=label, excerpt_sha256=hashlib.sha256(target.read_bytes()).hexdigest())


def llvm_function(source, pattern):
    return re.search(r'^define[^\n]*' + pattern + r'[^\n]*\{\n.*?^}', source, re.M | re.S)[0]


def call_counts(body):
    names = re.findall(r'\b(?:call|invoke)\b[^\n]*?@([^(]+)', body)
    return {name: names.count(name) for name in sorted(set(names))}


records = {}
source = CASE / 'strict.optimized.wat'
wat = source.read_text()
for name in ('function40', 'function57', 'function79', 'function99', 'function101'):
    body = form(wat, '(func $' + name + ' ')
    record = retain('scheme-' + name + '.wat', source, body)
    record['calls'] = {callee: len(re.findall(r'\(call \$' + callee + r'\b', body))
                       for callee in ('function40', 'function57', 'function79', 'foreign1')}
    record['tail_calls'] = re.findall(r'\(return_call \$(\S+)', body)
    record['array_allocating_sites'] = body.count('(array.new_default')
    records[name] = record

source = next((CASE / 'timing-native').glob('native.native-*/module.ll'))
llvm = source.read_text()
for name in ('4', '5', '16', '24', '26'):
    body = llvm_function(llvm, r'@f\.' + name + r'\(')
    records['native-f' + name] = dict(retain('native-f' + name + '.ll', source, body), calls=call_counts(body))

source = CASE / 'rust-reference/bv2string.wat'
wat = source.read_text()
name = re.search(r'\(func (\$[^\s]+roundtrip[^\s]+)', wat)[1]
body = form(wat, '(func ' + name + ' ')
records['rust-wasm-roundtrip'] = dict(retain('rust-wasm-roundtrip.wat', source, body),
    malloc=body.count('(call $dlmalloc'), payload_copies=body.count('(memory.copy'),
    utf8_validations=len(re.findall(r'\(call [^\s]+from_utf8\b', body)), comparisons=body.count('(call $memcmp'))

source = next((CASE / 'rust-reference/target/release/deps').glob('bv2string-*.ll'))
body = llvm_function(source.read_text(), 'roundtrip')
records['rust-native-roundtrip'] = dict(retain('rust-native-roundtrip.ll', source, body),
    calls=call_counts(body), payload_copies=len(re.findall(r'@llvm.memcpy[^\n]*ptr nonnull align 1', body)),
    exception_payload_copies=2)

for name in ('function99', 'function101'):
    if [records[name]['calls'][n] for n in ('function40', 'function57', 'function79')] != [1, 2, 1]:
        raise ValueError('Scheme roundtrip call path changed')
if records['function101']['calls']['foreign1'] != 2:
    raise ValueError('Scheme opacity calls changed')
rust = records['rust-wasm-roundtrip']
if [rust[n] for n in ('malloc', 'payload_copies', 'utf8_validations', 'comparisons')] != [3, 3, 2, 1]:
    raise ValueError('Rust optimized Wasm roundtrip path changed')
records['scope'] = 'Static retained call paths, not dynamic allocation counters; empty buffers may allocate no payload.'
records['rust_first_sanity_vector'] = 'Optimized into allocation/stores of [42,16,6,43,36,0,21]; stress RNG loops remain.'
records['native_array_storage'] = 'src/native.c native_array_new reserves 16 + length*8 bytes; all array slots are eight bytes.'
(REPORT / 'retained-work.json').write_text(json.dumps(records, indent=2) + '\n')
print('Retained Scheme Wasm/native and Rust Wasm/native conversion/comparison paths')
