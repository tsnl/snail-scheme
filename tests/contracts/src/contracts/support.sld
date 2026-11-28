;; What a contract test runs with and how it checks. A contract test is a
;; program that drives the command line, or a program it built, in
;; directories of its own, and ends at the first expectation that fails,
;; naming it: a panic, so its status is 1.
(define-library (contracts support)
  (export
   Context
   context
   Ran
   command
   snail
   node
   spawned
   read-until
   scratch
   put!
   text-of
   resolved
   removed!
   link!
   expect
   expect-text
   succeeded
   failed-with
   contains?
   starts-with?
   first-line
   lines)
  (import
   (snail core base)
   (snail core io)
   (snail shell utf8)
   (snail shell process))
  (begin

    ;; ---- Context ----

    ;; The repository a test checks, and the capabilities it checks with.
    (record Context
      ((root String)
       (fs Fs)
       (processes Processes)
       (environment ProcessEnvironment)))

    (define (context (arguments Arguments)
                     (fs Fs)
                     (processes Processes)
                     (environment ProcessEnvironment))
      (→ Context)
      (match (command-line arguments)
        ((Cons _ (Cons root _))
         (new Context (root root) (fs fs) (processes processes) (environment environment)))
        (_ (panic "usage: TEST ROOT"))))

    ;; ---- Commands ----

    ;; What a command printed and how it ended: its exit status, or -1 when a
    ;; signal ended it.
    (record Ran
      ((stdout String)
       (stderr String)
       (status I64)))

    ;; `program` with `arguments` in `directory`, given `input`, to its end.
    ;; The host keeps what a child writes, so its streams are read once it
    ;; has exited.
    (define (command (c Context)
                     (program String)
                     (arguments (List String))
                     (directory String)
                     (input String))
      (→ Ran)
      (let ((processes (● c processes)))
        (match ((● processes spawn)
                (new Command (program program) (arguments arguments) (directory directory)))
          ((Err error) (new Ran (stdout "") (stderr (● error code)) (status 127)))
          ((Ok child)
           ((● processes write-input) child (string->utf8 input))
           ((● processes close-input) child)
           (let* ((exit ((● processes wait-exit) child))
                  (stdout (read-all processes child (Stdout)))
                  (stderr (read-all processes child (Stderr))))
             ((● processes close-process) child)
             (new Ran (stdout stdout) (stderr stderr) (status (exit-status exit))))))))

    (define (snail (c Context) (arguments (List String)) (directory String)) (→ Ran)
      (command c (string-append (● c root) "/snail-scheme") arguments directory ""))

    (define (node (c Context) (arguments (List String)) (directory String)) (→ Ran)
      (command c "node" (Cons "--no-warnings" arguments) directory ""))

    ;; A child left running, for a test that talks to it as it runs.
    (define (spawned (c Context) (program String) (arguments (List String)) (directory String))
      (→ Process)
      (match ((● (● c processes) spawn)
              (new Command (program program) (arguments arguments) (directory directory)))
        ((Ok child) child)
        ((Err error) (panic (string-append program ": " (● error code))))))

    ;; What a running child writes to `stream` until it has written `marker`.
    (define (read-until (c Context) (child Process) (stream Stream) (marker String)) (→ String)
      (let loop ((text ""))
        (if (contains? text marker)
            text
            (match ((● (● c processes) read-output) child stream 65536)
              ((Ok (Some chunk)) (loop (string-append text (decoded chunk))))
              (_ (panic (string-append "the child ended before writing " marker ": " text)))))))

    (define (read-all (processes Processes) (child Process) (stream Stream)) (→ String)
      (let loop ((bytes #u8()))
        (match ((● processes read-output) child stream 65536)
          ((Ok (Some chunk)) (loop (array-append bytes chunk)))
          (_ (decoded bytes)))))

    (define (decoded (bytes Bytes)) (→ String)
      (match (utf8->string bytes)
        ((Ok text) text)
        ((Err _) "<output that is not UTF-8>")))

    (define (exit-status (exit (Result Exit ProcessError))) (→ I64)
      (match exit
        ((Ok (Exited code)) (i32->i64 code))
        (_ -1)))

    ;; ---- Files ----

    ;; A fresh directory of the test's own, outside the repository, so no
    ;; workspace declaration above it applies.
    (define (scratch (c Context) (name String)) (→ String)
      (let* ((temporary (match ((● (● c environment) variable) "TMPDIR")
                          ((Some directory) directory)
                          ((None) "/tmp")))
             (made
              (command c "mktemp" (list "-d" (string-append temporary "/snail-" name "-XXXXXX"))
                       "/" "")))
        (expect (= (● made status) 0) (string-append "mktemp: " (● made stderr)))
        (trimmed (● made stdout))))

    ;; `text` at `path`, with the directories above it made.
    (define (put! (c Context) (path String) (text String)) (→ Unit)
      (match (parent path)
        ((Some directory) (make-directories (● c fs) directory))
        ((None) (Ok (unit))))
      (write-file (● c fs) path text))

    (define (text-of (c Context) (path String)) (→ String)
      (read-file (● c fs) path))

    ;; The path with every symbolic link in it followed.
    (define (resolved (c Context) (path String)) (→ String)
      (let ((ran (command c "realpath" (list path) "/" "")))
        (expect (= (● ran status) 0) (string-append "realpath: " (● ran stderr)))
        (trimmed (● ran stdout))))

    ;; A symbolic link at `path` to `target`, made by the system's `ln`:
    ;; WASI refuses a link to an absolute target.
    (define (link! (c Context) (target String) (path String)) (→ Unit)
      (succeeded (command c "ln" (list "-s" target path) "/" "") "ln")
      (unit))

    (define (removed! (c Context) (path String)) (→ Unit)
      (match (remove-tree (● c fs) path)
        (_ (unit))))

    (define (parent (path String)) (→ (Option String))
      (let loop ((at (- (string-length path) 1)))
        (cond ((<= at 0) (None))
              ((char=? (string-ref path at) #\/) (Some (substring path 0 at)))
              (else (loop (- at 1))))))

    ;; ---- Expectations ----

    (define (expect (holds Bool) (what String)) (→ Unit)
      (unless holds (panic what)))

    (define (expect-text (actual String) (wanted String) (what String)) (→ Unit)
      (expect (string=? actual wanted)
              (string-append what "\n  actual: " actual "\n  wanted: " wanted)))

    ;; A command that ran to status 0, as a test expects of most.
    (define (succeeded (ran Ran) (what String)) (→ Ran)
      (expect (= (● ran status) 0) (string-append what " failed: " (● ran stderr)))
      ran)

    ;; A command that failed and said `part` on standard error.
    (define (failed-with (ran Ran) (part String) (what String)) (→ Unit)
      (expect (and (not (= (● ran status) 0)) (contains? (● ran stderr) part))
              (string-append what ": expected a failure saying " part ", got status "
                             (show (● ran status)) ": " (● ran stderr))))

    ;; ---- Text ----

    (define (contains? (text String) (part String)) (→ Bool)
      (let ((last (- (string-length text) (string-length part))))
        (let loop ((at 0))
          (cond ((> at last) #f)
                ((string=? (substring text at (+ at (string-length part))) part) #t)
                (else (loop (+ at 1)))))))

    (define (starts-with? (text String) (prefix String)) (→ Bool)
      (and (>= (string-length text) (string-length prefix))
           (string=? (substring text 0 (string-length prefix)) prefix)))

    (define (first-line (text String)) (→ String)
      (match (string-index text #\newline)
        ((Some at) (substring text 0 at))
        ((None) text)))

    (define (lines (text String)) (→ (List String))
      (match (string-index text #\newline)
        ((Some at)
         (Cons (substring text 0 at) (lines (substring text (+ at 1) (string-length text)))))
        ((None) (list text))))

    (define (trimmed (text String)) (→ String)
      (let loop ((end (string-length text)))
        (if (and (> end 0) (char-whitespace? (string-ref text (- end 1))))
            (loop (- end 1))
            (substring text 0 end))))

    ))
