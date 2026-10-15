"""Keep Clinger's complete generated scanner and LL(1) parsing workload."""

import difflib
import hashlib
import json
from pathlib import Path
import re
import shutil
import signal

from data_ports import form, replace
import browse_port
import reader_ports


# ---- Concrete boundaries around the original generated procedures ----

CONTROL = browse_port.CONTROL.replace('browse-cond', 'parsing-cond').replace('browse-do', 'parsing-do') + '''
(define-syntax parsing-case
  (syntax-rules (else)
    ((_ key (else body ...)) (begin body ...))
    ((_ key ((value ...) body ...) rest ...)
     (let ((saved key))
       (if (or (parsing-case=? saved (parsing-case-value value)) ...)
           (begin body ...) (parsing-case saved rest ...))))))
'''
COMMON = r'''(: parsing-list (All (T) (-> (Rest T) (List T))))
(define (parsing-list . values) values)
(: parsing-cadr (All (T) (-> (List T) T)))
(define (parsing-cadr values) (car (cdr values)))
(: parsing-reverse (All (T) (-> (List T) (List T))))
(define (parsing-reverse values)
  (let loop ((values values) (result '()))
    (if (null? values) result (loop (cdr values) (cons (car values) result)))))
(: parsing-member? (-> Symbol (List Symbol) Bool))
(define (parsing-member? value values)
  (and (not (null? values))
       (or (typed-symbol=? value (car values)) (parsing-member? value (cdr values)))))
(: parsing-char? (-> Char Bool))
(define (parsing-char? value) #t)
(: parsing-character-end? (-> CharacterResult Bool))
(define (parsing-character-end? value)
  (match value ((character-end) #t) ((character-value value) #f)))
(: parsing-character-text (-> CharacterResult Char))
(define (parsing-character-text value)
  (match value ((character-end) (datum-fail "parsing: unexpected physical EOF"))
               ((character-value value) value)))
(: parsing-integer (-> I64 Datum))
(define (parsing-integer value) (datum-number (exact-number value)))
(: parsing-exact (-> Datum I64))
(define (parsing-exact value)
  (match (datum-number-value value)
    ((exact-number value) value)
    ((inexact-number value) (datum-fail "parsing: expected an exact count"))
    ((complex-number real imaginary) (datum-fail "parsing: expected an exact count"))))
(: parsing-number (-> String Datum))
(define (parsing-number text)
  (match (typed-string->number text)
    ((not-a-number) (datum-boolean #f))
    ((parsed-number value) (datum-number value))
    ((number-error message) (datum-fail message))))
(: parsing-vector (-> Datum Datum))
(define (parsing-vector values)
  (let ((result (make-vector (datum-length values) (datum-null))))
    (let loop ((values values) (index 0))
      (if (datum-null? values) (datum-vector result)
          (begin (vector-set! result index (datum-car values))
                 (loop (datum-cdr values) (+ index 1)))))))
(: parsing-display-string (-> String Unit))
(define (parsing-display-string text)
  (let loop ((index 0))
    (when (< index (string-length text))
      (parsing-write-character (string-ref text index)) (loop (+ index 1)))))
(: parsing-display-symbol (-> Symbol Unit))
(define (parsing-display-symbol value) (parsing-display-string (typed-symbol->string value)))
(: parsing-display-symbols (-> (List Symbol) Unit))
(define (parsing-display-symbols values)
  ;; Every diagnostic name is a bare printable symbol in the pinned grammar.
  (parsing-write-character #\()
  (let loop ((values values) (first #t))
    (unless (null? values)
      (unless first (parsing-write-character #\space))
      (parsing-display-symbol (car values)) (loop (cdr values) #f)))
  (parsing-write-character #\)))
(define (parsing-newline) (parsing-write-character #\newline))
'''
STRICT_SERVICES = '''(define-overload parsing-case=? (-> Char Char Bool) char=?)
(define-overload parsing-case=? (-> Symbol Symbol Bool) typed-symbol=?)
(define-extern parsing-raw-whitespace "snail.library" "snail:datum/whitespace" (-> Char I32))
(define (parsing-whitespace? character)
  (i32-eq (parsing-raw-whitespace character) (ann 1 I32)))
(define-extern parsing-write-character "benchmark" "write_character" (-> Char Unit))
(define parsing-read-char read-char)
'''
CHEZ_SERVICES = '''(define (parsing-case=? left right)
  (if (char? left) (char=? left right) (typed-symbol=? left right)))
(define parsing-whitespace? char-whitespace?)
(define parsing-write-character write-char)
'''
IMPORTS = '''(import (snail strict) (snail io) (snail read)
  (rename (snail datum) (string->symbol typed-string->symbol)
    (symbol->string typed-symbol->string) (symbol=? typed-symbol=?)
    (string->number typed-string->number)))
'''
INPUTS = '''(define-data Specification
  (specification (count I64 specification-count) (path String specification-path)
                 (expected Datum specification-expected)))
(define (read-specification port)
  (let* ((count (parsing-exact (read-value! (read port))))
         (path (datum-string-value (read-value! (read port))))
         (expected (read-value! (read port))))
    (specification count path expected)))
(define configured (call-with-input-file "input.txt" read-specification))
(: configured-count (-> I64))
(define (configured-count) (specification-count configured))
(define-extern barrier "benchmark" "barrier" (-> Bool))
(: hide (All (T) (-> I64 T T)))
(define (hide count value) (if (barrier) value (unreachable)))
(: bench (-> I64 I64))
(define (bench count)
  (let ((result (parsing-benchmark (parsing-integer (hide count count))
                  (datum-string (hide count (specification-path configured))))))
    (if (datum=? result (specification-expected configured)) 1 0)))
'''


# ---- Counted source changes are reversed back to the pinned kernel ----

