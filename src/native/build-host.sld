;; Inherited-stream process operations for Chibi-hosted builds.
(define-library (native build-host)
  (export process-status run-command tool-name)
  (import
   (scheme base)
   (scheme process-context)
   (scheme write)
   (native chromium-trace)
   (only (native process) close-owned-descriptor)
   (only (chibi process) fork execute waitpid)
   (only (chibi filesystem) change-directory open open/read duplicate-file-descriptor-to))
  (begin

    ;; ---- Explicit tools and subprocesses ----

    (define (tool-name variable default)
      (or (get-environment-variable variable) default))
    (define (run-command stage arguments . directory)
      ((chromium-trace stage
                       (lambda ()
                         (let ((status (process-status arguments (if (null? directory) "." (car directory)) #f (car arguments))))
                           (unless (zero? status) (error "build command failed" arguments status)))))))

    (define (child-process argv directory input? identity)
      (if (not (change-directory directory)) (error "cannot enter directory" directory))
      (if (not input?)
          (let ((fd (open "/dev/null" open/read)))
            (if (not fd) (error "cannot open /dev/null"))
            (if (not (duplicate-file-descriptor-to fd 0)) (error "cannot redirect tool stdin"))
            (close-owned-descriptor fd)))
      (execute (car argv) (cons identity (cdr argv)))
      (emergency-exit 127))

    (define (process-status argv directory input? identity)
      (if (null? argv) (error "empty command"))
      (flush-output-port (current-output-port))
      (flush-output-port (current-error-port))
      (let ((pid (fork)))
        (if (not pid) (error "cannot fork build process"))
        (if (zero? pid)
            (guard (failure (else (write failure (current-error-port)) (newline (current-error-port)) (emergency-exit 127)))
              (child-process argv directory input? identity))
            (let* ((status (cadr (waitpid pid 0))) (signal (modulo status 128)))
              (if (zero? signal) (quotient status 256) (+ 128 signal))))))

    ))
