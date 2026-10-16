;; Concrete filesystem and subprocess operations for Chibi-hosted tools.
(define-library (wasm-native process)
  (export run-command/capture run-command! current-command-records current-command-log
          current-process-supervisor close-owned-descriptor
          read-text write-text read-bytes write-bytes read-json write-json
          absolute-path paths-alias? path-directory path-join make-build-directory file-sha256 tool-name
          option-ref command-line-main directory-files-recursive)
  (import (scheme base) (scheme char) (scheme cxr) (scheme file) (scheme write)
          (scheme process-context) (scheme time) (chibi filesystem) (chibi pathname)
          (wasm-native json)
          (only (chibi io) port->string port->bytevector)
          (only (chibi process) fork execute waitpid current-process-id)
          (only (chibi string) string-trim string-prefix?) (srfi 1) (srfi 151))
  (begin

    ;; ---- Files and retained evidence ----

    (define (read-text path) (call-with-input-file path port->string))
    (define (write-text path text) (call-with-output-file path (lambda (port) (display text port))))
    (define (read-bytes path) (call-with-port (open-binary-input-file path) port->bytevector))
    (define (write-bytes path bytes)
      (call-with-port (open-binary-output-file path) (lambda (port) (write-bytevector bytes port))))
    (define (read-json path) (call-with-input-file path json-read))
    (define (write-json path value)
      (call-with-output-file path (lambda (port) (json-write value port) (newline port))))
    (define (file-sha256 path)
      ;; Coreutils streams large artifacts without Scheme's per-byte I/O loop.
      (let* ((record (run-command/capture (list (tool-name "SHA256SUM" "sha256sum") "-z" "--" path)
                                          '((supervisor . #f) (include-output-hex? . #f))))
             (text (option-ref record 'stdout "")))
        (unless (and (zero? (option-ref record 'status 1)) (>= (string-length text) 64)
                     (every (lambda (character) (or (char<=? #\0 character #\9) (char<=? #\a character #\f)))
                            (string->list (substring text 0 64))))
          (error "cannot hash build input" path (option-ref record 'stderr "")))
        (substring text 0 64)))
    (define (path-join . pieces) (path-normalize (apply make-path pieces)))
    (define (tool-name variable default) (or (get-environment-variable variable) default))
    (define (option-ref options name default)
      (let ((entry (assq name options))) (if entry (cdr entry) default)))
    (define (paths-alias? left right)
      (and (string? left) (string? right)
           (or (string=? left right)
               (and (file-exists? left) (file-exists? right)
                    (= (file-device left) (file-device right)) (= (file-inode left) (file-inode right))))))

    (define (make-build-directory parent prefix)
      (set! parent (if (string-prefix? "/" parent) parent (path-join (current-directory) parent)))
      (create-directory* parent)
      (let ((base (string-append parent "/" prefix (number->string (current-process-id)) "-")))
        (let loop ((index 0))
          (let ((path (string-append base (number->string index))))
            (cond ((file-exists? path) (loop (+ index 1)))
                  ((create-directory path #o700) path)
                  ((file-exists? path) (loop (+ index 1)))
                  (else (error "cannot create build directory" path)))))))

    (define (directory-files-recursive directory)
      (directory-fold-tree directory #f #f
                           (lambda (path result) (if (file-regular? path) (cons path result) result)) '()))

    ;; Resolve existing symlinks as well as missing final components. Outputs
    ;; are compared with compiler inputs before any file is opened for writing.
    (define (absolute-path path)
      (string-trim (run-command! (list "realpath" "-m" "--" path)) char-whitespace?))

    ;; ---- Captured child processes ----

    (define (close-owned-descriptor descriptor)
      ;; Chibi 0.12's raw close-file-descriptor leaves its GC owner marked open.
      ;; Closing through a port consumes that ownership, so a later finalizer
      ;; cannot close an unrelated descriptor that reused the same number.
      (close-input-port (open-input-file-descriptor descriptor)))
    (define (redirect descriptor path flags)
      (let ((source (open path flags #o600)))
        (unless source (error "cannot open process redirect" descriptor path))
        (duplicate-file-descriptor-to source descriptor)
        (close-owned-descriptor source)))

    (define (child-command argv directory input output errors)
      (guard (failure (else (write failure (current-error-port)) (newline (current-error-port)) (emergency-exit 127)))
        (unless (change-directory directory) (error "cannot enter process directory" directory))
        (redirect 0 input open/read)
        (redirect 1 output (bitwise-ior open/write open/create open/truncate))
        (redirect 2 errors (bitwise-ior open/write open/create open/truncate))
        (execute (car argv) argv)
        (emergency-exit 127)))

    (define current-process-supervisor (make-parameter (get-environment-variable "SNAIL_NATIVE_SUPERVISOR")))
    (define (process-supervisor options)
      (let ((path (option-ref options 'supervisor (current-process-supervisor))))
        (when (and (option-ref options 'require-supervisor? #f) (not (and path (file-exists? path))))
          (error "captured command requires a built native process supervisor" path))
        (and path (file-exists? path) path)))
    (define (environment-arguments options)
      (let ((environment (option-ref options 'environment '())))
        (append (if (option-ref options 'inherit-environment? #t) '() '("-i"))
                (append-map (lambda (entry) (if (cdr entry) '() (list "-u" (car entry)))) environment)
                (map (lambda (entry) (string-append (car entry) "=" (cdr entry))) (filter cdr environment)))))
    (define (process-arguments argv options record)
      (let* ((timeout (option-ref options 'timeout #f)) (supervisor (process-supervisor options))
             (command (cond (supervisor
                             (append (list supervisor "--command"
                                           (number->string (if timeout (exact (ceiling (* 1000 timeout))) 0)) "--") argv))
                            (timeout (append (list "timeout" "--kill-after=2" (number->string timeout)) argv))
                            (else argv))))
        (append (list "env") (environment-arguments options)
                (if supervisor (list (string-append "SNAIL_PROCESS_RECORD=" record)) '()) command)))

    (define (decoded-status status)
      (let ((signal (modulo status 128)))
        (if (zero? signal) (quotient status 256) (+ 128 signal))))

    (define (captured-text path)
      (guard (failure (else "<non-UTF-8 output; consult the retained bytes>")) (read-text path)))

    (define (bytevector->hex-string bytes)
      ;; Two ASCII bytes per input byte: one bounded allocation, without
      ;; temporary strings or repeated Unicode string-index traversal.
      (let* ((digits #u8(48 49 50 51 52 53 54 55 56 57 97 98 99 100 101 102))
             (length (bytevector-length bytes)) (output (make-bytevector (* 2 length))))
        (do ((index 0 (+ index 1))) ((= index length) (utf8->string output))
          (let ((byte (bytevector-u8-ref bytes index)))
            (bytevector-u8-set! output (* 2 index) (bytevector-u8-ref digits (quotient byte 16)))
            (bytevector-u8-set! output (+ 1 (* 2 index)) (bytevector-u8-ref digits (modulo byte 16)))))))

    (define (capture-process argv options directory)
      (let* ((input (path-join directory "stdin")) (output (path-join directory "stdout"))
             (errors (path-join directory "stderr")) (record (path-join directory "process.json")) (start (current-jiffy))
             (cwd (option-ref options 'directory (current-directory))))
        (write-text input (option-ref options 'input ""))
        (flush-output-port (current-output-port)) (flush-output-port (current-error-port))
        (let ((pid (fork)))
          (unless pid (error "cannot fork process" argv))
          (when (zero? pid) (child-command (process-arguments argv options record) cwd input output errors))
          (let ((status (decoded-status (cadr (waitpid pid 0)))))
            (append `((command . ,(list->vector argv)) (status . ,status) (stdout . ,(captured-text output))
                      (stderr . ,(captured-text errors)) (supervisor_pid . ,pid) (cwd . ,cwd)
                      (timeout . ,(= status 124))
                      (seconds . ,(/ (inexact (- (current-jiffy) start)) (jiffies-per-second))))
                    (if (option-ref options 'include-output-hex? #t)
                        `((stdout_hex . ,(bytevector->hex-string (read-bytes output)))
                          (stderr_hex . ,(bytevector->hex-string (read-bytes errors)))) '())
                    (if (file-exists? record) (read-json record) `((pid . ,pid) (descendants_gone . #f)))
                    (if (option-ref options 'log-directory #f)
                        `((stdout_path . ,output) (stderr_path . ,errors)) '()))))))

    (define (run-command/capture argv . options)
      (unless (and (pair? argv) (list? argv)) (error "expected a nonempty command" argv))
      (let* ((options (if (null? options) '() (car options))) (logs (option-ref options 'log-directory #f)))
        (if logs (capture-process argv options (make-build-directory logs "process-"))
            (let ((directory (make-build-directory (tool-name "TMPDIR" "/tmp") "snail-process-")))
              (dynamic-wind (lambda () #f) (lambda () (capture-process argv options directory))
                            (lambda () (delete-file-hierarchy directory)))))))

    (define current-command-records (make-parameter '()))
    (define current-command-log (make-parameter #f))
    (define (run-command! argv . options)
      (let ((record (apply run-command/capture argv options)))
        (current-command-records (append (current-command-records) (list record)))
        (when (current-command-log)
          (write-json (current-command-log) (list->vector (current-command-records))))
        (unless (zero? (option-ref record 'status 1))
          (error "command failed" argv (option-ref record 'status 1)
                 (option-ref record 'stderr "") (option-ref record 'stdout "")))
        (option-ref record 'stdout "")))

    (define (command-line-main main . name)
      (guard (failure (else (display (if (null? name) "wasm-native" (car name)) (current-error-port))
                            (display ": " (current-error-port))
                            (write failure (current-error-port)) (newline (current-error-port)) (exit 1)))
        (exit (main (cdr (command-line)))))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-process)
    (import (wasm-native test-utils))
    (begin
      (define (test-captured-byte-identity)
        (expect (bytevector->hex-string #u8()) "")
        (expect (bytevector->hex-string #u8(0 1 15 16 31 32 127 128 254 255)) "00010f101f207f80feff")
        (let ((bytes (make-bytevector 256)))
          (do ((index 0 (+ index 1))) ((= index 256)) (bytevector-u8-set! bytes index index))
          (expect (bytevector->hex-string bytes)
                  (string-append
                   "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
                   "202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f"
                   "404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f"
                   "606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f"
                   "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f"
                   "a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf"
                   "c0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedf"
                   "e0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"))))
      (define (test-process) (run-test test-captured-byte-identity))))
   (else)))
