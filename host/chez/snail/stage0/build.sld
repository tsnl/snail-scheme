;; The command-line driver: one source file to a linked, runnable Wasm
;; program. The compiler runs as a separate program with one interface,
;; `compile MODE SOURCE OUTPUT GENERATED DIRECTORY ...`: normally as Wasm, built
;; from its own source by bootstrapping, and on Chez only to start a
;; bootstrap. The native executable assembles and links through the same
;; Rust backend compiled tools use.
(define-library (snail stage0 build)
  (export
   program->wat
   program->linked-wat
   place-links!
   place-object!
   file-bytes
   program->schemas
   build-program
   build-modules
   link-wat
   build-runtime
   build-tool
   build-toolchain-tool
   build-cli-tools
   build-engine
   build-editor-tools
   build-book-tools
   build-format-tools
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
   (chezscheme)
   (snail stage0 system)
   (snail stage0 process)
   (only (snail core base) match Ok Err)
   (only (snail shell compiler read) loc->string diagnostics->string compiling Failed GenerateInput ArtifactInput)
   (snail shell compiler inputs)
   (only (snail shell compiler sha256) sha256 bytes->hex))
  (begin

    ;; ---- Running programs ----

    ;; The command that runs a compiled program, one linked module or the
    ;; modules.json of a per-library build, which the engine links
    ;; (bootstrap/engine.sld), built first when it is stale. Node runs it,
    ;; unless SNAIL_ENGINE=wasmtime asks for build/snail, whose `run-wasm`
    ;; runs a program that needs of its host only WASI, the files it links
    ;; and loading modules, and drives its tasks. A program that imports
    ;; sockets or processes stays on Node.
    (define (program-command root program)
      (when (string-suffix? ".json" program) (build-engine root))
      (if (and (wasmtime-engine?) (not (node-hosted? (program-imports root program))))
          (list (snail-binary root) "run-wasm" program)
          (node-command root program)))

    (define (node-command root program)
      (list (or (getenv "NODE") "node")
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
          (error 'snail (string-append "snail imports failed:\n" (cadr result))))
        (text-lines (car result))))

    ;; SNAIL_ENGINE names the engine, so a misspelled one is an error rather
    ;; than Node without a word.
    (define (wasmtime-engine?)
      (let ((engine (getenv "SNAIL_ENGINE")))
        (cond ((member engine '(#f "" "node")) #f)
              ((equal? engine "wasmtime") #t)
              (else (error 'snail "SNAIL_ENGINE must be node or wasmtime" engine)))))

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

    ;; Chez compiles the erased source closure to native code. The loader
    ;; admits the compiler and its host boundary, never application libraries.
    (define (chez-compiler root)
      (list (or (getenv "CHEZ") "scheme") "--script"
            (path-join root "host/chez/load.scm") root "compile"))

    ;; The command that runs a compiler. The compiled compiler is rebuilt
    ;; first when its source has changed, and on wasmtime it runs from its
    ;; machine code; SNAIL_STAGE0=chez runs the source on Chez instead.
    (define (selected-compiler root)
      (cond ((equal? (getenv "SNAIL_STAGE0") "chez") (chez-compiler root))
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
                     (error 'snail "compiler succeeded with a pending input request"))
                   output)
                  ((and (= (caddr result) 256) (file-link-status request))
                   (provide-input! root
                                   directories
                                   generated
                                   (published-request request))
                   (loop))
                  (else (error 'snail (diagnostic (cadr result)))))))))

    ;; The request a compile published, read by the compiler's own grammar;
    ;; a malformed one is an error with its diagnostic.
    (define (published-request request)
      (match (compiling (lambda () (parse-request (read-file request) request)))
        ((Ok parsed) parsed)
        ((Err (Failed diagnostics)) (error 'snail (diagnostics->string diagnostics)))
        ((Err stop) (error 'snail "reading a request asked for an input" stop))))

    (define (provide-input! root directories generated request)
      (match request
        ((GenerateInput key)
         (when (file-exists? (path-join generated (string-append key ".syntax")))
           (error 'snail "compiler requested an already provided generated library" key))
         (produce! root directories generated key))
        ((ArtifactInput name loc)
         (error 'snail (string-append (loc->string loc)
                               ": artifact-bundle requires a project build resolver: "
                               name)))))

    ;; The compiler's message without the host's prefix.
    (define (diagnostic text)
      (let* ((cursor (string-contains text "snail: "))
             (start (if cursor (+ cursor 6) 0)))
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
      (when (member key (producing)) (error 'snail "generated library cycle through the producer" key))
      (parameterize ((producing (cons key (producing))))
        (let* ((source (path-join generated (string-append key ".sld")))
               (program (path-join generated (string-append key ".wasm")))
               (output (path-join generated (string-append key ".syntax")))
               (result (begin
                         (build-program root
                                        directories
                                        source
                                        program
                                        (build-runtime root #f))
                         (run-wasm root program (list output)))))
          (unless (zero? (caddr result))
            (error 'snail (string-append "the producer " source " failed:\n" (cadr result))))
          (unless (file-exists? output)
            (error 'snail "the producer did not write its generated library" source)))))

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
                                         ((or (string-suffix? ".sld" path) (string-suffix? ".sls" path) (string-suffix? ".scm" path))
                                          (modification-nanoseconds path))
                                         (else 0)))))))))

    ;; ---- Bootstrap ----

    ;; The compiler compiles itself until its output stops changing: stage 1
    ;; is built by the previous compiler if it can, or else by Chez running
    ;; the source; stage 2 by stage 1; and stage 2 must reproduce its own text.
    (define (compiler-path root)
      (path-join root "build/compiler/snailc.wasm"))

    ;; The compiled compiler, rebuilt when it is older than its own source:
    ;; its entry program, its modules, the three libraries it imports, and
    ;; the primitives they are built on.
    (define (current-compiler root)
      (rebuild-if-stale! root (compiler-path root)
                         (map (lambda (path) (path-join root path))
                              '("host/chez"
                                "crates/snail-core-support/src/assembler.rs"
                                "bootstrap/compile.sld"
                                "src/snail/shell/compiler.sld"
                                "src/snail/shell/compiler"
                                "src/snail/core/base.sld"
                                "src/snail/core/table.sld"
                                "src/snail/core/io.sld"
                                "src/snail/core/primitive.sld"))
                         (lambda () (rebuild-compiler! root))))

    ;; Stage 0 uses the native assembler/linker regardless of the engine
    ;; selected for running the resulting modules.
    (define (bootstrap! root)
      (snail-binary root)
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
    ;; previous compiler when one works and from Chez otherwise; stage 2 is
    ;; stage 1's, and stage 3 is stage 2's. Stage 2 must reproduce its own
    ;; text. When Chez produced stage 1, both hosts ran the same source on
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
          (link-wat root (cdr first) stage1)
          (link-wat root
                    (run-compiler root (compiler-command root stage1) "wat" sources entry)
                    stage2)
          (write-file stage3 (run-compiler root (compiler-command root stage2) "wat" sources entry))
          (unless (equal? (read-file (string-append stage2 ".wat")) (read-file stage3))
            (error 'snail "bootstrap: stage 2 does not reproduce its own text; compare build/compiler/stage2.wasm.wat with stage3.wat"))
          (when (and (car first)
                     (not (equal? (cdr first) (read-file (string-append stage2 ".wat")))))
            (error 'snail "bootstrap: the source on Chez and its compiled form emit different text; compare build/compiler/stage1.wasm.wat with stage2.wasm.wat"))
          (rename-file stage2 (compiler-path root)))))

    ;; Whether Chez produced the text, and the text.
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
            (cons #t (run-compiler root (chez-compiler root) "wat" sources entry)))))

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
      (call-with-replacing-output-file path (lambda (port) (write-string text port))))

    (define (copy-file! from to)
      (write-bytes! to (file-bytes from)))

    (define (file-bytes path)
      (call-with-port (open-binary-input-file path)
        (lambda (port) (read-bytevector (file-size path) port))))

    (define (write-bytes! path bytes)
      (call-with-port (open-binary-output-file path)
        (lambda (port) (write-bytevector bytes port))))

    ;; Runs a compiled program, returning (output error status).
    (define (run-wasm root program arguments)
      (capture-process (append (program-command root program) arguments)))

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
        (or channel (error 'snail "rust-toolchain.toml must name a channel" path))))

    ;; The text between the first pair of double quotes at or after KEY.
    (define (quoted-value text key)
      (let* ((at (string-contains text key))
             (rest (and at (substring text at (string-length text))))
             (open (and rest (string-contains rest "\"")))
             (tail (and open
                        (substring rest
                                   (+ open 1)
                                   (string-length rest))))
             (close (and tail (string-contains tail "\""))))
        (and close (substring tail 0 close))))

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

    ;; Writes OUTPUT from module text, keeping the text beside it.
    (define (link-wat root text output)
      (let ((wat (string-append output ".wat")))
        (write-file wat text)
        (link-wat-file root wat output (build-runtime root #f))))

    ;; The compiler already wrote this text. Assemble its file directly, and
    ;; link it with `runtime`; only callers that hold text need link-wat's
    ;; materialization above.
    (define (link-wat-file root wat output runtime)
      (run-command (list (snail-binary root) "link" wat runtime output))
      output)

    (define (build-program root directories source output runtime)
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
          (link-wat-file root wat output runtime)
          (place-links! links (path-directory output))
          output)))

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

    ;; ---- Linked files ----

    ;; The files a compile reports its program links, as (DIGEST . PATH)
    ;; pairs, from the `("DIGEST" "PATH")` lines the driver writes to
    ;; links.datum in the compile's directory.
    (define (read-links directory)
      (call-with-input-file (path-join directory "links.datum")
        (lambda (port)
          (let loop ((links '()))
            (let ((entry (read port)))
              (if (eof-object? entry)
                  (reverse links)
                  (loop (cons (cons (car entry) (cadr entry)) links))))))))

    ;; Each file is an object of the store beside the payload in
    ;; `directory`, at store/sha256/DIGEST, where its host reads it when
    ;; the program first asks.
    (define (place-links! links directory)
      (for-each (lambda (link) (place-object! directory (file-bytes (cdr link)))) links))

    ;; Places `bytes` as an object of the store beside the payload in
    ;; `directory`, unless it is there, answering (DIGEST . SIZE) as a
    ;; manifest names it. Chez runs the compiler's SHA-256 implementation
    ;; directly, so both hosts use the same digest algorithm.
    (define (place-object! directory bytes)
      (let* ((digest (bytes->hex (sha256 (list->vector (bytevector->u8-list bytes)))))
             (to (path-join directory "store" "sha256" digest)))
        (create-directory* (path-directory to))
        (unless (file-exists? to) (write-bytes! to bytes))
        (cons digest (bytevector-length bytes))))

    ;; ---- Linked modules ----

    ;; A program linked when it runs: each library's module, assembled but
    ;; not optimized, the runtime, and the files it links, all objects of
    ;; store/ in `output`, and modules.json naming them, the modules in
    ;; program order, for the loader in host/browser/load.mjs. Each
    ;; module's NAME.wasm stays beside its text, for a program that loads
    ;; one by path.
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
        (for-each (lambda (name) (assemble root (path-join output name))) names)
        (let ((runtime (place-object! output (file-bytes (build-runtime root #f))))
              (modules (map (lambda (name)
                              (cons name
                                    (place-object! output
                                                   (file-bytes (path-join output
                                                                          (string-append name
                                                                                         ".wasm"))))))
                            names)))
          (write-file (path-join output "modules.json") (modules-json runtime modules links))
          (place-links! links output)
          output)))

    ;; PATH.wat to PATH.wasm.
    (define (assemble root path)
      (run-command (list (snail-binary root) "assemble"
                         (string-append path ".wat") (string-append path ".wasm"))))

    (define (read-lines path)
      (text-lines (read-file path)))

    ;; Each line of TEXT that a newline ends.
    (define (text-lines text)
      (let loop ((lines '()) (rest text))
        (let ((cursor (string-contains rest "\n")))
          (if cursor
              (let ((end cursor))
                (loop (cons (substring rest 0 end) lines)
                      (substring rest (+ end 1) (string-length rest))))
              (reverse lines)))))

    ;; The manifest: the store beside it, the runtime, each module by name,
    ;; and each linked file, every object by digest with its size.
    (define (modules-json runtime modules links)
      (string-append "{\"store\": \"store/\", \"runtime\": " (object-json runtime)
                     ", \"modules\": ["
                     (joined (map (lambda (module)
                                    (string-append "{\"name\": \"" (car module) "\", "
                                                   (object-members (cdr module)) "}"))
                                  modules))
                     "], \"files\": ["
                     (joined (map (lambda (link)
                                    (object-json (cons (car link) (file-size (cdr link)))))
                                  links))
                     "]}\n"))

    ;; An object as a manifest names it, (DIGEST . SIZE).
    (define (object-json object)
      (string-append "{" (object-members object) "}"))

    (define (object-members object)
      (string-append "\"digest\": \"" (car object) "\", \"size\": " (number->string (cdr object))))

    (define (joined items)
      (let loop ((items items) (out ""))
        (if (null? items)
            out
            (loop (cdr items) (string-append out (if (string=? out "") "" ", ") (car items))))))

    ;; ---- Development tools ----

    ;; The `snail` command line, a Snail program that builds projects with
    ;; the compiler inside it, linked with the toolchain's runtime, which
    ;; assembles a development build's modules; the runtime it links
    ;; programs with; and the engine that runs a development build.
    (define (build-cli-tools root)
      (list (build-toolchain-tool root
                                  (path-join root "bootstrap/cli.sld")
                                  (path-join root "build/project/cli.wasm")
                                  (standard-directories root))
            (build-runtime root #f)
            (build-engine root)))

    ;; The engine, which host/native/run-snail.mjs and `snail run-wasm`
    ;; start to run a program compiled one library at a time, at the path
    ;; both look for it at.
    (define (build-engine root)
      (build-tool root
                  (path-join root "bootstrap/engine.sld")
                  (path-join root "build/engine/engine.wasm")
                  (standard-directories root)))

    ;; The development service adds two programs to the command line's
    ;; tools, whose `resident` builds for it: the editor's browser bundle
    ;; and the reload client its browser targets' pages load.
    (define (build-editor-tools root)
      (let* ((tools (build-cli-tools root))
             (project (path-join root "host/ide")))
        ;; The IDE is an ordinary browser target. Its public assets and
        ;; program are published together by the native project builder.
        (run-command (append (program-command root (car tools))
                             (list root (cadr tools) "build" "--release" project "ide")))
        (append (list (path-join project "build/ide")
                      (build-tool root
                                  (path-join root "host/browser/reload.sld")
                                  (path-join root "build/ide-tools/reload.wasm")
                                  (standard-directories root)))
                tools)))

    ;; The book's highlighter, the preprocessor scripts/highlight-book runs
    ;; while mdbook builds the book.
    (define (build-book-tools root)
      (list (build-tool root
                        (path-join root "bootstrap/highlight-book.sld")
                        (path-join root "build/book-tools/highlight-book.wasm")
                        (standard-directories root))))

    ;; The command-line formatter uses the same library as the browser editor.
    (define (build-format-tools root)
      (list (build-tool root
                        (path-join root "bootstrap/format.sld")
                        (path-join root "build/format-tools/format.wasm")
                        (standard-directories root))))

    ;; A program the tools run, built from `source` with the libraries in
    ;; `directories` when it is stale.
    (define (build-tool root source output directories)
      (rebuild-if-stale! root
                         output
                         (cons (path-join root "host/chez/snail/stage0/build.sld")
                               (cons source directories))
                         (lambda ()
                           (build-program root
                                          directories
                                          source
                                          output
                                          (build-runtime root #f)))))

    ;; A tool linked with the toolchain's runtime, which it is rebuilt
    ;; after, as after its sources.
    (define (build-toolchain-tool root source output directories)
      (let ((runtime (build-runtime root #t)))
        (rebuild-if-stale! root
                           output
                           (cons runtime (cons source directories))
                           (lambda () (build-program root directories source output runtime)))))

    ;; ---- Failures ----

    ;; Prints a failure as one diagnostic after the command's name, without
    ;; Chez's trace, and returns the status the command exits with.
    (define (report-failure command failure)
      (let ((port (current-error-port)))
        (display command port)
        (display ": " port)
        (display (failure-message failure) port)
        (newline port)
        1))

    (define (failure-message failure) (error-text failure))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-build)
    (import
     (only (snail shell compiler sha256) sha256 bytes->hex)
     (snail stage0 testing))
    (begin
      ;; Binary bytes and SHA padding boundaries must name the same objects
      ;; as the portable compiler does, including empty and repeated writes.
      (define (test-object-store root size)
        (with-private-directory root
                                (lambda (directory)
                                  (let ((bytes (make-bytevector size)) (values (make-vector size)))
                                    (do ((i 0 (+ i 1))) ((= i size))
                                      (bytevector-u8-set! bytes i (modulo i 256))
                                      (vector-set! values i (modulo i 256)))
                                    (let* ((digest (bytes->hex (sha256 values)))
                                           (object (place-object! directory bytes)))
                                      (expect object (cons digest size))
                                      (expect (place-object! directory bytes) object)
                                      (expect
                                       (file-bytes (path-join directory "store/sha256" digest))
                                       bytes))))))

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

      ;; Exercise the stage-zero boundary: host exceptions must follow the
      ;; compiler's exit-1 protocol. A
      ;; request that cannot be written is an ordinary failure, status 1
      ;; with a diagnostic naming the file, and leaves no request behind.
      (define (test-source-request-status root)
        (with-private-directory root
                                (lambda (directory)
                                  (let* ((request (path-join directory "request.datum"))
                                         (command (append (chez-compiler root)
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
        (for-each (lambda (size) (test-object-store root size)) '(0 55 56 63 64 65 257))
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
                                              (number->string (get-process-id))
                                              "-"
                                              (number->string (+ private-count 1)))))
               (sentinel (path-join old "123.syntax")))
          (unless (create-directory old #o700) (error 'snail "test scratch collision" old))
          (write-file sentinel "old compile")
          (dynamic-wind (lambda () #f)
              (lambda ()
                (with-private-directory root (lambda (fresh) (expect (string=? old fresh) #f)))
                (expect (read-file sentinel) "old compile"))
              (lambda () (delete-file-hierarchy old)))))))
   (else)))
