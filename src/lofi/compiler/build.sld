;; The compiler driver: one source file to a linked, runnable Wasm program.
;; Each pass's output is the next pass's only input; Binaryen assembles,
;; optimizes and links the result with the Rust runtime.
(define-library (lofi compiler build)
  (export
   compile->wat
   build-program
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
   (lofi compiler expand)
   (lofi compiler check)
   (lofi compiler mono)
   (lofi compiler wasm))
  (begin

    ;; ---- Passes ----

    (define (compile->wat root directories source)
      (let* ((program (expand-program (make-context directories (lambda (forms name) (run-producer root directories forms name))) source))
             (typed (check-program program))
             (mono (monomorphize typed)))
        (wat->string (emit-module mono))))

    ;; A generated library's producer is an ordinary program; what it prints
    ;; is the library.
    (define (run-producer root directories forms name)
      (let* ((source (path-join root "build/generated" (string-append (mangle-path name) ".sld")))
             (program (string-append source ".wasm")))
        (create-directory* (path-directory source))
        (call-with-output-file source (lambda (port) (for-each (lambda (form) (write form port) (newline port)) forms)))
        (build-program root directories source program #f)
        (let ((result (process->output+error+status (list "node" "--no-warnings" (path-join root "scripts/run-lofi.mjs") program))))
          (unless (zero? (caddr result)) (error (string-append "the producer of " name " failed:\n" (cadr result))))
          (car result))))

    (define (mangle-path path)
      (list->string (map (lambda (char) (if (memv char '(#\/ #\#)) #\_ char)) (string->list path))))

    ;; ---- Tools ----

    (define (path-join . parts)
      (path-normalize (apply make-path parts)))

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
        (call-with-output-file adapter-wat (lambda (port) (write-string adapter-text port)))
        (apply run-tool "WASM_AS" "wasm-as" (append wasm-features (list adapter-wat "-o" adapter)))
        (apply run-tool "WASM_MERGE" "wasm-merge" "-g"
               (append wasm-features (list module "snail.abi" runtime "snail.library" adapter "snail.platform" "-o" linked)))
        (apply wasm-opt linked output "--remove-exports" "--pass-arg=remove-exports@snail:*,diagnostics/*"
               (optimization release?))))

    ;; ---- Artifacts ----

    ;; Writes OUTPUT and keeps the intermediate text and modules beside it.
    (define (build-program root directories source output release?)
      (let ((wat (string-append output ".wat")) (raw (string-append output ".raw.wasm"))
            (module (string-append output ".module.wasm")))
        (create-directory* (path-directory output))
        (call-with-output-file wat (lambda (port) (write-string (compile->wat root directories source) port)))
        (apply run-tool "WASM_AS" "wasm-as" "-g" (append wasm-features (list wat "-o" raw)))
        (apply wasm-opt raw module (optimization release?))
        (link module output (build-runtime root) release?)
        output))

    ))
