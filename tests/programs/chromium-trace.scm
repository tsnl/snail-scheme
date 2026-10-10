(import (scheme base) (scheme write) (scheme process-context)
        (snail-scheme chromium-trace))

(define (check expected actual)
  (if (not (equal? expected actual)) (error "trace behavior mismatch" expected actual)))

;; Decoration precedes binding the port. The error case must not call the body.
(define unbound (trace "unbound" (lambda () (display "body ran"))))
(define name (string-append "quote\" slash\\ line\n tab\t λ" (string (integer->char 0))))
(define decorated (trace name values))
(define directory (cadr (command-line)))
(define outer (string-append directory "/outer.json"))
(define inner (string-append directory "/inner.json"))
(define empty (string-append directory "/empty.json"))

(define recorded
  (trace "outer"
         (lambda ()
           (check '(3 4) (call-with-values (lambda () (decorated 3 4)) list))
           (check '() (call-with-values (trace "zero" values) list))
           (check 5 ((trace "single" (lambda () 5))))
           (with-trace-to inner (trace "inner" values))
           ((trace "after" values))
           (values 1 2))))

(cond ((string=? directory "unbound") (unbound))
      ((and (> (length (command-line)) 2) (string=? (list-ref (command-line) 2) "abort"))
       (with-trace-to
        outer (trace "aborted"
                     (lambda ()
                       ((trace "completed" values))
                       (error "expected failure")))))
      (else
       (check '(1 2)
              (call-with-values
                  (lambda () (with-trace-to outer recorded)) list))
       (check '() (call-with-values (lambda () (with-trace-to empty values)) list))
       (display "trace file checks passed\n")))