TOKEN_PATTERN = r'#\\(?:[()]|[^\s()]+)|"(?:[^"\\]|\\.)*"|;[^\n]*|[()]|\x27|[^\s()\x27]+'
MUTABLE = [('kindOfNextToken', "'z1", 3), ('nextTokenIsReady', '#f', 5),
           ('tokenValue', '""', 8), ('lineNumber', '1', 5),
           ('string_accumulator_length', '0', 11), ('nextCharacter', '#\\space', 7),
           ('nextCharacterIsReady', '#f', 6), ('input-index', '0', 5)]


def tokens(source):
    return list(re.finditer(TOKEN_PATTERN, source))


def edit(source, ledger, before, after, count=1):
    return browse_port.edit(source, ledger, before, after, count)


def token_edit(source, ledger, name, replacement, count):
    matches = [token for token in tokens(source) if token[0] == name]
    if len(matches) != count:
        raise ValueError(f'expected {count} Parsing tokens named {name}')
    changed = source
    for token in reversed(matches):
        changed = changed[:token.start()] + replacement + changed[token.end():]
    return edit(source, ledger, source, changed)


def mutable_bindings(source, ledger):
    for name, initial, count in MUTABLE:
        source = token_edit(source, ledger, name, f'(ref-get {name})', count)
        source = edit(source, ledger, f'((ref-get {name}) {initial})', f'({name} (ref {initial}))')
        before = f'(set! (ref-get {name})'
        source = edit(source, ledger, before, f'(ref-set! {name}', source.count(before))
    return source


def argument_boundaries(source, ledger):
    source = edit(source, ledger, '(n (if (null? rest) 1000 (car rest)))',
                  '(n (parsing-exact (if (null? rest) (parsing-integer 1000) (car rest))))')
    before = '(input (if (or (null? rest) (null? (cdr rest)))\n                    "nboyer.sch"\n                    (cadr rest)))'
    after = '(input (datum-string-value (if (or (null? rest) (null? (cdr rest)))\n                    (datum-string "nboyer.sch")\n                    (parsing-cadr rest))))'
    source = edit(source, ledger, before, after)
    source = edit(source, ledger, '(result #f)', '(result (datum-boolean #f))')
    source = edit(source, ledger, '(cons x chars)', '(cons (parsing-character-text x) chars)')
    return edit(source, ledger, '(eof-object? x)', '(parsing-character-end? x)')


def result_boundaries(source, ledger):
    changes = [("(define (emptyList) '())", '(define (emptyList) (datum-null))', 1),
               ('(cons ast1 ast2)', '(datum-cons ast1 ast2)', 2),
               ('(list ast1 ast2)', '(datum-list ast1 ast2)', 1),
               ('(list->vector vals)', '(parsing-vector vals)', 1),
               ('(string=? tokenValue "#t")', '(datum-boolean (string=? tokenValue "#t"))', 1),
               ('(string-ref tokenValue 0)', '(datum-character (string-ref tokenValue 0))', 1),
               ('(string->number tokenValue)', '(parsing-number tokenValue)', 1),
               ('(substring tokenValue 1 (- (string-length tokenValue) 1))',
                '(datum-string (substring tokenValue 1 (- (string-length tokenValue) 1)))', 1),
               ('(string->symbol tokenValue)', '(datum-symbol (typed-string->symbol tokenValue))', 1),
               ('(null? vals)', '(datum-null? vals)', 1), ('(car vals)', '(datum-car vals)', 1),
               ('(cdr vals)', '(datum-cdr vals)', 1), ('(cons (datum-car vals)', '(datum-cons (datum-car vals)', 1)]
    for before, after, count in changes:
        source = edit(source, ledger, before, after, count)
    for name in ('symBackquote', 'symQuote', 'symSplicing', 'symUnquote'):
        before = form(source, f'(define ({name})')
        source = edit(source, ledger, before, before[:-1].replace(') ', ') (datum-symbol ', 1) + '))')
    source = edit(source, ledger, "          'eof\n", "          (datum-symbol 'eof)\n")
    source = edit(source, ledger, "(y 'eof x)", "(y (datum-symbol 'eof) x)")
    return edit(source, ledger, "(eq? x 'eof)", "(datum-eq? x (datum-symbol 'eof))")


def diagnostic_boundaries(source, ledger):
    changes = [('(display lineNumber)', '(parsing-display-string (i64->string lineNumber))', 1),
               ('(write nonterminal)', '(parsing-display-symbol nonterminal)', 1),
               ('(display (next-token))', '(parsing-display-symbol (next-token))', 1),
               ('(write expected-terminals)', '(parsing-display-symbols expected-terminals)', 1),
               ('(error #f (string-append "Lexical Error: " msgtxt) lineNumber)',
                '(datum-fail (string-append "Lexical Error: " msgtxt " " (i64->string lineNumber)))', 1),
               ('(error #f "Syntax error")', '(datum-fail "Syntax error")', 1),
               ('(scannererror errLongToken)', '(begin (scannererror errLongToken) (unit))', 1)]
    for before, after, count in changes:
        source = edit(source, ledger, before, after, count)
    return token_edit(source, ledger, 'display', 'parsing-display-string', 5)


def symbol_name(text):
    return 'parsing-symbol-' + text + '-value'


def quoted_literals(source):
    items = tokens(source)
    for index, token in enumerate(items):
        if token[0] != "'":
            continue
        following = items[index + 1]
        if following[0] == '(':
            end = next(i for i in range(index + 2, len(items)) if items[i][0] == ')')
            values = [item[0] for item in items[index + 2:end]]
            yield source[token.start():items[end].end()], values
        else:
            yield source[token.start():following.end()], following[0]


