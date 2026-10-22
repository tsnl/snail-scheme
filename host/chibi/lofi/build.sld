;; The command-line driver: one source file to a linked, runnable Wasm
;; program. The compiler runs as a separate program with one interface,
;; `compile MODE SOURCE OUTPUT GENERATED DIRECTORY ...`: normally as Wasm, built
;; from its own source by bootstrapping, and on Chibi only to start a
;; bootstrap. Binaryen assembles, optimizes and links the text with the Rust
;; runtime.
(define-library (lofi build)
  (export
   program->wat
   program->schemas
   build-program
   build-modules
   link-wat
   build-runtime
   build-assembler
   build-tools
   bootstrap!
   with-private-directory
   path-join
   report-failure)
  (import
   (scheme base)
   (scheme char)
   (scheme cxr)
   (scheme file)
   (scheme process-context)
   (scheme write)
   (chibi filesystem)
   (chibi pathname)
   (chibi process)
   (only (chibi string) string-contains string-cursor->index string-suffix?))
  (begin

    ;; ---- Compiling ----

    ;; The command that runs a compiler. The compiled compiler is rebuilt
    ;; first when its source has changed; LOFI_STAGE0=chibi runs the source
    ;; on Chibi instead.
    (define (wasm-compiler root path)
      (list (or (get-environment-variable "NODE") "node") "--no-warnings" (path-join root "scripts/run-lofi.mjs") path))

    ;; Chibi sweeps its whole heap on every collection, and compiling the
    ;; compiler allocates gigabytes, so a large heap keeps collections rare.
    (define (chibi-compiler root)
      (list (or (get-environment-variable "CHIBI") "chibi-scheme") "-h" (or (get-environment-variable "LOFI_STAGE0_HEAP") "6G")
            "-I" (path-join root "host/chibi") "-I" (path-join root "src") (path-join root "bootstrap/compile.sld")))

    (define (selected-compiler root)
      (if (equal? (get-environment-variable "LOFI_STAGE0") "chibi")
          (chibi-compiler root)
          (wasm-compiler root (current-compiler root))))

    (define (program->wat root directories source)
      (run-compiler root (selected-compiler root) "wat" directories source))

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
                                  (run-compiler-into root command mode directories source output directory)
                                  (read-file output)))))

    (define (with-private-directory root use)
      (let ((directory (private-directory root)))
        (dynamic-wind (lambda () #f) (lambda () (use directory)) (lambda () (delete-file-hierarchy directory)))))

    (define private-count 0)

    (define (private-directory root)
      (set! private-count (+ private-count 1))
      (let ((directory (path-join root "build/lofi-run"
                                  (string-append (number->string (current-process-id)) "-" (number->string private-count)))))
        (create-directory* directory)
        directory))

    ;; The compiler stops with `generate KEY` when it needs a generated
    ;; library that has not been produced; producing it into `generated` and
    ;; compiling again then finds the syntax the producer wrote, as
    ;; KEY.syntax.
    (define (run-compiler-into root command mode directories source output generated)
      (let ((result (process->output+error+status (append command (list mode source output generated) directories))))
        (cond ((zero? (caddr result)) output)
              ((generate-request (cadr result))
               => (lambda (key)
                    (produce! root directories generated key)
                    (run-compiler-into root command mode directories source output generated)))
              (else (error (diagnostic (cadr result)))))))

    ;; The digits after `generate `, if the compiler asked for a library.
    (define (generate-request text)
      (let ((cursor (string-contains text "generate ")))
        (and cursor
             (let* ((start (+ (string-cursor->index text cursor) 9))
                    (end (let loop ((end start)) (if (and (< end (string-length text)) (char-numeric? (string-ref text end))) (loop (+ end 1)) end))))
               (and (> end start) (substring text start end))))))

    ;; The compiler's message without the host's prefix.
    (define (diagnostic text)
      (let* ((cursor (string-contains text "lofi: "))
             (start (if cursor (+ (string-cursor->index text cursor) 6) 0)))
        (let loop ((end (string-length text)))
          (if (and (> end start) (char=? (string-ref text (- end 1)) #\newline)) (loop (- end 1)) (substring text start end)))))

    ;; ---- Generated libraries ----

    ;; A `generate-library` recipe becomes a producer program, which
    ;; bootstrap/compile.sld writes into the compile's directory under the
    ;; hash of its text: KEY.sld is the producer, and KEY.syntax the
    ;; library's syntax, which the producer writes to the path it is given.
    ;; A producer may read files the key does not cover, so nothing produced
    ;; outlives the compile that needed it.
    (define (produce! root directories generated key)
      (let* ((source (path-join generated (string-append key ".sld")))
             (program (path-join generated (string-append key ".wasm")))
             (output (path-join generated (string-append key ".syntax")))
             (result (begin (build-program root directories source program #f) (run-wasm root program (list output)))))
        (unless (zero? (caddr result)) (error (string-append "the producer " source " failed:\n" (cadr result))))))

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
                  (lambda () (set! build-lock-held? #f) (file-lock port lock/unlock) (close-port port)))))))

    ;; ---- Bootstrap ----

    ;; The compiler compiles itself until its output stops changing: stage 1
    ;; is built by the previous compiler if it can, or else by Chibi running
    ;; the source; stage 2 by stage 1; and stage 2 must reproduce its own text.
    (define (compiler-path root)
      (path-join root "build/compiler/lofic.wasm"))

    (define (compiler-directories root)
      (list (path-join root "src") (path-join root "lib")))

    ;; A stale compiler is rebuilt under the build lock, and only if no other
    ;; process rebuilt it while this one waited.
    (define (current-compiler root)
      (unless (compiler-current? root)
        (with-build-lock root (lambda () (unless (compiler-current? root) (rebuild-compiler! root)))))
      (compiler-path root))

    (define (compiler-current? root)
      (let ((compiler (compiler-path root)))
        (and (file-exists? compiler) (> (file-modification-time compiler) (newest-source-time root)))))

    (define (bootstrap! root)
      (with-build-lock root (lambda () (rebuild-compiler! root))))

    (define (rebuild-compiler! root)
      (let* ((directory (path-join root "build/compiler")) (entry (path-join root "bootstrap/compile.sld"))
             (stage1 (path-join directory "stage1.wasm")) (stage2 (path-join directory "stage2.wasm"))
             (stage3 (path-join directory "stage3.wat")) (sources (compiler-directories root)))
        (create-directory* directory)
        (link-wat root (stage1-text root entry) stage1 #f)
        (link-wat root (run-compiler root (wasm-compiler root stage1) "wat" sources entry) stage2 #f)
        (write-file stage3 (run-compiler root (wasm-compiler root stage2) "wat" sources entry))
        (unless (equal? (read-file (string-append stage2 ".wat")) (read-file stage3))
          (error "bootstrap: stage 2 does not reproduce its own text; compare build/compiler/stage2.wasm.wat with stage3.wat"))
        (rename-file stage2 (compiler-path root))))

    (define (stage1-text root entry)
      (let ((previous (compiler-path root)) (sources (compiler-directories root)))
        (or (and (file-exists? previous)
                 (guard (failure (#t #f)) (run-compiler root (wasm-compiler root previous) "wat" sources entry)))
            (run-compiler root (chibi-compiler root) "wat" sources entry))))

    ;; The compiler's own source: its modules, its entry program, and the
    ;; three libraries it imports.
    (define (newest-source-time root)
      (apply max (map file-modification-time
                      (append (map (lambda (path) (path-join root path))
                                   '("bootstrap/compile.sld" "src/lofi/compiler.sld" "lib/lofi/base.sld" "lib/lofi/table.sld"
                                     "lib/lofi/io.sld"))
                              (sld-files (path-join root "src/lofi/compiler"))))))

    (define (sld-files directory)
      (let loop ((files (directory-files directory)) (out '()))
        (cond ((null? files) out)
              ((and (> (string-length (car files)) 4)
                    (string=? (substring (car files) (- (string-length (car files)) 4) (string-length (car files))) ".sld"))
               (loop (cdr files) (cons (path-join directory (car files)) out)))
              (else (loop (cdr files) out)))))

    ;; ---- Tools ----

    (define (path-join . parts)
      (path-normalize (apply make-path parts)))

    (define (read-file path)
      (call-with-input-file path
        (lambda (port)
          (let loop ((chunks '()))
            (let ((chunk (read-string 65536 port)))
              (if (eof-object? chunk) (apply string-append (reverse chunks)) (loop (cons chunk chunks))))))))

    (define (write-file path text)
      (create-directory* (path-directory path))
      (call-with-output-file path (lambda (port) (write-string text port))))

    ;; Runs a compiled program under Node, returning (output error status).
    (define (run-wasm root program arguments)
      (process->output+error+status (append (wasm-compiler root program) arguments)))

    ;; Runs a command, raising its standard error if it fails. Tools can be
    ;; overridden by environment variables such as WASM_OPT.
    (define (run-tool variable default . arguments)
      (let* ((tool (or (get-environment-variable variable) default))
             (result (process->output+error+status (cons tool arguments))))
        (unless (zero? (caddr result))
          (error (string-append tool " failed:\n" (cadr result))))
        (car result)))

    (define wasm-features
      '("--enable-gc" "--enable-reference-types" "--enable-tail-call" "--enable-bulk-memory"
        "--enable-nontrapping-float-to-int" "--enable-sign-ext" "--enable-mutable-globals"))

    (define (optimization release?)
      (if release?
          '("-O3" "--closed-world" "--always-inline-max-function-size=40" "--converge")
          '("-O1" "--closed-world")))

    (define (wasm-opt input output . flags)
      (apply run-tool "WASM_OPT" "wasm-opt" "-g" (append wasm-features flags (list input "-o" output))))

    ;; ---- Runtime ----

    ;; The Rust runtime is a reactor built for WASI. The adapter routes its
    ;; diagnostics and exports the cleanup entry point the host calls.
    (define adapter-text
      "(module
  (import \"snail.library\" \"snail:report-error\" (func $report (param i32 i32)))
  (import \"snail.library\" \"snail:io/close-all\" (func $close (result i32)))
  (export \"diagnostics/report-error\" (func $report))
  (export \"close-resources\" (func $close)))\n")

    (define (build-runtime root)
      (let ((target (path-join root "build/wasm-runtime")))
        (run-tool "CARGO" "cargo" "rustc" "--crate-type=cdylib" "--quiet" "--offline" "--release"
                  "--target" "wasm32-wasip1" "--manifest-path" (path-join root "src/runtime/Cargo.toml")
                  "--target-dir" target)
        (path-join target "wasm32-wasip1/release/snail_runtime.wasm")))

    ;; The in-process assembler (src/assembler) is a reactor too: text in, a
    ;; binary module out, for a toolchain that runs as Wasm without Binaryen.
    ;; scripts/assemble.mjs drives it.
    (define (build-assembler root)
      (let ((target (path-join root "build/wasm-assembler")))
        (run-tool "CARGO" "cargo" "rustc" "--crate-type=cdylib" "--quiet" "--offline" "--release"
                  "--target" "wasm32-wasip1" "--manifest-path" (path-join root "src/assembler/Cargo.toml")
                  "--target-dir" target)
        (path-join target "wasm32-wasip1/release/snail_assembler.wasm")))

    (define (link module output runtime release?)
      (let ((adapter (string-append output ".adapter.wasm")) (linked (string-append output ".linked.wasm"))
            (adapter-wat (string-append output ".adapter.wat")))
        (write-file adapter-wat adapter-text)
        (apply run-tool "WASM_AS" "wasm-as" (append wasm-features (list adapter-wat "-o" adapter)))
        (apply run-tool "WASM_MERGE" "wasm-merge" "-g"
               (append wasm-features (list module "snail.abi" runtime "snail.library" adapter "snail.platform" "-o" linked)))
        (apply wasm-opt linked output "--remove-exports" "--pass-arg=remove-exports@snail:*,diagnostics/*"
               (optimization release?))))

    ;; ---- Artifacts ----

    ;; Writes OUTPUT from module text, keeping the text and intermediate
    ;; modules beside it.
    (define (link-wat root text output release?)
      (let ((wat (string-append output ".wat")) (raw (string-append output ".raw.wasm"))
            (module (string-append output ".module.wasm")))
        (write-file wat text)
        (apply run-tool "WASM_AS" "wasm-as" "-g" (append wasm-features (list wat "-o" raw)))
        (apply wasm-opt raw module (optimization release?))
        (link module output (build-runtime root) release?)
        output))

    (define (build-program root directories source output release?)
      (link-wat root (program->wat root directories source) output release?))

    ;; ---- Linked modules ----

    ;; A program linked when it runs: each library's module, assembled but
    ;; not optimized, the runtime beside them, and modules.json naming the
    ;; modules in program order for the loader in src/app/load.mjs.
    (define (build-modules root directories source output)
      (create-directory* output)
      (with-private-directory root (lambda (generated) (run-compiler-into root (selected-compiler root) "modules" directories source output generated)))
      (let ((names (read-lines (path-join output "modules"))))
        (for-each (lambda (name) (assemble (path-join output name))) names)
        (copy-file! (build-runtime root) (path-join output "runtime.wasm"))
        (write-file (path-join output "modules.json") (modules-json names))
        output))

    ;; PATH.wat to PATH.wasm.
    (define (assemble path)
      (apply run-tool "WASM_AS" "wasm-as" "-g" (append wasm-features (list (string-append path ".wat") "-o" (string-append path ".wasm")))))

    ;; ---- Development tools ----

    ;; What `lofi serve` and `lofi watch` run: the development loop, a
    ;; program that includes the compiler; the reload client pages load; the
    ;; runtime; and the assembler. Each is built again only when its sources
    ;; are newer. Returns their paths by name.
    (define (build-tools root)
      (let ((directory (path-join root "build/develop")))
        (create-directory* directory)
        (list (cons "develop" (build-tool root (path-join root "bootstrap/develop.sld") (path-join directory "develop.wasm")
                                          (list (path-join root "src") (path-join root "lib")) (list "bootstrap/develop.sld")))
              (cons "client" (build-tool root (path-join root "src/app/reload.sld") (path-join directory "reload.wasm")
                                         (list (path-join root "lib")) (list "src/app/reload.sld")))
              (cons "runtime" (build-runtime root))
              (cons "assembler" (build-assembler root)))))

    ;; A stale tool is rebuilt under the build lock, unless another process
    ;; rebuilt it while this one waited.
    (define (build-tool root source output directories files)
      (unless (tool-current? root output directories files)
        (with-build-lock root (lambda () (unless (tool-current? root output directories files) (build-program root directories source output #f)))))
      output)

    (define (tool-current? root output directories files)
      (and (file-exists? output)
           (> (file-modification-time output)
              (apply max (append (map (lambda (file) (file-modification-time (path-join root file))) files) (map newest-sld-time directories))))))

    ;; The newest .sld file under a directory, at any depth.
    (define (newest-sld-time directory)
      (let loop ((entries (directory-files directory)) (newest 0))
        (cond ((null? entries) newest)
              ((member (car entries) '("." "..")) (loop (cdr entries) newest))
              (else
               (let ((path (path-join directory (car entries))))
                 (loop (cdr entries)
                       (max newest (cond ((file-directory? path) (newest-sld-time path))
                                         ((string-suffix? ".sld" path) (file-modification-time path))
                                         (else 0)))))))))

    (define (read-lines path)
      (let loop ((lines '()) (rest (read-file path)))
        (let ((cursor (string-contains rest "\n")))
          (if cursor
              (let ((end (string-cursor->index rest cursor)))
                (loop (cons (substring rest 0 end) lines) (substring rest (+ end 1) (string-length rest))))
              (reverse lines)))))

    (define (modules-json names)
      (string-append "{\"runtime\": \"runtime.wasm\", \"modules\": ["
                     (let loop ((names names) (out ""))
                       (if (null? names)
                           out
                           (loop (cdr names) (string-append out (if (string=? out "") "" ", ") "{\"name\": \"" (car names)
                                                            "\", \"file\": \"" (car names) ".wasm\"}"))))
                     "]}\n"))

    (define (copy-file! from to)
      (let ((bytes (call-with-port (open-binary-input-file from) (lambda (port) (read-bytevector (file-size from) port)))))
        (call-with-port (open-binary-output-file to) (lambda (port) (write-bytevector bytes port)))))

    ;; ---- Failures ----

    ;; Prints a failure as one diagnostic after the command's name, without
    ;; Chibi's trace, and returns the status the command exits with.
    (define (report-failure command failure)
      (let ((port (current-error-port)))
        (display command port)
        (display ": " port)
        (if (error-object? failure)
            (begin (display (error-object-message failure) port)
                   (for-each (lambda (irritant) (display " " port) (write irritant port)) (error-object-irritants failure)))
            (write failure port))
        (newline port)
        1))

    ))
