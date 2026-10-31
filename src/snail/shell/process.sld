;; Child processes with piped standard streams, a command run to its end,
;; and replacing the program with a command. A handler can replace the
;; effect in a test. By default an operation that waits starts on the
;; native host and waits by ticket, as (snail shell socket)'s do. Stage 0's tool runner,
;; host/chibi/snail/stage0/process.sld, has the same name; Chibi never sees src/.
(define-library (snail shell process)
  (export
   process spawn read-output write-input close-input send-signal wait-exit close-process run exec
   signals termination
   Command Command-program Command-arguments Command-directory
   Process Process-token Process-id
   Stream Stdout Stderr
   Signal Terminate Kill Interrupt
   Exit Exited Signaled
   Captured Captured-exit Captured-stdout Captured-stderr
   ProcessError ProcessError-code)
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
      ((spawn (-> Command (Result Process ProcessError) ! tasks))
       (read-output (-> Process Stream I32 (Result (Option Bytes) ProcessError) ! tasks))
       (write-input (-> Process Bytes (Result I32 ProcessError) ! tasks))
       (close-input (-> Process (Result Unit ProcessError)))
       (send-signal (-> Process Signal (Result Unit ProcessError)))
       (wait-exit (-> Process (Result Exit ProcessError) ! tasks))
       (close-process (-> Process (Result Unit ProcessError)))
       (run (-> Command Bytes (Result Captured ProcessError)))
       (exec (-> Command ProcessError)))
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
      ((termination (-> Signal ! tasks)))
      (default
        ((termination (lambda ()
                        (received-signal (through-host host-start-termination host-finish)))))))

    ;; Only SIGINT (2) and SIGTERM (15) are delivered to `termination`.
    (: received-signal (-> I32 Signal))
    (define (received-signal number)
      (if (= number 2) (Interrupt) (Terminate)))

    ;; ---- Native tokens ----

    ;; Private to the native binding: a token from another handler crosses
    ;; as handle 0, which the host refuses with EBADF.
    (struct NativeProcess
      ((handle I32)))

    (: process-handle (-> Process I32))
    (define (process-handle child)
      (let ((token (Process-token child)))
        (if (type-test token NativeProcess)
            (NativeProcess-handle (type-convert token NativeProcess))
            0)))

    ;; The host reads a command a character at a time: its directory, the
    ;; program's path, the name it is run as, then its arguments.
    (: send-command (-> Command String Unit))
    (define (send-command command path)
      (for-each send-text
                (Cons (Command-directory command)
                      (Cons path (Cons (Command-program command) (Command-arguments command))))))

    (: send-text (-> String Unit))
    (define (send-text text)
      (let loop ((index 0))
        (when (< index (string-length text))
          (host-argument-character (string-ref text index))
          (loop (+ index 1))))
      (host-argument-end))

    (: stream-descriptor (-> Stream I32))
    (define (stream-descriptor stream)
      (match stream
        ((Stdout) 1)
        ((Stderr) 2)))

    ;; POSIX gives these three signals the same numbers everywhere.
    (: signal-number (-> Signal I32))
    (define (signal-number signal)
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
    (: located (-> Command (Result String ProcessError)))
    (define (located command)
      (let ((program (Command-program command)))
        (match (string-index program #\/)
          ((Some _) (Ok program))
          ((None)
           (match (find (lambda (path) (executable? (Command-directory command) path))
                        (candidates program))
             ((Some path) (Ok path))
             ((None) (Err (ProcessError "ENOENT"))))))))

    ;; Where each entry of PATH, in order, would hold `program`.
    (: candidates (-> String (List String)))
    (define (candidates program)
      (map (lambda (entry) (string-append (if (string=? entry "") "." entry) "/" program))
           (path-entries)))

    ;; PATH's entries, empty ones included.
    (: path-entries (-> (List String)))
    (define (path-entries)
      (match (environment-variable "PATH")
        ((Some text) (split-entries text))
        ((None) (Nil))))

    (: split-entries (-> String (List String)))
    (define (split-entries text)
      (match (string-index text #\:)
        ((Some index)
         (Cons (substring text 0 index)
               (split-entries (substring text (+ index 1) (string-length text)))))
        ((None) (list text))))

    ;; The host answers with access(2), which WASI lacks: whether `path`,
    ;; taken from `directory`, names a regular file this process may
    ;; execute.
    (: executable? (-> String String Bool))
    (define (executable? directory path)
      (send-text directory)
      (send-text path)
      (= (host-executable) 1))

    ;; ---- Native answers ----

    ;; As (snail shell socket) reads its answers, with the table in
    ;; (snail runtime native process).
    (: native (All (T) (-> (-> I64 Unit) (-> I32 T) (Result T ProcessError) ! tasks)))
    (define (native start success)
      (through-host start (lambda (ticket) (answered (host-finish ticket) success))))

    (: answered (All (T) (-> I32 (-> I32 T) (Result T ProcessError))))
    (define (answered answer success)
      (if (< answer 0)
          (Err (ProcessError (held-text 0)))
          (Ok (success answer))))

    (: held-bytes (-> I32 Bytes))
    (define (held-bytes position)
      (vector-generate (i32->i64 (host-held-length position))
                       (lambda (index) (i32->u8 (host-held-byte position (i64->i32 index))))))

    ;; Error codes and signal names are ASCII.
    (: held-text (-> I32 String))
    (define (held-text position)
      (string-generate (i32->i64 (host-held-length position))
                       (lambda (index) (i32->char (host-held-byte position (i64->i32 index))))))

    (: spawned (-> I32 Process))
    (define (spawned handle)
      (Process (type-convert (NativeProcess handle) Any) (host-held-number)))

    (: held-read (-> I32 (Option Bytes)))
    (define (held-read answer)
      (if (= answer 0) (None) (Some (held-bytes 0))))

    (: held-exit (-> I32 Exit))
    (define (held-exit answer)
      (if (= answer 0) (Exited (host-held-number)) (Signaled (held-text 0))))

    (: captured (-> I32 Captured))
    (define (captured answer)
      (Captured (held-exit answer) (held-bytes 1) (held-bytes 2)))

    (: count (-> I32 I32))
    (define (count written) written)

    (: done (-> I32 Unit))
    (define (done _) (unit))))