def symbol_declarations(names):
    declarations = ''.join(f'(define {symbol_name(name)} (typed-string->symbol {json.dumps(name)}))\n' for name in sorted(names))
    cases = '(define-syntax parsing-case-value\n  (syntax-rules (' + ' '.join(sorted(names)) + ')\n'
    cases += ''.join(f'    ((_ {name}) {symbol_name(name)})\n' for name in sorted(names))
    return declarations, cases + '    ((_ other) other)))\n'


def quoted_symbols(source, ledger):
    names, lists, changes = set(), [], []
    for text, values in quoted_literals(source):
        if isinstance(values, list):
            names.update(values)
            replacement = '(parsing-list ' + ' '.join(map(symbol_name, values)) + ')'
            name = f'parsing-literal-{len(lists)}'
            lists.append(f'(define {name} {replacement})\n')
            changes.append((text, name))
        else:
            names.add(values)
            changes.append((text, symbol_name(values)))
    for before, after in dict(changes).items():
        source = edit(source, ledger, before, after, source.count(before))
    declarations, cases = symbol_declarations(names)
    return source, declarations + ''.join(lists) + cases


def contracts():
    signatures = [('parsing-benchmark', '(Rest Datum)', 'Datum'), ('read-file-as-string', 'String', 'String'),
                  ('parse-string', 'String', 'Datum')]
    top = ''.join(f'(: {name} (-> {arguments} {result}))\n' for name, arguments, result in signatures)
    local = [('scanner0', '', 'Symbol'), ('next-token', '', 'Symbol'), ('accept', 'Symbol', 'Symbol'),
             ('consume-token!', '', 'Unit'), ('scannererror', 'I64', 'Symbol'), ('scanchar', '', 'Char'),
             ('consumechar', '', 'Unit'), ('pseudoAppend', 'Datum Datum', 'Datum'),
             ('parse-error', 'Symbol (List Symbol)', 'Datum')]
    local += [(f'state{index}', 'Char', 'Symbol') for index in range(42)]
    local += [(name, '', 'Datum') for name in ('parse-datum parse-simple-datum parse-symbol parse-compound-datum '
              'parse-list parse-list2 parse-list3 parse-list4 parse-abbreviation parse-abbrev-prefix '
              'parse-vector parse-data emptyList makeBool makeChar makeNum makeString makeSym '
              'symBackquote symQuote symSplicing symUnquote').split()]
    return top, ''.join(f'    (: {name} (-> {arguments} {result}))\n' for name, arguments, result in local)


def adaptation(source):
    adapted, ledger = source, []
    for operation in (argument_boundaries, result_boundaries, diagnostic_boundaries, mutable_bindings):
        adapted = operation(adapted, ledger)
    for name, replacement, count in [('case', 'parsing-case', 54), ('cond', 'parsing-cond', 1),
            ('do', 'parsing-do', 2), ('eq?', 'typed-symbol=?', 3), ('char?', 'parsing-char?', 1),
            ('char-whitespace?', 'parsing-whitespace?', 3), ('read-char', 'parsing-read-char', 2),
            ('write-char', 'parsing-write-character', 1), ('newline', 'parsing-newline', 3),
            ('reverse', 'parsing-reverse', 1), ('memq', 'parsing-member?', 1)]:
        adapted = token_edit(adapted, ledger, name, replacement, count)
    adapted, constants = quoted_symbols(adapted, ledger)
    top, local = contracts()
    adapted = edit(adapted, ledger, '    (define (scanner0)', local + '\n    (define (scanner0)')
    prefix = constants + CONTROL + top
    ledger = dict(introduced_prefix=prefix, edits=ledger, complete_reverse_verified=True)
    adapted = prefix + adapted
    if restore_kernel(adapted, ledger) != source:
        raise ValueError('Parsing edits did not restore the complete original kernel')
    return adapted, ledger


def restore_kernel(adapted, ledger):
    prefix = ledger['introduced_prefix']
    if not adapted.startswith(prefix):
        raise ValueError('Parsing declaration prefix differs')
    return restore_edits(adapted[len(prefix):], ledger['edits'])


def restore_edits(source, edits):
    for item in reversed(edits):
        source = replace(source, item['after'], item['before'], item['count'])
    return source


def kernel(source):
    return re.sub(r'^\(import [^\n]*\)\s*$', '', source[:source.index('(define (run-benchmark)')], flags=re.M)


def program(source):
    return IMPORTS + STRICT_SERVICES + COMMON + adaptation(kernel(source))[0] + INPUTS + '(unit)\n'


# ---- Chez runs both the untouched source and the identical adapted kernel ----

EXPORTS = '''datum-fail datum-null datum-cons datum-car datum-cdr datum-list datum-null? datum-pair?
  datum-length datum-vector datum-vector-values datum-symbol datum-number datum-string datum-boolean
  datum-character datum-number-value datum-string-value datum-symbol-value datum=? datum-eq? datum-kind
  datum-boolean-value datum-character-value datum-bytevector-values datum-set-car! datum-set-cdr!
  exact-number i64->string read-value! workload-read'''.split()


def chez_prelude(root):
    exports = [*EXPORTS, ('typed-string->symbol', 'string->symbol'), ('typed-symbol->string', 'symbol->string'),
               ('typed-symbol=?', 'symbol=?'), ('typed-string->number', 'string->number'), ('parsing-read-char', 'read-char')]
    return reader_ports.chez_reader(root, exports) + CHEZ_SERVICES + COMMON


def adapted_harness(source):
    harness = form(source, '(define (run-benchmark)')
    changes, original = [], harness
    for before, after in [('(output (read))', '(output (read-value! (workload-read (current-input-port))))'),
            ('(parsing-benchmark (hide count count) (hide count input1))',
             '(parsing-benchmark (parsing-integer (hide count count)) (datum-string (hide count input1)))'),
            ('(equal? result output)', '(datum=? result output)')]:
        harness = edit(harness, changes, before, after)
    if restore_edits(harness, changes) != original:
        raise ValueError('Parsing harness edits did not reverse')
    return harness, changes


