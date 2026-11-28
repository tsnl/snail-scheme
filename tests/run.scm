;; The test suite, after the compiler's unit tests (tests/unit.scm, on
;; Chez): every program is built by ./snail-scheme, as a user's is, and run
;; on its host.
;;
;;   ./snail-scheme run --target node tests/run.scm ROOT [NAME ...]
;;
;; - A program NAME.sld of a suite must print NAME.out exactly, its standard
;;   output and then its standard error, or fail to build with each line of
;;   NAME.err in its diagnostics, in order. NAME.in supplies standard input
;;   when present.
;; - Checks: a fixture built and handed to its check script, the command
;;   line's own contracts, and the suites that are scripts already.
;;
;; With names, only the programs so named run. Programs build and run eight
;; at a time, each a task waiting on its child processes. Every build's
;; output is removed first, so nothing here grows. A failed run panics, so
;; its status is 1.
(import
 (snail core base)
 (snail core io)
 (only (snail shell task) dispatch Mailbox make-mailbox mailbox-post mailbox-receive)
 (snail shell utf8)
 (snail shell process))

;; ---- Commands ----

;; Where the suite runs, and what it runs with.
(record Suite
  ((root String)
   (fs Fs)
   (processes Processes)
   (out OutputPort)))

;; What a command printed and how it ended: its exit status, or -1 when a
;; signal ended it.
(record Ran
  ((stdout String)
   (stderr String)
   (status I64)))

(define (path (suite Suite) (relative String)) (→ String)
  (string-append (● suite root) "/" relative))

;; `program` run in the root with `arguments`, given `input`. The host
;; keeps what a child writes, so its streams are read once it has exited.
(define (command (suite Suite) (program String) (arguments (List String)) (input Bytes)) (→ Ran)
  (let ((processes (● suite processes)))
    (match ((● processes spawn)
            (new Command (program program) (arguments arguments) (directory (● suite root))))
      ((Err error) (new Ran (stdout "") (stderr (● error code)) (status 127)))
      ((Ok child)
       (write-all processes child input)
       ((● processes close-input) child)
       (let* ((exit ((● processes wait-exit) child))
              (stdout (read-all processes child (Stdout)))
              (stderr (read-all processes child (Stderr))))
         ((● processes close-process) child)
         (new Ran (stdout stdout) (stderr stderr) (status (exit-status exit))))))))

(define (write-all (processes Processes) (child Process) (bytes Bytes)) (→ Unit)
  (unless (= (array-length bytes) 0)
    (match ((● processes write-input) child bytes)
      ((Ok count)
       (write-all processes child (subarray bytes (i32->i64 count) (array-length bytes))))
      ((Err _) (unit)))))

