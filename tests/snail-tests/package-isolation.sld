;; Exercise the compiler without native libraries, then compose them explicitly.
(define-library (snail-tests package-isolation)
  (export run-package-isolation)
  (import (scheme base) (scheme file) (scheme write)
          (only (chibi filesystem) chmod) (snail-tests harness)
          (only (wasm-native json) string->json))
  (begin

    ;; ---- A compiler copy containing only neutral package libraries ----

    (define neutral-libraries
      '("wasm" "wasm-optimize" "build-host" "chromium-trace" "process" "json" "runtime-wasm"))
    (define (copy-wasm-compiler outside)
      (let* ((copy (path-join outside "wasm-only")) (modules (path-join copy "wasm-native/scheme/wasm-native")))
        (create-directory* modules)
        (checked "copy-compiler" (list "cp" "-a" "--" (path "src") (path "lib") (path "scripts") (path "snail-sfir") copy))
        (for-each (lambda (name)
                    (write-bytes (path-join modules (string-append name ".sld"))
                                 (read-bytes (path "wasm-native/scheme/wasm-native" (string-append name ".sld"))))) neutral-libraries)
        (assert-that (not (file-exists? (path-join copy "wasm-native/scheme/wasm-native.sld"))))
        copy))
    (define (forbidden-tool)
      (let ((file (build-path "forbidden-native-tool")))
        (write-text file "#!/bin/sh\nprintf 'unexpected native tool invocation\\n' > \"$0.invoked\"\nprintf 'unexpected native tool invocation\\n' >&2\nexit 99\n")
        (chmod file #o755) file))
    (define (isolated-options directory forbidden)
      `((directory . ,directory)
        (environment . (("LLVM_OPT" . ,forbidden) ("LLC" . ,forbidden)
                        ("CARGO" . ,forbidden) ("RUSTC" . ,forbidden)))))
    (define (isolated-chibi copy script . arguments)
      (append (list "env" "-u" "SNAIL_NATIVE_SUPERVISOR" "-u" "CHIBI_MODULE_PATH"
                    (tool-name "CHIBI" "chibi-scheme") "-I" (path-join copy "src")
                    "-I" (path-join copy "wasm-native/scheme") (path-join copy script)) arguments))

    ;; ---- Real Wasm generation and supplied-runtime linking ----

    (define (check-wasm-only copy options)
      (let ((source (build-path "answer.sfir")) (binary (build-path "answer.wasm")))
        (write-text source "(import (sfir primitive))\n(i32-add 40 2)\n")
        (checked "isolated-compile" (isolated-chibi copy "scripts/build-sfir.scm" copy "--command" source binary) options)
        (for-each (lambda (artifact)
                    (checked "isolated-execute" (node (fixture "sfir-integration" "run.mjs") artifact "42") options))
                  (list binary (string-append binary ".raw.wasm")))
        (checked "isolated-link"
                 (isolated-chibi copy "scripts/link-sfir-runtime.scm" copy "--runtime"
                                 (path "build/wasm-runtime/wasm32-wasip1/release/snail_runtime.wasm") binary (build-path "linked.wasm")) options)
        (checked "isolated-linked-execute" (node (path-join copy "scripts/run-sfir.mjs") (build-path "linked.wasm"))
                 (cons '(status . 42) options))))

    ;; ---- The compiler service consumes a finite recorded request stream ----

    (define (service-requests directory)
      (let ((source "(define-library (isolated answer) (export answer) (begin (def answer (-> I32) (lambda () 42))))"))
        (write-text (path-join directory "requests")
                    (string-append (join (map json-text
                                              (list '#("empty") '#("primitives" 1)
                                                    (vector "source" 2 '#("isolated" "answer") "isolated-service.sfir" source)
                                                    '#("compile" 3 #("isolated" "answer") "answer") '#("close"))) "\n") "\n"))))
    (define (check-compiler-service copy options)
      (let ((session (build-path "service")) (runner (path-join copy "service-entry.mjs")))
        (create-directory* session) (service-requests session)
        (checked "isolated-service" (isolated-chibi copy "scripts/serve-sfir-compiler.scm" session) options)
        (assert-equal (map string->json (lines (read-text (path-join session "responses"))))
                      '(#(#t "ready") #(#t 1) #(#t 2) #(#t 3) #(#t #t) #(#t "closed")))
        (write-text runner
                    "import assert from 'node:assert/strict'; import {readFileSync} from 'node:fs';\nimport {loadWasm,instantiate,invokeEntry,closeInstance} from './src/snail-sfir/execute.mjs';\nconst instance=instantiate(loadWasm(readFileSync(process.argv[2])));\ntry { assert.equal(invokeEntry(instance, []), 42); } finally { closeInstance(instance); }\n")
        (checked "isolated-service-execute" (node runner (path-join session "artifact.wasm")) options)))

    ;; ---- A root recipe explicitly composes the independent libraries ----

    (define (check-composed-recipe working)
      (let ((program (build-path "composed-answer")))
        (checked "composed-recipe"
                 (chibi (path "build.scm") (root) (path "examples/native/answer.sfir") "answer"
                        (path "examples/native/entry.rs") program) `((directory . ,working)))
        (checked "composed-execute" (list program) `((directory . ,working) (stdout . "42\n")))))
    (define (run-package-isolation)
      (let* ((outside (make-build-directory "/tmp" "sfir-package-isolation-"))
             (copy (copy-wasm-compiler outside)) (working (path-join outside "working")) (forbidden (forbidden-tool))
             (options (isolated-options working forbidden)))
        (write-json (build-path "isolation-paths.json") `((compiler_copy . ,copy) (working_directory . ,working)))
        (create-directory* working) (runtime-build)
        (check-wasm-only copy options) (check-compiler-service copy options)
        (assert-that (not (file-exists? (string-append forbidden ".invoked"))) "Wasm-only compilation invoked a native tool")
        (check-composed-recipe working)
        (complete! "Wasm-only compiler isolation and explicit native library composition"
                   '((passed . #t) (native_libraries_absent . #t) (native_tools_forbidden . #t)
                     (compiler_service . #t) (supplied_runtime . #t) (outside_working_directory . #t)))))))
