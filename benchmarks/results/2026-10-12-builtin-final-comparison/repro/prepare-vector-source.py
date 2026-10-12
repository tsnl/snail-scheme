#!/usr/bin/env python3
"""Materialize portable-reference and public-builtin sources without compiling."""

import hashlib
import json
from pathlib import Path


# ---- Explicit implementation adapters ----


def main():
    directory = Path(__file__).resolve().parent
    template = directory / "vector-append-workload.scm.in"
    original = template.read_text()
    manifest = {"template_sha256": hashlib.sha256(template.read_bytes()).hexdigest(), "variants": {}}
    for label, target in (("reference", "reference-vector-append"), ("public", "vector-append")):
        output = directory / ("vector-append-" + label + ".scm")
        output.write_text(original.replace("@@TARGET@@", target))
        manifest["variants"][label] = {"target": target, "path": str(output),
                                        "sha256": hashlib.sha256(output.read_bytes()).hexdigest()}
    (directory / "vector-source-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
