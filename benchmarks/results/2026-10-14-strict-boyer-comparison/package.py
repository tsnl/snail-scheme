#!/usr/bin/env python3
"""Archive completed Boyer evidence, or verify archive bytes without guests."""

import argparse
import hashlib
import io
import json
import lzma
import os
from pathlib import Path, PurePosixPath
import shutil
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
TEMP = Path('/tmp')
AUTHOR = TEMP/'snail-strict-boyer-20261014'
SOURCE = AUTHOR/'build/boyer-prepared-combined'
PREPARED = ROOT/'build/boyer-measurement-prepared-a707974'
CLEAN = ROOT/'build/boyer-clean-a707974'
PUBLISHED = ('artifacts.tar.xz', 'manifest.json', 'archive-verification.json')


# ---- Select every evidence class, including failed and superseded attempts ----

def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def read(path):
    return json.loads(path.read_text())


def save(path, value):
    path.write_text(json.dumps(value, indent=2, allow_nan=False)+'\n')


def retained_files(root):
    require(root.is_dir(), 'missing selected evidence: ' + str(root))
    for directory, children, names in os.walk(root):
        children[:] = sorted(name for name in children if name not in ('target', '__pycache__'))
        require(all(not (Path(directory)/name).is_symlink() for name in children), 'selected evidence directory is a symlink')
        for name in sorted(names):
            path = Path(directory)/name
            require(path.is_file() and not path.is_symlink(), 'nonregular selected evidence: ' + str(path))
            yield path


def evidence_files():
    roots = [SOURCE,PREPARED,CLEAN,ROOT/'benchmarks/results/2026-10-14-strict-boyer-preparation']
    roots += [AUTHOR/'build'/name for name in ('boyer-native-lifetime','boyer-observer-development','boyer-order-witness',
        'boyer-compiled-chez-refinement','boyer-compiled-chez-sequencing','boyer-explicit-lemma-order','boyer-source')]
    for pattern in ('boyer-capture-tests-a707974*','boyer-archive-tests-a707974*','boyer-historical-source-provenance*',
                    'boyer-measurement-prepared-a707974-attempt*','boyer-raw-audit-attempt*','boyer-clean-a707974-attempt*'):
        roots += sorted(ROOT.glob('build/'+pattern))
    files = {path.relative_to(TEMP).as_posix():path for root in roots for path in retained_files(root)}
    for path in REPORT.iterdir():
        if path.is_file() and path.suffix in ('.py','.md','.json','.txt') and path.name not in PUBLISHED:
            files[path.relative_to(TEMP).as_posix()] = path
    for path in sorted(AUTHOR.glob('build/*boyer*.py'))+sorted(AUTHOR.glob('build/*boyer*.json')):
        files[path.relative_to(TEMP).as_posix()] = path
    for name in ('BENCHMARKS.md','benchmarks/README.md','benchmarks/strict-suite/README.md',
                 'benchmarks/strict-suite/capabilities.md','benchmarks/strict-suite/capabilities.json'):
        path = ROOT/name
        files[path.relative_to(TEMP).as_posix()] = path
    for original in read(REPORT/'independent-review.json')['capture_sha256']:
        path = Path(original)
        if path.is_relative_to(TEMP):
            require(path.is_file() and not path.is_symlink(),'missing audited local dependency: '+original)
            files[path.relative_to(TEMP).as_posix()] = path
    return dict(sorted(files.items()))


def private_copy(files, directory):
    copied = {}
    for name, source in files.items():
        before = source.stat()
        target = directory/name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        after = source.stat()
        require((before.st_ino, before.st_size, before.st_mtime_ns, before.st_mode) ==
                (after.st_ino, after.st_size, after.st_mtime_ns, after.st_mode), 'evidence metadata changed while copying: ' + str(source))
        require(digest(source) == digest(target) and (target.stat().st_mode & 0o777) == (before.st_mode & 0o777),
                'evidence bytes/mode changed while copying: ' + str(source))
        copied[name] = target
    return copied


# ---- Copied captures must match the independently reviewed completed campaign ----

def copied_original(original, files):
    name = Path(original).relative_to(TEMP).as_posix()
    require(name in files, 'missing audited evidence: ' + name)
    return files[name]


def check_snapshot(files):
    audit = read(copied_original(REPORT/'independent-review.json', files))
    campaign = read(copied_original(CLEAN/'campaign.json', files))
    require(audit['passed'] and audit['processes'] == 112 and audit['retained'] == 98 and audit['warmups'] == 14, 'complete independent review required')
    require(campaign['complete'] is True and campaign['summary'] == audit['summary'], 'completed campaign differs')
    release = read(copied_original(REPORT/'heavy-work-release.json', files))
    require(release['clean_run_exit_code'] == 0 and release['raw_campaign_terminal'] is True,
            'actual clean runner terminal release record required')
    require(release['quiet_window_released'] is True, 'quiet-window release required before compression')
    check_tool_terminal(files)
    required = [REPORT/'timing-plan.json', CLEAN/'campaign.json']
    required += [CLEAN/f'sample-{i:03}'/name for i in range(112) for name in ('record.json', 'stdout.bin', 'stderr.bin')]
    require(all(str(path) in audit['capture_sha256'] for path in required), 'review must bind plan and all 112 records/raw captures')
    for original, expected in audit['capture_sha256'].items():
        if Path(original).is_relative_to(TEMP):
            require(digest(copied_original(original, files)) == expected, 'copied audited bytes changed: ' + original)
        else:
            toolchain = Path(read(copied_original(PREPARED/'toolchain-selection/selection.json',files))['stdout'].strip())
            require(Path(original).resolve().is_relative_to('/nix') or Path(original).is_relative_to(toolchain),'unclassified omitted external dependency: '+original)
    check_source_commitments(files)


