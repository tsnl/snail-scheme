#!/usr/bin/env python3
"""Record the explicitly owned test host, then execute the real compiler."""

import json
import os
from pathlib import Path
import sys

if sys.argv[1] != '-q':
    Path(os.environ['SFIR_SERVICE_TEST_HOST']).write_text(
        json.dumps({'pid': os.getpid(), 'directory': sys.argv[-1]}))
chibi = os.environ.get('CHIBI', 'chibi-scheme')
os.execvp(chibi, [chibi, *sys.argv[1:]])
