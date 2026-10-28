;; The test suite: the compiler's unit tests, then every program suite. A
;; program NAME.sld must print NAME.out exactly, or fail to compile with the
;; text of NAME.err in its diagnostic. Then the Siegework package is built
;; and driven headlessly, and the in-process assembler assembles a program.
;; Programs compile one at a time, then link and run in parallel. Finally
;; some programs and Siegework run again as modules linked when they run,
;; and the development server serves and rebuilds an application.
;;
;;   chibi-scheme -D snail-tests -I tests -I bootstrap/chibi-include tests/run.scm ROOT [NAME ...]
(import
 (scheme base)
 (scheme cxr)
 (scheme file)
 (scheme process-context)
 (scheme write)
 (chibi filesystem)
 (only (chibi pathname) path-directory)
 (chibi process)
 (snail-core process)
 (only (chibi string) string-contains string-split string-suffix?)
 (srfi 1)
 (snail-core build)
 (only (snail-core compiler read) test-read)
 (only (snail-core compiler inputs) test-inputs)
 (only (snail-core compiler expand) test-expand)
 (only (snail-core compiler core) test-core)
 (only (snail-core compiler check) test-check)
 (only (snail-core compiler mono) test-mono)
 (only (snail-core compiler control) test-control)
 (only (snail-core compiler wasm) test-wasm)
 (only (snail-core compiler session) test-session)
 (only (snail-core compiler plan) test-plan)
 (only (snail-core project) test-project))

;; ---- Cases ----

(define (case-names directory)
  (sort-strings (filter-map (lambda (file) (and (string-suffix? ".sld" file) (substring file 0 (- (string-length file) 4))))
                            (directory-files directory))))

(define (sort-strings strings)
  (if (null? strings)
      '()
      (let ((pivot (car strings)))
        (append (sort-strings (filter (lambda (s) (string<? s pivot)) (cdr strings)))
                (list pivot)
                (sort-strings (filter (lambda (s) (string>=? s pivot)) (cdr strings)))))))

(define (error-text failure)
  (let ((port (open-output-string)))
    (if (error-object? failure)
        (begin (write-string (error-object-message failure) port)
               (for-each (lambda (irritant) (write-string " " port) (write irritant port)) (error-object-irritants failure)))
        (write failure port))
    (get-output-string port)))

