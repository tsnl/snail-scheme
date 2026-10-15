"""Prepare matched, diagnostic-only Tail file-provider artifacts and checks."""

import datetime
import difflib
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time


# ---- One frozen source, toolchain and pre-link Scheme program ----

ROOT = Path('/tmp/snail-tail-indexed-lookup-20261014')
REPORT = ROOT / 'benchmarks/results/2026-10-14-strict-tail-indexed-lookup'
BUILD = ROOT / 'build/tail-indexed-lookup'
PREPARATION = Path('/tmp/snail-strict-tail-20261014/build/strict-tail-final')
CASE = PREPARATION / 'tail'
EVIDENCE = Path('/tmp/snail-strict-tail-20261014/build/tail-evidence')
FEATURES = ['--mvp-features', '--enable-gc', '--enable-reference-types', '--enable-tail-call',
            '--enable-mutable-globals', '--enable-sign-ext', '--enable-bulk-memory',
            '--enable-nontrapping-float-to-int']
REMOVED_NODE = ['NODE_OPTIONS', 'NODE_V8_COVERAGE', 'NODE_DEBUG', 'NODE_DEBUG_NATIVE']
UNSET_BUILD = ['RUSTFLAGS', 'CARGO_ENCODED_RUSTFLAGS', 'RUSTC', 'RUSTC_WRAPPER', 'RUSTC_WORKSPACE_WRAPPER',
               'CARGO_TARGET_DIR', 'CARGO_INCREMENTAL', 'RUSTUP_TOOLCHAIN']


def load(path):
    return json.loads(Path(path).read_text())


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n')


def identity(path):
    return dict(path=str(path), sha256=hashlib.sha256(Path(path).read_bytes()).hexdigest())


def environment():
    assert all(not os.environ.get(key) for key in UNSET_BUILD), 'unfrozen Rust build override'
    assert not os.environ.get('LD_PRELOAD')
    env = {key: value for key, value in os.environ.items() if key not in REMOVED_NODE}
    env.update({key: tool['path'] for key, tool in load(PREPARATION / 'prepared.json')['tools'].items()})
    return env


def group_members(group):
    members = []
    for status in Path('/proc').glob('[0-9]*/stat'):
        try:
            fields = status.read_text().rsplit(')', 1)[1].split()
        except (FileNotFoundError, ProcessLookupError):
            continue
        if int(fields[2]) == group:
            members.append(dict(pid=int(status.parent.name), state=fields[0]))
    return members


def kill_group(group):
    try:
        os.killpg(group, signal.SIGKILL)
        return True
    except ProcessLookupError:
        return False


def finish_group(process):
    before = group_members(process.pid)
    killed = kill_group(process.pid) if any(member['state'] != 'Z' for member in before) else False
    deadline = time.monotonic() + 2
    while any(member['state'] != 'Z' for member in group_members(process.pid)) and time.monotonic() < deadline:
        time.sleep(0.01)
    after = group_members(process.pid)
    return dict(group=process.pid, killed_remaining_descendants=killed, remaining=after,
                no_executing_descendants=all(member['state'] == 'Z' for member in after))


