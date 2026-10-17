;; A concrete build recipe: compile a public Lofi entry to Wasm, then pass
;; those bytes to the independently imported native backend and Cargo linker.
;; From any working directory, using absolute paths:
;;   chibi-scheme -I "$repo/bootstrap" -I "$repo/wasm-native/scheme" "$repo/build.scm" \
;;     "$repo" "$repo/examples/native/answer.sld" answer \
;;     "$repo/examples/native/entry.rs" /tmp/lofi-answer
(import (scheme base) (scheme process-context) (chibi filesystem)
        (wasm-native) (wasm-native process) (wasm-native chromium-trace)
        (lofi compiler bootstrap) (lofi source-driver)
        (only (lofi frontend) make-primitive-library)
        (only (lofi primitives) primitive-names))

;; ---- Explicit build inputs ----

(define arguments (cdr (command-line)))
(unless (= 5 (length arguments))
  (error "usage: build.scm REPOSITORY SOURCE EXPORT RUST-ENTRY OUTPUT"))
(define root (absolute-path (list-ref arguments 0)))
(define source (absolute-path (list-ref arguments 1)))
(define selected (string->symbol (list-ref arguments 2)))
(define rust-entry (absolute-path (list-ref arguments 3)))
(define output (absolute-path (list-ref arguments 4)))
(define runtime-root (path-join root "wasm-native"))
(when (or (paths-alias? output source) (paths-alias? output rust-entry))
  (error "build output must not replace an input"))
(define directory (make-build-directory (path-directory output) "lofi-build-"))
(define binary (path-join directory "program.wasm"))
(define llvm (path-join directory "program.ll"))
(define bitcode (path-join directory "program.bc"))
(define imports
  (map (lambda (entry)
         (make-native-import (car (car entry)) (cadr (car entry)) (cadr entry)
                             (list-ref entry 2)
                             (if (null? (list-ref entry 3)) 'void (car (list-ref entry 3)))))
       (runtime-bindings runtime-root)))

;; ---- Library composition ----

(with-chromium-trace-to
 (path-join directory "build.trace.json")
 (lambda ()
   (let-values (((key libraries)
                 (collect-source-file source (list (path-directory source) (path-join root "src"))
                                      (list (cons '(lofi primitive) (make-primitive-library primitive-names)))
                                      (make-generation-context (path-join root "scripts/run-lofi-generator.mjs") #f))))
     (write-bytes binary (artifact-bytes (compile libraries (make-entry key selected)))))
   (wasm-binary->llvm binary imports directory llvm)
   (llvm-bitcode llvm bitcode)
   (rename-file (link-native-object runtime-root bitcode rust-entry '() directory) output)))
