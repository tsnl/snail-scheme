#!/usr/bin/env python3
"""Inspect the clean Browse artifacts independently of the observation builds."""

from collections import Counter, deque
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
CORE = ROOT / 'build/browse-attempt2'
sys.path.insert(0, str(ROOT / 'benchmarks/strict-suite'))
from data_ports import form
import reader_ports


# ---- Direct call paths preserve the three source investigation loops ----

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def functions(text):
    return {match[1]: form(text, match[0])[2:] for match in
            re.finditer(r'\n \(func (\$[^\s()]+)\s', text)}


def calls(body):
    return Counter(re.findall(r'\((?:return_)?call (\$[^\s()]+)', body))


def path_to(bodies, start, end):
    queue, seen = deque([[start]]), {start}
    while queue:
        path = queue.popleft()
        if path[-1] == end:
            return path
        for name in calls(bodies.get(path[-1], '')):
            if name not in seen:
                seen.add(name)
                queue.append([*path, name])
    raise ValueError('clean artifact lost call path to ' + end)


def inspect_wasm(label, module, wat, target):
    text = wat.read_text()
    bodies = functions(text)
    names = ['$export0', '$function252', '$function243', '$function244', '$function245',
             '$function239', '$function240', '$function225', '$function117', '$function118']
    paths = {name: path_to(bodies, '$export0', name) for name in names}
    for name in names:
        (target / (label + '-' + name[1:] + '.wat')).write_text(bodies[name] + '\n')
    if not re.search(r'\(drop\s+\(call \$function239\b', bodies['$function245']):
        raise ValueError('expected original discarded matcher result')
    if '$function239' not in calls(bodies['$function239']):
        raise ValueError('recursive matcher disappeared')
    if '"reader.test"' in text or re.search(r'"emit_i64"|"emit_character"', text):
        raise ValueError('clean artifact unexpectedly contains an observation import')
    return dict(module_sha256=digest(module), wat_sha256=digest(wat), paths=paths,
                calls={name: dict(calls(bodies[name])) for name in names},
                matcher_struct_allocations=bodies['$function239'].count('(struct.new '),
                prefix_struct_allocations=bodies['$function240'].count('(struct.new '),
                observation_imports=bool(re.search(r'"emit_i64"|"emit_character"', text)))


# ---- Follow the exact final Wasm numbering into LLVM and the executable ----

def native_functions(text):
    imports = re.findall(r'^ \(import .*?\(func (\$[^\s()]+)', text, re.M)
    names = imports + list(functions(text))
    return {name: 'f.' + str(index) for index, name in enumerate(names)}


def inspect_native(native, target, environment):
    folder, = native.glob('native.native-*')
    names = native_functions((folder / 'optimized.wat').read_text())
    llvm = (folder / 'module.ll').read_text()
    selected = {name: names[name] for name in ('$function239', '$function240', '$function252', '$export0')}
    for source, name in selected.items():
        definition = re.search(r'^define[^\n]*@' + re.escape(name) + r'\([^\n]*\{\n.*?^}', llvm, re.M | re.S)
        if not definition:
            raise ValueError('native lowering lost function ' + source)
        (target / ('native-' + source[1:] + '.ll')).write_text(definition[0] + '\n')
    label = 'native-machine-' + digest(native / 'native')[:12]
    log = CORE / 'commands' / label / 'record.json'
    run = json.loads(log.read_text()) if log.exists() else reader_ports.record(CORE, label,
        ['/run/current-system/sw/bin/llvm-objdump', '--disassemble', native / 'native'], environment)
    (target / 'native.asm').write_text(run['stdout'])
    return inspect_machine(run['stdout'], selected, native / 'native', target)


def inspect_machine(assembly, selected, executable, target):
    parts = re.split(r'(?m)^([0-9a-f]+) <([^>]+)>:\n', assembly)
    bodies = {parts[i + 1]: parts[i + 2] for i in range(1, len(parts), 3)}
    matcher = selected['$function239']
    if matcher not in bodies or not re.search(r'callq?\s+[^\n]*<' + re.escape(matcher) + '>', bodies[matcher]):
        raise ValueError('final native executable lost its recursive matcher')
    callers = {name: [line.strip() for line in body.splitlines()
                     if re.search(r'callq?\s+[^\n]*<' + re.escape(matcher) + '>', line)]
               for name, body in bodies.items()}
    callers = {name: lines for name, lines in callers.items() if lines}
    graph = {name: ''.join('(call $' + callee + ')' for callee in
                         re.findall(r'(?:callq?|jmpq?)\s+[^\n]*<([^>+]+)>', body))
             for name, body in bodies.items()}
    path = path_to({'$' + name: body for name, body in graph.items()}, '$main', '$' + matcher)
    (target / 'native-matcher.asm').write_text(bodies[matcher])
    (target / 'native-main.asm').write_text(bodies['main'])
    return dict(executable_sha256=digest(executable), final_wasm_to_llvm=selected, main_to_matcher=path,
                matcher_machine_callers=callers, matcher_machine_allocations=
                len(re.findall(r'callq?[^\n]*<[^>]*(?:allocate|alloc)[^>]*>', bodies[matcher])))


def main():
    import os
    target = REPORT / 'retained-work'
    target.mkdir(exist_ok=True)
    if (CORE / 'reproduced.wat').read_bytes() != (CORE / 'strict-native.wasm.wat').read_bytes():
        raise ValueError('source map does not reproduce the compiled clean WAT')
    native = CORE / 'controls/native'
    final, = native.glob('native.native-*/optimized.wat')
    cases = [('raw', CORE / 'raw.wasm', CORE / 'raw.wasm.wat'),
             ('optimized', CORE / 'optimized.wasm', CORE / 'optimized.wasm.wat'),
             ('native-final', native / 'native-final.wasm', final)]
    report = {name: inspect_wasm(name, module, wat, target) for name, module, wat in cases}
    report['native-executable'] = inspect_native(native, target, dict(os.environ))
    report['source_map_sha256'] = digest(CORE / 'source-map.tsv')
    report['scope'] = 'Static retained call paths in these exact clean artifacts; no full-count internal trace claim.'
    (REPORT / 'retained-work.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Verified clean matcher paths in raw, optimized, native-final Wasm and final native machine code')


if __name__ == '__main__':
    main()
