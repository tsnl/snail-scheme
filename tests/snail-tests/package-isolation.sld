;; Exercise Wasm compilation and supplied-runtime execution outside the checkout.
(define-library (snail-tests package-isolation)
  (export run-package-isolation)
  (import
   (scheme base)
   (scheme file)
   (scheme write)
   (only (chibi filesystem) chmod symbolic-link-file)
   (snail-tests harness)
   (only (lofi host json) string->json))
  (begin

    ;; ---- A compiler copy containing only neutral package libraries ----

    (define (copy-wasm-compiler outside)
      (let ((copy (path-join outside "wasm-only")))
        (create-directory* (path-join copy "bootstrap"))
        (create-directory* (path-join copy "src"))
        (checked "copy-compiler" (list "cp" "-a" "--" (path "src/lofi") (path "src/scheme") (path-join copy "src")))
        (checked "copy-commands" (list "cp" "-a" "--" (path "scripts") (path "lofi") copy))
        (assert-that (symbolic-link-file "../src/lofi" (path-join copy "bootstrap/lofi")))
        (assert-that (not (file-exists? (path-join copy "src/runtime"))))
        copy))
    (define (forbidden-tool)
      (let ((file (build-path "forbidden-build-tool")))
        (write-text file "#!/bin/sh\nprintf 'unexpected Rust build tool invocation\\n' > \"$0.invoked\"\nprintf 'unexpected Rust build tool invocation\\n' >&2\nexit 99\n")
        (chmod file #o755) file))
    (define (isolated-options directory forbidden)
      `((directory . ,directory)
        (environment . (("CARGO" . ,forbidden) ("RUSTC" . ,forbidden)))))
    (define (isolated-chibi copy script . arguments)
      (append (list "env" "-u" "SNAIL_PROCESS_SUPERVISOR" "-u" "CHIBI_MODULE_PATH"
                    (tool-name "CHIBI" "chibi-scheme") "-I" (path-join copy "bootstrap")
                    (path-join copy script)) arguments))

    ;; ---- Real Wasm generation and supplied-runtime linking ----

    (define (check-wasm-only copy options)
      (let ((source (build-path "answer.sld")) (binary (build-path "answer.wasm")))
        (write-text source "(import (lofi primitive))\n(i32-add 40 2)\n")
        (checked "isolated-compile" (isolated-chibi copy "scripts/build-lofi.scm" copy "--command" source binary) options)
        (for-each (lambda (artifact)
                    (checked "isolated-execute" (node (fixture "lofi-integration" "run.mjs") artifact "42") options))
                  (list binary (string-append binary ".raw.wasm")))
        (checked "isolated-link"
                 (isolated-chibi copy "scripts/link-lofi-runtime.scm" copy "--runtime"
                                 (path "build/wasm-runtime/wasm32-wasip1/release/snail_runtime.wasm") binary (build-path "linked.wasm")) options)
        (checked "isolated-linked-execute" (node (path-join copy "scripts/run-lofi.mjs") (build-path "linked.wasm"))
                 (cons '(status . 42) options))))

    ;; ---- The compiler service consumes a finite recorded request stream ----

    (define (service-requests directory)
      (let ((source "(define-library (isolated answer) (export answer) (begin (def answer (-> I32) (lambda () 42))))"))
        (write-text (path-join directory "requests")
                    (string-append (join (map json-text
                                              (list '#("empty") '#("primitives" 1)
                                                    (vector "source" 2 '#("isolated" "answer") "isolated-service.sld" source)
                                                    '#("compile" 3 #("isolated" "answer") "answer") '#("close"))) "\n") "\n"))))
    (define (check-compiler-service copy options)
      (let ((session (build-path "service")) (runner (path-join copy "service-entry.mjs")))
        (create-directory* session) (service-requests session)
        (checked "isolated-service" (isolated-chibi copy "scripts/serve-lofi-compiler.scm" session) options)
        (assert-equal (map string->json (lines (read-text (path-join session "responses"))))
                      '(#(#t "ready") #(#t 1) #(#t 2) #(#t 3) #(#t #t) #(#t "closed")))
        (write-text runner
                    "import assert from 'node:assert/strict'; import {readFileSync} from 'node:fs';\nimport {loadWasm,instantiate,invokeEntry,closeInstance} from './src/lofi/compiler/execute.mjs';\nconst instance=instantiate(loadWasm(readFileSync(process.argv[2])));\ntry { assert.equal(invokeEntry(instance, []), 42); } finally { closeInstance(instance); }\n")
        (checked "isolated-service-execute" (node runner (path-join session "artifact.wasm")) options)))

    (define (run-package-isolation)
      (let* ((outside (make-build-directory "/tmp" "lofi-package-isolation-"))
             (copy (copy-wasm-compiler outside)) (working (path-join outside "working")) (forbidden (forbidden-tool))
             (options (isolated-options working forbidden)))
        (write-json (build-path "isolation-paths.json") `((compiler_copy . ,copy) (working_directory . ,working)))
        (create-directory* working) (runtime-build)
        (check-wasm-only copy options) (check-compiler-service copy options)
        (assert-that (not (file-exists? (string-append forbidden ".invoked"))) "supplied-runtime execution invoked a Rust build tool")
        (complete! "Wasm compiler isolation and supplied-runtime execution"
                   '((passed . #t) (runtime_sources_absent . #t) (rust_tools_forbidden . #t)
                     (compiler_service . #t) (supplied_runtime . #t) (outside_working_directory . #t)))))))
