;; Run from the repository root with chibi-scheme -I bootstrap -I tests.
(import
 (scheme base)
 (scheme process-context)
 (chibi filesystem)
 (snail-tests harness)
 (snail-tests native-loading))
(initialize-suite! (current-directory) (cdr (command-line)) "lofi-native-loading")
(artifacts (absolute-path (argument-value "--reuse-artifacts" (output))))
(create-directory* (output))
(dynamic-wind (lambda () #f) (lambda () (run-native-loading)) finalize-records!)
