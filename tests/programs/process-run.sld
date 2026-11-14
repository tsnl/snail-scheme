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

(define (report (result (Result Captured ProcessError))) (→ Unit) (! output-port)
  (match result
    ((Ok captured)
     (write-line (exit-text (● captured exit)))
     (write-string (text (● captured stdout)))
     (write-string (text (● captured stderr))))
    ((Err error) (write-line (● error code)))))

(define (main) (→ Unit) (! output-port process)
  (report (run (new Command
                 (program "/bin/sh")
                 (arguments (list "-c" "cat; echo err >&2; exit 3"))
                 (directory "."))
               (string->utf8 "from input\n")))
  ;; A program with no slash is found on PATH, and runs as the name it was
  ;; given, in its directory.
  (report
   (run (new Command (program "sh") (arguments (list "-c" "echo $0; pwd")) (directory "/")) #u8()))
  (report
   (run (new Command (program "/bin/sh") (arguments (list "-c" "kill -TERM $$")) (directory "."))
        #u8()))
  ;; A missing executable or directory is an error, as for spawn.
  (report
   (run (new Command (program "/nonexistent/program") (arguments (Nil)) (directory ".")) #u8()))
  (report (run (new Command
                 (program "/bin/sh")
                 (arguments (list "-c" "true"))
                 (directory "/nonexistent/directory"))
               #u8()))
  (report
   (run (new Command (program "no-such-program-on-path") (arguments (Nil)) (directory ".")) #u8()))
  ;; More output than a pipe holds, which nothing reads until the child exits.
  (match (run (new Command
                (program "/bin/sh")
                (arguments (list "-c" "head -c 200000 /dev/zero"))
                (directory "."))
              #u8())
    ((Ok captured)
     (write-line (string-append (show (vector-length (● captured stdout))) " bytes")))
    ((Err error) (write-line (● error code))))
  (unit))