def adapted_chez(source, root):
    adapted, ledger = adaptation(kernel(source))
    harness, changes = adapted_harness(source)
    prefix = chez_prelude(root)
    return prefix + adapted + harness, dict(kernel=ledger, harness=changes, introduced_compatibility_prefix=prefix)


def specification(data):
    count, pathname, expected = data.decode().splitlines()
    return dict(name='parsing', count=int(count), pathnames=[json.loads(pathname)], expected=1,
                expected_datum=expected, inputs=[], worker_barriers=2, setup_barriers=0,
                additional_exports=['configured-count'], runtime='scalar-datum-reader')


def complete_chez(source, original, root):
    control, ledger = adapted_chez(source, root)
    body = re.sub(r'^\(import [^\n]*\)\s*$', '', source, flags=re.M)
    adjusted = replace(original, body, control)
    if replace(adjusted, control, body) != original:
        raise ValueError('Parsing complete Chez program did not reverse')
    ledger.update(complete_program_edit=dict(before=body, after=control, count=1), complete_reverse_verified=True)
    return adjusted, ledger


def write_sources(files, directory, runner, driver):
    source = files['src/parsing.scm'].decode()
    adapted, ledger = adaptation(kernel(source))
    original = runner.source_text(files, 'parsing', 'chez')
    adjusted, complete_ledger = complete_chez(source, original, driver.ROOT)
    for name, text in [('upstream.scm', source), ('upstream-kernel.scm', kernel(source)),
                       ('adapted-kernel.scm', adapted), ('strict.scm', program(source)),
                       ('chez/program.scm', original), ('chez-adapted/program.scm', adjusted),
                       ('chez-prelude.scm', files['src/Petite-Chez-prelude.scm'].decode())]:
        target = directory / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
    driver.save(directory / 'adaptation-ledger.json', ledger)
    driver.save(directory / 'complete-chez-edit-ledger.json', complete_ledger)
    (directory / 'chez-adaptation.patch').write_text(''.join(difflib.unified_diff(
        original.splitlines(True), adjusted.splitlines(True), fromfile='original-chez', tofile='adapted-chez')))


# ---- Every preparation build and execution has a terminal process record ----

NATIVE_PROVIDER = reader_ports.NATIVE_PROVIDER + '''#include <stdio.h>
void write_character(uint32_t value) {
    if (value < 128) { putchar(value); fflush(stdout); return; }
    unsigned width = value < 2048 ? 2 : value < 65536 ? 3 : 4;
    const unsigned first[] = {0, 0, 192, 224, 240};
    putchar(first[width] | (value >> (6 * (width - 1))));
    for (unsigned index = width - 1; index; index--)
        putchar(128 | ((value >> (6 * (index - 1))) & 63));
    fflush(stdout);
}
'''


def link_program(directory, target, artifact, tools, environment, driver):
    for label, suffix, flags in [('raw', '.raw.wasm', ['--diagnostic-prune-only']), ('optimized', '', [])]:
        reader_ports.record(target, label + '-link', [driver.ROOT / 'scripts/link-strict-runtime',
            '--runtime', directory / 'runtime.wasm', *flags, str(artifact) + suffix,
            target / (label + '.wasm')], environment, driver.ROOT)


def build(directory, tools, environment, driver):
    reader_ports.record(directory, 'strict-build', [driver.ROOT / 'scripts/build-strict', '--export', 'bench',
        '--export', 'configured-count', directory / 'strict.scm', directory / 'strict-native.wasm'], environment, driver.ROOT)
    reader_ports.record(directory, 'rust-runtime', [tools['CARGO'], 'rustc', '--crate-type=cdylib', '--quiet', '--offline',
        '--release', '--target', 'wasm32-wasip1', '--target-dir', driver.ROOT / 'build/wasm-runtime'], environment, driver.ROOT)
    shutil.copyfile(driver.ROOT / 'build/wasm-runtime/wasm32-wasip1/release/snail_runtime.wasm', directory / 'runtime.wasm')
    link_program(directory, directory, directory / 'strict-native.wasm', tools, environment, driver)
    for name, text in [('native-provider.h', reader_ports.NATIVE_HEADER + 'void write_character(uint32_t);\n'),
                       ('native-provider.c', NATIVE_PROVIDER), ('native-entry.c', reader_ports.NATIVE_ENTRY)]:
        (directory / name).write_text(text)
    reader_ports.record(directory, 'native-build', [driver.ROOT / 'scripts/build-native', '--wasm', '--c-provider', 'benchmark',
        directory / 'native-provider.h', directory / 'native-provider.c', '--entry-c', directory / 'native-entry.c',
        directory / 'strict-native.wasm', directory / 'native'], environment, driver.ROOT)


def fixture(label, text, expected, count=1, accepted=True):
    data = f'{count}\n"inputs/parsing.data"\n{expected}\n'.encode()
    return dict(label=label, data=data, text=text.encode(), accepted=accepted)


