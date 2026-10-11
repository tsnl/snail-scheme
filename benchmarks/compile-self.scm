;; Compile this entry point and its compiler dependencies. ROOT INPUT OUTPUT SYSTEM.
(import (scheme base) (scheme process-context) (scheme time) (scheme write)
        (snail-scheme compiler) (snail-scheme chromium-trace))

;; ---- Complete compiler workload ----

(define (compile-self root input output system)
  (let ((seconds
         (with-chromium-trace-to
          (string-append output ".trace.json")
          (lambda ()
            (let ((start (current-jiffy)))
              (source-file->wat-file root input output)
              (/ (- (current-jiffy) start) (* 1.0 (jiffies-per-second))))))))
    (display "+!CSVLINE!+") (display system) (display ",compiler-self,")
    (display seconds) (newline)))

(apply compile-self (cdr (command-line)))
