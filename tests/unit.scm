;; The compiler's unit tests: the Tests section of each of its modules, and
;; of stage 0's own, run from their source on Chez. The programs and every
;; other check are tests/run.scm's, built by the command line.
;;
;;   scheme --script host/chez/load.scm ROOT test
(import
 (chezscheme)
 (snail stage0 system)
 (only (snail stage0 process) test-process)
 (only (snail stage0 build) test-build)
 (only (snail stage0 forms) test-forms)
 (only (snail core base) test-base)
 (only (snail shell compiler read) test-read)
 (only (snail shell compiler inputs) test-inputs)
 (only (snail shell compiler expand) test-expand)
 (only (snail shell compiler core) test-core)
 (only (snail shell compiler sha256) test-sha256)
 (only (snail shell compiler check) test-check)
 (only (snail shell compiler specialize) test-specialize)
 (only (snail shell compiler prepare) test-prepare)
 (only (snail shell compiler wasm) test-wasm))

(let ((root (cadr (command-line))))
  (test-forms)
  (test-base)
  (test-read)
  (test-inputs)
  (test-build root)
  (test-process root)
  (test-core)
  (test-sha256)
  (test-check)
  (test-specialize)
  (test-prepare)
  (test-wasm)
  (test-expand (make-path root "build/tests/expand") (make-path root "src"))
  (display "the compiler's unit tests passed\n"))
