;; The command-line driver: one source file to a linked, runnable Wasm
;; program. The compiler runs as a separate program with one interface,
;; `compile MODE SOURCE OUTPUT GENERATED DIRECTORY ...`: normally as Wasm, built
;; from its own source by bootstrapping, and on Chibi only to start a
;; bootstrap. Binaryen assembles, optimizes and links the text with the Rust
;; runtime.
(define-library (snail stage0 build)
  (export
   program->wat
   program->linked-wat
   place-links!
   program->schemas
   build-program
   build-modules
   link-wat
   build-runtime
   build-tool
   build-toolchain-tool
   build-cli-tools
   build-editor-tools
   build-book-tools
   bootstrap!
   standard-directories
   with-private-directory
   program-command
   wasmtime-engine?
   path-join
   absolute
   read-file
   copy-file!
   report-failure)
  (import
   (scheme base)
   (scheme char)
   (scheme cxr)
   (scheme file)
   (scheme process-context)
   (scheme read)
   (scheme write)
   (chibi filesystem)
   (chibi pathname)
   (chibi process)
   (snail stage0 process)
   (only (snail core base)
         match
         Ok
         Err)
   (only (snail shell compiler read)
         loc->string
         diagnostics->string
         compiling
         Failed
         GenerateInput
         ArtifactInput)
   (snail shell compiler inputs)
   (only (chibi string) string-contains string-cursor->index string-suffix?))
  (begin

    ;; ---- Running programs ----

    ;; The command that runs a compiled program, one linked module or the
    ;; modules.json of a per-library build. Node runs it, unless
    ;; SNAIL_ENGINE=wasmtime asks for build/snail, whose `run-wasm` runs a
    ;; program that needs of its host only WASI, the files it links and
    ;; loading modules, and drives its tasks. A program that imports
    ;; sockets or processes stays on Node.
    (define (program-command root program)
      (if (and (wasmtime-engine?) (not (node-hosted? (program-imports root program))))
          (list (snail-binary root) "run-wasm" program)
          (node-command root program)))

    (define (node-command root program)
      (list (or (get-environment-variable "NODE") "node")
            "--no-warnings"
            (path-join root "host/native/run-snail.mjs")
            program))

    ;; The host modules only Node provides; `run-wasm` refuses a program
    ;; that imports one (crates/snail/src/program.rs).
    (define node-hosted-modules
      '("snail.runtime.native.socket" "snail.runtime.native.process" "snail.runtime.native.files"))

    (define (node-hosted? imports)
      (and (pair? imports)
           (or (and (member (car imports) node-hosted-modules) #t) (node-hosted? (cdr imports)))))

    ;; The modules a program's modules import from, which `snail imports`
    ;; reads from their import sections without compiling them.
    (define (program-imports root program)
      (let ((result (capture-process (list (snail-binary root) "imports" program))))
        (unless (zero? (caddr result))
          (error (string-append "snail imports failed:\n" (cadr result))))
        (text-lines (car result))))

    ;; SNAIL_ENGINE names the engine, so a misspelled one is an error rather
    ;; than Node without a word.
    (define (wasmtime-engine?)
      (let ((engine (get-environment-variable "SNAIL_ENGINE")))
        (cond ((member engine '(#f "" "node")) #f)
              ((equal? engine "wasmtime") #t)
              (else (error "SNAIL_ENGINE must be node or wasmtime" engine)))))

    ;; ---- Compiling ----

    ;; The command that runs the compiled compiler `program`, which is an
    ;; ordinary program: Node runs it through host/native/run-snail.mjs by
    ;; default, and with SNAIL_ENGINE=wasmtime, build/snail's `run-wasm`
    ;; does, from its machine code. The native executable stays an opt-in
    ;; because wasmtime's collector makes a compile 9 to 37 times slower
    ;; than on V8 (see "The native executable" in
    ;; doc/book/snail-core/bootstrap.md).
    (define (compiler-command root program)
      (if (wasmtime-engine?)
          (list (snail-binary root) "run-wasm" program)
          (node-command root program)))

    ;; Chibi sweeps its whole heap on every collection, and compiling the
    ;; compiler allocates gigabytes, so a large heap keeps collections rare.
    (define (chibi-compiler root)
      (list (or (get-environment-variable "CHIBI") "chibi-scheme")
            "-h"
            (or (get-environment-variable "SNAIL_STAGE0_HEAP") "6G")
            ;; Stage 0 sees only bootstrap/chibi-include, which symlinks the
            ;; libraries the compiler's own load closure reaches and nothing
            ;; else, so no other library under src/ can enter the bootstrap.
            "-I"
            (path-join root "bootstrap/chibi-include")
            (path-join root "host/chibi/compile.scm")))

    ;; The command that runs a compiler. The compiled compiler is rebuilt
    ;; first when its source has changed, and on wasmtime it runs from its
    ;; machine code; SNAIL_STAGE0=chibi runs the source on Chibi instead.
    (define (selected-compiler root)
      (cond ((equal? (get-environment-variable "SNAIL_STAGE0") "chibi") (chibi-compiler root))
            ((wasmtime-engine?) (compiler-command root (precompiled-compiler root)))
            (else (compiler-command root (current-compiler root)))))

    (define (program->wat root directories source)
      (run-compiler root (selected-compiler root) "wat" directories source))

    ;; The program's text with the files it links, (TEXT (NAME . PATH) ...),
    ;; for a caller that links the text itself and places the files.
    (define (program->linked-wat root directories source)
      (with-private-directory root
                              (lambda (directory)
                                (let ((output (path-join directory "output.wat")))
                                  (run-compiler-into root
                                                     (selected-compiler root)
                                                     "wat"
                                                     directories
                                                     source
                                                     output
                                                     directory)
                                  (cons (read-file output) (read-links directory))))))

    (define (program->schemas root directories source)
      (run-compiler root (selected-compiler root) "schema" directories source))

    ;; Each compile works in a directory of its own, for its output and the
    ;; libraries its producers generate, and removes it when done, as Cargo
    ;; gives each unit its own output directory. Compiles running at once in
    ;; one checkout, as the suite's do, never share a file.
    (define (run-compiler root command mode directories source)
      (with-private-directory root
                              (lambda (directory)
                                (let ((output (path-join directory "output.wat")))
                                  (run-compiler-into root
                                                     command
                                                     mode
                                                     directories
                                                     source
                                                     output
                                                     directory)
                                  (read-file output)))))

    ;; Every library that ships with the language, Snail-Core's own and Scheme's
    ;; alike, lives under src/. Stage 0 reaches it through
    ;; bootstrap/chibi-include instead, so `(scheme base)` here cannot shadow
    ;; the Scheme that runs stage 0.
    (define (standard-directories root)
      (list (path-join root "src")))

    (define (with-private-directory root use)
      (let ((directory (private-directory root)))
        (dynamic-wind (lambda () #f)
            (lambda () (use directory))
            (lambda () (delete-file-hierarchy directory)))))

    (define private-count 0)

    (define (private-directory root)
      (let ((directory (path-join root "build/snail-run")))
        (unless (create-directory* directory)
          (error "cannot create compiler scratch directory" directory))
        (create-staging-directory directory)))

    ;; Remove the old request immediately before starting each process;
    ;; stderr is only diagnostic text, never a work request. Only the
    ;; compile's own exit, status 1 (waitpid status 256), can supply a
    ;; request; a trap or a failure of the host is status 2 and must not
    ;; consume a partial file.
    ;; Nested producer compiles have their own scratch.
    (define (run-compiler-into root command mode directories source output generated)
      (let ((request (path-join generated "request.datum")))
        (let loop ()
          (when (file-link-status request) (delete-file request))
          (let ((result (capture-process
                         (append command (list mode source output generated) directories))))
            (cond ((zero? (caddr result))
                   (when (file-link-status request)
                     (error "compiler succeeded with a pending input request"))
                   output)
                  ((and (= (caddr result) 256) (file-link-status request))
                   (provide-input! root
                                   directories
                                   generated
                                   (published-request request))
                   (loop))
                  (else (error (diagnostic (cadr result)))))))))

    ;; The request a compile published, read by the compiler's own grammar;
    ;; a malformed one is an error with its diagnostic.
    (define (published-request request)
      (match (compiling (lambda () (parse-request (read-file request) request)))
        ((Ok parsed) parsed)
        ((Err (Failed diagnostics)) (error (diagnostics->string diagnostics)))
        ((Err stop) (error "reading a request asked for an input" stop))))

    (define (provide-input! root directories generated request)
      (match request
        ((GenerateInput key)
         (when (file-exists? (path-join generated (string-append key ".syntax")))
           (error "compiler requested an already provided generated library" key))
         (produce! root directories generated key))
        ((ArtifactInput name loc)
         (error (string-append (loc->string loc)
                               ": artifact-bundle requires a project build resolver: "
                               name)))))

    ;; The compiler's message without the host's prefix.
    (define (diagnostic text)
      (let* ((cursor (string-contains text "snail: "))
             (start (if cursor (+ (string-cursor->index text cursor) 6) 0)))
        (let loop ((end (string-length text)))
          (if (and (> end start) (char=? (string-ref text (- end 1)) #\newline))
              (loop (- end 1))
              (substring text start end)))))

    ;; ---- Generated libraries ----

    ;; A `generate-library` recipe becomes a producer program, which
    ;; bootstrap/compile.sld writes into the compile's directory under the
    ;; hash of its text: KEY.sld is the producer, and KEY.syntax the
    ;; library's syntax, which the producer writes to the path it is given.
    ;; A producer may read files the key does not cover, so nothing produced
    ;; outlives the compile that needed it.
    (define (produce! root directories generated key)
      (when (member key (producing)) (error "generated library cycle through the producer" key))
      (parameterize ((producing (cons key (producing))))
        (let* ((source (path-join generated (string-append key ".sld")))
               (program (path-join generated (string-append key ".wasm")))
               (output (path-join generated (string-append key ".syntax")))
               (result (begin
                         (build-program root
                                        directories
                                        source
                                        program
                                        #f
                                        (build-runtime root #f))
                         (run-wasm root program (list output)))))
          (unless (zero? (caddr result))
            (error (string-append "the producer " source " failed:\n" (cadr result))))
          (unless (file-exists? output)
            (error "the producer did not write its generated library" source)))))

    ;; The keys of the producers being built, innermost first. The compiler
    ;; reports a producer that leads back to the library it generates as an
    ;; import cycle, through the `(generating ...)` stack it prints. Each
    ;; nested compile has scratch of its own, so were that check missed, the
    ;; same producer would be requested inside itself without end; this
    ;; makes it an error instead.
    (define producing (make-parameter '()))

    ;; ---- The build lock ----

    ;; What every build in a checkout shares, the compiled compiler and the
    ;; development tools, is rebuilt under an exclusive lock on build/lock,
    ;; as Cargo locks its target directory, so a second process waits
    ;; rather than building over the first. A process takes it once, however
    ;; deep the rebuild that needs it.
    (define build-lock-held? #f)

    (define (with-build-lock root thunk)
      (if build-lock-held?
          (thunk)
          (begin
            (create-directory* (path-join root "build"))
            (let ((port (open-output-file (path-join root "build/lock"))))
              (dynamic-wind (lambda () (file-lock port lock/exclusive) (set! build-lock-held? #t))
                  thunk
                  (lambda ()
                    (set! build-lock-held? #f)
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
           (> (file-modification-time output) (apply max (map newest-time sources)))))

    (define (newest-time path)
      (if (file-directory? path) (newest-sld-time path) (file-modification-time path)))

    (define (newest-sld-time directory)
      (let loop ((entries (directory-files directory)) (newest 0))
        (cond ((null? entries) newest)
              ((member (car entries) '("." "..")) (loop (cdr entries) newest))
              (else
               (let ((path (path-join directory (car entries))))
                 (loop (cdr entries)
                       (max newest (cond ((file-directory? path) (newest-sld-time path))
                                         ((string-suffix? ".sld" path)
                                          (file-modification-time path))
                                         (else 0)))))))))

    ;; ---- Bootstrap ----

    ;; The compiler compiles itself until its output stops changing: stage 1
    ;; is built by the previous compiler if it can, or else by Chibi running
    ;; the source; stage 2 by stage 1; and stage 2 must reproduce its own text.
    (define (compiler-path root)
      (path-join root "build/compiler/snailc.wasm"))

    ;; The compiled compiler, rebuilt when it is older than its own source:
    ;; its entry program, its modules, the three libraries it imports, and
    ;; the primitives they are built on.
    (define (current-compiler root)
      (rebuild-if-stale! root (compiler-path root)
                         (map (lambda (path) (path-join root path))
                              '("bootstrap/compile.sld"
                                "src/snail/shell/compiler.sld"
                                "src/snail/shell/compiler"
                                "src/snail/core/base.sld"
                                "src/snail/core/table.sld"
                                "src/snail/core/io.sld"
                                "src/snail/core/primitive.sld"))
                         (lambda () (rebuild-compiler! root))))

    ;; The native executable is built only for the engine that runs on it:
    ;; with Node the default, a bootstrap never waits on a wasmtime build.
    (define (bootstrap! root)
      (when (wasmtime-engine?) (snail-binary root))
      (with-build-lock root (lambda () (rebuild-compiler! root))))

    ;; The current compiler as machine code for build/snail's engine, which
    ;; saves each compile the most of a second Cranelift takes to compile
    ;; it. It is rebuilt when the compiler or the executable is newer;
    ;; `precompile` renames it into place, so a compile never loads half of one.
    (define (precompiled-compiler root)
      (let ((module (current-compiler root))
            (binary (snail-binary root))
            (code (path-join root "build/compiler/snailc.cwasm")))
        (rebuild-if-stale! root code (list module binary)
                           (lambda () (run-command (list binary "precompile" module code))))))

    ;; Stage 1 is the source's output for its own entry program, from the
    ;; previous compiler when one works and from Chibi otherwise; stage 2 is
    ;; stage 1's, and stage 3 is stage 2's. Stage 2 must reproduce its own
    ;; text. When Chibi produced stage 1, both hosts ran the same source on
    ;; the same input, so stage 1 must be that text as well: the two hosts
    ;; agree, or the build says where they differ.
    (define (rebuild-compiler! root)
      (let* ((directory (path-join root "build/compiler"))
             (entry (path-join root "bootstrap/compile.sld"))
             (stage1 (path-join directory "stage1.wasm"))
             (stage2 (path-join directory "stage2.wasm"))
             (stage3 (path-join directory "stage3.wat")) (sources (standard-directories root)))
        (create-directory* directory)
        (let ((first (stage1-text root entry)))
          (link-wat root (cdr first) stage1 #f)
          (link-wat root
                    (run-compiler root (compiler-command root stage1) "wat" sources entry)
                    stage2
                    #f)
          (write-file stage3 (run-compiler root (compiler-command root stage2) "wat" sources entry))
          (unless (equal? (read-file (string-append stage2 ".wat")) (read-file stage3))
            (error
             "bootstrap: stage 2 does not reproduce its own text; compare build/compiler/stage2.wasm.wat with stage3.wat"))
          (when (and (car first)
                     (not (equal? (cdr first) (read-file (string-append stage2 ".wat")))))
            (error
             "bootstrap: the source on Chibi and its compiled form emit different text; compare build/compiler/stage1.wasm.wat with stage2.wasm.wat"))
          (rename-file stage2 (compiler-path root)))))

    ;; Whether Chibi produced the text, and the text.
    (define (stage1-text root entry)
      (let* ((previous (compiler-path root)) (sources (standard-directories root))
             (reused (and (file-exists? previous)
                          (guard (failure (#t #f))
                            (run-compiler root
                                          (compiler-command root previous)
                                          "wat"
                                          sources
                                          entry)))))
        (if reused
            (cons #f reused)
            (cons #t (run-compiler root (chibi-compiler root) "wat" sources entry)))))

    ;; ---- Files and commands ----

    (define (path-join . parts)
      (path-normalize (apply make-path parts)))

    ;; A path the user gave, relative to the current directory.
    (define (absolute path)
      (if (path-absolute? path) path (path-join (current-directory) path)))

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
      (call-with-output-file path (lambda (port) (write-string text port))))

    (define (copy-file! from to)
      (let ((bytes (call-with-port (open-binary-input-file from)
                     (lambda (port) (read-bytevector (file-size from) port)))))
        (call-with-port (open-binary-output-file to)
          (lambda (port) (write-bytevector bytes port)))))

    ;; Runs a compiled program, returning (output error status).
    (define (run-wasm root program arguments)
      (capture-process (append (program-command root program) arguments)))

    ;; Runs a command, raising its standard error if it fails. Tools can be
    ;; overridden by environment variables such as WASM_OPT.
    (define (run-tool variable default . arguments)
      (run-command (cons (or (get-environment-variable variable) default) arguments)))

    (define (run-command command)
      (let ((result (capture-process command)))
        (unless (zero? (caddr result))
          (error (string-append (car command) " failed:\n" (cadr result))))
        (car result)))

    (define wasm-features
      '("--enable-gc" "--enable-reference-types" "--enable-tail-call" "--enable-bulk-memory"
        "--enable-nontrapping-float-to-int" "--enable-sign-ext" "--enable-mutable-globals"))

    (define (optimization release?)
      ;; Libraries built apart, and plugins loaded at run time, read one
      ;; another's structs and call one another's closures. Closed-world
      ;; mode assumes nothing outside a module does.
      (if release?
          '("-O3" "--always-inline-max-function-size=40" "--converge")
          '("-O1")))

    (define (wasm-opt input output . flags)
      (apply run-tool
             "WASM_OPT"
             "wasm-opt"
             "-g"
             (append wasm-features flags (list input "-o" output))))

    ;; ---- Runtime ----

    ;; The Rust runtime is a reactor built for WASI. The adapter routes its
    ;; diagnostics and exports the cleanup entry point the host calls.
    (define adapter-text
      "(module
  (import \"snail.core.support\" \"snail:report-error\" (func $report (param i32 i32)))
  (import \"snail.core.support\" \"snail:io/close-all\" (func $close (result i32)))
  (export \"diagnostics/report-error\" (func $report))
  (export \"close-resources\" (func $close)))\n")

    ;; The scalar runtime, optionally with the assembler used by compiler
    ;; tools. Separate target directories keep the two artifacts independent;
    ;; Cargo decides whether each needs rebuilding.
    (define (build-runtime root assembler?)
      (let ((target (path-join root
                               (if assembler?
                                   "build/wasm-snail-core-support-toolchain"
                                   "build/wasm-snail-core-support"))))
        (apply run-tool "CARGO" "cargo" (string-append "+" (pinned-channel root))
               "rustc" "--crate-type=cdylib" "--quiet" "--offline" "--release"
               "--target" "wasm32-wasip1"
               "--manifest-path" (path-join root "crates/snail-core-support/Cargo.toml")
               "--target-dir" target
               (if assembler? '("--features" "assembler") '()))
        (path-join target "wasm32-wasip1/release/snail_core_support.wasm")))

    ;; rustup resolves a toolchain from the working directory, which belongs
    ;; to whoever ran the command: building a project in another directory
    ;; would otherwise compile these crates with whatever toolchain is default
    ;; there, which need not have the pinned `wasm32-wasip1` target.
    ;; rust-toolchain.toml holds the one pin; name its channel explicitly.
    (define (pinned-channel root)
      (let* ((path (path-join root "rust-toolchain.toml"))
             (channel (quoted-value (read-file path) "channel")))
        (or channel (error "rust-toolchain.toml must name a channel" path))))

    ;; The text between the first pair of double quotes at or after KEY.
    (define (quoted-value text key)
      (let* ((at (string-contains text key))
             (rest (and at (substring text (string-cursor->index text at) (string-length text))))
             (open (and rest (string-contains rest "\"")))
             (tail (and open
                        (substring rest
                                   (+ (string-cursor->index rest open) 1)
                                   (string-length rest))))
             (close (and tail (string-contains tail "\""))))
        (and close (substring tail 0 (string-cursor->index tail close)))))

    (define (link module output runtime release?)
      (let ((adapter (string-append output ".adapter.wasm"))
            (linked (string-append output ".linked.wasm"))
            (adapter-wat (string-append output ".adapter.wat")))
        (write-file adapter-wat adapter-text)
        (apply run-tool "WASM_AS" "wasm-as" (append wasm-features (list adapter-wat "-o" adapter)))
        (apply run-tool "WASM_MERGE" "wasm-merge" "-g"
               (append wasm-features
                       (list module
                             "snail.abi"
                             runtime
                             "snail.core.support"
                             adapter
                             "snail.platform"
                             "-o"
                             linked)))
        (apply wasm-opt
               linked
               output
               "--remove-exports"
               "--pass-arg=remove-exports@snail:*,diagnostics/*"
               (optimization release?))))

    ;; ---- The native executable ----

    ;; build/snail: crates/snail built for this machine, an executable that
    ;; embeds wasmtime and runs the compiled compiler and compiled programs
    ;; as Node does. Cargo decides whether it is stale, once per process,
    ;; since every compile and run asks; build/snail links to its output.
    (define snail-built? #f)

    (define (snail-binary root)
      (let ((link (path-join root "build/snail")))
        (unless snail-built?
          (run-tool "CARGO" "cargo" (string-append "+" (pinned-channel root))
                    "build" "--quiet" "--offline" "--release"
                    "--manifest-path" (path-join root "crates/snail/Cargo.toml")
                    "--target-dir" (path-join root "build/native-snail"))
          (unless (file-link-status link) (symbolic-link-file "native-snail/release/snail" link))
          (set! snail-built? #t))
        link))

    ;; ---- Artifacts ----

    ;; Writes OUTPUT from module text, keeping the text and intermediate
    ;; modules beside it.
    (define (link-wat root text output release?)
      (let ((wat (string-append output ".wat")))
        (write-file wat text)
        (link-wat-file wat output release? (build-runtime root #f))))

    ;; The compiler already wrote this text. Assemble its file directly, and
    ;; link it with `runtime`; only callers that hold text need link-wat's
    ;; materialization above.
    (define (link-wat-file wat output release? runtime)
      (let ((raw (string-append output ".raw.wasm")) (module (string-append output ".module.wasm")))
        (apply run-tool "WASM_AS" "wasm-as" "-g" (append wasm-features (list wat "-o" raw)))
        (apply wasm-opt raw module (optimization release?))
        (link module output runtime release?)
        output))

    (define (build-program root directories source output release? runtime)
      (let ((wat (string-append output ".wat")))
        (create-directory* (path-directory output))
        (let ((links (with-private-directory root
                                             (lambda (directory)
                                               (run-compiler-into root
                                                                  (selected-compiler root)
                                                                  "wat"
                                                                  directories
                                                                  source
                                                                  wat
                                                                  directory)
                                               (read-links directory)))))
          (link-wat-file wat output release? runtime)
          (place-links! links (path-directory output))
          output)))

    ;; Exclusive creation owns exactly this staging directory. A stale name
    ;; from a reused process id is skipped, never adopted or removed.
    (define (create-staging-directory output)
      (set! private-count (+ private-count 1))
      (let ((directory (path-join output
                                  (string-append ".snail-"
                                                 (number->string (current-process-id))
                                                 "-"
                                                 (number->string private-count)))))
        (cond ((create-directory directory #o700) directory)
              ((file-link-status directory) (create-staging-directory output))
              (else (error "cannot stage program in output directory" output)))))

    ;; ---- Linked files ----

    ;; The files a compile reports its program links, as (NAME . PATH)
    ;; pairs, from the `("NAME" "PATH")` lines the driver writes to
    ;; links.datum in the compile's directory.
    (define (read-links directory)
      (call-with-input-file (path-join directory "links.datum")
        (lambda (port)
          (let loop ((links '()))
            (let ((entry (read port)))
              (if (eof-object? entry)
                  (reverse links)
                  (loop (cons (cons (car entry) (cadr entry)) links))))))))

    ;; Each file goes to resources/NAME in `directory`, beside the payload,
    ;; where both hosts read it before the program starts.
    (define (place-links! links directory)
      (for-each (lambda (link)
                  (let ((to (path-join directory "resources" (car link))))
                    (create-directory* (path-directory to))
                    (copy-file! (cdr link) to)))
                links))

    ;; ---- Linked modules ----

    ;; A program linked when it runs: each library's module, assembled but
    ;; not optimized, the runtime beside them, and modules.json naming the
    ;; modules in program order for the loader in host/browser/load.mjs.
    (define (build-modules root directories source output)
      (create-directory* output)
      (let* ((links (with-private-directory root
                                            (lambda (generated)
                                              (run-compiler-into root
                                                                 (selected-compiler root)
                                                                 "modules"
                                                                 directories
                                                                 source
                                                                 output
                                                                 generated)
                                              (read-links generated))))
             (names (read-lines (path-join output "modules"))))
        (for-each (lambda (name) (assemble (path-join output name))) names)
        (copy-file! (build-runtime root #f) (path-join output "runtime.wasm"))
        (write-file (path-join output "modules.json") (modules-json names))
        (place-links! links output)
        output))

    ;; PATH.wat to PATH.wasm.
    (define (assemble path)
      (apply run-tool
             "WASM_AS"
             "wasm-as"
             "-g"
             (append wasm-features
                     (list (string-append path ".wat") "-o" (string-append path ".wasm")))))

    (define (read-lines path)
      (text-lines (read-file path)))

    ;; Each line of TEXT that a newline ends.
    (define (text-lines text)
      (let loop ((lines '()) (rest text))
        (let ((cursor (string-contains rest "\n")))
          (if cursor
              (let ((end (string-cursor->index rest cursor)))
                (loop (cons (substring rest 0 end) lines)
                      (substring rest (+ end 1) (string-length rest))))
              (reverse lines)))))

    (define (modules-json names)
      (string-append "{\"runtime\": \"runtime.wasm\", \"modules\": ["
                     (let loop ((names names) (out ""))
                       (if (null? names)
                           out
                           (loop (cdr names)
                                 (string-append out
                                                (if (string=? out "") "" ", ")
                                                "{\"name\": \""
                                                (car names)
                                                "\", \"file\": \"" (car names) ".wasm\"}"))))
                     "]}\n"))

    ;; ---- Development tools ----

    ;; The `snail` command line, a Snail program that builds projects with
    ;; the compiler inside it, linked with the toolchain's runtime, which
    ;; assembles a development build's modules; and the runtime it links
    ;; programs with.
    (define (build-cli-tools root)
      (list (build-toolchain-tool root
                                  (path-join root "bootstrap/cli.sld")
                                  (path-join root "build/project/cli.wasm")
                                  (standard-directories root))
            (build-runtime root #f)))

    ;; The development service adds two programs to the command line's
    ;; tools, whose `resident` builds for it: the editor, the interface it
    ;; serves, and the reload client its browser targets' pages load.
    (define (build-editor-tools root)
      (append (list (build-tool root
                                (path-join root "host/ide/ide.sld")
                                (path-join root "build/ide-tools/ide.wasm")
                                (standard-directories root))
                    (build-tool root
                                (path-join root "host/browser/reload.sld")
                                (path-join root "build/ide-tools/reload.wasm")
                                (standard-directories root)))
              (build-cli-tools root)))

    ;; The book's highlighter, the preprocessor scripts/highlight-book runs
    ;; while mdbook builds the book.
    (define (build-book-tools root)
      (list (build-tool root
                        (path-join root "bootstrap/highlight-book.sld")
                        (path-join root "build/book-tools/highlight-book.wasm")
                        (standard-directories root))))

    ;; A program the tools run, built from `source` with the libraries in
    ;; `directories` when it is stale.
    (define (build-tool root source output directories)
      (rebuild-if-stale! root
                         output
                         (cons source directories)
                         (lambda ()
                           (build-program root
                                          directories
                                          source
                                          output
                                          #f
                                          (build-runtime root #f)))))

    ;; A tool linked with the toolchain's runtime, which it is rebuilt
    ;; after, as after its sources.
    (define (build-toolchain-tool root source output directories)
      (let ((runtime (build-runtime root #t)))
        (rebuild-if-stale! root
                           output
                           (cons runtime (cons source directories))
                           (lambda () (build-program root directories source output #f runtime)))))

    ;; ---- Failures ----

    ;; Prints a failure as one diagnostic after the command's name, without
    ;; Chibi's trace, and returns the status the command exits with.
    (define (report-failure command failure)
      (let ((port (current-error-port)))
        (display command port)
        (display ": " port)
        (display (failure-message failure) port)
        (newline port)
        1))

    (define (failure-message failure)
      (let ((port (open-output-string)))
        (if (error-object? failure)
            (begin (display (error-object-message failure) port)
                   (for-each (lambda (irritant) (display " " port) (write irritant port))
                             (error-object-irritants failure)))
            (write failure port))
        (get-output-string port)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-build)
    (import
     (snail stage0 testing))
    (begin
      (define (request-failure thunk)
        (guard (failure (#t (failure-message failure))) (thunk) "accepted"))

      (define (test-request root scenario prepare)
        (with-private-directory root
                                (lambda (directory)
                                  (prepare directory)
                                  (run-compiler-into root
                                                     (list "sh"
                                                           (path-join root
                                                                      "tests/compiler-inputs/compiler.sh")
                                                           scenario)
                                                     "wat"
                                                     '()
                                                     "source.sld"
                                                     (path-join directory "output.wat")
                                                     directory))))

      (define (expect-request-error thunk wanted)
        (let ((actual (request-failure thunk)))
          (expect (if (string-contains actual wanted) wanted actual) wanted)))

      ;; Exercise the real stage-0 unwind wrapper: uncaught Chibi errors use
      ;; exit 70, so re-raising would silently break the exit-1 protocol. A
      ;; request that cannot be written is an ordinary failure, status 1
      ;; with a diagnostic naming the file, and leaves no request behind.
      (define (test-source-request-status root)
        (with-private-directory root
                                (lambda (directory)
                                  (let* ((request (path-join directory "request.datum"))
                                         (command (append (chibi-compiler root)
                                                          (list "wat"
                                                                (path-join root
                                                                           "tests/artifacts/native.sld")
                                                                (path-join directory "output.wat")
                                                                directory
                                                                (path-join root "src")))))
                                    (expect (caddr (capture-process command)) 256)
                                    (expect (match (published-request request)
                                              ((ArtifactInput "client" _) #t) (_ #f)) #t)
                                    (delete-file request)
                                    (create-directory request)
                                    (let ((failed (capture-process command)))
                                      (expect (caddr failed) 256)
                                      (expect
                                       (and (string-contains (cadr failed) "request.datum") #t)
                                       #t))))))

      (define (test-build root)
        (test-source-request-status root)
        (expect-request-error
         (lambda ()
           (test-request root
                         "stderr"
                         (lambda (directory)
                           (write-file (path-join directory "request.datum")
                                       "(artifact \"stale\" \"old.sld\" 1 1)"))))
         "generate 123")
        (test-request root
                      "stale"
                      (lambda (directory)
                        (write-file (path-join directory "request.datum") "(generate \"123\")")))
        (expect-request-error (lambda () (test-request root "malformed" (lambda (_) #f)))
                              "expected exactly one")
        (expect-request-error (lambda () (test-request root "success-request" (lambda (_) #f)))
                              "succeeded with a pending")
        (expect-request-error (lambda () (test-request root "publication-failed" (lambda (_) #f)))
                              "input publication failed")
        (expect-request-error (lambda ()
                                (test-request root
                                              "generated"
                                              (lambda (directory)
                                                (write-file (path-join directory "123.syntax")
                                                            "()"))))
                              "already provided generated library")
        (expect-request-error (lambda () (test-request root "artifact" (lambda (_) #f)))
                              "application.sld:3:8: artifact-bundle requires a project build resolver")
        ;; Simulate a reused process id/counter. The allocator must leave
        ;; the previous compile and its stale generated input untouched.
        (let* ((parent (path-join root "build/snail-run"))
               (old (path-join parent
                               (string-append ".snail-"
                                              (number->string (current-process-id))
                                              "-"
                                              (number->string (+ private-count 1)))))
               (sentinel (path-join old "123.syntax")))
          (unless (create-directory old #o700) (error "test scratch collision" old))
          (write-file sentinel "old compile")
          (dynamic-wind (lambda () #f)
              (lambda ()
                (with-private-directory root (lambda (fresh) (expect (string=? old fresh) #f)))
                (expect (read-file sentinel) "old compile"))
              (lambda () (delete-file-hierarchy old)))))))
   (else)))
