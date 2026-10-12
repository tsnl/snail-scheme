#!/usr/bin/env python3
"""Count operations in frozen optimized Wasm; never use its time as a baseline."""

import argparse
import hashlib
import json
import re
import subprocess
from collections import Counter
from pathlib import Path


# ---- Folded WAT reader ----


def tokens(text):
    pattern = r';;[^\n]*|\(;.*?;\)|"(?:[^"\\]|\\.)*"|[()]|[^\s()]+'
    return [m[0] for m in re.finditer(pattern, text, re.DOTALL)
            if not m[0].startswith((';;', '(;'))]


def read_wat(text):
    stack, roots = [], []
    for token in tokens(text):
        if token == '(':
            node = []
            (stack[-1] if stack else roots).append(node)
            stack.append(node)
        elif token == ')':
            stack.pop()
        else:
            stack[-1].append(token)
    if stack or len(roots) != 1:
        raise ValueError('expected one balanced WAT module')
    return roots[0]


def write_wat(node):
    if isinstance(node, str):
        return node
    return '(' + ' '.join(write_wat(child) for child in node) + ')'


def head(node):
    return node[0] if isinstance(node, list) and node else None


# ---- Defined function and type signatures ----


def definitions(module):
    result = {}
    for node in module[1:]:
        if head(node) == 'rec':
            result.update(definitions(['module', *node[1:]]))
        elif head(node) == 'type':
            result[node[1]] = node[2]
    return result


def signature(function, types):
    results = [n for n in function if head(n) == 'result']
    if results:
        return results[0][1:]
    reference = next((n[1] for n in function if head(n) == 'type'), None)
    if reference:
        return signature(types[reference], types)
    return []


def imported_functions(module, types):
    return {node[3][1]: signature(node[3], types) for node in module
            if head(node) == 'import' and head(node[3]) == 'func'}


# ---- Explicit operation counters ----


class Instrumentation:
    def __init__(self, module):
        self.module = module
        self.types = definitions(module)
        self.imports = imported_functions(module, self.types)
        self.counters = {}
        self.sites = Counter()

    def increment(self, key):
        self.sites[key] += 1
        index = self.counters.setdefault(key, len(self.counters))
        name = '$snail_probe_' + str(index)
        return ['global.set', name, ['i64.add', ['global.get', name], ['i64.const', '1']]]

    def visit(self, node, function):
        if not isinstance(node, list) or not node:
            return node
        rewritten = [self.visit(n, function) for n in node]
        operation = head(node)
        if operation == 'array.copy':
            return self.wrap(rewritten, [], ('array-copy', function, node[1], node[2]))
        if operation in ('struct.new', 'struct.new_default', 'array.new', 'array.new_default',
                         'array.new_fixed', 'array.new_data', 'array.new_elem'):
            return self.wrap(rewritten, [['ref', ['exact', node[1]]]],
                             ('constructor', function, operation, node[1]))
        if operation in ('call_ref', 'return_call_ref'):
            results = [] if operation == 'return_call_ref' else signature(self.types[node[1]], self.types)
            return self.wrap(rewritten, results,
                             ('indirect-call', function, operation, node[1]))
        if operation in ('call', 'return_call') and node[1] in self.imports:
            return self.wrap(rewritten, [] if operation == 'return_call' else self.imports[node[1]],
                             ('host-import', function, operation, node[1]))
        return rewritten

    def wrap(self, node, results, key):
        declaration = [['result', *results]] if results else []
        return ['block', *declaration, self.increment(key), node]

    def function(self, node):
        name = node[1]
        declarations = ('type', 'param', 'result', 'local', 'export')
        index = next((i for i in range(2, len(node)) if head(node[i]) not in declarations), len(node))
        return [*node[:index], self.increment(('function-entry', name)),
                *(self.visit(n, name) for n in node[index:])]

    def transform(self):
        self.module = [self.function(n) if head(n) == 'func' else n for n in self.module]
        for key, index in self.counters.items():
            name = '$snail_probe_' + str(index)
            self.module.append(['global', name, ['mut', 'i64'], ['i64.const', '0']])
            self.module.append(['export', json.dumps('__snail_probe_' + str(index)), ['global', name]])
        return self.module

    def metadata(self):
        return [{'export': '__snail_probe_' + str(index), 'key': list(key),
                 'static_sites': self.sites[key]} for key, index in self.counters.items()]


# ---- Frozen diagnostic artifacts ----


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    original = args.output / 'original.wat'
    subprocess.run(['wasm-dis', str(args.input), '-o', str(original)], check=True)
    instrumentation = Instrumentation(read_wat(original.read_text()))
    wat = args.output / 'instrumented.wat'
    wat.write_text(write_wat(instrumentation.transform()) + '\n')
    artifact = args.output / 'instrumented.wasm'
    features = ['--mvp-features', '--enable-gc', '--enable-reference-types', '--enable-tail-call',
                '--enable-mutable-globals', '--enable-sign-ext', '--enable-bulk-memory',
                '--enable-nontrapping-float-to-int']
    subprocess.run(['wasm-as', str(wat), '-o', str(artifact), *features, '-g'], check=True)
    manifest = {'input': str(args.input), 'input_sha256': digest(args.input),
                'instrumented_sha256': digest(artifact), 'counters': instrumentation.metadata(),
                'types': instrumentation.types,
                'scope': 'Function-body operations over the full invocation, including initialization and '
                         'result checking. Constant global initializers are excluded.',
                'caveat': 'Constructor operations are allocation requests, not materialized V8 heap objects. '
                          'Instrumentation alters optimized code and its timing is diagnostic only.'}
    (args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps({'input': str(args.input), 'counters': len(manifest['counters'])}))


if __name__ == '__main__':
    main()