def run(command, cwd, log, env=None, stdin=b'', inputs=None, timeout=900):
    record = dict(command=list(map(str, command)), cwd=str(cwd), status='started', performance_samples=False,
                  started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    if inputs is not None:
        record['identities_before'] = inputs
    save(log, record)
    start, process = time.monotonic(), None
    try:
        process = subprocess.Popen(record['command'], cwd=cwd, env=env or environment(),
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   start_new_session=True)
        record['owned_process_group'] = process.pid
        save(log, record)
        stdout, stderr = process.communicate(stdin, timeout=timeout)
        outcome = dict(status='exited', returncode=process.returncode)
    except subprocess.TimeoutExpired as error:
        record['timeout_group_kill_sent'] = kill_group(process.pid)
        stdout, stderr = process.communicate()
        outcome = dict(status='timeout', returncode=process.returncode, timeout_seconds=timeout)
    except OSError as error:
        if process is not None:
            kill_group(process.pid)
            process.wait()
        outcome, stdout, stderr = dict(status='launch-failed', returncode=None, error=repr(error)), b'', b''
    finally:
        if process is not None:
            record['group_cleanup'] = finish_group(process)
    for suffix, data in [('stdout.bin', stdout), ('stderr.bin', stderr)]:
        Path(str(log) + '.' + suffix).write_bytes(data)
    record.update(outcome, diagnostic_process_seconds=time.monotonic() - start,
                  stdout_raw=identity(str(log) + '.stdout.bin'), stderr_raw=identity(str(log) + '.stderr.bin'))
    save(log, record)
    record.update(stdout=stdout.decode(), stderr=stderr.decode())
    save(log, record)
    assert process is None or record['group_cleanup']['no_executing_descendants'], record
    assert record['returncode'] == 0, record
    return record


def require_frozen_inputs():
    prepared = load(PREPARATION / 'prepared.json')
    for directory, hashes in [(PREPARATION / 'compiler-source', prepared['compiler_files']),
                              (CASE, prepared['cases'][0]['hashes'])]:
        for leaf, expected in hashes.items():
            assert identity(directory / leaf)['sha256'] == expected, leaf
    for tool in prepared['tools'].values():
        assert identity(tool['path'])['sha256'] == tool['sha256']
    for path, expected in load(CASE / 'runtime-toolchain.json')['toolchain_files'].items():
        assert identity(path)['sha256'] == expected
    assert identity(CASE / 'strict-native.wasm')['sha256'] == '097a7eab1e03b7a8905d6487bb622d70aa2e55a7e5da89ae1fa5e827e89b6594'
    assert (CASE / 'input.txt').read_bytes() == b'50\n"inputs/bib"\n"outputs/tail.output"\nignored\n'
    return prepared


# ---- Sparse private-helper history supplements the unchanged unit tests ----

COMMON_TEST = r'''
    #[test]
    fn successful_and_failed_opens_consume_ids_without_reuse() {
        let root = std::path::PathBuf::from(std::env::var("TAIL_LOOKUP_TEST_ROOT").unwrap());
        std::fs::create_dir(&root).unwrap();
        let present = root.join("present.txt").to_str().unwrap().to_owned();
        let absent = root.join("absent/child.txt").to_str().unwrap().to_owned();
        let first = FILES.with_borrow(|files| files.next);
        let output = open_output(present.clone()).unwrap() as u32;
        assert_eq!(output, first);
        write_code(output, 0x03bb);
        close(output);
        assert!(open_input(absent.clone()).is_err());
        assert!(open_output(absent).is_err());
        let input = open_input(present).unwrap() as u32;
        assert_eq!(input, first + 3);
        assert_eq!(read_code(input), 0x03bb);
        assert_eq!(read_code(input), -1);
        assert!(FILES.with_borrow_mut(|files| files.get(first).is_err()));
        assert!(FILES.with_borrow_mut(|files| files.get(first + 1).is_err()));
        assert!(FILES.with_borrow_mut(|files| files.get(first + 2).is_err()));
        close(input);
        assert_eq!(FILES.with_borrow(|files| files.next), first + 4);
        assert_eq!(close_all(), 0);
    }
'''


def candidate_source(original):
    changes = [('use std::{cell::RefCell, collections::BTreeMap, path::Path};',
                'use std::{cell::RefCell, path::Path};'),
               ('    live: BTreeMap<u32, Port>,',
                '    // Diagnostic only: historical ID holes remain until invocation cleanup.\n    live: Vec<Option<Port>>,'),
               ('.get_mut(&id)\n            .ok_or_else', '.get_mut(id as usize)\n            .and_then(Option::as_mut)\n            .ok_or_else'),
               ('.remove(&id)\n            .ok_or_else', '.get_mut(id as usize)\n            .and_then(Option::take)\n            .ok_or_else'),
               ('    fn get(&mut self, id: u32)', '''    fn insert(&mut self, id: u32, port: Port) {
        // The opened Port stays locally owned until its slot is published.
        // reserve_id never reuses an ID, so publication cannot replace a live Port.
        let index = id as usize;
        if self.live.len() <= index {
            self.live.resize_with(index + 1, || None);
        }
        self.live[index] = Some(port);
    }

    fn get(&mut self, id: u32)'''),
               ('files.live.insert(', 'files.insert('),
               ('files\n                .live\n                .insert(', 'files\n                .insert('),
               ('ports.into_values()', 'ports.into_iter().flatten()')]
    text, ledger = original, []
    for before, after in changes:
        occurrences = text.count(before)
        assert occurrences > 0, before
        text = text.replace(before, after)
        ledger.append(dict(before=before, after=after, occurrences=occurrences))
    erased = text
    for change in reversed(ledger):
        assert erased.count(change['after']) == change['occurrences']
        erased = erased.replace(change['after'], change['before'])
    assert erased == original
    save(BUILD / 'representation-erasure.json', dict(exact_erasure=True, changes=ledger,
         common_tests_are_cfg_test_only=True, production_authorized=False))
    return text


def prepare_sources(prepared):
    source = PREPARATION / 'compiler-source'
    original = (source / 'src/strict_io.rs').read_text()
    assert original.endswith('\n}\n')
    baseline = original[:-2] + COMMON_TEST + '}\n'
    for name, strict_io in [('baseline', baseline), ('indexed', candidate_source(baseline))]:
        project = BUILD / name / 'source'
        for leaf in prepared['compiler_files']:
            destination = project / leaf
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / leaf, destination)
        (project / 'src/strict_io.rs').write_text(strict_io)
    indexed = (BUILD / 'indexed/source/src/strict_io.rs').read_text()
    (BUILD / 'provider-change.patch').write_text(''.join(difflib.unified_diff(
        baseline.splitlines(keepends=True), indexed.splitlines(keepends=True),
        fromfile='baseline/src/strict_io.rs', tofile='indexed/src/strict_io.rs')))
    shutil.copyfile(CASE / 'strict-native.wasm', BUILD / 'program.wasm')
    prepare_full_observer()
    save(BUILD / 'spec.json', dict(load(CASE / 'spec.json'), trace=True))


