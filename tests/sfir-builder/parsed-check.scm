;; Parsing and copied syntax must leave the same decisions to ordinary checking.
(import (scheme base) (scheme file) (scheme process-context) (scheme write)
        (snail-scheme reader) (snail-scheme syntax-parser) (snail-scheme chromium-trace)
        (snail-scheme strict-primitives) (snail-scheme source) (snail-sfir frontend)
        (snail-sfir compiler) (snail-sfir library-transfer) (snail-scheme test-utils))

(define directory (cadr (command-line)))
(define primitive (cons '(sfir primitive) (make-primitive-library primitive-names)))
(define (parsed text)
  (parse-library (car (reader->syntax-list (string->reader "precision.sfir" text)))))
(define (received library)
  (let ((port (open-output-string)))
    (write-library-transfer library port)
    (receive-library-transfer (make-library-transfer-context)
                              (read-library-transfer (open-input-string (get-output-string port))))))
(define (compiled library entry)
  (compile (list primitive (cons '(precision) library)) (make-entry '(precision) entry) wasm-target))
(define (diagnostic library)
  (guard (failure
          (else (let* ((details (error-object-irritants failure)) (location (and (pair? details) (car details))))
                  (list (error-object-message failure)
                        (and (loc? location) (list (loc-filename location) (loc-line location) (loc-column location)))))))
    (compiled library 'run) #f))

(with-chromium-trace-to
 (string-append directory "/parsed-check.trace.json")
 (lambda ()
   (let ((source (parsed
                  "(define-library (precision) (import (sfir primitive)) (export wide halfway subnormal negative-zero conversion readiness)
                     (begin
                       (def wide (-> I64) (lambda () (ann 9223372036854775807 I64)))
                       (def halfway (-> F32) (lambda () (ann 1.0000000596046448 F32)))
                       (def subnormal (-> F32) (lambda () (ann 7.006492321624085354618647916449580656402e-46 F32)))
                       (def negative-zero (-> F64) (lambda () -0.0))
                       (def conversion (-> I64) (lambda () (i32->i64 (i32-add 20 22))))
                       (def readiness (-> I32) (lambda () (begin (def x y) (def y 1) x)))))")))
     (for-each
      (lambda (row)
        (for-each
         (lambda (entry)
           (let ((artifact (compiled (cdr row) entry)))
             (call-with-port (open-binary-output-file
                              (string-append directory "/precision-" (car row) "-" (symbol->string entry) ".wasm"))
               (lambda (port) (write-bytevector (artifact-bytes artifact) port)))))
         '(wide halfway subnormal negative-zero conversion readiness)))
      (list (cons "source" source) (cons "received" (received source)))))
   (for-each
    (lambda (body)
      (let* ((source (parsed (string-append "(define-library (precision) (import (sfir primitive)) (export run)\n(begin " body "))")))
             (copy (received source)) (failure (diagnostic source)))
        (unless failure (error "expected source rejection" body))
        (expect (diagnostic copy) failure)))
    '("(def run (-> I32) (lambda () 2147483648))"
      "(def run (-> I64) (lambda () 9223372036854775808))"
      "(def run (-> F32) (lambda () 1e999))"
      "(def run (-> I32) (lambda () 1+2i))"
      "(def run (-> I32) (lambda () (begin (let x y) (let y 1) x)))"
      "(def run (-> I32) (lambda () (ann (i32->i64 1) I32)))"
      "(def run (Rest I32) 1)"
      "(define-overload run (-> I32 I32) (lambda (value) #f))"
      "(def wrong (All (T) (-> T T)) (lambda (value) (ann 0 T))) (def run (-> I32) (lambda () (wrong 1)))"
      "(def Wrong Constraint (datatype () (wrong))) (def run (-> I32) (lambda () 1))"))))
(display "PASS source/received diagnostics, delayed number width selection and exact source spans\n")
