;; Stage 0's driver. Its one product is the stage 1 command line,
;; bootstrap/cli.sld, which `bootstrap` builds from its source and checks
;; to a fixpoint ("Bootstrap"). Everything else, every program and the
;; test suite's, the command line builds. A compile here runs the command
;; line's `compile TARGET SOURCE OUTPUT DIRECTORY ...`, or
;; the same interface on Chez, and `snail-link` links through the Rust
;; backend compiled programs use.
(define-library (snail stage0 build)
  (export
   bootstrap)
  (import
   (chezscheme)
   (snail stage0 system)
   (snail stage0 process))
  (begin

    ;; ---- Compiling ----

    ;; The command that compiles with the command line `program`, which is
    ;; an ordinary program: its `compile` action, after the root and the two
    ;; runtimes every action takes, on Node through
    ;; host/native/run-snail.mjs.
    (define (compiler-command root program)
      (list (or (getenv "NODE") "node")
            "--no-warnings"
            (path-join root "host/native/run-snail.mjs")
            program
            root
            (runtime-path root #f)
            (runtime-path root #t)
            "compile"))

    ;; Chez compiles the erased source closure to native code. The loader
    ;; admits the compiler and its host boundary, never application libraries.
    (define (chez-compiler root)
      (list (or (getenv "CHEZ") "scheme") "--script"
            (path-join root "host/chez/load.scm") root "compile"))

    ;; One compile by `command` of the program at `source`, for (snail
    ;; target node): its text. The compile works in a directory of its own,
    ;; removed when done, so compiles running at once in one checkout never
    ;; share a file. The command line reaches no generated library, so a
    ;; compile that asks for one has failed, as with any other diagnostic.
    (define (run-compiler root command directories source)
      (with-private-directory root
                              (lambda (directory)
                                (let* ((output (path-join directory "output.wat"))
                                       (result (capture-process
                                                (append command
                                                        (list "node" source output)
                                                        directories))))
                                  (unless (zero? (caddr result))
                                    (error 'snail (diagnostic (cadr result))))
                                  (read-file output)))))

    ;; Programs resolve ordinary libraries under src/. The Chez loader has
    ;; its own explicit closure and replaces only the compiler's host boundary.
    (define (standard-directories root)
      (list (path-join root "src")))

    (define (with-private-directory root use)
      (let ((directory (private-directory root)))
        (dynamic-wind (lambda () #f)
            (lambda () (use directory))
            (lambda () (delete-file-hierarchy directory)))))

    (define private-count 0)
    (define counter-lock (make-mutex))

    (define (private-directory root)
      (let ((directory (path-join root "build/snail-run")))
        (unless (create-directory* directory)
          (error 'snail "cannot create compiler scratch directory" directory))
        (create-staging-directory directory)))

    ;; Exclusive creation owns exactly this staging directory. A stale name
    ;; from a reused process id is skipped, never adopted or removed.
    (define (create-staging-directory output)
      (let ((number (with-mutex counter-lock
                                (set! private-count (+ private-count 1)) private-count)))
        (let ((directory (path-join output
                                    (string-append ".snail-"
                                                   (number->string (get-process-id))
                                                   "-"
                                                   (number->string number)))))
          (cond ((create-directory directory #o700) directory)
                ((file-link-status directory) (create-staging-directory output))
                (else (error 'snail "cannot stage program in output directory" output))))))

    ;; The compiler's message without the host's prefix.
    (define (diagnostic text)
      (let* ((cursor (string-contains text "snail: "))
             (start (if cursor (+ cursor 6) 0)))
        (let loop ((end (string-length text)))
          (if (and (> end start) (char=? (string-ref text (- end 1)) #\newline))
              (loop (- end 1))
              (substring text start end)))))

    ;; ---- The build lock ----

    ;; What every build in a checkout shares, the compiled compiler and the
    ;; development tools, is rebuilt under an exclusive lock on build/lock,
    ;; as Cargo locks its target directory, so a second process waits
    ;; rather than building over the first. A process takes it once, however
    ;; deep the rebuild that needs it.
    (define build-lock-held? (make-thread-parameter #f))

    (define (with-build-lock root thunk)
      (if (build-lock-held?)
          (thunk)
          (begin
            (create-directory* (path-join root "build"))
            (let ((port (open-replacing-output-file (path-join root "build/lock"))))
              (dynamic-wind (lambda () (file-lock port lock/exclusive) (build-lock-held? #t))
                  thunk
                  (lambda ()
                    (build-lock-held? #f)
                    (file-lock port lock/unlock)
                    (close-port port)))))))

    ;; `output` is stale when it is missing or older than one of its
    ;; `sources`: files, or directories whose .sld files count at any depth.
    ;; A stale output is rebuilt under the build lock, and only if no other
    ;; process rebuilt it while this one waited.
    (define (rebuild-if-stale! root output sources rebuild!)
      (unless (current? output sources)
        (with-build-lock root (lambda () (unless (current? output sources) (rebuild!)))))
      output)

    (define (current? output sources)
      (and (file-exists? output)
           (> (modification-nanoseconds output) (apply max (map newest-time sources)))))

    (define (newest-time path)
      (if (file-directory? path) (newest-sld-time path) (modification-nanoseconds path)))

    (define (newest-sld-time directory)
      (let loop ((entries (directory-list directory)) (newest 0))
        (cond ((null? entries) newest)
              ((member (car entries) '("." "..")) (loop (cdr entries) newest))
              (else
               (let ((path (path-join directory (car entries))))
                 (loop (cdr entries)
                       (max newest (cond ((file-directory? path) (newest-sld-time path))
                                         ((or (string-suffix? ".sld" path)
                                              (string-suffix? ".sls" path)
                                              (string-suffix? ".scm" path))
                                          (modification-nanoseconds path))
                                         (else 0)))))))))

    ;; ---- Bootstrap ----

    ;; The command line compiles itself until its output stops changing:
    ;; stage 1 is built by the previous command line if it can, or else by
    ;; Chez running the compiler's source; stage 2 by stage 1; and stage 2
    ;; must reproduce its own text. It links with the toolchain runtime,
    ;; whose services include the assembler its builds use.
    (define (cli-path root)
      (path-join root "build/bootstrap/snail-scheme.wasm"))

    ;; The compiler's own sources: its entry's driver, its modules, the
    ;; three libraries it imports and the primitives they are built on, the
    ;; assembler it links with, and this host.
    (define (compiler-sources root)
      (map (lambda (path) (path-join root path))
           '("host/chez"
             "crates/snail-scheme-support/src/assembler.rs"
             "src/snail/shell/compiler.sld"
             "src/snail/shell/compiler"
             "src/snail/core/base.sld"
             "src/snail/core/table.sld"
             "src/snail/core/io.sld"
             "src/snail/core/primitive.sld")))

    ;; Everything the command line is built from: its entry, every library
    ;; under src/, and the runtime it links, built first if it is missing.
    ;; Cargo is asked again only by `bootstrap`, since every compile asks
    ;; for the command line.
    (define (cli-sources root)
      (unless (file-exists? (runtime-path root #t)) (build-runtime root #t))
      (cons* (runtime-path root #t)
             (path-join root "bootstrap")
             (path-join root "src")
             (compiler-sources root)))

    ;; The current command line. When the compiler's own sources are older
    ;; than it, the compiler inside it is the source's, so one compile by it
    ;; is the fixpoint's output; otherwise the whole fixpoint runs again.
    (define (current-cli root)
      (rebuild-if-stale! root (cli-path root) (cli-sources root)
                         (lambda ()
                           (if (current? (cli-path root) (compiler-sources root))
                               (recompile-cli! root)
                               (rebuild-cli! root)))))

    ;; What scripts/bootstrap prints, a line each: the command line, then
    ;; the runtime programs link with, then the toolchain's, which the
    ;; launcher passes it.
    (define (bootstrap root)
      (let* ((runtime (build-runtime root #f)) (toolchain (build-runtime root #t)))
        (for-each (lambda (path) (write-string path) (newline))
                  (list (current-cli root) runtime toolchain))))

    ;; One compile of the entry by the current command line, linked into
    ;; place; if that command line cannot, the whole fixpoint instead.
    (define (recompile-cli! root)
      (let* ((directory (path-join root "build/bootstrap"))
             (next (path-join directory "next.wasm"))
             (text (guard (failure (#t #f))
                     (run-compiler root
                                   (compiler-command root (cli-path root))
                                   (standard-directories root)
                                   (cli-entry root)))))
        (if text
            (begin (link-cli root text next) (rename-file next (cli-path root)))
            (rebuild-cli! root))))

    (define (cli-entry root)
      (path-join root "bootstrap/cli.sld"))

    ;; Writes OUTPUT from the command line's text, keeping the text beside it.
    (define (link-cli root text output)
      (let ((wat (string-append output ".wat")))
        (write-file wat text)
        (link-wat-file root wat output (build-runtime root #t))))

    ;; Stage 1 is the source's output for the command line, from the
    ;; previous one when one works and from Chez otherwise; stage 2 is stage
    ;; 1's, and stage 3 is stage 2's. Stage 2 must reproduce its own text.
    ;; When Chez produced stage 1, both hosts ran the same source on the
    ;; same input, so stage 1 must be that text as well: the two hosts
    ;; agree, or the build says where they differ.
    (define (rebuild-cli! root)
      (let* ((directory (path-join root "build/bootstrap"))
             (entry (cli-entry root))
             (stage1 (path-join directory "stage1.wasm"))
             (stage2 (path-join directory "stage2.wasm"))
             (stage3 (path-join directory "stage3.wat")) (sources (standard-directories root)))
        (create-directory* directory)
        (let ((first (stage1-text root entry)))
          (link-cli root (cdr first) stage1)
          (link-cli root
                    (run-compiler root (compiler-command root stage1) sources entry)
                    stage2)
          (write-file stage3 (run-compiler root (compiler-command root stage2) sources entry))
          (unless (equal? (read-file (string-append stage2 ".wat")) (read-file stage3))
            (error 'snail
                   "bootstrap: stage 2 does not reproduce its own text; compare build/bootstrap/stage2.wasm.wat with stage3.wat"))
          (when (and (car first)
                     (not (equal? (cdr first) (read-file (string-append stage2 ".wat")))))
            (error 'snail
                   "bootstrap: the source on Chez and its compiled form emit different text; compare build/bootstrap/stage1.wasm.wat with stage2.wasm.wat"))
          (rename-file stage2 (cli-path root)))))

    ;; Whether Chez produced the text, and the text.
    (define (stage1-text root entry)
      (let* ((previous (cli-path root)) (sources (standard-directories root))
             (reused (and (file-exists? previous)
                          (guard (failure (#t #f))
                            (run-compiler root (compiler-command root previous) sources entry)))))
        (if reused
            (cons #f reused)
            (cons #t (run-compiler root (chez-compiler root) sources entry)))))

    ;; ---- Files and commands ----

    (define (path-join . parts)
      (path-normalize (apply make-path parts)))

    (define (read-file path)
      (call-with-input-file path
        (lambda (port)
          (let loop ((chunks '()))
            (let ((chunk (read-string 65536 port)))
              (if (eof-object? chunk)
                  (apply string-append (reverse chunks))
                  (loop (cons chunk chunks))))))))

    (define (write-file path text)
      (create-directory* (path-directory path))
      (call-with-replacing-output-file path (lambda (port) (write-string text port))))

    ;; Runs a command, raising its standard error if it fails. Tools can be
    ;; overridden by environment variables such as CARGO.
    (define (run-tool variable default . arguments)
      (run-command (cons (or (getenv variable) default) arguments)))

    (define (run-command command)
      (let ((result (capture-process command)))
        (unless (zero? (caddr result))
          (error 'snail (string-append (car command) " failed:\n" (cadr result))))
        (car result)))

    ;; ---- Runtime ----

    ;; The scalar runtime, optionally with the assembler used by compiler
    ;; tools. Separate target directories keep the two artifacts independent;
    ;; Cargo decides whether each needs rebuilding.
    (define (build-runtime root assembler?)
      (run-command (append (list (path-join root "scripts/build-runtime")
                                 (runtime-target root assembler?))
                           (if assembler? '("--features" "assembler") '())))
      (runtime-path root assembler?))

    ;; Where Cargo puts each runtime, without building it.
    (define (runtime-target root assembler?)
      (path-join root
                 (if assembler?
                     "build/wasm-snail-scheme-support-toolchain"
                     "build/wasm-snail-scheme-support")))

    (define (runtime-path root assembler?)
      (path-join (runtime-target root assembler?)
                 "wasm32-wasip1/release/snail_scheme_support.wasm"))

    ;; rustup resolves a toolchain from the working directory, which belongs
    ;; to whoever ran the command: building a project in another directory
    ;; would otherwise compile these crates with whatever toolchain is default
    ;; there, which need not have the pinned `wasm32-wasip1` target.
    ;; rust-toolchain.toml holds the one pin; name its channel explicitly.

    ;; ---- Linking ----

    ;; The support crate's `snail-link`, built for this machine beside the
    ;; toolchain's runtime: the assembler and linker the command line holds,
    ;; for linking the command line itself. Cargo decides whether it is
    ;; stale.
    (define (linker-binary root)
      (let ((target (runtime-target root #t)))
        (run-tool "CARGO" "cargo" (string-append "+" (pinned-channel root))
                  "build" "--quiet" "--release"
                  "--bin" "snail-link" "--features" "assembler"
                  "--manifest-path" (path-join root "crates/snail-scheme-support/Cargo.toml")
                  "--target-dir" target)
        (path-join target "release/snail-link")))

    ;; Assembles the compiler's text at `wat` and links it with `runtime`.
    (define (link-wat-file root wat output runtime)
      (run-command (list (linker-binary root) wat runtime output))
      output)

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-build)
    (import
     (snail stage0 testing))
    (begin
      ;; Simulate a reused process id/counter. The allocator must leave the
      ;; previous compile's directory untouched.
      (define (test-build root)
        (let* ((parent (path-join root "build/snail-run"))
               (old (path-join parent
                               (string-append ".snail-"
                                              (number->string (get-process-id))
                                              "-"
                                              (number->string (+ private-count 1)))))
               (sentinel (path-join old "output.wat")))
          (create-directory* parent)
          (unless (create-directory old #o700) (error 'snail "test scratch collision" old))
          (write-file sentinel "old compile")
          (dynamic-wind (lambda () #f)
              (lambda ()
                (with-private-directory root (lambda (fresh) (expect (string=? old fresh) #f)))
                (expect (read-file sentinel) "old compile"))
              (lambda () (delete-file-hierarchy old)))))))
   (else)))
