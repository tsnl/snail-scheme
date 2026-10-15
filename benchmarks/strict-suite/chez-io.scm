;; Scalar I/O providers for the exact typed io/read/write bodies under Chez.
;; This private scope holds native ports only. Datum traversal and formatting
;; stay in the shared Scheme modules; older reader controls retain their own
;; native input boundary and never instantiate this provider.

;; ---- One owner per issued ID and one synchronous pathname transfer ----

(define io-next-id 0)
(define io-path #f)
(define io-files '())
(define io-stdout (standard-output-port (buffer-mode block) #f))
(define (io-begin-path) (set! io-path '()))
(define (io-scalar-code value)
  (let ((code (if (char? value) (char->integer value) value)))
    (unless (and (integer? code) (exact? code) (<= 0 code #x10ffff)
                 (not (<= #xd800 code #xdfff)))
      (error 'scalar-io "invalid Unicode scalar"))
    code))
(define (io-path-character character)
  (unless io-path (error 'scalar-io "no pathname transfer is active"))
  (set! io-path (cons (integer->char (io-scalar-code character)) io-path)))
(define (io-take-path)
  (let ((path io-path))
    (set! io-path #f)
    (unless path (error 'scalar-io "no pathname transfer is active"))
    (list->string (reverse path))))
(define (io-reserve-id)
  (when (> io-next-id 2147483647) (error 'scalar-io "file port IDs exhausted"))
  (let ((id io-next-id)) (set! io-next-id (+ id 1)) id))
(define (io-open direction)
  (let* ((path (io-take-path)) (id (io-reserve-id))
         (port (if (eq? direction 'input)
                   (open-file-input-port path (file-options) (buffer-mode block) #f)
                   (open-file-output-port path (file-options no-fail) (buffer-mode block) #f))))
    ;; Newest IDs are first; reversing once during cleanup gives Rust's ascending
    ;; ID order, including when two independently buffered ports name one file.
    (set! io-files (cons (cons id (vector port direction #f)) io-files))
    id))
(define (io-entry id)
  (let ((entry (assv id io-files)))
    (unless entry (error 'scalar-io "unknown or closed file port"))
    entry))
(define (io-input id)
  (let ((entry (cdr (io-entry id))))
    (unless (eq? (vector-ref entry 1) 'input) (error 'scalar-io "expected an input port"))
    entry))
(define (io-output id)
  (if (= id -2) io-stdout
      (let ((entry (cdr (io-entry id))))
        (unless (eq? (vector-ref entry 1) 'output)
          (error 'scalar-io "expected an open output port"))
        (vector-ref entry 0))))

;; ---- Strict incremental UTF-8 preserves BOM and separate CR/LF scalars ----

(define (io-utf8-width first)
  (cond ((<= #xc2 first #xdf) 2) ((<= #xe0 first #xef) 3) ((<= #xf0 first #xf4) 4)
        (else (error 'scalar-io "invalid UTF-8"))))
(define (io-utf8-bytes port first width)
  (let ((bytes (make-bytevector width first)))
    (do ((index 1 (+ index 1))) ((= index width) bytes)
      (let ((byte (get-u8 port)))
        (when (eof-object? byte) (error 'scalar-io "incomplete UTF-8 scalar"))
        (bytevector-u8-set! bytes index byte)))))
(define (io-decode-utf8 bytes)
  (let* ((width (bytevector-length bytes)) (first (bytevector-u8-ref bytes 0))
         (mask (case width ((2) #x1f) ((3) #x0f) (else #x07))))
    (let loop ((index 1) (code (bitwise-and first mask)))
      (if (= index width)
          (begin
            (when (or (< code (case width ((2) #x80) ((3) #x800) (else #x10000)))
                      (> code #x10ffff) (<= #xd800 code #xdfff))
              (error 'scalar-io "invalid UTF-8"))
            code)
          (let ((byte (bytevector-u8-ref bytes index)))
            (unless (<= #x80 byte #xbf) (error 'scalar-io "invalid UTF-8"))
            (loop (+ index 1) (+ (* code 64) (- byte #x80))))))))
(define (io-read-scalar port)
  (let ((first (get-u8 port)))
    (cond ((eof-object? first) -1) ((< first #x80) first)
          (else (io-decode-utf8 (io-utf8-bytes port first (io-utf8-width first)))))))
(define (io-read id peek?)
  (let* ((entry (io-input id)) (old (vector-ref entry 2))
         (value (if old old (io-read-scalar (vector-ref entry 0)))))
    ;; #f is absent; both NUL (0) and EOF (-1) are cached values. A failed decode
    ;; publishes no cache, and an ordinary read consumes even a cached EOF.
    (vector-set! entry 2 (if peek? value #f))
    value))
(define (io-write id character)
  ;; Resolve the ID first, validate the scalar next, then check direction.
  ;; Rust's scalar writer has this order even for malformed raw ABI calls.
  (let* ((port (if (= id -2) io-stdout (vector-ref (cdr (io-entry id)) 0)))
         (code (io-scalar-code character)))
    (unless (output-port? port) (error 'scalar-io "expected an output port"))
    (put-bytevector port (string->utf8 (string (integer->char code))))
    (when (= id -2) (flush-output-port port))))

;; ---- Detached close preserves the first failure and releases its owner ----

(define (io-release port)
  (guard (first
          (else
           ;; Rust drops its failed buffered port, attempting its pending bytes
           ;; once more. Chez leaves a failed-close port open: retry once, then
           ;; discard failed output and close its descriptor before propagating.
           (guard (retry
                   (else
                    (guard (release (else (void)))
                      (when (output-port? port) (clear-output-port port))
                      (close-port port))))
             (close-port port))
           (raise first)))
    (close-port port)))
(define (io-close id)
  (unless (= id -2)
    (let ((entry (io-entry id)))
      (set! io-files (remq entry io-files))
      (io-release (vector-ref (cdr entry) 0)))))
(define (io-finish prior-error)
  (let ((owned (reverse io-files)))
    (set! io-files '())
    (set! io-path #f)
    (let loop ((owned owned) (failure prior-error))
      (if (null? owned) failure
          (let ((next (guard (error (else (or failure error)))
                        (io-release (vector-ref (cdar owned) 0)) failure)))
            (loop (cdr owned) next))))))

;; ---- Fixed scalar services, with no Datum or arbitrary-number operations ----

(define (io-scalar-service name)
  (cond
   ((string=? name "snail:io/path-begin") io-begin-path)
   ((string=? name "snail:io/path-character") io-path-character)
   ((string=? name "snail:io/file-exists") (lambda () (if (file-exists? (io-take-path)) 1 0)))
   ((string=? name "snail:io/delete-file") (lambda () (delete-file (io-take-path))))
   ((string=? name "snail:io/open-input-file") (lambda () (io-open 'input)))
   ((string=? name "snail:io/open-output-file") (lambda () (io-open 'output)))
   ((string=? name "snail:io/read-character") (lambda (id) (io-read id #f)))
   ((string=? name "snail:io/peek-character") (lambda (id) (io-read id #t)))
   ((string=? name "snail:io/write-character") io-write)
   ((string=? name "snail:io/check-output") (lambda (id) (io-output id) (void)))
   ((string=? name "snail:io/close") io-close)
   ((string=? name "snail:io/standard-output") (lambda () -2))
   (else (error 'scalar-io "unknown scalar export" name))))
