#!/usr/bin/env python3
"""Render the Scheme studio scene and convert its pixels to a PNG preview."""

import argparse
import os
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


# ---- Build and render ----


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--system", choices=["chez", "guile", "chibi"], default="chez")
    parser.add_argument("--width", type=int, default=800)
    parser.add_argument(
        "--samples", type=int, default=2, help="sample grid per pixel: 2 means 4 rays"
    )
    parser.add_argument("--output", type=Path, default=ROOT / "build/studio")
    args = parser.parse_args()
    if args.width < 5 or args.samples < 1:
        parser.error("width must be >= 5 and samples >= 1")
    return args


def main():
    from PIL import Image

    args = arguments()
    args.output.mkdir(parents=True, exist_ok=True)
    source = ROOT / "benchmarks/studio.scm"
    command = prepare(args.system, source, args.output.resolve())
    ppm = args.output.resolve() / "studio.ppm"
    ppm.unlink(missing_ok=True)
    started = time.perf_counter()
    subprocess.run([*command, str(ppm), str(args.width), str(args.samples)], check=True)
    elapsed = time.perf_counter() - started
    with Image.open(ppm) as image:
        image.save(args.output / "studio.png")
    print(
        f"{args.system}: {elapsed:.3f} s (process startup and PPM output included; build/PNG excluded)"
    )
    print(args.output / "studio.png")


def prepare(system, source, output):
    if system == "chez":
        program = output / "studio.scm"
        body = "\n".join(
            line for line in source.read_text().splitlines() if not line.startswith("(import ")
        )
        program.write_text(
            "(import (chezscheme))\n(define (exact-integer? x) (and (integer? x) (exact? x)))\n"
            + body
        )
        compiler = output / "compile.scm"
        compiler.write_text(
            '(import (chezscheme))\n(parameterize ((optimize-level 2)) (compile-program "studio.scm" "studio.so"))\n'
        )
        chez = os.environ.get("CHEZ", "scheme")
        subprocess.run([chez, "--script", str(compiler)], cwd=output, check=True)
        return [chez, "--program", str(output / "studio.so")]
    binary = os.environ.get(system.upper(), "guile" if system == "guile" else "chibi-scheme")
    return [shutil.which(binary) or binary, *(["--r7rs"] if system == "guile" else []), str(source)]


if __name__ == "__main__":
    main()
