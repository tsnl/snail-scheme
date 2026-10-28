;; Chibi's private unwind boundary; the compiler source stays host-independent.
(import
 (scheme base)
 (scheme process-context)
 (only (snail stage0 build) report-failure)
 (snail shell compiler driver))

(guard (failure
        (else
         (guard (publication
                 (else (report-failure "compiler request" publication) (exit 2)))
           (publish-compiler-request!))
         (exit (report-failure "snail" failure))))
  (compile-command-line))
