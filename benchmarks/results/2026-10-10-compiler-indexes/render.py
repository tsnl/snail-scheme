"""Render the saved compiler comparison without executing compilers."""

import json
import sys
from pathlib import Path

DIRECTORY = Path(__file__).resolve().parent
sys.path.insert(0, str(DIRECTORY.parents[1]))
from plots import GRAY, ORANGE, duration_chart

report = json.loads((DIRECTORY / "results.json").read_text())
assert report["complete"] and all(
    case["status"] == "passed" for case in report["cases"]
)
labels = {"chibi": "Chibi", "snail-wasm": "Wasm / V8", "snail-native": "Native"}
series = []
for case in report["cases"]:
    system, version = case["system"].rsplit("-", 1)
    series.append(
        {
            "label": labels[system]
            + "\n"
            + ("indexed" if version == "after" else "before"),
            "seconds": [sample["seconds"] for sample in case["samples"]],
            "color": ORANGE if version == "after" else GRAY,
        }
    )
duration_chart(
    series,
    DIRECTORY / "comparison",
    title="Indexing compiler evidence",
    subtitle="Same frozen compiler input → byte-identical WAT",
    notes=[
        "3 rotating measured rounds on CPU 2; bars show medians, whiskers the observed range.",
        "Includes compilation, tracing and writing; excludes process startup, assembly and linking.",
    ],
)
