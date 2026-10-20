;; The command-line driver: one source file to a linked, runnable Wasm
;; program. The compiler normally runs as Wasm, built from its own source by
;; bootstrapping; Chibi runs the source directly only when no compiled
;; compiler can. Binaryen assembles, optimizes and links the text with the
;; Rust runtime.
(define-library (lofi build)
  (export
   program->wat
   build-program
   bootstrap!
   run-tool
   path-join)
  (import
   (scheme base)
   (scheme cxr)
   (scheme file)
   (scheme process-context)
   (scheme write)
   (chibi filesystem)
   (chibi pathname)
   (chibi process)
   (only (chibi string) string-contains string-cursor->index)
   (only (lofi compiler read) syntax->string)
   (only (lofi compiler core) fnv-1a)
   (lofi compiler))
  (begin

    ;; ---- Compiling ----

    ;; The compiled compiler is rebuilt first when its source has changed.
    ;; LOFI_STAGE0=chibi compiles with the source running on Chibi instead.
    (define (program->wat root directories source)
      (if (equal? (get-environment-variable "LOFI_STAGE0") "chibi")
          (chibi-program->wat root directories source)
          (wasm-program->wat root (current-compiler root) directories source)))

    (define (chibi-program->wat root directories source)
      (compile->wat directories source (lambda (forms name) (generated-text root directories forms))))

    ;; The compiler stops with `generate KEY` when it needs a generated
    ;; library that has not been produced; producing it and compiling again
    ;; then finds its text.
    (define (wasm-program->wat root compiler directories source)
      (create-directory* (generated-directory root))
      (create-directory* (path-join root "build/lofi-run"))
      (let* ((output (path-join root "build/lofi-run/compiler-output.wat"))
             (result (run-wasm root compiler (append (list source output (generated-directory root)) directories))))
        (cond ((zero? (caddr result)) (read-file output))
              ((generate-request (cadr result))
               => (lambda (key) (produce! root directories key) (wasm-program->wat root compiler directories source)))
              (else (error (strip-prefix (cadr result)))))))

    (define (generate-request text)
      (let ((cursor (string-contains text "lofi: generate ")))
        (and cursor
             (string-trim-newline (substring text (+ (string-cursor->index text cursor) 15) (string-length text))))))

    (define (strip-prefix text)
      (string-trim-newline (if (and (>= (string-length text) 6) (string=? (substring text 0 6) "lofi: ")) (substring text 6 (string-length text)) text)))

    (define (string-trim-newline text)
      (let loop ((end (string-length text)))
        (if (and (> end 0) (char=? (string-ref text (- end 1)) #\newline)) (loop (- end 1)) (substring text 0 end))))

    ;; ---- Generated libraries ----

    ;; A `generate-library` recipe becomes a producer program, cached under
    ;; the hash of its text: KEY.sld is the producer and KEY.out what it
    ;; printed, which is the library. bootstrap/compile.sld uses the same
    ;; names.
    (define (generated-directory root)
      (path-join root "build/generated"))

    (define (generated-text root directories forms)
      (let* ((text (producer-text forms)) (key (number->string (fnv-1a text)))
             (output (path-join (generated-directory root) (string-append key ".out"))))
        (unless (file-exists? output)
          (write-file (path-join (generated-directory root) (string-append key ".sld")) text)
          (produce! root directories key))
        (read-file output)))

    (define (producer-text forms)
      (let loop ((forms forms) (texts '()))
        (if (null? forms)
            (apply string-append (reverse texts))
            (loop (cdr forms) (cons (string-append (syntax->string (car forms)) (if (null? (cdr forms)) "" "\n")) texts)))))

    (define (produce! root directories key)
      (let* ((source (path-join (generated-directory root) (string-append key ".sld")))
             (program (path-join (generated-directory root) (string-append key ".wasm")))
             (result (begin (build-program root directories source program #f) (run-wasm root program '()))))
        (unless (zero? (caddr result)) (error (string-append "the producer " source " failed:\n" (cadr result))))
        (write-file (path-join (generated-directory root) (string-append key ".out")) (car result))))

    ;; ---- Bootstrap ----

    ;; The compiler compiles itself until its output stops changing: stage 1
    ;; is built by the current compiler (or by Chibi running the source),
    ;; stage 2 by stage 1, and stage 2 must reproduce its own text.
    (define (compiler-path root)
      (path-join root "build/compiler/lofic.wasm"))

    (define (compiler-directories root)
      (list (path-join root "src") (path-join root "lib")))

    (define (current-compiler root)
      (let ((compiler (compiler-path root)))
        (unless (and (file-exists? compiler) (> (file-modification-time compiler) (newest-source-time root)))
          (bootstrap! root))
        compiler))

    (define (bootstrap! root)
      (let* ((directory (path-join root "build/compiler")) (entry (path-join root "bootstrap/compile.sld"))
             (stage1 (path-join directory "stage1.wasm")) (stage2 (path-join directory "stage2.wasm"))
             (stage3 (path-join directory "stage3.wat")))
        (create-directory* directory)
        (link-wat root (stage1-text root entry) stage1 #f)
        (link-wat root (wasm-program->wat root stage1 (compiler-directories root) entry) stage2 #f)
        (write-file stage3 (wasm-program->wat root stage2 (compiler-directories root) entry))
        (unless (equal? (read-file (string-append stage2 ".wat")) (read-file stage3))
          (error "bootstrap: stage 2 does not reproduce its own text; compare build/compiler/stage2.wasm.wat with stage3.wat"))
        (rename-file stage2 (compiler-path root))))

    ;; The previous compiler builds stage 1 if it can; Chibi always can.
    (define (stage1-text root entry)
      (let ((previous (compiler-path root)))
        (or (and (file-exists? previous)
                 (guard (failure (#t #f)) (wasm-program->wat root previous (compiler-directories root) entry)))
            (chibi-program->wat root (compiler-directories root) entry))))

    (define (newest-source-time root)
      (apply max (map file-modification-time
                      (append (list (path-join root "bootstrap/compile.sld") (path-join root "src/lofi/compiler.sld"))
                              (sld-files (path-join root "src/lofi/compiler")) (sld-files (path-join root "lib/lofi"))))))

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
      (process->output+error+status
       (append (list (or (get-environment-variable "NODE") "node") "--no-warnings" (path-join root "scripts/run-lofi.mjs") program)
               arguments)))

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

    ))