def fixtures(data, text):
    cases = [dict(label='canonical', data=data, text=text, accepted=True)]
    cases += [fixture('count-' + str(count), text.decode(), '(should return this list)', count) for count in (1, 2)]
    cases += [fixture('wrong-final-element', text.decode(), '(should return this nope)', 1, False),
              fixture('zero-parses', text.decode(), '#f', 0),
              fixture('zero-wrong-predicate', text.decode(), '(should return this list)', 0, False),
              fixture('empty', '', 'eof'), fixture('datum-eof', 'old eof ignored', 'old'),
              fixture('sentinel-eof', 'old ~ ignored', 'old'), fixture('eof-recovery', '(x ', '(x . eof)'),
              fixture('quote-recovery', "'", '(quote eof)'), fixture('nested', "`(,a ,@b)",
                      '(quasiquote ((unquote a) (unquote-splicing b)))'),
              fixture('values', 'old (last #(1 2) (a . b) "raw\\n" #\\space -.5)',
                      '(last #(1 2) (a . b) "raw\\\\n" #\\# -0.5)'),
              fixture('long-token-limit', 'a' * 1024 + ' ', 'a' * 1024)]
    return cases


def compiled_commands(directory, target, tools, driver):
    host = [tools['NODE'], '--disable-warning=ExperimentalWarning', driver.HERE / 'reader-host.mjs']
    return [('raw', [*host, directory / 'raw.wasm', target / 'spec.json']),
            ('optimized', [*host, directory / 'optimized.wasm', target / 'spec.json']),
            ('native', [directory / 'native'])]


def compiled_result(run, spec, text, data):
    value = json.loads(run['stdout'])
    required = dict(result=spec['expected'], barriers=2, setup_closed=1, worker_closed=1)
    if run['stderr'] or any(value.get(key) != amount for key, amount in required.items()):
        raise ValueError('Parsing result, opacity count or file lifetime differs')
    if 'phases' in value:
        reader_ports.validate_io(value, len(data), spec['pathnames'][0], [len(text)])
    return value


def chez_result(run, spec):
    name = 'parsing:' + str(spec['count'])
    prefix, frame = f'Running {name}\n', f'+!CSVLINE!+chez,{name},'
    number = r'[0-9.eE+\-]+'
    if spec['expected']:
        valid = re.fullmatch(re.escape(prefix) + rf'Elapsed time: ({number}) seconds \(({number})\) for '
                            + re.escape(name + '\n' + frame) + rf'({number})\n', run['stdout'])
        valid = valid and float(valid[1]) == float(valid[3])
    else:
        valid = re.fullmatch(re.escape(prefix) + r'ERROR: returned incorrect result: [^\n]+\n'
                            + re.escape(frame + 'INCORRECT\n'), run['stdout'])
    if run['stderr'] or not valid:
        raise ValueError('Parsing complete Chez predicate or output frame differs')
    return dict(accepted=bool(spec['expected']))


def seed_fixture(target, case, driver):
    target.mkdir(parents=True)
    spec = dict(specification(case['data']), expected=int(case['accepted']))
    reader_ports.seed_files(target, spec, case['data'], case['text'])
    driver.save(target / 'spec.json', spec)
    return spec


def compiled_fixture(directory, target, case, spec, tools, environment, driver):
    results = {}
    for system, command in compiled_commands(directory, target, tools, driver):
        run = reader_ports.record(target, system, command, environment, target)
        results[system] = compiled_result(run, spec, case['text'], case['data'])
    return results


def validate_fixture(directory, case, commands, tools, environment, driver):
    target = directory / 'checks' / case['label']
    spec = seed_fixture(target, case, driver)
    results = compiled_fixture(directory, target, case, spec, tools, environment, driver)
    for system, command in commands.items():
        run = reader_ports.record(target, system, command, environment, target, case['data'].decode())
        results[system] = chez_result(run, spec)
    driver.save(target / 'validation.json', results)
    return dict(label=case['label'], count=spec['count'], accepted=case['accepted'], systems=list(results))


def rejection_cases():
    syntax = ('Syntax error in line 1 while parsing a <list4>\n'
              '  Encountered a id while expecting something in\n  (rparen)\n')
    return [('syntax', '(a . b c)', 'Syntax error', syntax),
            ('incomplete-character', '#\\n', 'Lexical Error:', ''),
            ('unterminated-string', '"unclosed', 'Amazingly long token', ''),
            ('unterminated-comment', '; comment at eof', 'Amazingly long token', ''),
            ('long-token', 'a' * 1025 + ' ', 'Amazingly long token', '')]


def rejection_output(run, system, count):
    output = run['stdout']
    if system.startswith('chez'):
        prefix = f'Running parsing:{count}\n'
        if not output.startswith(prefix):
            raise ValueError('missing original failure harness frame')
        output = output[len(prefix):]
    elif system in ('raw', 'optimized'):
        lines = output.splitlines(keepends=True)
        state = json.loads(lines[-1])
        output = ''.join(lines[:-1])
        if not state.get('failed') or state.get('cleanup_closed') != 0:
            raise ValueError('failed Parsing worker leaked a file')
    return output


def rejected_output(run, system, count, marker, emitted):
    if rejection_output(run, system, count) != emitted or marker not in run['stderr']:
        raise ValueError('Parsing emitted diagnostics or fatal error category differs: ' + system)


def validate_rejection(directory, rejection, commands, tools, environment, driver):
    label, text, marker, emitted = rejection
    case, target = fixture(label, text, '#f'), directory / 'rejections' / label
    seed_fixture(target, case, driver)
    for system, command in [*commands.items(), *compiled_commands(directory, target, tools, driver)]:
        stdin = case['data'].decode() if system.startswith('chez') else None
        run = reader_ports.record(target, system, command, environment, target, stdin, failure=True)
        rejected_output(run, system, 1, marker, emitted)
    return dict(label=label, message=marker, emitted=emitted)


def validate_rejections(directory, commands, tools, environment, driver):
    checks = []
    for rejection in rejection_cases():
        checks.append(validate_rejection(directory, rejection, commands, tools, environment, driver))
        driver.save(directory / 'rejections' / 'validation.json', checks)


# ---- Native lowering and V8 also execute the identical final Wasm module ----


