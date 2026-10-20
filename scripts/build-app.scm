;; Packages a (lofi app) application as a static site:
;;   build-app [--release] APP-DIRECTORY OUTPUT-DIRECTORY
;; The application's main.sld and src/ libraries become app.wasm, beside its
;; index.html and the shared browser host.
(import
 (scheme base)
 (scheme process-context)
 (chibi filesystem)
 (chibi pathname)
 (lofi host process)
 (lofi compiler build))

(define host-files '("host.mjs" "renderer.mjs" "hud.mjs" "storage.mjs" "style.css"))

(define (copy-file! from to)
  (write-bytes to (read-bytes from)))

(define (package root release? app output)
  (let ((intermediate (path-join root "build/app-intermediates" (path-strip-directory app) "app.wasm")))
    (create-directory* output)
    (build-program root (list (path-join app "src") (path-join root "lib")) (path-join app "main.sld") intermediate release?)
    (copy-file! intermediate (path-join output "app.wasm")))
  (for-each (lambda (file) (copy-file! (path-join root "src/app" file) (path-join output file))) host-files)
  (copy-file! (path-join app "index.html") (path-join output "index.html"))
  0)

(let* ((arguments (cdr (command-line))) (root (car arguments)) (rest (cdr arguments))
       (release? (and (pair? rest) (string=? (car rest) "--release")))
       (paths (if release? (cdr rest) rest)))
  (unless (= (length paths) 2) (error "usage: build-app [--release] APP-DIRECTORY OUTPUT-DIRECTORY"))
  (exit (package root release? (absolute-path (car paths)) (absolute-path (cadr paths)))))
