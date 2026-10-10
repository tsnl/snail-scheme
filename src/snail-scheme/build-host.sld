;; The build library's OS operations. Chibi supplies the bootstrap adapter;
;; compiled commands import these same operations from the native Rust runtime.
(define-library (snail-scheme build-host)
  (export build-host-imports absolute-path same-file? process-status create-directory*
          call-with-build-directory publish-file)
  (import (scheme base) (scheme cxr) (scheme process-context) (scheme write))
  (begin
    (define build-host-imports
      (map (lambda (name) (cons name "snail.cli"))
           '(%absolute-path %same-file? %process-status %publish-file %create-directory*
                            %reserve-build-directory %clean-build-directory))))
  (cond-expand
   (snail-scheme
    (import (snail-scheme extensions))
    (begin
      (define absolute-path %absolute-path)
      (define same-file? %same-file?)
      (define process-status %process-status)
      (define publish-file %publish-file)
      (define create-directory* %create-directory*)

      ;; Terminal faults report registered directories in Rust. Ordinary returns
      ;; clean them, including a completed child with a nonzero exit status.
      (define (call-with-build-directory output procedure)
        (let* ((directory (%reserve-build-directory output))
               (result (procedure directory)))
          (%clean-build-directory directory)
          result))))
   (else
    (import (scheme file)
            (only (chibi process) fork execute waitpid current-process-id)
            (only (chibi pathname) path-absolute? path-normalize path-directory)
            (only (chibi filesystem) current-directory change-directory
                  create-directory create-directory* delete-file-hierarchy rename-file
                  file-status file-device file-inode open open/read
                  duplicate-file-descriptor-to))
    (begin
      ;; ---- Chibi process and filesystem adapter ----

      (define (absolute-path path)
        (path-normalize (if (path-absolute? path) path
                            (string-append (current-directory) "/" path))))

      (define (same-file? first second)
        (and (file-exists? first) (file-exists? second)
             (let ((a (file-status first)) (b (file-status second)))
               (and (= (file-device a) (file-device b))
                    (= (file-inode a) (file-inode b))))))

      (define (child-process argv directory input? identity)
        (if (not (change-directory directory)) (error "cannot enter directory" directory))
        (if (not input?)
            (let ((fd (open "/dev/null" open/read)))
              (if (not fd) (error "cannot open /dev/null"))
              (if (not (duplicate-file-descriptor-to fd 0)) (error "cannot redirect tool stdin"))))
        (execute (car argv) (cons identity (cdr argv)))
        (exit 127))

      (define (process-status argv directory input? identity)
        (if (null? argv) (error "empty command"))
        (flush-output-port (current-output-port))
        (flush-output-port (current-error-port))
        (let ((pid (fork)))
          (if (not pid) (error "cannot fork build process"))
          (if (zero? pid)
              (guard (failure (else (write failure (current-error-port)) (newline (current-error-port)) (exit 127)))
                (child-process argv directory input? identity))
              (let* ((status (cadr (waitpid pid 0))) (signal (modulo status 128)))
                (if (zero? signal) (quotient status 256) (+ 128 signal))))))

      (define (publish-file source output)
        (if (not (rename-file source output)) (error "cannot publish build output" output)))

      ;; ---- Build directory ownership ----

      (define (reserve-build-directory parent)
        (let ((prefix (string-append parent "/.snail-build-"
                                     (number->string (current-process-id)) "-")))
          (let loop ((serial 0))
            (if (> serial 100) (error "cannot reserve build directory" parent))
            (let ((path (string-append prefix (number->string serial))))
              (cond ((create-directory path #o700) path)
                    ((file-exists? path) (loop (+ serial 1)))
                    (else (error "cannot create build directory" path)))))))

      (define (report-build-directory message directory)
        (display message (current-error-port))
        (display directory (current-error-port))
        (newline (current-error-port)))

      (define (clean-build-directory directory)
        (guard (failure (else (report-build-directory "could not remove build directory: " directory)))
          (delete-file-hierarchy directory)))

      (define (call-in-build-directory directory procedure)
        (guard (failure (else (report-build-directory "build failed; intermediates retained: " directory)
                              (raise failure)))
          (let ((result (procedure directory)))
            (clean-build-directory directory)
            result)))

      (define (call-with-build-directory output procedure)
        (let ((parent (if output (path-directory (absolute-path output))
                          (or (get-environment-variable "TMPDIR") "/tmp"))))
          (if (not (create-directory* parent)) (error "cannot create output directory" parent))
          (call-in-build-directory (reserve-build-directory parent) procedure)))))))
