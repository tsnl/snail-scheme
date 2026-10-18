;; From any directory:
;; chibi-scheme -I "$repo/bootstrap" \
;;   "$repo/examples/applications/marker-board/build.scm" "$repo" "$repo/build/marker-board"
(import
 (scheme base)
 (scheme process-context)
 (scheme write)
 (chibi filesystem)
 (chibi string)
 (native process)
 (native chromium-trace)
 (lofi compiler bootstrap)
 (lofi compiler source-driver)
 (application manifest bootstrap)
 (only (lofi compiler frontend) make-primitive-library)
 (only (lofi compiler primitives) primitive-names))

;; ---- Explicit inputs and product source roots ----

(define arguments (cdr (command-line)))
(unless (= 2 (length arguments)) (error "usage: build.scm REPOSITORY OUTPUT-DIRECTORY"))
(define root (absolute-path (car arguments)))
(define output (absolute-path (cadr arguments)))
(define app (path-join root "examples/applications/marker-board"))
(define source-roots (list (path-join app "src") (path-join root "src")))
(when (or (string-prefix? (string-append (path-join root "src") "/") (string-append output "/"))
          (string-prefix? (string-append app "/") (string-append output "/")))
  (error "build output must be outside application and library source directories"))
(create-directory* output)

;; ---- Compile the same library API for simulation and shader generation ----

(define (compile-entry file selected target)
  (let-values (((key libraries)
                (collect-source-file (path-join app "src/tutorial" file) source-roots
                                     (list (cons '(lofi primitive) (make-primitive-library primitive-names)))
                                     (make-generation-context (path-join root "scripts/run-lofi-generator.mjs") #f))))
    (when (eq? selected 'application-entry)
      (write-json (path-join output "application.syntax.json")
                  (application-source-manifest (cdr (assoc key libraries)))))
    (write-bytes (path-join output target) (artifact-bytes (compile libraries (make-entry key selected))))))
(with-chromium-trace-to
 (path-join output "build.trace.json")
 (lambda ()
   (compile-entry "shaders.sld" 'shader-entry "shader.wasm")
   (compile-entry "board.sld" 'application-entry "simulation.wasm")))
(display (run-command! (list "node" (path-join root "src/browser/build.mjs") root app output)))
