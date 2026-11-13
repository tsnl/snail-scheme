(import
 (snail core base)
 (only (snail core forms) host)
 (snail core io)
 (only (snail shell task) tasks dispatch-local)
 (snail shell utf8)
 (snail shell process))

(define (require (result (Result T ProcessError))) (→ T) (∀ (T))
  (match result
    ((Ok value) value)
    ((Err error) (panic (● error code)))))

(define (shell (script String)) (→ Process) (! process tasks)
  (require
   (spawn (new Command (program "/bin/sh") (arguments (list "-c" script)) (directory ".")))))

;; A stream's bytes up to its end, as text.
(define (read-all (child Process) (stream Stream)) (→ String) (! process tasks)
  (let loop ((bytes #u8()))
    (match (require (read-output child stream 4096))
      ((Some chunk) (loop (vector-append bytes chunk)))
      ((None) (match (utf8->string bytes)
                ((Ok text) text)
                ((Err _) (panic "the output is not UTF-8")))))))

(define (exit-text (exit Exit)) (→ String)
  (match exit
    ((Exited code) (string-append "exited " (show code)))
    ((Signaled name) (string-append "signaled " name))))

(define (report-error (result (Result T ProcessError)))
  (→ Unit)
  (! output-port)
  (∀ (T))
  (⊨ (Copy T) (Drop (!) T))
  (match result
    ((Err error) (write-line (● error code)))
    ((Ok _) (panic "the operation succeeded"))))

(define (main) (→ Unit) (! host mut output-port process tasks)

  ;; A program waits on processes from a task, which the scheduler runs once
  ;; main returns.
  ;; Both output streams, and the exit status, with output read after exit.
  (dispatch-local
   (once (lambda ()
           (let ((child (shell "echo out; echo err >&2; exit 3")))
             (write-line (exit-text (require (wait-exit child))))
             (write-string (read-all child (Stdout)))
             (write-string (read-all child (Stderr)))
             (write-line (if (> (● child id) 0) "has a process id" "has no process id"))
             (require (close-process child)))

           ;; Input echoed back once it is closed.
           (let ((child (shell "cat")))
             (display (require (write-input child (string->utf8 "echoed back\n"))))
             (newline)
             (require (close-input child))
             (write-string (read-all child (Stdout)))
             (write-line (exit-text (require (wait-exit child))))
             (report-error (write-input child #u8(1)))
             (require (close-process child)))

           ;; Signals end a sleep; one sent after it has exited reaches nothing.
           (let ((terminated (shell "exec sleep 10"))
                 (killed (shell "exec sleep 10")))
             (require (send-signal terminated (Terminate)))
             (require (send-signal killed (Kill)))
             (write-line (exit-text (require (wait-exit terminated))))
             (write-line (exit-text (require (wait-exit killed))))
             (report-error (send-signal terminated (Interrupt)))
             (require (close-process terminated))
             (require (close-process killed)))

           ;; A missing executable or directory is an error, not a process.
           (report-error (spawn (new Command
                                  (program "/nonexistent/program")
                                  (arguments (Nil))
                                  (directory "."))))
           (report-error (spawn (new Command
                                  (program "/bin/sh")
                                  (arguments (list "-c" "true"))
                                  (directory "/nonexistent/directory"))))

           ;; A program with no slash is found on PATH and runs as the name it
           ;; was given, in its directory; one PATH lacks is missing too.
           (let ((child (require (spawn (new Command
                                          (program "sh")
                                          (arguments (list "-c" "echo $0; pwd"))
                                          (directory "/"))))))
             (write-string (read-all child (Stdout)))
             (write-line (exit-text (require (wait-exit child))))
             (require (close-process child)))
           (report-error (spawn (new Command
                                  (program "no-such-program-on-path")
                                  (arguments (Nil))
                                  (directory "."))))

           ;; Closing kills a running child and revokes its handle; closing again
           ;; succeeds, and a token from another handler is no native handle.
           (let ((child (shell "exec sleep 10")))
             ;; A read takes 1 to 65,536 bytes.
             (report-error (read-output child (Stdout) 0))
             (require (close-process child))
             (require (close-process child))
             (report-error (read-output child (Stdout) 1))
             (report-error (wait-exit child)))
           (report-error (close-process (new Process (token (Any (ann 1 I32))) (id 0))))

           ;; Ending the program must kill a child left running.
           (shell "exec sleep 10")
           (unit))))
  (unit))
