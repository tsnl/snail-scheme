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
   (only (snail shell task) tasks through-host))
  (begin

    ;; ---- Public values ----

    ;; What to run: an executable, found on PATH when it has no slash, its
    ;; arguments after the name it is run as, and the directory it runs in.
    ;; The program is apart from the arguments, so no command is empty.
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
      (host "snail.runtime.native.process"
            ((close-input "close-input")
             (send-signal "send-signal")
             (close-process "close-process")
             (run "run")
             (exec "exec")))
      (default
        ((spawn (lambda (command)
                  (through-host (lambda (ticket) (start-spawn ticket command)) finish-spawn)))
         (read-output (lambda (child stream maximum)
                        (through-host
                         (lambda (ticket) (start-read-output ticket child stream maximum))
                         finish-read-output)))
         (write-input (lambda (child bytes)
                        (through-host (lambda (ticket) (start-write-input ticket child bytes))
                                      finish-write-input)))
         (wait-exit (lambda (child)
                      (through-host (lambda (ticket) (start-wait-exit ticket child))
                                    finish-wait-exit))))))

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
        ((termination (lambda () (through-host start-termination finish-termination))))))

    ;; ---- Native waits ----

    ;; Each operation that waits starts on the host and finishes with the
    ;; result the host built for its ticket, as (snail shell socket)'s do.
    (extern start-spawn "snail.runtime.native.process" "start-spawn" (-> I64 Command Unit))
    (extern finish-spawn
            "snail.runtime.native.process"
            "finish-spawn"
            (-> I64 (Result Process ProcessError)))
    (extern start-read-output
            "snail.runtime.native.process"
            "start-read-output"
            (-> I64 Process Stream I32 Unit))
    (extern finish-read-output
            "snail.runtime.native.process"
            "finish-read-output"
            (-> I64 (Result (Option Bytes) ProcessError)))
    (extern start-write-input
            "snail.runtime.native.process"
            "start-write-input"
            (-> I64 Process Bytes Unit))
    (extern finish-write-input
            "snail.runtime.native.process"
            "finish-write-input"
            (-> I64 (Result I32 ProcessError)))
    (extern start-wait-exit "snail.runtime.native.process" "start-wait-exit" (-> I64 Process Unit))
    (extern finish-wait-exit
            "snail.runtime.native.process"
            "finish-wait-exit"
            (-> I64 (Result Exit ProcessError)))
    (extern start-termination "snail.runtime.native.process" "start-termination" (-> I64 Unit))
    (extern finish-termination "snail.runtime.native.process" "finish-termination" (-> I64 Signal))

    ;; ---- Native tokens ----

    ;; Private to the native binding: a token from another handler reaching
    ;; it becomes EBADF instead of being cast to a native handle.
    (struct NativeProcess
      ((handle I32)))

    (: process-handle (-> Process I32))
    (define (process-handle child)
      (let ((token (Process-token child)))
        (if (type-test token NativeProcess)
            (NativeProcess-handle (type-convert token NativeProcess))
            0)))

    ;; The host reads a command a character at a time: its directory, its
    ;; program, then its arguments.
    (: command-parts (-> Command (Vector String)))
    (define (command-parts command)
      (list->vector (Cons (Command-directory command)
                          (Cons (Command-program command) (Command-arguments command)))))

    (: part-count (-> (Vector String) I32))
    (define (part-count parts)
      (i64->i32 (vector-length parts)))

    (: part-length (-> (Vector String) I32 I32))
    (define (part-length parts part)
      (i64->i32 (string-length (vector-ref parts (i32->i64 part)))))

    (: part-character (-> (Vector String) I32 I32 Char))
    (define (part-character parts part index)
      (string-ref (vector-ref parts (i32->i64 part)) (i32->i64 index)))

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

    (expose process-handle "process:handle")
    (expose command-parts "process:command-parts")
    (expose part-count "process:part-count")
    (expose part-length "process:part-length")
    (expose part-character "process:part-character")
    (expose stream-descriptor "process:stream-descriptor")
    (expose signal-number "process:signal-number")

    ;; Only SIGINT (2) and SIGTERM (15) are delivered to `termination`.
    (: received-signal (-> I32 Signal))
    (define (received-signal number)
      (if (= number 2) (Interrupt) (Terminate)))

    (expose received-signal "process:received-signal")

    ;; ---- Host result construction ----

    ;; JavaScript carries GC references opaquely. These synchronous helpers
    ;; run only inside a finish, which the waiting task calls.
    (: buffer (-> I32 (Array U8) ! mut))
    (define (buffer count)
      (make-array (i32->i64 count) (i32->u8 0)))

    (: put! (-> (Array U8) I32 I32 Unit ! mut))
    (define (put! target index byte)
      (array-set! target (i32->i64 index) (i32->u8 byte)))

    (: ascii-text (-> (Array U8) String ! mut))
    (define (ascii-text bytes)
      (string-generate (array-length bytes)
                       (lambda (index) (i32->char (u8->i32 (array-ref bytes index))))))

    (: error-code (-> (Array U8) ProcessError ! mut))
    (define (error-code bytes)
      (ProcessError (ascii-text bytes)))

    (: spawned (-> I32 I32 (Result Process ProcessError)))
    (define (spawned handle id)
      (Ok (Process (type-convert (NativeProcess handle) Any) id)))

    (: received (-> (Array U8) (Result (Option Bytes) ProcessError) ! mut))
    (define (received bytes)
      (Ok (Some (array->vector bytes))))

    (: eof (-> (Result (Option Bytes) ProcessError)))
    (define (eof)
      (Ok (None)))

    (: written (-> I32 (Result I32 ProcessError)))
    (define (written count)
      (Ok count))

    (: done (-> (Result Unit ProcessError)))
    (define (done)
      (Ok (unit)))

    (: exited (-> I32 (Result Exit ProcessError)))
    (define (exited code)
      (Ok (Exited code)))

    (: signaled (-> (Array U8) (Result Exit ProcessError) ! mut))
    (define (signaled name)
      (Ok (Signaled (ascii-text name))))

    ;; A command `run` waited for: its exit status, or, when `code` is -1,
    ;; the signal `signal` names, and what it wrote.
    (: captured (-> I32 (Array U8) (Array U8) (Array U8) (Result Captured ProcessError) ! mut))
    (define (captured code signal stdout stderr)
      (Ok (Captured (if (< code 0) (Signaled (ascii-text signal)) (Exited code))
                    (array->vector stdout)
                    (array->vector stderr))))

    ;; Each Result has its own concrete Wasm type, including its Err variant.
    (: spawn-error (-> ProcessError (Result Process ProcessError)))
    (define (spawn-error error) (Err error))

    (: read-error (-> ProcessError (Result (Option Bytes) ProcessError)))
    (define (read-error error) (Err error))

    (: write-error (-> ProcessError (Result I32 ProcessError)))
    (define (write-error error) (Err error))

    (: unit-error (-> ProcessError (Result Unit ProcessError)))
    (define (unit-error error) (Err error))

    (: exit-error (-> ProcessError (Result Exit ProcessError)))
    (define (exit-error error) (Err error))

    (: run-error (-> ProcessError (Result Captured ProcessError)))
    (define (run-error error) (Err error))

    (expose buffer "process:buffer")
    (expose put! "process:put")
    (expose error-code "process:error-code")
    (expose spawned "process:spawned")
    (expose received "process:received")
    (expose eof "process:eof")
    (expose written "process:written")
    (expose done "process:done")
    (expose exited "process:exited")
    (expose signaled "process:signaled")
    (expose captured "process:captured")
    (expose spawn-error "process:spawn-error")
    (expose read-error "process:read-error")
    (expose write-error "process:write-error")
    (expose unit-error "process:unit-error")
    (expose exit-error "process:exit-error")
    (expose run-error "process:run-error")))
