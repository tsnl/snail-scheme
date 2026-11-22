(import
 (snail core base)
 (snail core io)
 (snail shell utf8)
 (snail shell process))

;; `run` takes a command to its end, with no task to wait in: the input goes
;; in, and how it ended and both outputs come back.
(define (text (bytes Bytes)) (→ String)
  (match (utf8->string bytes)
    ((Ok text) text)
    ((Err _) (panic "the output is not UTF-8"))))

(define (exit-text (exit Exit)) (→ String)
  (match exit
    ((Exited code) (string-append "exited " (show code)))
    ((Signaled name) (string-append "signaled " name))))

(define (report (out OutputPort) (result (Result Captured ProcessError))) (→ Unit)
  (match result
    ((Ok captured)
     (write-line out (exit-text (● captured exit)))
     (write-string out (text (● captured stdout)))
     (write-string out (text (● captured stderr))))
    ((Err error) (write-line out (● error code)))))

(define (main (processes Processes) (out OutputPort)) (→ Unit)
  (report out (run processes (new Command
                               (program "/bin/sh")
                               (arguments (list "-c" "cat; echo err >&2; exit 3"))
                               (directory "."))
                   (string->utf8 "from input\n")))
  ;; A program with no slash is found on PATH, and runs as the name it was
  ;; given, in its directory.
  (report out
          (run processes
               (new Command (program "sh") (arguments (list "-c" "echo $0; pwd")) (directory "/"))
               #u8()))
  (report out
          (run processes
               (new Command
                 (program "/bin/sh")
                 (arguments (list "-c" "kill -TERM $$"))
                 (directory "."))
               #u8()))
  ;; A missing executable or directory is an error, as for spawn.
  (report out
          (run processes
               (new Command (program "/nonexistent/program") (arguments (Nil)) (directory "."))
               #u8()))
  (report out (run processes (new Command
                               (program "/bin/sh")
                               (arguments (list "-c" "true"))
                               (directory "/nonexistent/directory"))
                   #u8()))
  (report out
          (run processes
               (new Command (program "no-such-program-on-path") (arguments (Nil)) (directory "."))
               #u8()))
  ;; More output than a pipe holds, which nothing reads until the child exits.
  (match (run processes (new Command
                          (program "/bin/sh")
                          (arguments (list "-c" "head -c 200000 /dev/zero"))
                          (directory "."))
              #u8())
    ((Ok captured)
     (write-line out (string-append (show (array-length (● captured stdout))) " bytes")))
    ((Err error) (write-line out (● error code))))
  (unit))
