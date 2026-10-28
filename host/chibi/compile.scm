;; Chibi's private unwind boundary; the compiler source stays host-independent.
(import
 (scheme base)
 (scheme process-context)
 (only (snail stage0 build) report-failure)
 (snail shell compiler driver))

(guard (failure
        (else (exit (report-failure "snail" failure))))
  (compile-command-line))
