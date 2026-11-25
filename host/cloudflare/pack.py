"""Publish a Pages directory with a 25 MB upper bound on every physical file."""
import hashlib
import json
import mimetypes
from pathlib import Path
import re
import shutil
import sys
import tempfile
from urllib.parse import quote


PART_SIZE = 25_000_000
STORED_PART = re.compile(r"(.*)/store/chunks/([0-9a-f]{2})/([0-9a-f]{64})/(0|[1-9][0-9]*)")
RESERVED = {"_worker.js", "_routes.json", "_snail_parts"}


def split_file(path, site, size):
    parent = site / "_snail_parts"
    parent.mkdir(exist_ok=True)
    sha, written = hashlib.sha256(), 0
    with tempfile.TemporaryDirectory(dir=parent) as tmp, path.open("rb") as source:
        parts = Path(tmp) / "parts"
        parts.mkdir()
        for i, part in enumerate(iter(lambda: source.read(PART_SIZE), b"")):
            (parts / str(i)).write_bytes(part)
            sha.update(part)
            written += len(part)
        if written != size:
            raise ValueError(f"input changed while packing {path}")
        digest = sha.hexdigest()
        if not (parent / digest).exists():
            parts.rename(parent / digest)
    mime, encoding = mimetypes.guess_type(path.name)
    if encoding:
        mime = {"gzip": "application/gzip", "bzip2": "application/x-bzip2"}.get(encoding)
    return [size, digest, "/_snail_parts/" + digest, mime or "application/octet-stream"]


def stored_routes(groups, site):
    for prefix, lengths in groups.items():
        total = sum(lengths.values())
        expected = {i: min(PART_SIZE, total - offset) for i, offset in enumerate(range(0, total, PART_SIZE))}
        if total <= PART_SIZE or expected != lengths:
            raise ValueError(f"incomplete multipart resource at {prefix}")
        store, key = prefix.rsplit("/store/chunks/", 1)
        digest = key.split("/")[1]
        sha = hashlib.sha256()
        for index in range(len(lengths)):
            sha.update((site / prefix[1:] / str(index)).read_bytes())
        if sha.hexdigest() != digest:
            raise ValueError(f"multipart resource does not match its SHA-256: {prefix}")
        yield store + "/store/sha256/" + key, [total, digest, quote(prefix), "application/octet-stream"]


def publish_assets(source, site):
    routes, groups = {}, {}
    for path in sorted(source.rglob("*")):
        if not path.is_file() or path.name in {".snail-target", ".snail-publish"}:
            continue
        relative = path.relative_to(source)
        if relative.parts[0] in RESERVED:
            raise ValueError(f"reserved Pages output path: {relative}")
        url = "/" + relative.as_posix()
        size = path.stat().st_size
        match = STORED_PART.fullmatch(url)
        if match and match[2] == match[3][:2]:
            groups.setdefault(url.rsplit("/", 1)[0], {})[int(match[4])] = size
        elif size > PART_SIZE:
            routes[url] = split_file(path, site, size)
            continue
        dest = site / relative
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, dest)
    for url, blob in stored_routes(groups, site):
        if url in routes or (site / url[1:]).exists():
            raise ValueError(f"conflicting resource layouts at {url}")
        routes[url] = blob
    return routes


def publish_worker(site, routes):
    worker = Path(__file__).with_name("blobs.mjs").read_text()
    table = json.dumps(sorted(routes.items()), separators=(",", ":"))
    (site / "_worker.js").write_text(f"const partSize = {PART_SIZE};\nconst blobs = new Map({table});\n" + worker)
    paths = [quote(url) for url in routes]
    include = paths if len(paths) <= 100 and all(len(p) <= 100 and "%" not in p for p in paths) else ["/*"]
    (site / "_routes.json").write_text(json.dumps({"version": 1, "include": include, "exclude": []}))


def pack(source, dest):
    # Build from fresh input. A failed validation leaves the last complete release available.
    with tempfile.TemporaryDirectory(dir=dest.parent, prefix="pages-pack-") as tmp:
        site, previous = Path(tmp) / "new", Path(tmp) / "previous"
        site.mkdir()
        routes = publish_assets(source, site)
        if routes:
            publish_worker(site, routes)
        for path in site.rglob("*"):
            if path.is_file() and path.stat().st_size > PART_SIZE:
                raise ValueError(f"publication exceeds {PART_SIZE} bytes: {path}")
        if dest.exists():
            dest.rename(previous)
        try:
            site.rename(dest)
        except OSError:
            if previous.exists():
                previous.rename(dest)
            raise


if __name__ == "__main__":
    pack(Path(sys.argv[1]), Path(sys.argv[2]))
