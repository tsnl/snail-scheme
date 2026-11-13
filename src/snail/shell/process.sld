;; Child processes with piped standard streams, a command run to its end,
;; and replacing the program with a command. A handler can replace the
;; effect in a test. By default an operation that waits starts on the
;; native host and waits by ticket, as (snail shell socket)'s do. Stage 0's tool runner,
;; host/chez/snail/stage0/process.sls, has the same name; Chez never sees src/.
(define-library (snail shell process)
  (export
   process spawn read-output write-input close-input send-signal wait-exit close-process run exec
   signals termination
   Command
   Process
   Stream Stdout Stderr
   Signal Terminate Kill Interrupt
   Exit Exited Signaled
   Captured
   ProcessError)
  (import
   (snail core base)
   (only (snail core io) environment-variable)
   (prefix (snail runtime native process) host-)
   (only (snail shell task) tasks through-host))
  (begin

    ;; ---- Public values ----

    ;; What to run: an executable, found on PATH when it has no slash
    ;; (Finding the program, below), its arguments after the name it is run
    ;; as, and the directory it runs in. The program is apart from the
    ;; arguments, so no command is empty.
    (struct Command
      ((program String)
       (arguments (List String))
       (directory String)))

    ;; The token belongs to the effect handler that spawned the process, as
    ;; a socket's does; `id` is the operating system's process id.
    (struct Process
      ((token Any)
       (id I32)))

    (enum Stream
      (Stdout)
      (Stderr))

    ;; The signals a program sends, and the two that end it (SIGTERM, SIGKILL,
    ;; SIGINT).
    (enum Signal
      (Terminate)
      (Kill)
      (Interrupt))

    ;; How a child ended: with an exit status, or by a signal, named as the
    ;; operating system names it, such as "SIGTERM".
    (enum Exit
      (Exited
       ((code I32)))
      (Signaled
       ((name String))))

    ;; How a command `run` waited for ended, and everything it wrote.
    (struct Captured
      ((exit Exit)
       (stdout Bytes)
       (stderr Bytes)))

    (struct ProcessError
      ((code String)))

    ;; Spawning starts the child with its three standard streams piped to
    ;; the parent. Reading gives an available prefix of at most `maximum`
    ;; bytes, or None at the end of the stream; writing gives the count
    ;; accepted. Closing a process that is still running kills it.
    ;;
    ;; `run` runs a command to its end with `input` as its standard input,
    ;; and gives how it ended and what it wrote. It blocks the program: no
    ;; task runs until the child exits, so it serves a tool that runs once,
    ;; and a service spawns instead. `exec` replaces the program with the
    ;; command, as execve does: the command takes over this process and its
    ;; standard streams, and nothing of the program runs after. It returns
    ;; only when it cannot, with why.
    (effect process
      ((spawn (Fn Command → (Result Process ProcessError) ! tasks))
       (read-output (Fn Process Stream I32 → (Result (Option Bytes) ProcessError) ! tasks))
       (write-input (Fn Process Bytes → (Result I32 ProcessError) ! tasks))
       (close-input (Fn Process → (Result Unit ProcessError)))
       (send-signal (Fn Process Signal → (Result Unit ProcessError)))
       (wait-exit (Fn Process → (Result Exit ProcessError) ! tasks))
       (close-process (Fn Process → (Result Unit ProcessError)))
       (run (Fn Command Bytes → (Result Captured ProcessError)))
       (exec (Fn Command → ProcessError)))
      (default
        ((spawn (lambda (command)
                  (match (located command)
                    ((Ok path)
                     (send-command command path)
                     (native host-start-spawn spawned))
                    ((Err error) (Err error)))))
         ;; A read takes 1 to 65,536 bytes, which the host takes as given.
         (read-output (lambda (child stream maximum)
                        (if (and (>= maximum 1) (<= maximum 65536))
                            (native (lambda (ticket)
                                      (host-start-read-output ticket
                                                              (process-handle child)
                                                              (stream-descriptor stream)
                                                              maximum))
                                    held-read)
                            (Err (ProcessError "EINVAL")))))
         (write-input (lambda (child bytes)
                        (native (lambda (ticket)
                                  (host-start-write-input ticket (process-handle child) bytes))
                                count)))
         (close-input (lambda (child)
                        (answered (host-close-input (process-handle child)) done)))
         (send-signal (lambda (child signal)
                        (answered (host-send-signal (process-handle child) (signal-number signal))
                                  done)))
         (wait-exit (lambda (child)
                      (native (lambda (ticket) (host-start-wait-exit ticket (process-handle child)))
                              held-exit)))
         (close-process (lambda (child)
                          (answered (host-close-process (process-handle child)) done)))
         (run (lambda (command input)
                (match (located command)
                  ((Ok path)
                   (send-command command path)
                   (answered (host-run input) captured))
                  ((Err error) (Err error)))))
         (exec (lambda (command)
                 (match (located command)
                   ((Ok path)
                    (send-command command path)
                    (host-exec)
                    (ProcessError (held-text 0)))
                   ((Err error) error)))))))

    ;; ---- Termination ----

    ;; SIGINT and SIGTERM, as values the program can wait for. A program
    ;; opts in by waiting: a signal that arrives while tasks wait in
    ;; `termination` is the result of every such wait, (Interrupt) or
    ;; (Terminate), and one that arrives while none waits ends the program
    ;; as it always has. A wait ends with its signal, so a second signal
    ;; during an orderly shutdown still ends the program at once, unless a
    ;; task waits again.
    (effect signals
      ((termination (Fn → Signal ! tasks)))
      (default
        ((termination (lambda ()
                        (received-signal (through-host host-start-termination host-finish)))))))

    ;; Only SIGINT (2) and SIGTERM (15) are delivered to `termination`.

    (define (received-signal (number I32)) (→ Signal)
      (if (= number 2) (Interrupt) (Terminate)))

    ;; ---- Native tokens ----

    ;; Private to the native binding: a token from another handler crosses
    ;; as handle 0, which the host refuses with EBADF.
    (struct NativeProcess
      ((handle I32)))

    (define (process-handle (child Process)) (→ I32)
      (let ((token (● child token)))
        (match (try-convert token NativeProcess)
          ((Ok native) (● native handle))
          ((Err _) 0))))

    ;; The host reads a command a character at a time: its directory, the
    ;; program's path, the name it is run as, then its arguments.

    (define (send-command (command Command) (path String)) (→ Unit)
      (for-each send-text
                (Cons (● command directory)
                      (Cons path (Cons (● command program) (● command arguments))))))

    (define (send-text (text String)) (→ Unit)
      (let loop ((index 0))
        (when (< index (string-length text))
          (host-argument-character (string-ref text index))
          (loop (+ index 1))))
      (host-argument-end))

    (define (stream-descriptor (stream Stream)) (→ I32)
      (match stream
        ((Stdout) 1)
        ((Stderr) 2)))

    ;; POSIX gives these three signals the same numbers everywhere.

    (define (signal-number (signal Signal)) (→ I32)
      (match signal
        ((Terminate) 15)
        ((Kill) 9)
        ((Interrupt) 2)))

    ;; ---- Finding the program ----

    ;; A program with a slash is its own path. One without is found on
    ;; PATH, as execvp finds it: in the first entry holding a regular file
    ;; this process may execute, where an empty entry is the command's
    ;; directory and a relative one is taken from that directory, as the
    ;; child takes it. With no PATH, nothing is found. Finding it here gives
    ;; spawn, run and exec one rule, and the host runs the path it is given.

    (define (located (command Command)) (→ (Result String ProcessError))
      (let ((program (● command program)))
        (match (string-index program #\/)
          ((Some _) (Ok program))
          ((None)
           (match (find (lambda (path) (executable? (● command directory) path))
                        (candidates program))
             ((Some path) (Ok path))
             ((None) (Err (ProcessError "ENOENT"))))))))

    ;; Where each entry of PATH, in order, would hold `program`.

    (define (candidates (program String)) (→ (List String))
      (map (lambda (entry) (string-append (if (string=? entry "") "." entry) "/" program))
           (path-entries)))

    ;; PATH's entries, empty ones included.

    (define (path-entries) (→ (List String))
      (match (environment-variable "PATH")
        ((Some text) (split-entries text))
        ((None) (Nil))))

    (define (split-entries (text String)) (→ (List String))
      (match (string-index text #\:)
        ((Some index)
         (Cons (substring text 0 index)
               (split-entries (substring text (+ index 1) (string-length text)))))
        ((None) (list text))))

    ;; The host answers with access(2), which WASI lacks: whether `path`,
    ;; taken from `directory`, names a regular file this process may
    ;; execute.

    (define (executable? (directory String) (path String)) (→ Bool)
      (send-text directory)
      (send-text path)
      (= (host-executable) 1))

    ;; ---- Native answers ----

    ;; As (snail shell socket) reads its answers, with the table in
    ;; (snail runtime native process).

    (define (native (start (Fn I64 → Unit)) (success (Fn I32 → T)))
      (→ (Result T ProcessError))
      (! tasks)
      (∀ T)
      (through-host start (lambda (ticket) (answered (host-finish ticket) success))))

    (define (answered (answer I32) (success (Fn I32 → T))) (→ (Result T ProcessError)) (∀ T)
      (if (< answer 0)
          (Err (ProcessError (held-text 0)))
          (Ok (success answer))))

    (define (held-bytes (position I32)) (→ Bytes)
      (vector-generate (i32->i64 (host-held-length position))
                       (lambda (index) (i32->u8 (host-held-byte position (i64->i32 index))))))

    ;; Error codes and signal names are ASCII.

    (define (held-text (position I32)) (→ String)
      (string-generate (i32->i64 (host-held-length position))
                       (lambda (index) (i32->char (host-held-byte position (i64->i32 index))))))

    (define (spawned (handle I32)) (→ Process)
      (Process (type-convert (NativeProcess handle) Any) (host-held-number)))

    (define (held-read (answer I32)) (→ (Option Bytes))
      (if (= answer 0) (None) (Some (held-bytes 0))))

    (define (held-exit (answer I32)) (→ Exit)
      (if (= answer 0) (Exited (host-held-number)) (Signaled (held-text 0))))

    (define (captured (answer I32)) (→ Captured)
      (Captured (held-exit answer) (held-bytes 1) (held-bytes 2)))

    (define (count (written I32)) (→ I32) written)

    (define (done (_ I32)) (→ Unit) (unit))))