def check_tool_terminal(files):
    terminal = read(copied_original(REPORT/'clean-run-tool-terminal.json',files))
    transcript = read(copied_original(REPORT/'clean-run-tool-transcript.json',files))
    require(terminal['terminal'] and terminal['exit_code']==0 and terminal['session_id']==57880,'actual tool terminal record differs')
    require(transcript[-1]['exit_code']==0 and transcript[-1]['chunk_id']==terminal['terminal_chunk'],'actual terminal chunk differs')
    rows = [line for chunk in transcript for line in chunk['output'].splitlines()]
    planned = read(copied_original(REPORT/'timing-plan.json',files))['schedule']
    expected = [' '.join(map(str,(row['index'],row['benchmark'],row['system'],row['phase'],'verified'))) for row in planned]
    require(rows==expected,'actual runner progress transcript differs from all112 frozen rows')


def check_source_commitments(files):
    historical = read(copied_original(SOURCE/'prepared.json',files))
    for case in historical['cases']:
        for name,expected in case['hashes'].items():
            require(digest(copied_original(SOURCE/case['name']/name,files))==expected,'historical artifact commitment changed: '+name)
    snapshot = ROOT/'build/boyer-historical-source-provenance'
    for name,expected in read(copied_original(snapshot/'source-provenance.json',files))['source_files'].items():
        require(digest(copied_original(snapshot/'source'/name,files))==expected,'historical source snapshot changed: '+name)
    provenance = read(copied_original(REPORT/'committed-source-provenance.json',files))
    for name,expected in provenance['snapshot_files'].items():
        require(digest(copied_original(PREPARED/'compiler-source'/name,files))==expected,'current compiler snapshot changed: '+name)


def archive_files(path, files):
    with tarfile.open(path, 'w:xz', preset=6) as target:
        for name, source in files.items():
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = source.stat().st_size, source.stat().st_mode & 0o777, 0
            with source.open('rb') as contents:
                target.addfile(info, contents)


def inventory(archive, files):
    members = {name: dict(sha256=digest(path), bytes=path.stat().st_size, mode=path.stat().st_mode & 0o777)
               for name, path in files.items()}
    return dict(archive_sha256=digest(archive), bytes=archive.stat().st_size, files=members,
        regular_files=len(members), uncompressed_file_bytes=sum(row['bytes'] for row in members.values()),
        excluded='Regenerable target/Python caches and external Nix/selected-Rust-toolchain binaries; tool/import/library identities remain in the frozen plan and independent replay. Selected Rust toolchain paths are mutable locations verified by digest, not bundled. All audited local dependencies and source snapshots are retained.',
        path_basis='All member paths are relative to /tmp; recorded execution paths preserve their original absolute locations.')


# ---- Fully decode one XZ stream and inspect every safe regular tar member ----

def decompress(archive, output):
    decoder = lzma.LZMADecompressor(format=lzma.FORMAT_XZ)
    with archive.open('rb') as source, output.open('xb') as target:
        while chunk := source.read(1024*1024):
            target.write(decoder.decompress(chunk))
            require(not decoder.unused_data, 'trailing compressed payload or second stream')
            if decoder.eof:
                require(source.read(1) == b'', 'trailing compressed bytes')
                break
    require(decoder.eof, 'incomplete compressed stream')


def safe_member(member):
    path = PurePosixPath(member.name)
    return (member.isfile() and bool(path.parts) and not path.is_absolute() and path.as_posix() == member.name
            and '..' not in path.parts and '\\' not in member.name and ':' not in member.name)


def tar_inventory(path):
    result = {}
    with tarfile.open(path, 'r:') as archive:
        for member in archive:
            require(safe_member(member) and member.name not in result, 'unsafe, duplicate or nonregular tar member')
            with archive.extractfile(member) as contents:
                result[member.name] = dict(sha256=hashlib.file_digest(contents, 'sha256').hexdigest(), bytes=member.size, mode=member.mode)
            require_zero_padding(path, member)
        offset = archive.offset
    with path.open('rb') as source:
        source.seek(offset)
        require(not any(source.read()), 'nonzero trailing tar payload')
    for name in result:
        require(all(parent.as_posix() not in result for parent in PurePosixPath(name).parents), 'file/parent member conflict')
    return result


def require_zero_padding(path, member):
    padding = (-member.size) % tarfile.BLOCKSIZE
    with path.open('rb') as source:
        source.seek(member.offset_data+member.size)
        data = source.read(padding)
    require(len(data) == padding and not any(data), 'nonzero or truncated member padding')


