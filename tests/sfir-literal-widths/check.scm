;; Run from the repository root with chibi-scheme -I src -I tests.
(import (scheme base) (scheme process-context) (chibi filesystem)
        (snail-tests harness) (snail-tests contracts))
(initialize-suite! (current-directory) (cdr (command-line)) "sfir-literal-widths")
(artifacts (absolute-path (argument-value "--reuse-artifacts" (output))))
(create-directory* (output))
(dynamic-wind (lambda () #f) (lambda () (run-contract-suite "sfir-literal-widths")) finalize-records!)
