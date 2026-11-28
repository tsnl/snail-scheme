"""Publish a Pages directory using the Snail compiler's object store."""
import hashlib
import json
import mimetypes
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import quote


STORED_PART = re.compile(r"(.*)/store/chunks/(\d+)/([0-9a-f]{2})/([0-9a-f]{64})/(0|[1-9][0-9]*)")
RESERVED = {"_worker.js", "_routes.json", "_snail_parts"}


def store_assets(site, paths):
    root = Path(__file__).resolve().parents[2]
    process = subprocess.run([root / "snail-scheme", "run", "--target", "node", "tools/store-blobs.scm",
                              (site / "_snail_parts").resolve()], cwd=root, input=json.dumps(paths) + "\n",
                             capture_output=True, text=True)
    if process.returncode:
        raise ValueError(process.stderr.strip())
    return json.loads(process.stdout)


def content_type(path):
    mime, encoding = mimetypes.guess_type(path.name)
    if encoding:
        mime = {"gzip": "application/gzip", "bzip2": "application/x-bzip2"}.get(encoding)
    return mime or "application/octet-stream"


def stored_routes(groups, site):
    for (prefix, width, url, digest), lengths in groups.items():
        total = sum(lengths.values())
        expected = {i: min(width, total - offset) for i, offset in enumerate(range(0, total, width))}
        if total <= width or expected != lengths:
            raise ValueError(f"incomplete multipart resource at {prefix}")
        sha = hashlib.sha256()
        for index in range(len(lengths)):
            sha.update((site / prefix[1:] / str(index)).read_bytes())
        if sha.hexdigest() != digest:
            raise ValueError(f"multipart resource does not match its SHA-256: {prefix}")
        yield url, [total, digest, quote(prefix), "application/octet-stream", width]


def publish_assets(source, site):
    source = source.resolve()
    files = [p for p in sorted(source.rglob("*")) if p.is_file() and p.name not in {".snail-target", ".snail-publish"}]
    for path in files:
        if path.relative_to(source).parts[0] in RESERVED:
            raise ValueError(f"reserved Pages output path: {path.relative_to(source)}")
    addresses = {path: "/" + path.relative_to(source).as_posix() for path in files}
    parts = {p: m for p, url in addresses.items() if (m := STORED_PART.fullmatch(url)) and m[3] == m[4][:2]}
    layout = store_assets(site, [str(p) for p in files if p not in parts])
    width = layout["partSize"]
    routes, groups = {}, {}
    for file in layout["files"]:
        path = Path(file["path"])
        routes[addresses[path]] = [file["size"], file["sha256"], "/_snail_parts/" + file["directory"], content_type(path), width]
    for path, url in addresses.items():
        if url in routes:
            continue
        if path in parts:
            store, tag, shard, digest, index = parts[path].groups()
            if tag != str(width):
                raise ValueError(f"unknown blob layout at {url}")
            key = (url.rsplit("/", 1)[0], width, f"{store}/store/sha256/{shard}/{digest}", digest)
            groups.setdefault(key, {})[int(index)] = path.stat().st_size
        dest = site / path.relative_to(source)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, dest)
    for url, blob in stored_routes(groups, site):
        raw = site / url[1:]
        if raw.exists():
            if raw.stat().st_size != blob[0] or hashlib.sha256(raw.read_bytes()).hexdigest() != blob[1]:
                raise ValueError(f"conflicting resource layouts at {url}")
        else:
            routes[url] = blob
    return width, routes


def publish_worker(site, routes):
    worker = Path(__file__).with_name("blobs.mjs").read_text()
    table = json.dumps(sorted(routes.items()), separators=(",", ":"))
    (site / "_worker.js").write_text(f"const blobs = new Map({table});\n" + worker)
    paths = [quote(url) for url in routes]
    include = paths if len(paths) <= 100 and all(len(p) <= 100 and "%" not in p for p in paths) else ["/*"]
    (site / "_routes.json").write_text(json.dumps({"version": 1, "include": include, "exclude": []}))


def pack(source, dest):
    # Build from fresh input. A failed validation leaves the last complete release available.
    with tempfile.TemporaryDirectory(dir=dest.parent, prefix="pages-pack-") as tmp:
        site, previous = Path(tmp) / "new", Path(tmp) / "previous"
        site.mkdir()
        limit, routes = publish_assets(source, site)
        if routes:
            publish_worker(site, routes)
        for path in site.rglob("*"):
            if path.is_file() and path.stat().st_size > limit:
                raise ValueError(f"publication exceeds {limit} bytes: {path}")
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