;; A stream's bytes up to its end, as text; bytes that are not UTF-8 are
;; reported as such, which no expected output contains.
(define (read-all (processes Processes) (child Process) (stream Stream)) (→ String)
  (let loop ((bytes #u8()))
    (match ((● processes read-output) child stream 65536)
      ((Ok (Some chunk)) (loop (array-append bytes chunk)))
      (_ (match (utf8->string bytes)
           ((Ok text) text)
           ((Err _) "<output that is not UTF-8>"))))))

(define (exit-status (exit (Result Exit ProcessError))) (→ I64)
  (match exit
    ((Ok (Exited code)) (i32->i64 code))
    (_ -1)))

(define (printed (ran Ran)) (→ String)
  (string-append (● ran stdout) (● ran stderr)))

(define (snail (suite Suite) (arguments (List String))) (→ Ran)
  (command suite (path suite "snail-scheme") arguments #u8()))

(define (node (suite Suite) (arguments (List String)) (input Bytes)) (→ Ran)
  (command suite "node" (Cons "--no-warnings" arguments) input))

;; Builds `source`, a path from the root, for `target`: its module's path,
;; or the failure's text.
(define (build (suite Suite) (source String) (target String)) (→ (Result String String))
  (let ((built (snail suite (list "build" "--target" target source))))
    (if (= (● built status) 0)
        (Ok (string-append (trimmed (● built stdout)) "/" (base-name source) ".wasm"))
        (Err (● built stderr)))))

;; Runs a built module on Node, as `snail-scheme run` would.
(define (run-module (suite Suite) (module String) (arguments (List String)) (input Bytes)) (→ Ran)
  (node suite (Cons (path suite "host/native/run-snail.mjs") (Cons module arguments)) input))

;; ---- Text ----

;; A path's last part without its extension.
(define (base-name (file String)) (→ String)
  (let* ((name (last-part file #\/))
         (dot (last-index name #\.)))
    (match dot
      ((Some at) (substring name 0 at))
      ((None) name))))

(define (last-part (text String) (separator Char)) (→ String)
  (match (last-index text separator)
    ((Some at) (substring text (+ at 1) (string-length text)))
    ((None) text)))

(define (last-index (text String) (char Char)) (→ (Option I64))
  (let loop ((at (- (string-length text) 1)))
    (cond ((< at 0) (None))
          ((char=? (string-ref text at) char) (Some at))
          (else (loop (- at 1))))))

(define (trimmed (text String)) (→ String)
  (let loop ((end (string-length text)))
    (if (and (> end 0) (char-whitespace? (string-ref text (- end 1))))
        (loop (- end 1))
        (substring text 0 end))))

;; Where `part` first occurs in `text` at or after `from`.
(define (search (text String) (part String) (from I64)) (→ (Option I64))
  (let ((last (- (string-length text) (string-length part))))
    (let loop ((at from))
      (cond ((> at last) (None))
            ((string=? (substring text at (+ at (string-length part))) part) (Some at))
            (else (loop (+ at 1)))))))

(define (contains-in-order? (text String) (parts (List String))) (→ Bool)
  (let loop ((parts parts) (from 0))
    (match parts
      ((Nil) #t)
      ((Cons part rest)
       (match (search text part from)
         ((Some at) (loop rest (+ at (string-length part))))
         ((None) #f))))))

(define (lines (text String)) (→ (List String))
  (match (string-index text #\newline)
    ((Some at) (Cons (substring text 0 at) (lines (substring text (+ at 1) (string-length text)))))
    ((None) (if (string=? text "") (Nil) (list text)))))

(define (has-suffix? (text String) (suffix String)) (→ Bool)
  (and (>= (string-length text) (string-length suffix))
       (string=?
        (substring text (- (string-length text) (string-length suffix)) (string-length text))
        suffix)))

;; ---- Reporting ----

(define (fail (suite Suite) (name String) (problem String) (detail String)) (→ Bool)
  (write-line (● suite out) (string-append "FAIL " name ": " problem "\n" detail))
  #f)

(define (read-text (suite Suite) (relative String)) (→ String)
  (read-file (● suite fs) (path suite relative)))

(define (exists? (suite Suite) (relative String)) (→ Bool)
  (file-exists? (● suite fs) (path suite relative)))

;; ---- Programs ----

(define (program (suite Suite) (directory String) (name String)) (→ Bool)
  (let* ((base (string-append directory "/" name))
         (built (build suite (string-append base ".sld") "node")))
    (if (exists? suite (string-append base ".err"))
        (diagnosed suite name built (read-text suite (string-append base ".err")))
        (match built
          ((Err failure) (fail suite name "compile failed" failure))
          ((Ok module) (printed-as-expected suite name base module))))))

(define (diagnosed (suite Suite) (name String) (built (Result String String)) (wanted String))
  (→ Bool)
  (match built
    ((Ok _) (fail suite name "compiled, but a diagnostic was expected" ""))
    ((Err failure)
     (or (contains-in-order? failure (lines wanted))
         (fail suite name "wrong diagnostic" (string-append failure "\nexpected: " wanted))))))

(define (printed-as-expected (suite Suite) (name String) (base String) (module String)) (→ Bool)
  (if (not (exists? suite (string-append base ".out")))
      (fail suite name "no expected output" "")
      (let* ((input (if (exists? suite (string-append base ".in"))
                        (read-bytes (● suite fs) (path suite (string-append base ".in")))
                        #u8()))
             (output (printed (run-module suite module (Nil) input)))
             (wanted (read-text suite (string-append base ".out"))))
        (or (string=? output wanted)
            (fail suite name "wrong output" (string-append output "\nexpected:\n" wanted))))))

;; The programs of a suite directory, named by `selected` when it names any.
(define (programs (suite Suite) (directory String) (selected (List String))) (→ (List (Fn → Bool)))
  (let* ((files (match (list-directory (● suite fs) (path suite directory))
                  ((Ok files) files)
                  ((Err _) (Nil))))
         (names (list-sort string<?
                           (map (lambda (file) (substring file 0 (- (string-length file) 4)))
                                (filter (lambda (file) (has-suffix? file ".sld")) files)))))
    (map (lambda (name) (lambda () (program suite directory name)))
         (filter (lambda (name) (or (null? selected) (member? name selected))) names))))

;; ---- Checks ----

;; A fixture built for `target` and handed to a script, which fails by its
;; status.
(define (fixture (suite Suite) (name String) (source String) (script String) (target String))
  (→ (Fn → Bool))
  (lambda ()
    (match (build suite source target)
      ((Err failure) (fail suite name "compile failed" failure))
      ((Ok module)
       (let ((checked (node suite (list (path suite script) module) #u8())))
         (or (= (● checked status) 0) (fail suite name "failed" (printed checked))))))))

;; A suite that is a script already, given the root.
(define (script (suite Suite) (name String) (flags (List String))) (→ (Fn → Bool))
  (lambda ()
    (let ((ran (node suite
                     (append flags
                             (list (path suite (string-append "tests/" name ".mjs"))
                                   (● suite root)))
                     #u8())))
      (or (= (● ran status) 0) (fail suite name "failed" (printed ran))))))

;; A contract test, a snail-scheme program under tests/contracts run with
;; the root, which panics at the first expectation that fails.
(define (contract (suite Suite) (name String)) (→ (Fn → Bool))
  (lambda ()
    (match (build suite (string-append "tests/contracts/" name ".scm") "node")
      ((Err failure) (fail suite name "compile failed" failure))
      ((Ok module)
       (let ((ran (run-module suite module (list (● suite root)) #u8())))
         (or (= (● ran status) 0) (fail suite name "failed" (printed ran))))))))

;; A run's status is its program's. A panic exits with 1, and a trap is 2.
(define (exit-statuses (suite Suite)) (→ Bool)
  (let ((run (lambda ((file String)) (→ Ran) (snail suite (list "run" "--target" "node" file)))))
    (let ((failed (run "tests/tasks/failure.sld")))
      (if (not (and (= (● failed status) 1) (string=? (● failed stdout) "")))
          (fail suite "command line"
                "a fatal child panic must exit with status 1 before starting queued siblings"
                (printed failed))
          (let ((trapped (run "tests/programs/traps.sld")))
            (or (= (● trapped status) 2)
                (fail suite "command line" "a trap must be status 2" (● trapped stderr))))))))

;; An Any's TypeId describes its type's structure: reordering an enum's
;; cases keeps the enum's representation and gives it a new identity.
(define (type-id (suite Suite) (name String) (cases String)) (→ (Option String))
  (let ((source (string-append "build/tests/type-ids/" name ".sld")))
    (make-directories (● suite fs) (path suite "build/tests/type-ids"))
    (write-file (● suite fs) (path suite source)
                (string-append "(import (snail core base))\n(enum Phase " cases ")\n"
                               "(define (main) (→ Unit) (match (Any (Day)) (_ (unit))))\n"))
    (let* ((wat (● (snail suite (list "wat" "--target" "node" source)) stdout))
           (marker "(struct.new $any (i32.const "))
      (match (search wat marker 0)
        ((Some at)
         (let* ((start (+ at (string-length marker)))
                (rest (substring wat start (string-length wat))))
           (match (string-index rest #\))
             ((Some end) (Some (substring rest 0 end)))
             ((None) (None)))))
        ((None) (None))))))

(define (type-ids (suite Suite)) (→ Bool)
  (match (new Pair (first (type-id suite "day-night" "(Day) (Night)"))
              (second (type-id suite "night-day" "(Night) (Day)")))
    ((Pair (Some day-night) (Some night-day))
     (or (not (string=? day-night night-day))
         (fail suite "type ids" "unchanged by reordering an enum's cases" day-night)))
    (_ (fail suite "type ids" "no TypeId in the text" ""))))

;; The native async file provider, where io_uring is available.
(define (async-files (suite Suite)) (→ Bool)
  (match (build suite "tests/async-files/main.sld" "node")
    ((Err failure) (fail suite "async files" "compile failed" failure))
    ((Ok module)
     (let ((output
            (printed (run-module suite module (list (path suite "build/tests/async-data")) #u8()))))
       (cond ((string=? output "SKIP: native async file provider unavailable\n")
              (write-line (● suite out)
                          "async files: io_uring unavailable; native integration skipped")
              #t)
             ((string=? output (read-text suite "tests/async-files/main.out")) #t)
             (else (fail suite "async files" "wrong output" output)))))))

;; The toolchain's runtime assembles in-process: a tool linked with it
;; turns a program's text into a module and links it, which must print what
;; the program prints, and names the line and column of broken text.
(define (toolchain-assembler (suite Suite)) (→ Bool)
  (let ((directory "build/tests/toolchain")
        (wat (snail suite (list "wat" "--target" "node" "examples/fibonacci.sld"))))
    (make-directories (● suite fs) (path suite directory))
    (if (not (and (= (● wat status) 0) (some? (search (● wat stdout) "(func $main" 0))))
        (fail suite "toolchain assembler" "wat printed no module text" (● wat stderr))
        (begin
          (write-file (● suite fs)
                      (path suite "build/tests/toolchain/fibonacci.wat")
                      (● wat stdout))
          (match (build suite "tests/toolchain/assemble.sld" "node")
            ((Err failure) (fail suite "toolchain assembler" "compile failed" failure))
            ((Ok tool) (assembled suite tool)))))))

(define (assembled (suite Suite) (tool String)) (→ Bool)
  (let* ((tools (lines (● (command suite (path suite "scripts/bootstrap") (Nil) #u8()) stdout)))
         (runtime (list-ref tools 1))
         (file (lambda ((name String))
                 (→ String)
                 (path suite (string-append "build/tests/toolchain/" name))))
         (output (printed (run-module suite tool
                                      (list (file "fibonacci.wat")
                                            (file "fibonacci.wasm")
                                            runtime
                                            (file "linked.wasm"))
                                      #u8()))))
    (if (not (string=? output
                       (string-append
                        "assembled the program\nlinked the program after a failed link\n"
                        "broken text names its line and column\n")))
        (fail suite "toolchain assembler" "assembling failed" output)
        (let ((ran (printed (node suite
                                  (list (path suite "host/native/run-snail.mjs")
                                        (file "linked.wasm"))
                                  #u8()))))
          (or (string=? ran (read-text suite "examples/fibonacci.out"))
              (fail suite "toolchain assembler" "the module printed" ran))))))

(define (some? (found (Option I64))) (→ Bool)
  (match found
    ((Some _) #t)
    ((None) #f)))

;; The book's preprocessor, tools/highlight-book.scm, on a small book.
(define (book-highlighter (suite Suite)) (→ Bool)
  (match (build suite "tools/highlight-book.scm" "node")
    ((Err failure) (fail suite "book highlighter" "compile failed" failure))
    ((Ok module)
     (let ((checked (node suite
                          (list (path suite "tests/highlight-book.mjs") (● suite root) module)
                          #u8())))
       (or (= (● checked status) 0) (fail suite "book highlighter" "failed" (printed checked)))))))

(define (checks (suite Suite)) (→ (List (Fn → Bool)))
  (concatenate
   (list
    (list (lambda () (exit-statuses suite))
          (lambda () (type-ids suite))
          (lambda () (async-files suite))
          (lambda () (toolchain-assembler suite))
          (lambda () (book-highlighter suite))
          (fixture suite
                   "host values"
                   "tests/host-values/main.sld"
                   "tests/host-values/check.mjs"
                   "node")
          (fixture suite
                   "host boundary"
                   "tests/host-boundary/main.sld"
                   "tests/host-boundary/check.mjs"
                   "node")
          (fixture suite
                   "socket boundary"
                   "tests/socket-boundary/main.sld"
                   "tests/socket-boundary/check.mjs"
                   "node")
          (fixture suite
                   "termination"
                   "tests/termination/main.sld"
                   "tests/termination/check.mjs"
                   "node")
          (fixture suite
                   "app runtime"
                   "tests/app-runtime/main.sld"
                   "tests/app-runtime/check.mjs"
                   "browser"))
    (map (lambda (name) (contract suite name))
         (list "scripts" "workspaces" "launcher" "script-failures" "script-builds" "embedding"))
    (map (lambda (name) (script suite name (Nil)))
         (list "script-run" "script-resources" "web-zip" "lsp" "tree-sitter"
               "vscode" "tcp" "udp" "sf-relief" "format-scheme" "siegework/headless"))
    (list (script suite "udp" (list "--test-udp-no-try-send"))))))

;; ---- The run ----

;; The cases not yet taken, and how many passed.
(record Work
  ((cases (List (Fn → Bool)))
   (passed I64)))

;; Each case in turn until none is left, then a word to `done`.
(define (work! (work Work) (done (Mailbox Unit))) (→ Unit)
  (match (● work cases)
    ((Nil) (mailbox-post done (unit)))
    ((Cons next rest)
     (set! (● work cases) rest)
     (when (next) (set! (● work passed) (+ (● work passed) 1)))
     (work! work done))))

;; What the suite's builds publish, removed so that no run adds to the
;; last, but for the runner's own build.
(define (clean! (suite Suite)) (→ Unit)
  (for-each (lambda (output) (removed! suite output))
            (list "build/examples"
                  "build/tools"
                  "tests/programs/build"
                  "tests/host-boundary/build"
                  "tests/contracts/build"))
  (match (list-directory (● suite fs) (path suite "build/tests"))
    ((Ok entries)
     (for-each (lambda (entry) (removed! suite (string-append "build/tests/" entry)))
               (filter kept? entries)))
    ((Err _) (unit))))

;; The runner's own build, `run`, and the generation beside it, whose name
;; begins with a dot, as every generation's does.
(define (kept? (entry String)) (→ Bool)
  (or (string=? entry "run") (string=? (substring entry 0 1) ".")))

;; A tree removed, or already gone.
(define (removed! (suite Suite) (relative String)) (→ Unit)
  (match (remove-tree (● suite fs) (path suite relative))
    (_ (unit))))

(define (run! (suite Suite) (selected (List String))) (→ Unit)
  (clean! suite)
  (let* ((cases (append (concatenate (map (lambda (directory) (programs suite directory selected))
                                          (list "examples" "tests/programs" "tests/siegework")))
                        (if (null? selected) (checks suite) (Nil))))
         (work (new Work (cases cases) (passed 0)))
         (done (ann (make-mailbox) (Mailbox Unit)))
         (jobs 8))
    (for-each (lambda (job) (dispatch (lambda () (work! work done)))) (iota jobs))
    (for-each (lambda (job) (mailbox-receive done)) (iota jobs))
    (let ((summary (string-append (show (● work passed)) "/" (show (length cases)) " passed")))
      (write-line (● suite out) summary)
      (unless (= (● work passed) (length cases))
        (panic summary)))))

(define (main (arguments Arguments) (fs Fs) (processes Processes) (out OutputPort)) (→ Unit)
  (match (command-line arguments)
    ((Cons _ (Cons root selected))
     (run! (new Suite (root root) (fs fs) (processes processes) (out out)) selected))
    (_ (panic "usage: tests/run.scm ROOT [NAME ...]"))))