def native_module(directory, tools, environment, driver):
    modules = list(directory.glob('native.native-*/optimized.wasm'))
    if len(modules) != 1:
        raise ValueError('expected one final native Wasm input')
    target = directory / 'native-module'
    target.mkdir()
    shutil.copy2(modules[0], target / 'native-final.wasm')
    reader_ports.prepare_scalar_provider(target / 'native-final.wasm', directory / 'runtime.wasm',
                                         target, tools, environment, driver)
    return target


def validate_native_module(directory, tools, environment, driver):
    target = native_module(directory, tools, environment, driver)
    command = [tools['NODE'], '--disable-warning=ExperimentalWarning', driver.HERE / 'reader-host.mjs',
               target / 'native-final.wasm', directory / 'spec.json', target / 'provider.wasm']
    run = reader_ports.record(target, 'canonical', command, environment, directory)
    checked = compiled_result(run, driver.load(directory / 'spec.json'),
                              (directory / 'inputs/parsing.data').read_bytes(), (directory / 'input.txt').read_bytes())
    driver.save(target / 'validation.json', dict(result=checked,
        native_final_wasm_sha256=driver.digest(target / 'native-final.wasm'), provider_sha256=driver.digest(target / 'provider.wasm')))


def verify_recorded_reversal(directory, driver):
    ledger = driver.load(directory / 'adaptation-ledger.json')
    restored = restore_kernel((directory / 'adapted-kernel.scm').read_text(), ledger)
    if restored.encode() != (directory / 'upstream-kernel.scm').read_bytes():
        raise ValueError('retained Parsing kernel does not reverse exactly')
    change = driver.load(directory / 'complete-chez-edit-ledger.json')['complete_program_edit']
    restored = restore_edits((directory / 'chez-adapted/program.scm').read_text(), [change])
    if restored.encode() != (directory / 'chez/program.scm').read_bytes():
        raise ValueError('retained complete Chez program does not reverse exactly')


def retain_source_proof(directory, driver):
    verify_recorded_reversal(directory, driver)
    names = ['upstream.scm', 'upstream-kernel.scm', 'adapted-kernel.scm', 'strict.scm',
             'chez/program.scm', 'chez-adapted/program.scm', 'input.txt', 'inputs/parsing.data']
    driver.save(directory / 'source-proof.json', dict(complete_reverse_verified=True,
        hashes={name: driver.digest(directory / name) for name in names},
        bytes=len((directory / 'inputs/parsing.data').read_bytes()),
        characters=len((directory / 'inputs/parsing.data').read_text()), count=2500, outer_invocations=1,
        source_comment='The actual timed lambda includes the one character-list file load.',
        domain='Nonnegative I64 counts; existing Number supports I64/F64/complex scalars and rejects rationals or larger exact integers.'))


# ---- Separate observers expose all top-level datums, work and shared tails ----

ORIGINAL_ALIASES = '''(define datum-cons cons)
(define datum-car car)
(define datum-cdr cdr)
(define datum-list list)
(define datum-eq? eq?)
(define datum=? equal?)
(define datum-string values)
(define datum-string-value values)
(define datum-vector-values values)
(define datum-set-car! set-car!)
(define datum-set-cdr! set-cdr!)
(define parsing-integer values)
(define parsing-exact values)
(define typed-symbol->string symbol->string)
(define (datum-null) '())
(define (datum-fail text) (error 'parsing text))
'''


def counter_names(source):
    # scannererror has internal definitions; the anonymous loader callback also
    # has no individual counter. Describe the 79 named entries, not all calls.
    return [item[1] for item in re.finditer(r'\(define \(([^\s()]+)[^)]*\)', kernel(source)) if item[1] != 'scannererror']


def observe_entries(body, names, ledger):
    for index, name in enumerate(names):
        signature = re.search(r'\(define \(' + re.escape(name) + r'(?:[\s.]|\))[^\n]*', body)
        end = body.index(')', signature.start()) + 1
        before = body[signature.start():end]
        body = edit(body, ledger, before, before + f'\n      (observer-tick! {index})')
    return body


def observed_kernel(source, adapted):
    original = adaptation(kernel(source))[0] if adapted else kernel(source)
    ledger = []
    body = observe_entries(original, counter_names(source), ledger)
    token = '(ref-set! nextTokenIsReady #t)' if adapted else '(set! nextTokenIsReady #t)'
    text = '(ref-get tokenValue)' if adapted else 'tokenValue'
    body = edit(body, ledger, token, token + f'\n      (observer-token t {text})')
    do = 'parsing-do' if adapted else 'do'
    before = f'({do} ((x (parse-datum) (parse-datum))'
    after = ('(when (ref-get observer-sharing-enabled) (observer-sharing pseudoAppend))\n\n'
             f'    ({do} ((x (observer-datum (parse-datum)) (observer-datum (parse-datum)))')
    body = edit(body, ledger, before, after)
    if restore_edits(body, ledger) != original:
        raise ValueError('Parsing observation edits did not reverse')
    return body, ledger


def observer_prefix(source, root, adapted):
    names = counter_names(source)
    prefix = f'(define observer-counts (make-vector {len(names)} 0))\n'
    observer = reader_ports.strict_observer(root) if adapted else reader_ports.original_observer(root)
    return prefix + observer.replace('(symbol->string ', '(typed-symbol->string ') + (root / 'tests/strict-parsing/probe.scm').read_text()


def strict_probe(source, root):
    prefix = IMPORTS.replace('(snail strict)', '(snail strict) (snail bytes)') + STRICT_SERVICES + COMMON
    bindings = '''(define observer-count (specification-count configured))
(define observer-path (specification-path configured))
(define observer-expected (specification-expected configured))
'''
    return prefix + observer_prefix(source, root, True) + observed_kernel(source, True)[0] + INPUTS + bindings + '(unit)\n'


