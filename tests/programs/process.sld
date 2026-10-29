(import
 (snail core base)
 (snail core io)
 (only (snail shell task) tasks)
 (snail shell utf8)
 (snail shell process))

(: require (All (T) (-> (Result T ProcessError) T)))
(define (require result)
  (match result
    ((Ok value) value)
    ((Err error) (panic (ProcessError-code error)))))

(: shell (-> String Process ! process tasks))
(define (shell script)
  (require (spawn (Command "/bin/sh" (list "-c" script) "."))))

;; A stream's bytes up to its end, as text.
(: read-all (-> Process Stream String ! process tasks))
(define (read-all child stream)
  (let loop ((bytes #u8()))
    (match (require (read-output child stream 4096))
      ((Some chunk) (loop (vector-append bytes chunk)))
      ((None) (match (utf8->string bytes)
                ((Ok text) text)
                ((Err _) (panic "the output is not UTF-8")))))))

(: exit-text (-> Exit String))
(define (exit-text exit)
  (match exit
    ((Exited code) (string-append "exited " (show code)))
    ((Signaled name) (string-append "signaled " name))))

(: report-error (All (T) (requires (Copy T)) (-> (Result T ProcessError) Unit ! console)))
(define (report-error result)
  (match result
    ((Err error) (write-line (ProcessError-code error)))
    ((Ok _) (panic "the operation succeeded"))))

;; Both output streams, and the exit status, with output read after exit.
(let ((child (shell "echo out; echo err >&2; exit 3")))
  (write-line (exit-text (require (wait-exit child))))
  (write-string (read-all child (Stdout)))
  (write-string (read-all child (Stderr)))
  (write-line (if (> (Process-id child) 0) "has a process id" "has no process id"))
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
(report-error (spawn (Command "/nonexistent/program" (Nil) ".")))
(report-error (spawn (Command "/bin/sh" (list "-c" "true") "/nonexistent/directory")))

;; Closing kills a running child and revokes its handle; closing again
;; succeeds, and a token from another handler is no native handle.
(let ((child (shell "exec sleep 10")))
  (require (close-process child))
  (require (close-process child))
  (report-error (read-output child (Stdout) 1))
  (report-error (wait-exit child)))
(report-error (close-process (Process (type-convert (ann 1 I32) Any) 0)))

;; Returning from main must kill a child left running.
(shell "exec sleep 10")
