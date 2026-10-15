"""Adapt the complete upstream compiler; keep source extent and edits auditable."""

import hashlib
import json
import re
from pathlib import Path

from data_ports import replace


# ---- Complete source extents include character literals and quoted forms ----

# In particular, #\( and #\) are atoms in the upstream reader. Treating their
# parentheses as source delimiters can silently remove definitions after it.
TOKEN = re.compile(r';[^\n]*|"(?:[^"\\]|\\.)*"|#\\(?:[^()\s]+|[()])|#\(|,@|[()]|[\'`,]|[^\s()\'`,;]+')


def tokens(source):
    return [token for token in TOKEN.finditer(source) if not token[0].startswith(';')]


def datum_end(items, start):
    token = items[start][0]
    if token in ("'", '`', ',', ',@'):
        return datum_end(items, start + 1)
    if token not in ('(', '#('):
        if token == ')':
            raise ValueError('unexpected source close parenthesis')
        return start + 1
    index = start + 1
    while items[index][0] != ')':
        index = datum_end(items, index)
    return index + 1


def source_forms(source):
    items, index = tokens(source), 0
    while index < len(items):
        end = datum_end(items, index)
        yield items[index].start(), items[end - 1].end()
        index = end


def named_form(source, prefix):
    matches = [(start, end) for start, end in source_forms(source)
               if source.startswith(prefix, start)]
    if len(matches) != 1:
        raise ValueError(f'expected one complete compiler form starting with {prefix!r}')
    start, end = matches[0]
    return source[start:end]


def kernel(source):
    # Remove exactly the imports and harness, wherever the harness occurs.
    # Every other source byte remains, including comments and later forms.
    for prefix in ('(import ', '(define (run-benchmark)'):
        source = replace(source, named_form(source, prefix), '')
    return source


def source_inventory(source):
    result = []
    for start, end in source_forms(source):
        text = source[start:end]
        heading = re.match(r'\(define\s+(?:\(\s*)?([^\s()]+)', text)
        result.append(dict(name=heading[1] if heading else None,
                           start=start, end=end,
                           line=source.count('\n', 0, start) + 1,
                           sha256=hashlib.sha256(text.encode()).hexdigest()))
    return result


# ---- Original input and the complete ordered assembly predicate ----

def specification(data):
    source = data.decode()
    forms = [source[start:end] for start, end in source_forms(source)]
    if len(forms) != 5:
        raise ValueError('compiler input requires count, program, target, option and expected output')
    expected = tokens(forms[4])[1:-1]
    lines = [json.loads(token[0]) for token in expected]
    return dict(name='compiler', count=int(forms[0]), program=forms[1],
                target=forms[2], option=forms[3], expected_lines=lines,
                expected=1, barriers_per_iteration=3, setup_barriers=0,
                input_sha256=hashlib.sha256(data).hexdigest())


def representations():
    return Path(__file__).with_name('compiler-data.scm').read_text()
