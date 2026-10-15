#!/usr/bin/env python3
"""Owned host fixtures for startup, streaming deadlines and group cleanup."""

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

signal.signal(signal.SIGTERM, signal.SIG_IGN)
child = subprocess.Popen([sys.executable, '-c',
                          'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); '
                          'print("ready", flush=True); time.sleep(600)'], stdout=subprocess.PIPE)
assert child.stdout.readline() == b'ready\n'
directory = Path(sys.argv[-1])
Path(os.environ['SFIR_SERVICE_TEST_HOST']).write_text(json.dumps(
    {'pid': os.getpid(), 'descendant': child.pid, 'directory': str(directory)}))
mode = os.environ['SFIR_SERVICE_TEST_MODE']
response = os.open(directory / 'responses', os.O_WRONLY)
print('owned host diagnostic sentinel', file=sys.stderr, flush=True)
if mode.endswith('request') or mode == 'ignore-close':
    os.write(response, b'[true,"ready"]\n')
    with (directory / 'requests').open() as requests:
        requests.readline()
if mode.startswith('noisy'):
    while True:
        os.write(response, b' ' * 65536)
while True:
    time.sleep(600)
