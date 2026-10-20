;; The compiler driver: one source file to a linked, runnable Wasm program.
;; Each pass's output is the next pass's only input.
(define-library (lofi compiler build)
  (export
   compile->wat
   build-program)
  (import
   (scheme base)
   (scheme file)
   (chibi filesystem)
   (lofi compiler expand)
   (lofi compiler check)
   (lofi compiler mono)
   (lofi compiler wasm)
   (lofi host process)
   (lofi host wasm-optimize)
   (lofi host runtime-wasm))
  (begin

    ;; ---- Passes ----

    (define (compile->wat directories source)
      (let* ((program (expand-program (make-context directories) source))
             (typed (check-program program))
             (mono (monomorphize typed)))
        (wat->string (emit-module mono))))

    ;; ---- Artifacts ----

    ;; Writes OUTPUT and keeps the intermediate text and modules beside it.
    (define (build-program root directories source output release?)
      (let ((wat (string-append output ".wat")) (raw (string-append output ".raw.wasm"))
            (module (string-append output ".module.wasm")))
        (create-directory* (path-directory output))
        (write-text wat (compile->wat directories source))
        (parameterize ((wasm-release-optimization? release?))
          (assemble-wasm wat raw)
          (optimize-wasm raw module)
          (link-wasm-runtime module output (build-wasm-runtime (path-join root "src/runtime")) #f))
        output))

    ))
