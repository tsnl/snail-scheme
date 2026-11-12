;; Synchronous commands write to files, so neither output stream can block
;; the other. A private directory and its files have one lexical owner.
(library (snail stage0 process)
  (export capture-process test-process)
  (import (chezscheme) (snail stage0 system))
  (define capture-count 0)
  (define counter-lock (make-mutex))
  (define (capture-directory)
    (let ([number (with-mutex counter-lock
                    (set! capture-count (+ capture-count 1)) capture-count)])
    (let ([path (string-append (or (getenv "TMPDIR") "/tmp") "/snail-command-"
                              (number->string (get-process-id)) "-" (number->string number))])
      (if (create-directory path #o700) path
          (if (file-link-status path) (capture-directory)
              (error 'capture-process "cannot create capture directory" path))))))
  (define (capture-process arguments)
    ;; Validate before allocating the scratch directory.
    (command-text arguments)
    (let* ([directory (capture-directory)] [out (make-path directory "stdout")]
           [err (make-path directory "stderr")])
      (dynamic-wind (lambda () (void))
        (lambda ()
          (flush-output-port (current-output-port))
          (flush-output-port (current-error-port))
          (let ([status (run-command-status
                         (append (list "/bin/sh" "-c"
                                 "exec </dev/null >\"$1\" 2>\"$2\"; shift 2; exec \"$@\""
                                 "snail-capture" out err) arguments))])
            (list (call-with-input-file out port->string)
                  (call-with-input-file err port->string) status)))
        (lambda () (delete-file-hierarchy directory)))))
  ;; ---- Tests ----

  (define (test-process root)
    (let* ([fixture (string-append root "/tests/process-capture.mjs")]
           [arguments (capture-process (list "node" fixture "args" "a b" "it's \"quoted\"" ""
                                             "$(false); `false`"))]
           [streams (capture-process (list "node" fixture "streams"))])
      (unless (and (equal? arguments (list "a b\nit's \"quoted\"\n\n$(false); `false`" "" 0))
                   (equal? streams (list "stdin EOF; no newline" (make-string 1048576 #\e) 1792))
                   (= (caddr (capture-process '("/snail/nonexistent/tool"))) (* 127 256))
                   (guard (failure [else #t])
                     (capture-process (list "true" (string #\nul))) #f))
        (error 'test-process "process capture lost arguments, output, or status"))))

)
