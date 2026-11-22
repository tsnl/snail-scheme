(import
 (snail core base)
 (only (snail core forms) host)
 (snail core io)
 (only (snail shell task) tasks dispatch)
 (snail shell utf8)
 (snail shell process))

(define (require (result (Result T ProcessError))) (→ T) (∀ (T))
  (match result
    ((Ok value) value)
    ((Err error) (panic (● error code)))))

(define (shell (processes Processes) (script String)) (→ Process) (! mut tasks)
  (require
   (spawn processes (new Command (program "/bin/sh") (arguments (list "-c" script)) (directory ".")))))

;; A stream's bytes up to its end, as text.
(define (read-all (processes Processes) (child Process) (stream Stream)) (→ String) (! mut tasks)
  (let loop ((bytes #u8()))
    (match (require (read-output processes child stream 4096))
      ((Some chunk) (loop (array-append bytes chunk)))
      ((None) (match (utf8->string bytes)
                ((Ok text) text)
                ((Err _) (panic "the output is not UTF-8")))))))

(define (exit-text (exit Exit)) (→ String)
  (match exit
    ((Exited code) (string-append "exited " (show code)))
    ((Signaled name) (string-append "signaled " name))))

(define (report-error (out OutputPort) (result (Result T ProcessError)))
  (→ Unit)
  (! mut)
  (∀ (T))
  (match result
    ((Err error) (write-line out (● error code)))
    ((Ok _) (panic "the operation succeeded"))))

(define (main (processes Processes) (out OutputPort)) (→ Unit) (! host mut tasks)

  ;; A program waits on processes from a task, which the scheduler runs once
  ;; main returns.
  ;; Both output streams, and the exit status, with output read after exit.
  (dispatch
   (lambda ()
     (let ((child (shell processes "echo out; echo err >&2; exit 3")))
       (write-line out (exit-text (require (wait-exit processes child))))
       (write-string out (read-all processes child (Stdout)))
       (write-string out (read-all processes child (Stderr)))
       (write-line out (if (> (● child id) 0) "has a process id" "has no process id"))
       (require (close-process processes child)))

     ;; Input echoed back once it is closed.
     (let ((child (shell processes "cat")))
       (display out (require (write-input processes child (string->utf8 "echoed back\n"))))
       (newline out)
       (require (close-input processes child))
       (write-string out (read-all processes child (Stdout)))
       (write-line out (exit-text (require (wait-exit processes child))))
       (report-error out (write-input processes child #u8(1)))
       (require (close-process processes child)))

     ;; Signals end a sleep; one sent after it has exited reaches nothing.
     (let ((terminated (shell processes "exec sleep 10"))
           (killed (shell processes "exec sleep 10")))
       (require (send-signal processes terminated (Terminate)))
       (require (send-signal processes killed (Kill)))
       (write-line out (exit-text (require (wait-exit processes terminated))))
       (write-line out (exit-text (require (wait-exit processes killed))))
       (report-error out (send-signal processes terminated (Interrupt)))
       (require (close-process processes terminated))
       (require (close-process processes killed)))

     ;; A missing executable or directory is an error, not a process.
     (report-error out (spawn processes (new Command
                            (program "/nonexistent/program")
                            (arguments (Nil))
                            (directory "."))))
     (report-error out (spawn processes (new Command
                            (program "/bin/sh")
                            (arguments (list "-c" "true"))
                            (directory "/nonexistent/directory"))))

     ;; A program with no slash is found on PATH and runs as the name it
     ;; was given, in its directory; one PATH lacks is missing too.
     (let ((child (require (spawn processes (new Command
                                    (program "sh")
                                    (arguments (list "-c" "echo $0; pwd"))
                                    (directory "/"))))))
       (write-string out (read-all processes child (Stdout)))
       (write-line out (exit-text (require (wait-exit processes child))))
       (require (close-process processes child)))
     (report-error out (spawn processes (new Command
                            (program "no-such-program-on-path")
                            (arguments (Nil))
                            (directory "."))))

     ;; Closing kills a running child and revokes its handle; closing again
     ;; succeeds, and a token from another handler is no native handle.
     (let ((child (shell processes "exec sleep 10")))
       ;; A read takes 1 to 65,536 bytes.
       (report-error out (read-output processes child (Stdout) 0))
       (require (close-process processes child))
       (require (close-process processes child))
       (report-error out (read-output processes child (Stdout) 1))
       (report-error out (wait-exit processes child)))
     (report-error out (close-process processes (new Process (token (Any (ann 1 I32))) (id 0))))

     ;; Ending the program must kill a child left running.
     (shell processes "exec sleep 10")
     (unit)))
  (unit))
