#!/usr/bin/env python3
"""Package the saved bigint loop ablation, or verify its archive read-only."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
import tarfile
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import review

REPORT = Path(__file__).resolve().parent


# ---- Concrete timing, correctness, sampling and code evidence ----

def evidence_files(campaign, preparation, diagnostics, profiles, code):
    files = {}
    roots = dict(campaign=campaign, preparation=preparation, diagnostics=diagnostics, profiles=profiles, code=code)
    for prefix, directory in roots.items():
        for path in directory.rglob('*'):
            if path.is_file() and '__pycache__' not in path.parts:
                files[prefix + '/' + str(path.relative_to(directory))] = path
    plan = review.read(preparation / 'timing-plan.json')
    driver = next(Path(path) for path in plan['identities']
                  if path.endswith('/2026-10-14-strict-integer-measurement-preparation/measure.py'))
    files['preparation/integer-measure.py'] = driver
    for name in ('data_ports.py', 'matrix_port.py'):
        files['preparation/supervisor/' + name] = Path(plan['supervisor']) / name
    files['preparation/integer.sld'] = preparation.parents[1] / 'src/snail/integer.sld'
    files['preparation/integer-control-host.mjs'] = Path(plan['systems']['pi']['original']['command'][1])
    for name in review.WORKLOADS:
        files['preparation/specifications/' + name + '/full.json'] = Path(plan['systems'][name]['original']['command'][3])
    for path in preparation.with_name('tail-backedge').rglob('*'):
        if path.is_file() and path.suffix in ('.py', '.json') and '__pycache__' not in path.parts:
            files['lineage/' + str(path.relative_to(preparation.with_name('tail-backedge')))] = path
    files['code/capture-bigint-loops.py'] = preparation.parent / 'capture-bigint-loops.py'
    for path in (REPORT / 'original-code').iterdir():
        files['code/original/' + path.name] = path
    for name in ('README.md', 'review.py', 'package.py', 'independent-review.json', 'coordination.json'):
        files['comparison/' + name] = REPORT / name
    return dict(sorted(files.items()))


def stage_evidence(files, directory):
    staged = {}
    for name, source in files.items():
        target = directory / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        staged[name] = target
    return staged


def audit_snapshot(directory):
    return review.review(directory / 'campaign', directory / 'preparation', directory / 'diagnostics',
                         directory / 'profiles', directory / 'code', True)


def control_archives():
    directory = REPORT.parent / '2026-10-14-strict-integer-controls'
    manifest = review.read(directory / 'manifest.json')
    names = ('pi.tar.gz', 'chudnovsky.tar.gz', 'preparation.tar.gz')
    for name in names:
        expected = manifest['archives'][name]
        review.require(review.digest(directory / name) == expected['sha256']
                       and (directory / name).stat().st_size == expected['bytes'], 'existing control archive differs')
    verify_original_excerpts(directory)
    return {name: manifest['archives'][name] for name in names}


def verify_original_excerpts(controls):
    for name, identity in review.read(REPORT / 'original-code/sources.json').items():
        with tarfile.open(controls / identity['control_archive'], 'r:gz') as archive:
            source = archive.extractfile(identity['control_archive_member']).read()
        review.require(hashlib.sha256(source).hexdigest() == identity['source_sha256'], 'original full code source differs')
        blocks = re.findall(r'--- WebAssembly code ---\n(.*?)--- End code ---', source.decode(), re.S)
        selected = [body.rstrip() + '\n' for body in blocks
                    if body.startswith('name: function85\n') and '\ncompiler: TurboFan\n' in body]
        review.require(selected == [(REPORT / 'original-code' / identity['excerpt']).read_text()],
                       'original function excerpt differs from the existing control archive')


def write_archive(files, archive):
    with tarfile.open(archive, 'w:xz', preset=6) as target:
        for name, path in files.items():
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = path.stat().st_size, 0o644, 0
            with path.open('rb') as source:
                target.addfile(info, source)
    return archive


def prepare(options):
    review.require(not (REPORT / 'artifacts.tar.xz').exists(), 'refusing to replace a recorded archive')
    controls = control_archives()
    selected = evidence_files(options.campaign, options.preparation, options.diagnostics, options.profiles, options.code)
    with tempfile.TemporaryDirectory(prefix='bigint-loop-audit-') as temporary:
        directory = Path(temporary)
        files = stage_evidence(selected, directory)
        checked = audit_snapshot(directory)
        payload = json.dumps(checked, indent=2) + '\n'
        files['comparison/independent-review.json'].write_text(payload)
        archive = write_archive(files, directory / 'artifacts.tar.xz')
        manifest = archive_manifest(files, archive, controls)
        publish_snapshot(archive, manifest, payload)


def archive_manifest(files, archive, controls):
    manifest = dict(archive_sha256=review.digest(archive), bytes=archive.stat().st_size,
        regular_members=len(files), uncompressed_bytes=sum(path.stat().st_size for path in files.values()),
        files={name: review.digest(path) for name, path in files.items()},
        executable_controls='../2026-10-14-strict-integer-controls/', executable_control_archives=controls)
    return manifest


def publish_snapshot(archive, manifest, review_payload):
    destination = REPORT / 'artifacts.tar.xz'
    # Exclusive creation preserves any existing report; only our new archive
    # is removed if copying or publishing its companion records fails.
    target = destination.open('xb')
    try:
        with target, archive.open('rb') as source:
            shutil.copyfileobj(source, target)
        (REPORT / 'independent-review.json').write_text(review_payload)
        (REPORT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    except BaseException:
        destination.unlink()
        raise


# ---- Exact safe regular-member inventory; no extraction or execution ----

def safe_member(member):
    path = PurePosixPath(member.name)
    return (member.isfile() and not path.is_absolute() and str(path) == member.name
            and '..' not in path.parts and '\\' not in member.name and ':' not in member.name)


def verify():
    manifest, archive = review.read(REPORT / 'manifest.json'), REPORT / 'artifacts.tar.xz'
    review.require(review.digest(archive) == manifest['archive_sha256']
                   and archive.stat().st_size == manifest['bytes'], 'archive identity differs')
    observed, size = {}, 0
    with tarfile.open(archive, 'r:xz') as source:
        for member in source:
            review.require(safe_member(member) and member.name not in observed, 'invalid archive member')
            with source.extractfile(member) as contents:
                observed[member.name] = hashlib.file_digest(contents, 'sha256').hexdigest()
            size += member.size
    review.require(observed == manifest['files'] and len(observed) == manifest['regular_members']
                   and size == manifest['uncompressed_bytes'], 'archive members differ')
    print(f'Verified {len(observed)} safe regular members; no guests started')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare', action='store_true')
    for name in ('campaign', 'preparation', 'diagnostics', 'profiles', 'code'):
        parser.add_argument('--' + name, type=Path)
    options = parser.parse_args()
    if options.prepare:
        if any(getattr(options, name) is None for name in ('campaign', 'preparation', 'diagnostics', 'profiles', 'code')):
            parser.error('--prepare requires --campaign, --preparation, --diagnostics, --profiles and --code')
        prepare(options)
    verify()


if __name__ == '__main__':
    main()
