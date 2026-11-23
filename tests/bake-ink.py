"""Authoring checks against a locally installed reference inklecate."""
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory

root = Path(__file__).resolve().parents[1]
bake = root / "scripts/bake-ink"
source = root / "src/apps/last-mile/rosa.ink"
output = root / "src/apps/last-mile/lines.sld"


def run(*args):
    return subprocess.run([sys.executable, bake, *args], capture_output=True, text=True)


# Exercise the compiler, its JSON play protocol, the Scheme emitter and the
# canonical formatter without modifying the committed conversation.
checked = run("--check", source, output)
if checked.returncode:
    sys.exit(checked.stderr)

with TemporaryDirectory() as scratch:
    ink = Path(scratch) / "sample.ink"

    def refused(text, reason, *options):
        ink.write_text(text)
        result = run("--check", *options, ink, output)
        if result.returncode == 0 or reason not in result.stderr:
            raise AssertionError(f"expected {reason!r}, got {result.stderr!r}")

    refused("Roll {RANDOM(1, 20)}\n-> END\n", "random output")
    refused("EXTERNAL cue()\n{cue()}\n-> END\n", "EXTERNAL cue")
    refused("-> again\n=== again ===\nWait? # id:again\n+ [Repeat] -> again\n", "cyclic passage")
    refused("Wait?\n+ [Yes] -> END\n+ [No] -> END\n", "exceeds 2 turns", "--max-turns", "2")
    refused("Changed text.\n-> END\n", "is stale")

print("Ink source matches its Snail dialogue. Unsupported stories and stale output were rejected.")
