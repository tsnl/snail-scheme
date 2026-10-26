;; Chibi's private unwind boundary; the compiler source stays host-independent.
(import
 (scheme base)
 (scheme process-context)
 (only (lofi build) report-failure)
 (lofi compiler driver))

(guard (failure
        (else
         (guard (publication
                 (else (report-failure "compiler request" publication) (exit 2)))
           (publish-compiler-request!))
         (exit (report-failure "lofi" failure))))
  (compile-command-line))
