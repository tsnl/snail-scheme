;; Concrete text-file output. Rust owns file payloads; the Scheme wrapper's
;; shared Ref makes explicit close idempotent across aliases. No GC finalizer
;; owns these files. The invocation host closes outstanding files after traps.
(define-library (snail io)
  (export OutputPort file-exists? delete-file open-output-file close-output-port
          call-with-output-file write-char write-string write-i64 newline)
  (import (snail strict))
  (begin

    ;; ---- Scalar resource boundary ----

    (define-data OutputPort
      (output-port (handle (Ref I32) output-handle)))
    (define-extern path-begin "snail.library" "snail:io/path-begin" (-> Unit))
    (define-extern path-character "snail.library" "snail:io/path-character" (-> Char Unit))
    (define-extern path-exists "snail.library" "snail:io/file-exists" (-> I32))
    (define-extern path-delete "snail.library" "snail:io/delete-file" (-> Unit))
    (define-extern path-open "snail.library" "snail:io/open-output-file" (-> I32))
    (define-extern port-write "snail.library" "snail:io/write-character" (-> I32 Char Unit))
    (define-extern port-close "snail.library" "snail:io/close" (-> I32 Unit))

    ;; No user callback occurs between begin and the consuming file operation.
    ;; UTF-8 encoding happens in Rust; String traversal stays in Scheme.
    (: stage-path (-> String Unit))
    (define (stage-path pathname)
      (path-begin)
      (let ((count (string-length pathname)))
        (let loop ((index 0))
          (unless (= index count)
            (path-character (string-ref pathname index))
            (loop (+ index 1))))))
    (: file-exists? (-> String Bool))
    (define (file-exists? pathname)
      (stage-path pathname)
      (i32-eq (path-exists) (ann 1 I32)))
    (: delete-file (-> String Unit))
    (define (delete-file pathname) (stage-path pathname) (path-delete))
    (: open-output-file (-> String OutputPort))
    (define (open-output-file pathname)
      (stage-path pathname)
      (output-port (ref (path-open))))

    ;; ---- Explicit close and a normally returning callback ----

    (: close-output-port (-> OutputPort Unit))
    (define (close-output-port port)
      (let* ((cell (output-handle port)) (handle (ref-get cell)))
        (unless (i32-eq handle (ann -1 I32))
          (ref-set! cell (ann -1 I32))
          (port-close handle))))
    (: call-with-output-file (All (T) (-> String (-> OutputPort T) T)))
    (define (call-with-output-file pathname procedure)
      (let* ((port (open-output-file pathname)) (result (procedure port)))
        (close-output-port port)
        result))

    ;; ---- Character iteration and decimal integer formatting ----

    (: write-char (-> Char OutputPort Unit))
    (define (write-char character port)
      (port-write (ref-get (output-handle port)) character))
    (: write-string (-> String OutputPort Unit))
    (define (write-string text port)
      (let ((count (string-length text)))
        (let loop ((index 0))
          (unless (= index count)
            (write-char (string-ref text index) port)
            (loop (+ index 1))))))
    (: newline (-> OutputPort Unit))
    (define (newline port) (write-char #\newline port))
    (: write-i64 (-> I64 OutputPort Unit))
    (define (write-i64 number port)
      (when (< number 0) (write-char #\- port))
      (write-negative-digits (if (> number 0) (- 0 number) number) port))
    ;; Nonpositive digits avoid negating I64_MIN. Remainders are in [-9, 0],
    ;; recursion has at most 19 levels, and zero still emits one digit.
    (: write-negative-digits (-> I64 OutputPort Unit))
    (define (write-negative-digits number port)
      (let ((prefix (quotient number 10)))
        (unless (= prefix 0) (write-negative-digits prefix port))
        (write-char (integer->char (- 48 (remainder number 10))) port)))))
