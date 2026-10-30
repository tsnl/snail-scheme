(import
 (snail core base)
 (snail core io)
 (snail shell utf8)
 (snail shell process))

;; `run` takes a command to its end, with no task to wait in: the input goes
;; in, and how it ended and both outputs come back.
(: text (-> Bytes String))
(define (text bytes)
  (match (utf8->string bytes)
    ((Ok text) text)
    ((Err _) (panic "the output is not UTF-8"))))

(: exit-text (-> Exit String))
(define (exit-text exit)
  (match exit
    ((Exited code) (string-append "exited " (show code)))
    ((Signaled name) (string-append "signaled " name))))

(: report (-> (Result Captured ProcessError) Unit ! console))
(define (report result)
  (match result
    ((Ok captured)
     (write-line (exit-text (Captured-exit captured)))
     (write-string (text (Captured-stdout captured)))
     (write-string (text (Captured-stderr captured))))
    ((Err error) (write-line (ProcessError-code error)))))

(report (run (Command "/bin/sh" (list "-c" "cat; echo err >&2; exit 3") ".")
             (string->utf8 "from input\n")))

;; A program with no slash is found on PATH, and runs in its directory.
(report (run (Command "sh" (list "-c" "pwd") "/") #u8()))
(report (run (Command "/bin/sh" (list "-c" "kill -TERM $$") ".") #u8()))

;; A missing executable or directory is an error, as for spawn.
(report (run (Command "/nonexistent/program" (Nil) ".") #u8()))
(report (run (Command "/bin/sh" (list "-c" "true") "/nonexistent/directory") #u8()))

;; More output than a pipe holds, which nothing reads until the child exits.
(match (run (Command "/bin/sh" (list "-c" "head -c 200000 /dev/zero") ".") #u8())
  ((Ok captured)
   (write-line (string-append (show (vector-length (Captured-stdout captured))) " bytes")))
  ((Err error) (write-line (ProcessError-code error))))
