(import
 (snail core base)
 (snail core io)
 (only (snail shell task) dispatch)
 (snail shell utf8)
 (snail shell process))

(define (require (result (Result T ProcessError))) (→ T) (∀ (T))
  (match result
    ((Ok value) value)
    ((Err error) (panic (● error code)))))

(define (shell (processes Processes) (script String)) (→ Process)
  (require
   (processes::spawn
    (new Command (program "/bin/sh") (arguments (list "-c" script)) (directory ".")))))

;; A stream's bytes up to its end, as text.
(define (read-all (processes Processes) (child Process) (stream Stream)) (→ String)
  (let loop ((bytes #u8()))
    (match (require (processes::read-output child stream 4096))
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
  (∀ (T))
  (match result
    ((Err error) (write-line out (● error code)))
    ((Ok _) (panic "the operation succeeded"))))

(define (main (processes Processes) (out OutputPort)) (→ Unit)

  ;; A program waits on processes from a task, which the scheduler runs once
  ;; main returns.
  ;; Both output streams, and the exit status, with output read after exit.
  (dispatch
   (lambda ()
     (let ((child (shell processes "echo out; echo err >&2; exit 3")))
       (write-line out (exit-text (require (processes::wait-exit child))))
       (out::write-string (read-all processes child (Stdout)))
       (out::write-string (read-all processes child (Stderr)))
       (write-line out (if (> (● child id) 0) "has a process id" "has no process id"))
       (require (processes::close-process child)))

     ;; Input echoed back once it is closed.
     (let ((child (shell processes "cat")))
       (display out (require (processes::write-input child (string->utf8 "echoed back\n"))))
       (newline out)
       (require (processes::close-input child))
       (out::write-string (read-all processes child (Stdout)))
       (write-line out (exit-text (require (processes::wait-exit child))))
       (report-error out (processes::write-input child #u8(1)))
       (require (processes::close-process child)))

     ;; Signals end a sleep; one sent after it has exited reaches nothing.
     (let ((terminated (shell processes "exec sleep 10"))
           (killed (shell processes "exec sleep 10")))
       (require (processes::send-signal terminated (Terminate)))
       (require (processes::send-signal killed (Kill)))
       (write-line out (exit-text (require (processes::wait-exit terminated))))
       (write-line out (exit-text (require (processes::wait-exit killed))))
       (report-error out (processes::send-signal terminated (Interrupt)))
       (require (processes::close-process terminated))
       (require (processes::close-process killed)))

     ;; A missing executable or directory is an error, not a process.
     (report-error out (processes::spawn (new Command
                                           (program "/nonexistent/program")
                                           (arguments (Nil))
                                           (directory "."))))
     (report-error out (processes::spawn (new Command
                                           (program "/bin/sh")
                                           (arguments (list "-c" "true"))
                                           (directory "/nonexistent/directory"))))

     ;; A program with no slash is found on PATH and runs as the name it
     ;; was given, in its directory; one PATH lacks is missing too.
     (let ((child (require (processes::spawn (new Command
                                               (program "sh")
                                               (arguments (list "-c" "echo $0; pwd"))
                                               (directory "/"))))))
       (out::write-string (read-all processes child (Stdout)))
       (write-line out (exit-text (require (processes::wait-exit child))))
       (require (processes::close-process child)))
     (report-error out (processes::spawn (new Command
                                           (program "no-such-program-on-path")
                                           (arguments (Nil))
                                           (directory "."))))

     ;; Closing kills a running child and revokes its handle; closing again
     ;; succeeds, and a token from another handler is no native handle.
     (let ((child (shell processes "exec sleep 10")))
       ;; A read takes 1 to 65,536 bytes.
       (report-error out (processes::read-output child (Stdout) 0))
       (require (processes::close-process child))
       (require (processes::close-process child))
       (report-error out (processes::read-output child (Stdout) 1))
       (report-error out (processes::wait-exit child)))
     (report-error out (processes::close-process (new Process (token (Any (ann 1 I32))) (id 0))))

     ;; Ending the program must kill a child left running.
     (shell processes "exec sleep 10")
     (unit)))
  (unit))
