;; Packages a (lofi app) application as a static site:
;;   build-app [--release] APP-DIRECTORY OUTPUT-DIRECTORY
;; The application's main.sld and src/ libraries become app.wasm, beside its
;; index.html, the files in its public/ directory and the shared browser host.
(import
 (scheme base)
 (scheme file)
 (scheme process-context)
 (chibi filesystem)
 (chibi pathname)
 (only (srfi 1) filter)
 (lofi build))

(define host-files
  '("host.mjs" "renderer.mjs" "hud.mjs" "storage.mjs" "load.mjs" "style.css"))

(define (copy-file! from to)
  (let ((bytes (call-with-port (open-binary-input-file from) (lambda (port) (read-bytevector (file-size from) port)))))
    (call-with-port (open-binary-output-file to) (lambda (port) (write-bytevector bytes port)))))

(define (absolute path)
  (if (path-absolute? path) path (path-join (current-directory) path)))

(define (package root release? app output)
  (let ((intermediate (path-join root "build/app-intermediates" (path-strip-directory app) "app.wasm")))
    (create-directory* output)
    (build-program root (list (path-join app "src") (path-join root "lib")) (path-join app "main.sld") intermediate release?)
    (copy-file! intermediate (path-join output "app.wasm")))
  (for-each (lambda (file) (copy-file! (path-join root "src/app" file) (path-join output file))) host-files)
  (copy-file! (path-join app "index.html") (path-join output "index.html"))
  (for-each (lambda (file) (copy-file! (path-join app "public" file) (path-join output file))) (public-files app))
  0)

(define (public-files app)
  (let ((directory (path-join app "public")))
    (if (file-directory? directory)
        (filter (lambda (file) (not (member file '("." "..")))) (directory-files directory))
        '())))

(let* ((arguments (cdr (command-line))) (root (car arguments)) (rest (cdr arguments))
       (release? (and (pair? rest) (string=? (car rest) "--release")))
       (paths (if release? (cdr rest) rest)))
  (unless (= (length paths) 2) (error "usage: build-app [--release] APP-DIRECTORY OUTPUT-DIRECTORY"))
  (exit (guard (failure (#t (report-failure "build-app" failure)))
          (package root release? (absolute (car paths)) (absolute (cadr paths))))))
