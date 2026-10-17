#!/usr/bin/env chibi-scheme
(import (scheme base) (scheme process-context) (lofi runner) (wasm-native process))
(command-line-main runner-main)
