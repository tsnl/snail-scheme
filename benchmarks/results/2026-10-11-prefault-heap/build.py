"""Build heap-preparation controls without changing frozen generated code."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path.cwd()
BUILD = ROOT / 'build/prefault-heap'
FROZEN = Path('/tmp/snail-native-ablation-20261011/build/ablation')
PRECISE = Path('/tmp/snail-precise-gc-20261011/build/precise-gc')
records = []
for workload in ('tail', 'compiler'):
    for variant in os.environ.get('PREF_BUILD_VARIANTS', 'bdw,bump,precise').split(','):
        llvm = (PRECISE if variant == 'precise' else FROZEN) / f'{workload}.ll'
        source = ROOT / 'src/native.c' if variant == 'precise' else BUILD / ('bdw-prefault.c' if variant == 'bdw' else 'native-bump.c')
        flags = ['-lm', '-ldl', '-lpthread']
        if variant == 'bdw':
            flags += ['-I', os.environ['BDWGC_INCLUDE'], '-L', os.environ['BDWGC_LIB'], '-Wl,-rpath,' + os.environ['BDWGC_LIB'], '-lgc']
        if variant == 'precise':
            flags += ['-DSNAIL_PRECISE_GC', '-I', str(ROOT / 'src'), str(BUILD / 'precise-300.c')]
        binary = BUILD / f'{workload}-{variant}'
        command = ['clang', '-O3', '-flto', '-fuse-ld=lld', str(llvm), str(source), str(FROZEN / 'runtime.a'), *flags, '-o', str(binary)]
        result = subprocess.run(command, check=True, text=True, capture_output=True)
        records.append(dict(command=command, stderr=result.stderr, llvm_sha256=hashlib.sha256(llvm.read_bytes()).hexdigest(), binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest()))
        (BUILD / 'builds.json').write_text(json.dumps(records, indent=2) + '\n')
        print(workload, variant, 'built', flush=True)