def prepare_full_observer():
    original = (EVIDENCE / 'retention-host.mjs').read_text()
    check = '''    if (status === 0 && pathname === config.pathnames[1]) {
      const actual = fs.readFileSync(pathname);
      outputChecks.push({iteration: outputChecks.length + 1, bytes: actual.length,
                        sha256: createHash('sha256').update(actual).digest('hex')});
      assert(actual.equals(expectedOutput), 'every repetition writes the complete reversed oracle');
    }
'''
    changes = [('import fs', "import {createHash} from 'node:crypto';\nimport fs"),
               ('const events = [], live = new Map();',
                "const expectedOutput = fs.readFileSync(process.argv[5]);\nconst outputChecks = [];\nconst events = [], live = new Map();"),
               ('    const status = wasi.wasiImport.fd_close(descriptor);',
                '    const pathname = live.get(descriptor);\n    const status = wasi.wasiImport.fd_close(descriptor);'),
               ('    if (status === 0) live.delete(descriptor);\n    return status;',
                '    if (status === 0) live.delete(descriptor);\n' + check + '    return status;'),
               ('  observation.written_bytes = writtenBytes;',
                '  observation.written_bytes = writtenBytes;\n  observation.output_checks = outputChecks;')]
    text = original
    for before, after in changes:
        assert text.count(before) == 1
        text = text.replace(before, after)
    erased = text
    for before, after in reversed(changes):
        assert erased.count(after) == 1
        erased = erased.replace(after, before)
    assert erased == original
    (BUILD / 'retention-host.mjs').write_text(text)
    save(BUILD / 'observer-erasure.json', dict(exact_erasure=True, original=identity(EVIDENCE / 'retention-host.mjs'),
         changes=changes, diagnostic_only=True, output_checks_after_each_successful_output_close=True))


# ---- Matched Rust builds, mandatory Binaryen links and scalar probes ----

def build_provider(name, tools):
    directory = BUILD / name
    project = BUILD / 'compile-source'
    leaves = load(PREPARATION / 'prepared.json')['compiler_files']
    for leaf in leaves:
        destination = project / leaf
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(directory / 'source' / leaf, destination)
    before = [identity(project / leaf) for leaf in leaves]
    inputs = dict(source_snapshot=str(directory / 'source'), compile_path=str(project), identities_before=before)
    save(directory / 'build-inputs.json', inputs)
    manifest, target = project / 'Cargo.toml', directory / 'target'
    command = [tools['CARGO']['path'], 'rustc', '--crate-type=cdylib', '--quiet', '--offline', '--locked',
               '--release', '--target', 'wasm32-wasip1', '--manifest-path', manifest, '--target-dir', target]
    run(command, project, directory / 'runtime-build.json')
    shutil.copyfile(target / 'wasm32-wasip1/release/snail_runtime.wasm', directory / 'runtime.wasm')
    command = [tools['PYTHON']['path'], project / 'scripts/link-strict-runtime', '--runtime',
               directory / 'runtime.wasm', BUILD / 'program.wasm', directory / 'strict.wasm']
    run(command, project, directory / 'link-build.json')
    command = [tools['WASM_OPT']['path'], '-g', *FEATURES, '-O3', '--closed-world',
               '--always-inline-max-function-size=40', '--converge', directory / 'runtime.wasm',
               '-o', directory / 'probe-runtime.wasm']
    run(command, project, directory / 'probe-build.json')
    env = environment()
    env['TAIL_LOOKUP_TEST_ROOT'] = str(directory / 'unit-files')
    command = [tools['CARGO']['path'], 'test', '--quiet', '--offline', '--locked', '--manifest-path',
               manifest, '--target-dir', directory / 'unit-target', 'strict_io::tests::', '--', '--test-threads=1']
    record = run(command, project, directory / 'unit-tests.json', env)
    assert '6 passed; 0 failed' in record['stdout'], record
    command = [tools['NODE']['path'], '--no-warnings', REPORT / 'probe.mjs',
               directory / 'probe-runtime.wasm', directory / 'scalar-probes']
    run(command, directory, directory / 'scalar-probes.json')
    inputs['identities_after'] = [identity(project / leaf) for leaf in leaves]
    assert inputs['identities_after'] == before
    save(directory / 'build-inputs.json', inputs)


