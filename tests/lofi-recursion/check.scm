;; Run from the repository root with chibi-scheme -I bootstrap -I tests.
(import
 (scheme base)
 (scheme process-context)
 (chibi filesystem)
 (snail-tests harness)
 (snail-tests contracts))
(initialize-suite! (current-directory) (cdr (command-line)) "lofi-recursion")
(artifacts (absolute-path (argument-value "--reuse-artifacts" (output))))
(create-directory* (output))
(dynamic-wind (lambda () #f) (lambda () (run-contract-suite "lofi-recursion")) finalize-records!)
