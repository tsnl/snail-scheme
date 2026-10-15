#!/usr/bin/env python3
"""Inspect source-mapped Earley functions and the two production Wasm artifacts."""

from collections import Counter, deque
import hashlib
import json
from pathlib import Path
import re
import sys


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def form(text, start):
    depth, quoted, escaped = 0, False, False
    for index in range(start, len(text)):
        char = text[index]
        if quoted:
            quoted, escaped = char != '"' or escaped, char == '\\' and not escaped
        elif char == '"':
            quoted = True
        else:
            depth += (char == '(') - (char == ')')
            if depth == 0:
                return text[start:index + 1]
    raise ValueError('unclosed WAT form')


def definitions(text, kind):
    pattern = (r'\(type (\$[^\s()]+) (?=\()' if kind == 'type'
               else r'(?m)^[ \t]*\(' + kind + r' (\$[^\s()]+)')
    return {match[1]: form(text, text.index('(', match.start()))
            for match in re.finditer(pattern, text)}


def edges(body):
    return sorted(set(re.findall(r'\((?:call|return_call|ref.func) (\$[^\s()]+)', body)))


def reachable(functions, roots):
    queue, seen = deque(roots), set()
    while queue:
        name = queue.popleft()
        if name not in seen:
            seen.add(name)
            queue.extend(edges(functions.get(name, '')))
    return seen


def path_to(functions, root, target):
    queue, seen = deque([[root]]), set()
    while queue:
        path = queue.popleft()
        if path[-1] == target:
            return path
        if path[-1] not in seen:
            seen.add(path[-1])
            queue.extend(path + [name] for name in edges(functions.get(path[-1], '')))
    return None


def function_observation(body):
    sites = Counter(' '.join(pair) for pair in
                    re.findall(r'\((struct.new(?:_default)?|array.new(?:_default)?) (\$[^\s()]+)', body))
    return dict(lines=len(body.splitlines()), calls=edges(body), allocation_sites=dict(sites),
                loops=len(re.findall(r'\(loop\b', body)),
                dynamic_calls=len(re.findall(r'\((?:return_call_ref|call_ref)\b', body)))


def inspect(path):
    text = path.read_text()
    functions, types = definitions(text, 'func'), definitions(text, 'type')
    exports = dict(re.findall(r'\(export "([^"]+)" \(func (\$[^\s()]+)\)\)', text))
    exports.update({export: name for name, body in functions.items()
                    for export in re.findall(r'\(export "([^"]+)"\)', body)})
    live = reachable(functions, exports.values())
    observed = {name: function_observation(body) for name, body in functions.items()}
    return dict(sha256=digest(path), functions=len(functions), exports=exports,
                reachable=sorted(live), observations=observed,
                tree_types={name: types.get(name) for name in
                            ['$type49', '$type50', '$type51', '$type52', '$type53', '$type54', '$type55']},
                paths={name: path_to(functions, exports['bench'], name) for name in
                       ['$function138', '$function143', '$function146', '$function170']})


def main():
    preparation, audit, output = map(Path, sys.argv[1:])
    case = preparation / 'earley'
    native = next(case.glob('native.native-*/optimized.wat'))
    files = {'raw': case / 'strict.wasm.wat', 'once_optimized': case / 'strict.optimized.wat',
             'final_common': native}
    report = {name: inspect(path) for name, path in files.items()}
    report['source_function_map_sha256'] = digest(audit / 'function-map-02.tsv')
    report['function_map_source_matches_final'] = (
        (preparation.parent / 'earley-prepare-03/earley/strict.scm').read_bytes() ==
        (case / 'strict.scm').read_bytes())
    report['wasm_identity'] = {name: {'bytes': path.stat().st_size, 'sha256': digest(path)}
                              for name, path in [('once_optimized', case / 'strict.wasm'),
                                                 ('final_common', native.with_suffix('.wasm'))]}
    report['wasm_identity']['byte_identical'] = (case / 'strict.wasm').read_bytes() == native.with_suffix('.wasm').read_bytes()
    first, final = report['once_optimized'], report['final_common']
    report['optimization_difference'] = dict(
        same_reachable_names=first['reachable'] == final['reachable'],
        same_tree_type_shapes=first['tree_types'] == final['tree_types'],
        changed_functions={name: {'once': observation, 'final': final['observations'].get(name)}
                           for name, observation in first['observations'].items()
                           if observation != final['observations'].get(name)},
        graph_scope='Static direct calls, tail calls and ref.func references; dynamic calls are separately counted, not resolved.',
        allocation_scope='Static sites, not dynamic counts; recursive unrolling duplicates sites without proving more runtime allocations.')
    output.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
