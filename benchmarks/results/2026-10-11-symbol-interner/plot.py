#!/usr/bin/env python3
"""Render the checked compiler and complete-program comparisons."""

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[2] / "benchmarks"))
from plots import GRAY, ORANGE, duration_chart


def compiler_chart():
    report = json.loads((HERE / "compiler.json").read_text())
    assert report["complete"] and all(case["status"] == "passed" for case in report["cases"])
    labels = {"chibi-after": "Chibi", "snail-native-before": "Native\noriginal heap",
              "snail-native-before-4gib": "Native\n4 GiB only", "snail-native-after": "Native\nRust interner",
              "snail-wasm-before": "Wasm\nlinear interner", "snail-wasm-after": "Wasm\nRust interner"}
    series = [{"label": labels[case["system"]], "seconds": [item["seconds"] for item in case["samples"]],
               "color": ORANGE if case["system"] in ("snail-native-after", "snail-wasm-after") else GRAY}
              for case in report["cases"] if case["system"] in labels]
    duration_chart(series, HERE / "compiler", title="Compiling the compiler",
                   subtitle="One frozen input → WAT · native interner comparison uses matching 4 GiB heaps",
                   notes=["3 rotating measured runs after one discarded run · bars show medians; whiskers show ranges",
                          "Outputs match each implementation’s validated Chibi reference. Startup and linking excluded."])


def runtime_charts():
    report = json.loads((HERE / "schemes.json").read_text())
    assert report["complete"]
    labels = {"snail-wasm-untyped": "Wasm\nuntyped", "snail-native-untyped": "Native\nuntyped",
              "snail-wasm-i32": "Wasm\ni32", "snail-native-i32": "Native\ni32",
              "chez-safe-O2": "Chez\nsafe O2", "chibi": "Chibi"}
    for workload in report["workloads"]:
        series = [{"label": labels[name], "seconds": variant["seconds"],
                   "color": ORANGE if name.startswith("snail") else GRAY}
                  for name, variant in workload["variants"].items()]
        duration_chart(series, HERE / workload["workload"], title=workload["workload"].replace("-", " ").title(),
                       subtitle="Complete Scheme workload · compilation and process startup excluded",
                       notes=["8 rotating measured runs after one discarded run · every checksum verified",
                              "Native uses the 4 GiB minimum heap. Tail Fibonacci has an equally sized in-process warmup."])


if __name__ == "__main__":
    compiler_chart()
    runtime_charts()
    for name in ("compiler", "fibonacci", "tail-fibonacci"):
        path = HERE / (name + ".svg")
        path.write_text("\n".join(line.rstrip() for line in path.read_text().splitlines()) + "\n")
