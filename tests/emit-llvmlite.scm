(import (scheme base) (snail-scheme test-llvmlite)
        (prefix (snail-scheme llvmlite) ir:))
(ir:write-module (llvmlite-fixture) (current-output-port))
