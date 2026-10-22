;; Packages the browser IDE around an application, as a static site:
;;   build-ide ROOT APP-DIRECTORY OUTPUT-DIRECTORY
;; The site holds the development loop compiled one library at a time, with
;; the runtime, the reload client and the assembler; the browser host and
;; the IDE's page; the application's public files; and files.json, the text
;; of the standard library and of the application, which the toolchain
;; keeps in memory.
(import
 (scheme base)
 (scheme char)
 (scheme cxr)
 (scheme file)
 (scheme process-context)
 (chibi filesystem)
 (chibi pathname)
 (only (chibi string) string-suffix?)
 (lofi build))

(define host-files
  '("host.mjs" "renderer.mjs" "hud.mjs" "storage.mjs" "load.mjs" "style.css" "reload-client.mjs"))

(define ide-files
  '("index.html" "ide.mjs" "ide.css" "toolchain.mjs"))

(define (copy-file! from to)
  (let ((bytes (call-with-port (open-binary-input-file from) (lambda (port) (read-bytevector (file-size from) port)))))
    (call-with-port (open-binary-output-file to) (lambda (port) (write-bytevector bytes port)))))

(define (read-text path)
  (call-with-input-file path
    (lambda (port)
      (let loop ((chunks '()))
        (let ((chunk (read-string 65536 port)))
          (if (eof-object? chunk) (apply string-append (reverse chunks)) (loop (cons chunk chunks))))))))

(define (absolute path)
  (if (path-absolute? path) path (path-join (current-directory) path)))

;; ---- Packaging ----

(define (package root app output)
  (create-directory* output)
  (build-modules root (list (path-join root "src") (path-join root "lib")) (path-join root "bootstrap/develop.sld") (path-join output "toolchain"))
  (let ((tools (build-tools root)))
    (copy-file! (cdr (assoc "client" tools)) (path-join output "reload.wasm"))
    (copy-file! (cdr (assoc "assembler" tools)) (path-join output "assembler.wasm")))
  (copy-file! (path-join root "scripts/assemble.mjs") (path-join output "assemble.mjs"))
  (for-each (lambda (file) (copy-file! (path-join root "src/app" file) (path-join output file))) host-files)
  (for-each (lambda (file) (copy-file! (path-join root "src/ide" file) (path-join output file))) ide-files)
  (for-each (lambda (file) (copy-file! (path-join app "public" file) (path-join output file))) (directory-names (path-join app "public")))
  (call-with-output-file (path-join output "files.json") (lambda (port) (write-string (files-json root app) port)))
  0)

;; The library's and the application's text by the path the toolchain reads
;; them at: /lib/... and /app/....
(define (files-json root app)
  (let ((entries (append (map (lambda (file) (cons (string-append "/lib/" file) (path-join root "lib" file))) (sld-files (path-join root "lib") ""))
                         (map (lambda (file) (cons (string-append "/app/" file) (path-join app file)))
                              (append '("main.sld" "index.html") (sld-files app "src")
                                      (map (lambda (name) (string-append "public/" name)) (directory-names (path-join app "public"))))))))
    (string-append "{"
                   (let loop ((entries entries) (out ""))
                     (if (null? entries)
                         out
                         (loop (cdr entries) (string-append out (if (string=? out "") "" ",\n") (json-string (caar entries)) ": "
                                                            (json-string (read-text (cdar entries)))))))
                   "}\n")))

;; The .sld files under `directory`/`relative`, as paths relative to
;; `directory`.
(define (sld-files directory relative)
  (let loop ((names (directory-names (path-join directory relative))) (out '()))
    (if (null? names)
        out
        (let ((path (if (string=? relative "") (car names) (string-append relative "/" (car names)))))
          (loop (cdr names)
                (cond ((file-directory? (path-join directory path)) (append out (sld-files directory path)))
                      ((string-suffix? ".sld" path) (append out (list path)))
                      (else out)))))))

(define (directory-names directory)
  (if (file-directory? directory)
      (filter-names (directory-files directory))
      '()))

(define (filter-names names)
  (cond ((null? names) '())
        ((member (car names) '("." "..")) (filter-names (cdr names)))
        (else (cons (car names) (filter-names (cdr names))))))

(define (json-string text)
  (let ((port (open-output-string)))
    (write-char #\" port)
    (string-for-each (lambda (c)
                       (cond ((char=? c #\") (write-string "\\\"" port))
                             ((char=? c #\\) (write-string "\\\\" port))
                             ((char=? c #\newline) (write-string "\\n" port))
                             ((char=? c #\tab) (write-string "\\t" port))
                             ((< (char->integer c) 32) (write-string (string-append "\\u00" (if (< (char->integer c) 16) "0" "")
                                                                                    (number->string (char->integer c) 16))
                                                                     port))
                             (else (write-char c port))))
                     text)
    (write-char #\" port)
    (get-output-string port)))

(let ((arguments (cdr (command-line))))
  (unless (= (length arguments) 3) (error "usage: build-ide ROOT APP-DIRECTORY OUTPUT-DIRECTORY"))
  (exit (guard (failure (#t (report-failure "build-ide" failure)))
          (package (car arguments) (absolute (cadr arguments)) (absolute (caddr arguments))))))