def full_count(name, tools):
    reference = ROOT / 'benchmarks/results/2026-10-14-strict-tail-diagnostics/diagnose.py'
    spec = importlib.util.spec_from_file_location('tail_diagnostic_contract', reference)
    diagnostic = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(diagnostic)
    before = diagnostic.original_files()
    directory = BUILD / name / 'full-count'
    (directory / 'inputs').mkdir(parents=True, exist_ok=False)
    (directory / 'outputs').mkdir()
    shutil.copyfile(CASE / 'upstream-input.bin', directory / 'inputs/bib')
    command = [tools['TASKSET']['path'], '-c', '5', tools['NODE']['path'], '--no-warnings',
               BUILD / 'retention-host.mjs', BUILD / name / 'strict.wasm', BUILD / 'spec.json', '--validate',
               CASE / 'canonical-output.bin']
    record = run(command, directory, BUILD / name / 'full-count.json', stdin=(CASE / 'input.txt').read_bytes(), inputs=before)
    result = diagnostic.validate_files_and_lifecycle(record)
    expected = identity(CASE / 'canonical-output.bin')['sha256']
    assert result['output_checks'] == [dict(iteration=index, bytes=4460056, sha256=expected) for index in range(1, 51)]
    record['complete_output_checks'] = 50
    save(BUILD / name / 'full-count.json', record)


def close_preparation(prepared):
    paths = [BUILD / 'program.wasm', BUILD / 'representation-erasure.json', BUILD / 'provider-change.patch',
             BUILD / 'retention-host.mjs', BUILD / 'observer-erasure.json', BUILD / 'spec.json', REPORT / 'prepare.py', REPORT / 'probe.mjs']
    for name in ['baseline', 'indexed']:
        paths += [BUILD / name / 'source' / leaf for leaf in prepared['compiler_files']]
        paths += [BUILD / name / leaf for leaf in ['runtime.wasm', 'strict.wasm', 'strict.wasm.link.json',
                   'runtime-build.json', 'build-inputs.json', 'link-build.json', 'probe-runtime.wasm', 'probe-build.json',
                   'unit-tests.json', 'scalar-probes.json', 'full-count.json']]
    source_hashes = {name: {leaf: identity(BUILD / name / 'source' / leaf)['sha256'] for leaf in prepared['compiler_files']}
                     for name in ['baseline', 'indexed']}
    changed = [leaf for leaf in prepared['compiler_files'] if source_hashes['baseline'][leaf] != source_hashes['indexed'][leaf]]
    assert changed == ['src/strict_io.rs'], changed
    baseline = identity(BUILD / 'baseline/strict.wasm')
    save(BUILD / 'prepared.json', dict(ready=True, performance_samples=False, artifacts={
         name: identity(BUILD / name / 'strict.wasm') for name in ['baseline', 'indexed']},
         original_guest=identity(CASE / 'strict.wasm'), baseline_reproduces_original=baseline['sha256'] == identity(CASE / 'strict.wasm')['sha256'],
         program=identity(BUILD / 'program.wasm'), source_hashes=source_hashes, changed_source_files=changed,
         identities=[identity(path) for path in paths], tools=prepared['tools'],
         limitations=['Vec slots retain historical holes; successful publication across the I32 range is not tested or scalable.',
                      'Binaryen may optimize the linked module differently; this is a full-workload source ablation, not a universal per-lookup cost.']))


def main():
    assert not BUILD.exists(), 'retain previous attempts; never replace a preparation'
    BUILD.mkdir(parents=True)
    prepared = require_frozen_inputs()
    prepare_sources(prepared)
    for name in ['baseline', 'indexed']:
        build_provider(name, prepared['tools'])
        full_count(name, prepared['tools'])
    require_frozen_inputs()
    close_preparation(prepared)
    print('PASS matched providers, sparse-ID/cleanup probes and both complete full-count files; no clean timing')


if __name__ == '__main__':
    main()
