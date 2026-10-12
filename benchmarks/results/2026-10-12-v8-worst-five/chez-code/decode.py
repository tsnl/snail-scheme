"""Decode two captured Chez code objects, excluding inline return metadata."""

import hashlib
import json
from pathlib import Path
import re
import subprocess

directory = Path(__file__).resolve().parent
objdump = "/nix/store/w88q44gqd1qg5wmkk7v0h97rpiqvam0l-gcc-wrapper-15.3.0/bin/objdump"
scheme = "/nix/store/bzqpmy5kmvf0xn4xh5ixzkw00w9srh07-chez-scheme-10.4.1/bin/scheme"
capture_command = ["taskset", "-c", "4", scheme, "--quiet", "--optimize-level", "2",
                   "--script", "audit/chez/capture.ss"]
records = []

for name in ("copy-characters", "invoke-callback"):
    binary = directory / f"{name}.bin"
    compiler = (directory / f"{name}.compiler.asm").read_text()
    length = len(binary.read_bytes())
    declared_end = re.search(rf"(\d+):\s+<end {name}>", compiler)
    assert declared_end and int(declared_end[1]) == length
    data_ranges = [(int(offset), int(offset) + 16)
                   for offset in re.findall(r"^(\d+):\s+code-top-link", compiler, re.M)]
    cursor, segments = 0, []
    for start, end in data_ranges:
        segments.append((cursor, start))
        cursor = end
    segments.append((cursor, length))
    decoded, commands = [], []
    for start, end in segments:
        command = [objdump, "-D", "-b", "binary", "-m", "i386:x86-64",
                   f"--start-address={start}", f"--stop-address={end}", str(binary)]
        commands.append(command)
        decoded.append(f"# Executable byte range [{start}, {end})\n")
        decoded.append(subprocess.run(command, capture_output=True, text=True, check=True).stdout)
    (directory / f"{name}.code.disassembly").write_text("\n".join(decoded))
    records.append({"name": name, "code_bytes": length, "excluded_inline_metadata": data_ranges,
                    "executable_segments": segments, "decode_commands": commands})

metadata = {
    "scope": "Two representative procedures; no full benchmark binary or performance attribution.",
    "working_directory": str(directory.parents[1]),
    "snail_revision": "648e9aef31c939c64fbb87b1c0fd9f53f29aae9a",
    "chez_version": "10.4.1", "machine_type": "ta6le", "optimize_level": 2,
    "unsafe_application": False, "unsafe_variable_reference": False, "interrupt_traps": True,
    "capture_command": capture_command,
    "capture_stdout_redirect": "audit/chez/capture.stdout",
    "capture_stderr_redirect": "audit/chez/capture.stderr",
    "upstream_layout": "https://github.com/cisco/ChezScheme/blob/v10.4.1/s/cmacros.ss#L1551",
    "upstream_revision": "e95a7efbafa2cf3bd5343ea542e6bc909a7ab2c4",
    "code_layout": {"length_displacement": 9, "data_displacement": 65,
                    "header_displacement": 1, "header_mask": 255, "header_tag": 190},
    "relocation_note": "Binary bytes are copied after Chez linking; absolute targets vary by process.",
    "raw_decode_note": "Plain objdump treats embedded code-top-link and return metadata as instructions.",
    "examples": records,
    "objdump_version": subprocess.run([objdump, "--version"], capture_output=True, text=True,
                                      check=True).stdout.splitlines()[0],
    "sha256": {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
               for path in sorted(directory.iterdir()) if path.is_file() and path.name != "metadata.json"},
}
(directory / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