def chez_observers(source, root, adapted):
    observers = observer_prefix(source, root, adapted)
    if adapted:
        externs = reader_ports.strict_observer(root).split('(: observe-string', 1)[0]
        emitters = reader_ports.original_observer(root).split('(define (observe-string', 1)[0]
        observers = replace(observers, externs, emitters)
    return observers


def chez_probe(source, root, adapted):
    prefix = chez_prelude(root) if adapted else reader_ports.CHEZ_TYPES + ORIGINAL_ALIASES
    body = observed_kernel(source, adapted)[0]
    count, pathname = '(read port)', '(read port)'
    expected = '(read-value! (workload-read port))' if adapted else '(read port)'
    bindings = f'''(define observer-input (call-with-input-file "input.txt"
  (lambda (port) (let* ((count {count}) (path {pathname}) (expected {expected})) (vector count path expected)))))
(define observer-count (vector-ref observer-input 0))
(define observer-path (vector-ref observer-input 1))
(define observer-expected (vector-ref observer-input 2))
(define mode (cadr (command-line)))
(let ((result (cond ((string=? mode "semantics-probe") (semantics-probe))
                    ((string=? mode "work-probe") (work-probe)) (else (observe-once)))))
  (display "result:") (write result) (newline))
'''
    observers = chez_observers(source, root, adapted)
    return '(import (except (chezscheme) string-copy!))\n' + prefix + observers + body + bindings


def compile_chez_probes(target, tools, environment):
    for system in ('chez', 'chez-adapted'):
        source, artifact = str(target / (system + '.scm')), str(target / (system + '.so'))
        script = target / (system + '-compile.scm')
        script.write_text('(import (chezscheme))\n(parameterize ((optimize-level 2))\n'
                          f'  (compile-program {json.dumps(source)} {json.dumps(artifact)}))\n')
        reader_ports.record(target, system + '-compile', [tools['CHEZ'], '--script', script], environment)


def write_probe_sources(directory, driver):
    target = directory / 'observations'
    target.mkdir()
    source = (directory / 'upstream.scm').read_text()
    (target / 'strict.scm').write_text(strict_probe(source, driver.ROOT))
    for adapted, system in [(False, 'chez'), (True, 'chez-adapted')]:
        (target / (system + '.scm')).write_text(chez_probe(source, driver.ROOT, adapted))
        driver.save(target / (system + '-edits.json'), observed_kernel(source, adapted)[1])
    return target


def build_probe(directory, tools, environment, driver):
    target = write_probe_sources(directory, driver)
    compile_chez_probes(target, tools, environment)
    exports = [part for name in ('observe-once', 'work-probe', 'semantics-probe') for part in ('--export', name)]
    reader_ports.record(target, 'compile', [driver.ROOT / 'scripts/build-strict', *exports,
                        target / 'strict.scm', target / 'strict.wasm'], environment, driver.ROOT)
    link_program(directory, target, target / 'strict.wasm', tools, environment, driver)
    shutil.copy2(driver.ROOT / 'tests/strict-parsing/entry.c', target / 'entry.c')
    reader_ports.record(target, 'native-build', [driver.ROOT / 'scripts/build-native', '--wasm',
        '--c-provider', 'benchmark', directory / 'native-provider.h', directory / 'native-provider.c',
        '--c-provider', 'reader.test', driver.ROOT / 'tests/strict-reader/observer.h', driver.ROOT / 'tests/strict-reader/observer.c',
        '--entry-c', target / 'entry.c', target / 'strict.wasm', target / 'native'], environment, driver.ROOT)
    return target


def probe_commands(probe, target, mode, tools, driver):
    host = [tools['NODE'], '--disable-warning=ExperimentalWarning', driver.HERE / 'browse-observe.mjs']
    return [('chez', [tools['CHEZ'], '--program', probe / 'chez.so', mode]),
            ('chez-adapted', [tools['CHEZ'], '--program', probe / 'chez-adapted.so', mode]),
            ('raw', [*host, probe / 'raw.wasm', target / 'spec.json']),
            ('optimized', [*host, probe / 'optimized.wasm', target / 'spec.json']),
            ('native', [probe / 'native', mode])]


def checked_trace(run, mode, system):
    trace = run['stdout']
    result = 42 if mode == 'semantics-probe' else 1
    if run['stderr'] or not re.fullmatch(r'(?:(?:i|c|f):(?:-?\d+|nan)\n)*result:' + str(result) + '\n', trace):
        raise ValueError('invalid Parsing observation frame: ' + system)
    return trace


def probe_trace(target, mode, system, command, environment):
    run = reader_ports.record(target, system, command, environment, target)
    trace = checked_trace(run, mode, system)
    (target / (system + '.trace')).write_text(trace)
    identity = dict(sha256=hashlib.sha256(trace.encode()).hexdigest(), bytes=len(trace), fields=len(trace.splitlines()))
    return trace, identity


def compare_probe(probe, case, mode, tools, environment, driver):
    target = probe / case['label']
    seed_fixture(target, case, driver)
    driver.save(target / 'spec.json', dict(export=mode))
    expected, results = None, {}
    for system, command in probe_commands(probe, target, mode, tools, driver):
        trace, results[system] = probe_trace(target, mode, system, command, environment)
        expected = trace if expected is None else expected
        if trace != expected:
            raise ValueError('Parsing complete datum, token order or work counters differ: ' + system)
    driver.save(target / 'validation.json', results)
    return dict(label=case['label'], mode=mode, systems=results)


