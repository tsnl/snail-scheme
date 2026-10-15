;; Run from the repository root with chibi-scheme -I src -I tests.
(import (scheme base) (scheme process-context) (chibi filesystem)
        (snail-tests harness) (snail-tests commands))
(initialize-suite! (current-directory) (cdr (command-line)) "build")
(artifacts (absolute-path (argument-value "--reuse-artifacts" (output))))
(create-directory* (output))
(dynamic-wind (lambda () #f) (lambda () (run-command-suite "build")) finalize-records!)
