"""Archive or hash-verify the rejected String experiment without workload runs."""

import argparse
import hashlib
import json
from pathlib import Path
import tarfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PREPARATION = Path('/tmp/snail-string-hybrid-preparation-20261014')


# ---- Preserve exact artifacts, observations and partial checks ----


def digest(data):
    return hashlib.sha256(data).hexdigest()


def inputs():
    excluded = {'artifacts.tar.xz', 'manifest.json', 'archive-verification.json'}
    groups = [('preparation', PREPARATION), ('evidence', HERE),
              ('checks/focused', ROOT / 'build/strict-contracts'),
              ('checks/incomplete', ROOT / 'build/strict-all-contracts')]
    result = [(prefix + '/' + str(path.relative_to(root)), path)
              for prefix, root in groups for path in sorted(root.rglob('*'))
              if path.is_file() and not (root == HERE and path.name in excluded)]
    result.append(('checks/incomplete.log', ROOT / 'build/strict-all-contracts.log'))
    names = {path.name.removesuffix('-compile.json') for _, path in result if path.name.endswith('-compile.json')}
    result += [('checks/fixtures/' + name + '.scm', ROOT / 'tests/strict' / (name + '.scm')) for name in sorted(names)]
    result += [('checks/cases.json', ROOT / 'tests/strict/cases.json'), ('checks/test-strict.py', ROOT / 'scripts/test-strict')]
    return result


def create():
    files = inputs()
    manifest = {name: dict(sha256=digest(path.read_bytes()), size=path.stat().st_size, source=str(path))
                for name, path in files}
    with tarfile.open(HERE / 'artifacts.tar.xz', 'w:xz', preset=6) as archive:
        for name, path in files:
            archive.add(path, arcname=name, recursive=False)
    report = dict(source_commit='3370a372c96635dc2888dcc38804799c4c2dcbea', files=manifest,
                  archive_sha256=digest((HERE / 'artifacts.tar.xz').read_bytes()))
    (HERE / 'manifest.json').write_text(json.dumps(report, indent=2) + '\n')


# ---- Verify all archive bytes without extracting or executing them ----


def verify():
    manifest = json.loads((HERE / 'manifest.json').read_text())
    assert digest((HERE / 'artifacts.tar.xz').read_bytes()) == manifest['archive_sha256']
    with tarfile.open(HERE / 'artifacts.tar.xz', 'r:xz') as archive:
        members = {member.name: member for member in archive.getmembers() if member.isfile()}
        assert members.keys() == manifest['files'].keys()
        for name, expected in manifest['files'].items():
            data = archive.extractfile(members[name]).read()
            assert len(data) == expected['size'] and digest(data) == expected['sha256'], name
    (HERE / 'archive-verification.json').write_text(json.dumps(dict(verified=True,
        files=len(members), archive_sha256=manifest['archive_sha256'], workload_executed=False), indent=2) + '\n')
    print(json.dumps(dict(verified=True, files=len(members), workload_executed=False)))


# ---- Explicit archive operation ----

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--verify', action='store_true')
args = parser.parse_args()
if not args.verify:
    create()
verify()