def verify_archive(archive, expected):
    require(digest(archive) == expected['archive_sha256'] and archive.stat().st_size == expected['bytes'], 'compressed archive identity differs')
    with tempfile.TemporaryDirectory(prefix='boyer-archive-verify-') as temporary:
        tar = Path(temporary)/'archive.tar'
        decompress(archive, tar)
        actual = tar_inventory(tar)
    require(actual == expected['files'] and len(actual) == expected['regular_files'], 'full member inventory differs')
    require(sum(row['bytes'] for row in actual.values()) == expected['uncompressed_file_bytes'], 'file byte total differs')
    return dict(complete=True, archive_sha256=expected['archive_sha256'], regular_files=len(actual),
        manifest_sha256=hashlib.sha256((json.dumps(expected, indent=2, allow_nan=False)+'\n').encode()).hexdigest(),
        scope='Compressed identity, complete single-stream decompression, safe exact regular-file inventory and member byte/mode integrity. No semantic replay or guest execution.')


# ---- Exclusive publication leaves preexisting or partial evidence untouched ----

def publish(directory):
    created = []
    try:
        for name in PUBLISHED:
            destination = REPORT/name
            target = destination.open('xb')
            created.append(destination)
            with target, (directory/name).open('rb') as source:
                shutil.copyfileobj(source, target)
                target.flush()
                os.fsync(target.fileno())
            require(digest(destination) == digest(directory/name), 'published bytes differ: ' + name)
        sync_report_directory()
    except BaseException:
        for path in reversed(created):
            path.unlink()
        sync_report_directory()
        raise


def sync_report_directory():
    descriptor = os.open(REPORT, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def prepare():
    require(not any((REPORT/name).exists() for name in PUBLISHED), 'refusing to replace existing or partial published evidence')
    with tempfile.TemporaryDirectory(prefix='boyer-evidence-') as temporary:
        directory = Path(temporary)
        selected = evidence_files()
        files = private_copy(selected, directory)
        require(selected == evidence_files(), 'selected evidence inventory changed during copy')
        check_snapshot(files)
        archive = directory/'artifacts.tar.xz'
        archive_files(archive, files)
        expected = inventory(archive, files)
        checked = verify_archive(archive, expected)
        save(directory/'manifest.json', expected)
        save(directory/'archive-verification.json', checked)
        publish(directory)


def verify():
    checked = verify_archive(REPORT/'artifacts.tar.xz', read(REPORT/'manifest.json'))
    require(checked == read(REPORT/'archive-verification.json'), 'published verification differs')
    print('PASS compressed bytes, complete decompression and', checked['regular_files'], 'safe regular-file identities; no guest started')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_mutually_exclusive_group()
    actions.add_argument('--prepare', action='store_true')
    actions.add_argument('--self-test', action='store_true')
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return
    if arguments.prepare:
        prepare()
    verify()


# ---- Tests ----

def self_test():
    directory = ROOT/'build/boyer-archive-tests-a707974'
    directory.mkdir(exist_ok=False)
    source = directory/'source'
    source.write_bytes(b'exact\x00bytes\xff\n')
    files = {'evidence/source.bin':source}
    archive = directory/'test.tar.xz'
    archive_files(archive,files)
    expected = inventory(archive,files)
    require(verify_archive(archive,expected)['complete'],'valid archive rejected')
    test_rejections(directory,archive,expected)
    save(directory/'summary.json',dict(passed=True,retained_inputs=True,checks=['valid binary archive','changed identity rejection','trailing compressed payload rejection','unsafe name rejection','file/parent conflict rejection','nonzero member padding rejection']))
    print('PASS binary archive, changed identity, trailing payload, unsafe names, conflicts and padding; synthetic inputs retained')


def must_reject(operation):
    try:
        operation()
    except (ValueError, lzma.LZMAError):
        return
    raise AssertionError('invalid archive accepted')


def test_rejections(directory, archive, expected):
    changed = dict(expected, archive_sha256='0'*64)
    must_reject(lambda: verify_archive(archive, changed))
    trailing = directory/'trailing.tar.xz'
    trailing.write_bytes(archive.read_bytes()+b'junk')
    must_reject(lambda: decompress(trailing, directory/'trailing.tar'))
    unsafe = tarfile.TarInfo('../escape')
    require(not safe_member(unsafe), 'unsafe parent traversal accepted')
    conflict = directory/'conflict.tar.xz'
    source = directory/'source'
    archive_files(conflict, {'a': source, 'a/b': source})
    must_reject(lambda: verify_archive(conflict, inventory(conflict, {'a': source, 'a/b': source})))
    test_member_padding(directory, archive)


def test_member_padding(directory, archive):
    data = bytearray(lzma.decompress(archive.read_bytes()))
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:') as source:
        member, = source.getmembers()
    data[member.offset_data+member.size] = 1
    damaged = directory/'member-padding.tar'
    damaged.write_bytes(data)
    must_reject(lambda: tar_inventory(damaged))


if __name__ == '__main__':
    main()
