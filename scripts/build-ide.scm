;; Packages the browser IDE as a static site, with an application as the
;; project it opens until another is chosen:
;;   build-ide ROOT APP-DIRECTORY OUTPUT-DIRECTORY
;; The site holds the IDE's development loop (src/ide/develop.sld) compiled
;; one library at a time, with the runtime, the reload client, the assembler
;; and the formatter; the browser host and the IDE's pages; files.json, the
;; text of the standard library; and sample.json, the application's text
;; files.
(import
 (scheme base)
 (scheme char)
 (scheme cxr)
 (scheme file)
 (scheme process-context)
 (chibi filesystem)
 (chibi pathname)
 (only (chibi string) string-suffix?)
 (only (srfi 1) any filter)
 (lofi build))

(define host-files
  '("host.mjs" "renderer.mjs" "hud.mjs" "pictures.mjs" "storage.mjs" "load.mjs" "style.css" "reload-client.mjs"))

(define ide-files
  '("index.html" "ide.mjs" "ide.css" "editor.mjs" "panes.mjs" "project.mjs" "formatter.mjs" "preview.html" "preview.mjs"
    "toolchain.mjs"))

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
  (build-modules root (list (path-join root "src") (path-join root "lib")) (path-join root "src/ide/develop.sld") (path-join output "toolchain"))
  (let ((tools (build-tools root)) (formatter (path-join root "build/ide-tools/format.wasm")))
    (create-directory* (path-join root "build/ide-tools"))
    (build-program root (list (path-join root "lib")) (path-join root "src/ide/format.sld") formatter #f)
    (copy-file! formatter (path-join output "format.wasm"))
    (copy-file! (cdr (assoc "client" tools)) (path-join output "reload.wasm"))
    (copy-file! (cdr (assoc "assembler" tools)) (path-join output "assembler.wasm")))
  (copy-file! (path-join root "scripts/assemble.mjs") (path-join output "assemble.mjs"))
  (for-each (lambda (file) (copy-file! (path-join root "src/app" file) (path-join output file))) host-files)
  (for-each (lambda (file) (copy-file! (path-join root "src/ide" file) (path-join output file))) ide-files)
  (write-json (path-join output "files.json")
              (files-json (map (lambda (file) (cons (string-append "/lib/" file) (path-join root "lib" file)))
                               (filter (lambda (file) (string-suffix? ".sld" file)) (tree-files (path-join root "lib") "")))))
  (write-json (path-join output "sample.json")
              (string-append "{\"name\": " (json-string (path-strip-directory app)) ", \"files\": "
                             (files-json (map (lambda (file) (cons file (path-join app file))) (filter text-file? (tree-files app ""))))
                             "}"))
  0)

(define (write-json path text)
  (call-with-output-file path (lambda (port) (write-string text port) (newline port))))

;; Each entry's name with the text of the file it names.
(define (files-json entries)
  (string-append "{"
                 (let loop ((entries entries) (out ""))
                   (if (null? entries)
                       out
                       (loop (cdr entries) (string-append out (if (string=? out "") "" ",\n") (json-string (caar entries)) ": "
                                                          (json-string (read-text (cdar entries)))))))
                 "}"))

;; The files a project keeps, as the IDE reads a folder.
(define (text-file? path)
  (any (lambda (suffix) (string-suffix? suffix path)) '(".sld" ".scm" ".html" ".css" ".js" ".mjs" ".json" ".svg" ".txt" ".md")))

;; The files under `directory`/`relative`, as paths relative to
;; `directory`, leaving out hidden ones and build output.
(define (tree-files directory relative)
  (let loop ((names (directory-names (path-join directory relative))) (out '()))
    (if (null? names)
        out
        (let ((path (if (string=? relative "") (car names) (string-append relative "/" (car names)))))
          (loop (cdr names)
                (cond ((or (char=? (string-ref (car names) 0) #\.) (string=? (car names) "build")) out)
                      ((file-directory? (path-join directory path)) (append out (tree-files directory path)))
                      (else (append out (list path)))))))))

(define (directory-names directory)
  (if (file-directory? directory)
      (filter (lambda (name) (not (member name '("." "..")))) (directory-files directory))
      '()))

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