def retain_counters(probe, names, driver):
    fields = (probe / 'complete-work' / 'chez.trace').read_text().splitlines()
    start = fields.index('i:102') + 1
    if fields[start] != f'i:{len(names)}':
        raise ValueError('Parsing counter inventory differs')
    values = (int(field[2:]) for field in fields[start + 1:-1])
    driver.save(probe / 'complete-work' / 'counters.json', dict(zip(names, values, strict=True)))


def validate_observations(directory, tools, environment, driver):
    probe = build_probe(directory, tools, environment, driver)
    text = (directory / 'inputs/parsing.data').read_text()
    cases = [(fixture('complete-input-order', text, '(should return this list)'), 'observe-once'),
             (fixture('small-order', '(first 1) (last "text" #(a b) . tail)', '(last "text" #(a b) . tail)'), 'observe-once'),
             (fixture('sharing-and-reset', '', 'eof'), 'semantics-probe'),
             (fixture('complete-work', text, '(should return this list)', 2500), 'work-probe')]
    results = []
    for case, mode in cases:
        results.append(compare_probe(probe, case, mode, tools, environment, driver))
        driver.save(probe / 'validation.json', dict(cases=results, counter_names=counter_names((directory / 'upstream.scm').read_text())))
    retain_counters(probe, counter_names((directory / 'upstream.scm').read_text()), driver)


# ---- The independent Rust control retains its existing parser and Rc pairs ----


def rust_result(run, spec, accepted):
    if not accepted:
        if run['stdout'] or 'assertion' not in run['stderr']:
            raise ValueError('Rust Parsing did not reject the wrong complete result')
        return
    expected = 'Result: ' + spec['expected_datum'] + '\n'
    frame = f'+!CSVLINE!+rust-wasm,parsing:{spec["count"]},'
    if run['stderr'] or not re.fullmatch(re.escape(expected + frame) + r'[0-9.eE+\-]+\n', run['stdout']):
        raise ValueError('Rust Parsing complete result or output frame differs')


def build_rust_control(directory, tools, environment, driver):
    target = directory / 'rust-control'
    source = driver.ROOT / 'benchmarks/wasm-reference'
    shutil.copytree(source / 'src', target / 'src')
    for name in ('Cargo.toml', 'Cargo.lock', 'run-wasi.mjs'):
        shutil.copy2(source / name, target / name)
    reader_ports.record(target, 'unit-tests', [tools['CARGO'], 'test', '--offline', '--bin', 'parsing'],
                        dict(environment, CARGO_TARGET_DIR=str(target / 'target')), target)
    reader_ports.build_rust_bin(target, 'parsing', tools, environment)
    retain_rust_ir(target)
    return target


def retain_rust_ir(target):
    for system, directory in [('native', 'release'), ('wasm', 'wasm32-wasip1/release')]:
        modules = list((target / 'target' / directory / 'deps').glob('parsing-*.ll'))
        if len(modules) != 1:
            raise ValueError('expected one Rust Parsing LLVM module: ' + system)
        shutil.copy2(modules[0], target / ('parsing-' + system + '.ll'))


def prepare_rust_control(directory, tools, environment, driver):
    target = build_rust_control(directory, tools, environment, driver)
    checks = []
    for case in fixtures((directory / 'input.txt').read_bytes(), (directory / 'inputs/parsing.data').read_bytes()):
        spec, working = specification(case['data']), directory / 'checks' / case['label']
        for system, command in reader_ports.rust_commands(target, 'parsing', tools):
            run = reader_ports.record(target, case['label'] + '-' + system, command, environment, working,
                                      case['data'].decode(), failure=not case['accepted'])
            rust_result(run, spec, case['accepted'])
            checks.append(dict(label=case['label'], system=system, accepted=case['accepted']))
    driver.save(target / 'validation.json', dict(checks=checks,
        representation='Existing independent Rust state machine, LinkedList character loading, interned Rc symbols and immutable Rc pairs; no equal-allocation claim.'))


def prepare_sources(files, output, runner, driver):
    directory = output / 'parsing'
    directory.mkdir()
    data, text = files['inputs/parsing.input'], files['inputs/parsing.data']
    spec = specification(data)
    reader_ports.seed_files(directory, spec, data, text)
    driver.save(directory / 'spec.json', spec)
    write_sources(files, directory, runner, driver)
    return directory


def validate_fixtures(directory, commands, tools, environment, driver):
    checks = []
    data, text = (directory / 'input.txt').read_bytes(), (directory / 'inputs/parsing.data').read_bytes()
    for case in fixtures(data, text):
        checks.append(validate_fixture(directory, case, commands, tools, environment, driver))
        driver.save(directory / 'validation.json', checks)


def prepared_case(directory, commands, driver):
    return dict(name='parsing', status='ready', spec=driver.load(directory / 'spec.json'), chez_commands=commands,
                systems=['strict', 'native', 'chez', 'chez-adapted'],
                hashes={str(path.relative_to(directory)): driver.digest(path)
                        for path in directory.rglob('*')
                        if path.is_file() and 'target' not in path.relative_to(directory).parts})


def prepare_workload(files, output, runner, tools, environment, driver):
    directory = prepare_sources(files, output, runner, driver)
    build(directory, tools, environment, driver)
    commands = reader_ports.build_chez(directory, runner, tools, environment)
    validate_fixtures(directory, commands, tools, environment, driver)
    validate_rejections(directory, commands, tools, environment, driver)
    validate_observations(directory, tools, environment, driver)
    validate_native_module(directory, tools, environment, driver)
    prepare_rust_control(directory, tools, environment, driver)
    retain_source_proof(directory, driver)
    return prepared_case(directory, commands, driver)


def prepare_case(files, output, runner, tools, environment, driver):
    previous = signal.signal(signal.SIGTERM, reader_ports.interrupted)
    try:
        return prepare_workload(files, output, runner, tools, environment, driver)
    finally:
        signal.signal(signal.SIGTERM, previous)