(define (trim-newline text)
  (let ((length (string-length text)))
    (if (and (> length 0) (char=? (string-ref text (- length 1)) #\newline)) (substring text 0 (- length 1)) text)))

(define (report name problem detail)
  (display (string-append "FAIL " name ": " problem "\n" detail "\n") (current-error-port))
  #f)

;; ---- Programs ----

(define (run-wasm root program)
  (let ((result (capture-process (node-command root program))))
    (string-append (car result) (cadr result))))

;; Compiles a case. A case that expects a diagnostic is decided here; any
;; other becomes the check that links its program, places the files it
;; links beside it, runs it and compares the output.
(define (compile-case root directories directory build name)
  (let ((source (path-join directory (string-append name ".sld")))
        (expected-output (path-join directory (string-append name ".out")))
        (expected-error (path-join directory (string-append name ".err"))))
    (guard (failure
            ((file-exists? expected-error)
             (let ((text (error-text failure)) (wanted (trim-newline (read-file expected-error))))
               (or (string-contains text wanted) (report name "wrong diagnostic" (string-append text "\nexpected: " wanted)))))
            (#t (report name "compile failed" (error-text failure))))
      (let ((compiled (program->linked-wat root directories source)))
        (cond ((file-exists? expected-error) (report name "compiled, but a diagnostic was expected" ""))
              ((not (file-exists? expected-output)) (report name "no expected output" ""))
              (else (lambda () (check-output root compiled (path-join build (string-append name ".wasm")) name expected-output))))))))

(define (check-output root compiled program name expected-output)
  (guard (failure (#t (report name "link failed" (error-text failure))))
    (link-wat root (car compiled) program #f)
    (place-links! (cdr compiled) (path-directory program))
    (let ((output (run-wasm root program)) (expected (read-file expected-output)))
      (or (equal? output expected) (report name "wrong output" (string-append output "\nexpected:\n" expected))))))

(define (run-suite root suite libraries selected)
  (let* ((directory (path-join root suite)) (build (path-join root "build/tests" suite))
         (names (filter (lambda (name) (or (null? selected) (member name selected))) (case-names directory))))
    (create-directory* build)
    (map (lambda (name)
           (compile-case root (append (map (lambda (library) (path-join root library)) libraries) (standard-directories root))
                         directory build name))
         names)))

;; ---- Applications ----

(define (compile-siegework root)
  (guard (failure (#t (report "siegework" "compile failed" (error-text failure))))
    (let ((text (program->wat root (cons (path-join root "apps/siegework/src") (standard-directories root))
                              (path-join root "apps/siegework/main.sld"))))
      (lambda () (check-siegework root text)))))

(define (check-siegework root text)
  (guard (failure (#t (report "siegework" "headless run failed" (error-text failure))))
    (let ((program (path-join root "build/tests/siegework/app.wasm")))
      (link-wat root text program #f)
      (let ((result (capture-process (list "node" "--no-warnings" (path-join root "apps/siegework/tests/headless.mjs") program))))
        (or (zero? (caddr result)) (report "siegework" "headless run failed" (string-append (car result) (cadr result))))))))

;; The in-process assembler, itself Wasm, turns a program's text into a
;; module that runs with the runtime as its own instance.
(define (compile-assembler root)
  (guard (failure (#t (report "assembler" "compile failed" (error-text failure))))
    (let ((text (program->wat root (cons (path-join root "examples") (standard-directories root)) (path-join root "examples/fibonacci.sld"))))
      (lambda () (check-assembler root text)))))

(define (check-assembler root text)
  (guard (failure (#t (report "assembler" "test failed" (error-text failure))))
    (let ((wat (path-join root "build/tests/assembler/fibonacci.wat")))
      (create-directory* (path-join root "build/tests/assembler"))
      (call-with-output-file wat (lambda (port) (write-string text port)))
      (let ((result (capture-process
                     (list "node" "--no-warnings" (path-join root "tests/assembler.mjs") (build-crate root "assembler") (build-crate root "runtime") wat
                           (path-join root "examples/fibonacci.out")))))
        (or (zero? (caddr result)) (report "assembler" "test failed" (string-append (car result) (cadr result))))))))

;; An Any's TypeId describes its type's structure: reordering an enum's
;; cases keeps the enum's representation and gives it a new identity, so a
;; relinked program cannot adopt a state that means something else.
(define (check-type-ids root)
  (let ((day-night (enum-type-id root "(Day) (Night)")) (night-day (enum-type-id root "(Night) (Day)")))
    (or (not (string=? day-night night-day)) (report "type ids" "unchanged by reordering an enum's cases" day-night))))

;; The exposed and foreign ABI, exercised from JavaScript against linked Wasm.
(define (check-host-boundary root)
  (let* ((program (path-join root "build/tests/host-boundary.wasm"))
         (text (program->wat root (cons (path-join root "tests/host-boundary") (standard-directories root)) (path-join root "tests/host-boundary/main.sld"))))
    (link-wat root text program #f)
    (run-host-boundary root program)))

(define (run-host-boundary root program)
  (let ((result (capture-process (list "node" "--no-warnings" (path-join root "tests/host-boundary/check.mjs") program))))
    (or (zero? (caddr result)) (report "host boundary" "failed" (string-append (car result) (cadr result))))))

(define (compile-app-runtime root)
  (guard (failure (#t (report "app runtime" "compile failed" (error-text failure))))
    (let ((text (program->wat root (standard-directories root) (path-join root "tests/app-runtime/main.sld"))))
      (lambda ()
        (let ((program (path-join root "build/tests/app-runtime.wasm")))
          (link-wat root text program #f)
          (check-app-runtime root program))))))

(define (check-app-runtime root program)
  (let ((result (capture-process (list "node" "--no-warnings" (path-join root "tests/app-runtime/check.mjs") program))))
    (or (zero? (caddr result)) (report "app runtime" "failed" (string-append (car result) (cadr result))))))

(define (check-task-runtime root)
  (let ((result (capture-process
                 (list "node" "--no-warnings" (path-join root "tests/tasks/check.mjs") (build-crate root "assembler")))))
    (or (zero? (caddr result)) (report "task runtime" "failed" (string-append (car result) (cadr result))))))

(define (compile-task-boundary root)
  (let ((text (program->wat root (standard-directories root) (path-join root "tests/tasks/boundary.sld"))))
    (lambda ()
      (let ((program (path-join root "build/tests/task-boundary.wasm")))
        (link-wat root text program #f)
        (check-task-boundary root program)))))

(define (check-task-boundary root program)
  (let ((result (capture-process (list "node" "--no-warnings" (path-join root "tests/tasks/boundary.mjs") program))))
    (or (zero? (caddr result)) (report "task boundary" "failed" (string-append (car result) (cadr result))))))

;; Exercise scratch isolation in separate runtime instances, as linked modules use.
(define (check-numeric-runtime root)
  (let ((result (capture-process
                 (list "node" "--no-warnings" (path-join root "tests/numeric.mjs") (build-crate root "runtime")))))
    (or (zero? (caddr result)) (report "numeric runtime" "conversion failed" (string-append (car result) (cadr result))))))

(define (enum-type-id root cases)
  (let ((source (path-join root "build/tests/type-ids/main.sld")) (marker "(struct.new $any (i32.const "))
    (create-directory* (path-join root "build/tests/type-ids"))
    (call-with-output-file source
      (lambda (port) (write-string (string-append "(import (snail-core base))\n(enum Phase " cases ")\n(type-convert (Day) Any)\n") port)))
    (let* ((text (program->wat root (standard-directories root) source)) (start (+ (text-index text marker 0) (string-length marker))))
      (substring text start (text-index text ")" start)))))

(define (text-index text pattern from)
  (cond ((> (+ from (string-length pattern)) (string-length text)) (error "not found" pattern))
        ((string=? (substring text from (+ from (string-length pattern))) pattern) from)
        (else (text-index text pattern (+ from 1)))))

;; The IDE's formatter, (snail-core format) as a program, leaves every Scheme
;; file in the repository as the Emacs formatter that `make check` runs
;; left it.
(define (compile-formatter root)
  (guard (failure (#t (report "formatter" "compile failed" (error-text failure))))
    (let ((text (program->wat root (standard-directories root) (path-join root "host/ide/format.sld"))))
      (lambda () (check-formatter root text)))))

(define (check-formatter root text)
  (guard (failure (#t (report "formatter" "check failed" (error-text failure))))
    (let ((program (path-join root "build/tests/formatter/format.wasm"))
          (files (capture-process (list "git" "-C" root "ls-files" "*.scm" "*.sld"))))
      (create-directory* (path-join root "build/tests/formatter"))
      (link-wat root text program #f)
      (let ((result (capture-process
                     (append (list "node" "--no-warnings" (path-join root "host/native/run-snail.mjs") program "--check")
                             (map (lambda (file) (path-join root file)) (delete "" (string-split (car files) #\newline)))))))
        (or (and (zero? (caddr result)) (string=? (car result) ""))
            (report "formatter" "formats differently from Emacs" (string-append (car result) (cadr result))))))))

;; The book's preprocessor, host/native/highlight-book.mjs, run on a small
;; book with its highlighter, (snail-core highlight) as a program, turns
;; each `scheme` block into spans and leaves the rest as it was.
(define (compile-book-highlighter root)
  (guard (failure (#t (report "book highlighter" "compile failed" (error-text failure))))
    (let ((text (program->wat root (standard-directories root) (path-join root "host/native/highlight.sld"))))
      (lambda () (check-book-highlighter root text)))))

(define (check-book-highlighter root text)
  (guard (failure (#t (report "book highlighter" "check failed" (error-text failure))))
    (let ((program (path-join root "build/tests/book-highlighter/highlight.wasm")))
      (create-directory* (path-join root "build/tests/book-highlighter"))
      (link-wat root text program #f)
      (let ((result (capture-process (list "node" "--no-warnings" (path-join root "tests/highlight-book.mjs") root program))))
        (or (zero? (caddr result)) (report "book highlighter" "failed" (string-append (car result) (cadr result))))))))

;; The internal compiler driver: printing text and running a program.
(define (run-command-line root)
  (let ((wat (capture-process (list (path-join root "scripts/snail-tool") "wat" (path-join root "examples/fibonacci.sld"))))
        (run (capture-process (list (path-join root "scripts/snail-tool") "run" (path-join root "examples/fibonacci.sld"))))
        (failed (capture-process (list (path-join root "scripts/snail-tool") "run" (path-join root "tests/tasks/failure.sld")))))
    (cond ((not (and (zero? (caddr wat)) (string-contains (car wat) "(func $main"))) (report "compiler wat" "no module text" (cadr wat)))
          ((not (equal? (car run) "832040\n")) (report "compiler run" "wrong output" (string-append (car run) (cadr run))))
          ((not (and (not (zero? (caddr failed))) (equal? (car failed) "survived\n")))
           (report "compiler run" "a failed child must set failure status and let its sibling finish" (string-append (car failed) (cadr failed))))
          (else #t))))

;; The compiled compiler and its source on Chibi must emit the same text
;; for the same program; `make bootstrap` checks the compiler itself.
(define (check-host-agreement root)
  (let* ((tool (path-join root "scripts/snail-tool")) (source (path-join root "examples/fibonacci.sld"))
         (compiled (capture-process (list tool "wat" source)))
         (interpreted (capture-process (list "env" "SNAIL_STAGE0=chibi" tool "wat" source))))
    (cond ((not (zero? (caddr compiled))) (report "host agreement" "the compiled compiler failed" (cadr compiled)))
          ((not (zero? (caddr interpreted))) (report "host agreement" "the source on Chibi failed" (cadr interpreted)))
          ((not (equal? (car compiled) (car interpreted)))
           (report "host agreement" "the two hosts emit different text for examples/fibonacci.sld" ""))
          (else #t))))

(define (check-project-builds root)
  (let ((result (capture-process (list "node" "--no-warnings" (path-join root "tests/project-builds.mjs") root))))
    (or (zero? (caddr result)) (report "project builds" "failed" (string-append (car result) (cadr result))))))

(define (check-project-run root)
  (let ((result (capture-process (list "node" "--no-warnings" (path-join root "tests/project-run.mjs") root))))
    (or (zero? (caddr result)) (report "project run" "failed" (string-append (car result) (cadr result))))))

(define (check-application-process root)
  (let ((result (capture-process (list "node" "--no-warnings" (path-join root "tests/application-process.mjs") root))))
    (or (zero? (caddr result)) (report "application process" "failed" (string-append (car result) (cadr result))))))

(define (check-project-failures root)
  (let ((result (capture-process (list "node" "--no-warnings" (path-join root "tests/project-failures.mjs") root))))
    (or (zero? (caddr result)) (report "project failures" "failed" (string-append (car result) (cadr result))))))

(define (check-project-resources root)
  (let ((result (capture-process (list "node" "--no-warnings" (path-join root "tests/project-resources.mjs") root))))
    (or (zero? (caddr result)) (report "project resources" "failed" (string-append (car result) (cadr result))))))

(define (check-project-artifacts root)
  (let ((result (capture-process (list "node" "--no-warnings" (path-join root "tests/project-artifacts.mjs") root))))
    (or (zero? (caddr result)) (report "project artifacts" "failed" (string-append (car result) (cadr result))))))

(define (check-project-development root)
  (let ((result (capture-process (list "node" "--no-warnings" "--max-semi-space-size=384" (path-join root "tests/project-development.mjs") root))))
    (or (zero? (caddr result)) (report "project development" "failed" (string-append (car result) (cadr result))))))

(define (check-project-watcher root)
  (let ((result (capture-process (list "node" "--no-warnings" (path-join root "tests/watch.mjs")))))
    (or (zero? (caddr result)) (report "project watcher" "failed" (string-append (car result) (cadr result))))))

(define (check-project-attempts root)
  (let ((result (capture-process (list "node" "--no-warnings" (path-join root "tests/project-attempts.mjs") root))))
    (or (zero? (caddr result)) (report "project attempts" "failed" (string-append (car result) (cadr result))))))

(define (check-development-runs root)
  (let ((result (capture-process (list "node" "--no-warnings" (path-join root "tests/development-runs.mjs") root))))
    (or (zero? (caddr result)) (report "development runs" "failed" (string-append (car result) (cadr result))))))

(define (check-project-http root)
  (let ((result (capture-process (list "node" "--no-warnings" (path-join root "tests/project-http.mjs") root))))
    (or (zero? (caddr result)) (report "project HTTP" "test failed" (string-append (car result) (cadr result))))))

(define (check-project-files root)
  (let ((result (capture-process (list "node" "--no-warnings" (path-join root "tests/project-files.mjs")))))
    (or (zero? (caddr result)) (report "project files" "failed" (string-append (car result) (cadr result))))))

(define (check-tcp root)
  (let ((result (capture-process (list "node" "--no-warnings" (path-join root "tests/tcp.mjs")))))
    (or (zero? (caddr result)) (report "native TCP" "failed" (string-append (car result) (cadr result))))))

(define (check-udp root)
  (every (lambda (flags)
           (let ((result (capture-process (append (list "node" "--no-warnings") flags (list (path-join root "tests/udp.mjs"))))))
             (or (zero? (caddr result)) (report "native UDP" "failed" (string-append (car result) (cadr result))))))
         '(() ("--test-udp-no-try-send"))))

(define (compile-socket-boundary root)
  (let ((text (program->wat root (standard-directories root) (path-join root "tests/socket-boundary/main.sld"))))
    (lambda ()
      (let ((program (path-join root "build/tests/socket-boundary.wasm")))
        (link-wat root text program #f)
        (check-socket-boundary root program)))))

(define (check-socket-boundary root program)
  (let ((result (capture-process (list "node" "--no-warnings" (path-join root "tests/socket-boundary/check.mjs") program))))
    (or (zero? (caddr result)) (report "socket boundary" "failed" (string-append (car result) (cadr result))))))

;; A compiler running as Wasm resolves concrete file snapshots, then emits
;; static and cached library builds whose current bytes are executed.
(define (compile-artifacts root)
  (let ((text (program->wat root (standard-directories root) (path-join root "tests/artifacts/compiler.sld"))))
    (lambda ()
      (let* ((output (path-join root "build/tests/artifacts")) (compiler (path-join output "compiler.wasm")))
        (for-each (lambda (name) (create-directory* (path-join output name))) '("first" "unchanged" "changed"))
        (link-wat root text compiler #f)
        (check-artifacts root output compiler)))))

(define (check-artifacts root output compiler)
  (let ((compiled (capture-process
                   (append (node-command root compiler)
                           (append (list (path-join root "tests/artifacts/main.sld") output)
                                   (standard-directories root) (list (path-join root "tests/artifacts/lib")))))))
    (if (not (zero? (caddr compiled)))
        (report "artifacts" "fixture compiler failed" (string-append (car compiled) (cadr compiled)))
        (let ((result (capture-process
                       (list "node" "--no-warnings" (path-join root "tests/artifacts/check.mjs")
                             (build-crate root "assembler") (build-crate root "runtime") output (path-join root "tests/artifacts/main.out")))))
          (or (zero? (caddr result)) (report "artifacts" "execution failed" (string-append (car result) (cadr result))))))))

;; One resident compiler instance returns opaque sessions and parsed records.
(define (compile-native-compiler root)
  (let ((text (program->wat root (standard-directories root) (path-join root "bootstrap/compiler.sld"))))
    (lambda ()
      (let* ((program (path-join root "build/tests/native-compiler.wasm"))
             (linked (link-wat root text program #f))
             (result (capture-process
                      (list "node" "--no-warnings" "--max-semi-space-size=384" (path-join root "tests/compiler.mjs") linked
                            (build-crate root "assembler") (build-crate root "runtime")))))
        (or (zero? (caddr result)) (report "resident compiler" "failed" (string-append (car result) (cadr result))))))))

;; ---- Linked modules ----

;; Programs compiled one library at a time and linked when they run, by
;; host/native/run-snail.mjs and the loader in host/browser/load.mjs, must print what
;; their statically linked builds print. A sample of the suites covers each
;; kind of definition crossing a module boundary, and Siegework covers an
;; application. Building runs the compiler, so these run after the others.
(define linked-cases
  '(("examples" "fibonacci") ("examples" "effects") ("examples" "colors") ("examples" "scheme-fibonacci")
    ("tests/programs" "closures") ("tests/programs" "classes-advanced") ("tests/programs" "data") ("tests/programs" "dynamic")
    ("tests/programs" "wire") ("tests/programs" "tables") ("tests/programs" "libraries") ("tests/programs" "generated") ("tests/programs" "wasm")
    ("tests/programs" "capabilities") ("tests/programs" "handler-captures") ("tests/programs" "once") ("tests/programs" "tasks")
    ("tests/programs" "effect-row-inclusion") ("tests/programs" "link-bytes") ("tests/programs" "control-early-exit")
    ("tests/programs" "control-per-library") ("tests/programs" "control-placeholders") ("tests/programs" "control-generator")
    ("tests/programs" "control-resumable-exception") ("tests/programs" "control-stored-resume") ("tests/programs" "control-tail-loop")
    ("tests/programs" "tcp") ("tests/programs" "tcp-handler")
    ("tests/programs" "udp") ("tests/programs" "udp-handler") ("tests/programs" "http")
    ("tests/programs" "http-exchange") ("tests/programs" "http-sockets")))

(define (suite-libraries suite)
  (if (string=? suite "examples") '("examples") '("tests/programs" "tests/programs/lib")))

(define (run-linked root suite name)
  (guard (failure (#t (report name "linked build failed" (error-text failure))))
    (let ((output (path-join root "build/tests/linked" name)))
      (build-modules root (append (map (lambda (library) (path-join root library)) (suite-libraries suite)) (standard-directories root))
                     (path-join root suite (string-append name ".sld")) output)
      (let ((printed (run-wasm root (path-join output "modules.json")))
            (expected (read-file (path-join root suite (string-append name ".out")))))
        (or (equal? printed expected) (report name "wrong output when linked" (string-append printed "\nexpected:\n" expected)))))))

(define (run-linked-siegework root)
  (guard (failure (#t (report "siegework" "linked build failed" (error-text failure))))
    (let ((output (path-join root "build/tests/linked/siegework")))
      (build-modules root (cons (path-join root "apps/siegework/src") (standard-directories root)) (path-join root "apps/siegework/main.sld") output)
      (let ((result (capture-process (list "node" "--no-warnings" (path-join root "apps/siegework/tests/headless.mjs")
                                           (path-join output "modules.json")))))
        (or (zero? (caddr result)) (report "siegework" "linked headless run failed" (string-append (car result) (cadr result))))))))

(define (run-linked-app-runtime root)
  (guard (failure (#t (report "app runtime" "linked build failed" (error-text failure))))
    (let ((output (path-join root "build/tests/linked/app-runtime")))
      (build-modules root (standard-directories root) (path-join root "tests/app-runtime/main.sld") output)
      (check-app-runtime root (path-join output "modules.json")))))

(define (run-linked-cases root)
  (append (map (lambda (entry) (run-linked root (car entry) (cadr entry))) linked-cases)
          (list (run-linked-siegework root) (run-linked-app-runtime root) (run-linked-task-boundary root) (run-linked-host-boundary root)
                (run-linked-socket-boundary root))))

(define (run-linked-socket-boundary root)
  (let ((output (path-join root "build/tests/linked/socket-boundary")))
    (build-modules root (standard-directories root) (path-join root "tests/socket-boundary/main.sld") output)
    (check-socket-boundary root (path-join output "modules.json"))))

(define (run-linked-host-boundary root)
  (let ((output (path-join root "build/tests/linked/host-boundary")))
    (build-modules root (cons (path-join root "tests/host-boundary") (standard-directories root)) (path-join root "tests/host-boundary/main.sld") output)
    (run-host-boundary root (path-join output "modules.json"))))

(define (run-linked-task-boundary root)
  (let ((output (path-join root "build/tests/linked/task-boundary")))
    (build-modules root (standard-directories root) (path-join root "tests/tasks/boundary.sld") output)
    (check-task-boundary root (path-join output "modules.json"))))

;; ---- Development loop ----

;; `snail-tool serve` and `snail-tool watch` build while they run, and the check waits
;; for their builds with a timeout, so it runs alone, after the others,
;; rather than competing with them.
(define (run-develop root)
  (let ((result (capture-process (list "node" "--no-warnings" (path-join root "tests/develop.mjs") root))))
    (or (zero? (caddr result)) (report "develop" "the development loop failed" (string-append (car result) (cadr result))))))

;; ---- Checks in parallel ----

;; Cases compile one at a time, in this process, before any check starts:
;; the compiler's source on Chibi, as `make test-chibi` runs it, takes a
;; heap too large to run many at once. A check links and runs a program in
;; its own files, and each compile works in a directory of its own, so
;; checks, some of which compile, run in child processes, `jobs` at a time.
;; A child reports its own failure and exits with its result.
(define jobs 8)

(define (run-checks cases)
  (let ((results (list->vector cases)))
    (let loop ((pending (filter (lambda (index) (procedure? (vector-ref results index))) (iota (vector-length results))))
               (running '()))
      (cond ((and (pair? pending) (< (length running) jobs))
             (loop (cdr pending) (cons (cons (start-check (vector-ref results (car pending))) (car pending)) running)))
            ((pair? running)
             (let* ((done (waitpid -1 0)) (entry (assv (car done) running)))
               (vector-set! results (cdr entry) (zero? (cadr done)))
               (loop pending (delete entry running))))
            (else (vector->list results))))))

;; Ports are flushed before the fork so no buffered text is written twice,
;; and the child exits without unwinding into the parent's continuation.
(define (start-check check)
  (flush-output-port (current-output-port))
  (flush-output-port (current-error-port))
  (let ((pid (fork)))
    (if (zero? pid)
        (let ((passed (guard (failure (#t (report "check" "raised" (error-text failure)))) (check))))
          (flush-output-port (current-output-port))
          (flush-output-port (current-error-port))
          (emergency-exit (if passed 0 1)))
        pid)))

;; ---- Suite ----

(define (main root selected)
  (test-read)
  (test-inputs)
  (test-build root)
  (test-process root)
  (test-core)
  (test-check)
  (test-mono)
  (test-control)
  (test-wasm)
  (test-expand (path-join root "build/tests/expand") (path-join root "src"))
  (test-session (path-join root "build/tests/session") (path-join root "src"))
  (test-plan (path-join root "build/tests/plan") (path-join root "src"))
  (test-project)
  (let* ((cases (append (run-suite root "examples" '("examples") selected)
                        (run-suite root "tests/programs" '("tests/programs" "tests/programs/lib") selected)
                        (run-suite root "tests/projects" '("src") selected)
                        (run-suite root "apps/siegework/tests" '("apps/siegework/src") selected)
                        (run-suite root "apps/hearsay/tests" '("apps/hearsay/src") selected)
                        (if (null? selected) (list (lambda () (run-command-line root)) (lambda () (check-host-agreement root)) (lambda () (check-project-builds root)) (lambda () (check-project-run root)) (lambda () (check-application-process root)) (lambda () (check-project-failures root)) (lambda () (check-project-artifacts root)) (lambda () (check-project-resources root)) (lambda () (check-project-development root)) (lambda () (check-project-watcher root)) (lambda () (check-project-attempts root)) (lambda () (check-development-runs root)) (lambda () (check-project-files root)) (lambda () (check-project-http root)) (lambda () (check-tcp root)) (lambda () (check-udp root)) (lambda () (check-type-ids root)) (lambda () (check-numeric-runtime root)) (lambda () (check-host-boundary root)) (lambda () (check-task-runtime root)) (compile-artifacts root) (compile-native-compiler root) (compile-task-boundary root) (compile-socket-boundary root) (compile-app-runtime root) (compile-siegework root) (compile-assembler root) (compile-formatter root) (compile-book-highlighter root)) '())))
         (results (append (run-checks cases) (if (null? selected) (append (run-linked-cases root) (list (run-develop root))) '())))
         (failures (count not results)))
    (display (string-append (number->string (- (length results) failures)) "/" (number->string (length results)) " passed\n"))
    (if (zero? failures) 0 1)))

(let ((arguments (command-line)))
  (exit (main (cadr arguments) (cddr arguments))))
