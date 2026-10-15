;; Run with -D snail-tests -I src -I tests -I benchmarks.
(import (scheme base) (snail-tools process) (wasm-reference audit) (wasm-reference suite))
(command-line-main
 (lambda (arguments)
   (unless (null? arguments) (error "audit tests take no arguments"))
   (test-reference-audits)
   (test-reference-suite)
   0))
