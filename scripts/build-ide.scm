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
 (scheme cxr)
 (scheme file)
 (scheme process-context)
 (chibi filesystem)
 (chibi pathname)
 (only (chibi string) string-suffix?)
 (only (srfi 1) any filter)
 (lofi build))

(define ide-files
  '("index.html" "ide.mjs" "ide.css" "editor.mjs" "panes.mjs" "project.mjs" "formatter.mjs" "preview.html" "preview.mjs"
    "toolchain.mjs"))

;; ---- Packaging ----

(define (package root app output)
  (create-directory* output)
  (copy-programs! root output)
  (copy-pages! root output)
  (write-json (path-join output "files.json") (library-json root))
  (write-json (path-join output "sample.json") (sample-json app))
  0)

;; The development loop, one module per library, and the programs it runs
;; beside the runtime: the reload client, the assembler and the formatter.
;; The formatter is built, as the development tools are, when it is stale.
(define (copy-programs! root output)
  (build-modules root (list (path-join root "src") (path-join root "lib")) (path-join root "src/ide/develop.sld") (path-join output "toolchain"))
  (let ((tools (build-tools root))
        (formatter (build-tool root (path-join root "src/ide/format.sld") (path-join root "build/ide-tools/format.wasm")
                               (list (path-join root "lib")))))
    (copy-file! formatter (path-join output "format.wasm"))
    (copy-file! (cdr (assoc "client" tools)) (path-join output "reload.wasm"))
    (copy-file! (cdr (assoc "assembler" tools)) (path-join output "assembler.wasm"))))

;; The browser host with its reload client, the assembler's driver, and
;; the IDE's own pages.
(define (copy-pages! root output)
  (copy-file! (path-join root "scripts/assemble.mjs") (path-join output "assemble.mjs"))
  (for-each (lambda (file) (copy-file! (path-join root "src/app" file) (path-join output file)))
            (append app-host-files '("reload-client.mjs")))
  (for-each (lambda (file) (copy-file! (path-join root "src/ide" file) (path-join output file))) ide-files))

;; The text of every library in lib/, under its path in the IDE.
(define (library-json root)
  (files-json (map (lambda (file) (cons (string-append "/lib/" file) (path-join root "lib" file)))
                   (filter (lambda (file) (string-suffix? ".sld" file)) (tree-files (path-join root "lib") "")))))

;; The application's name and its text files.
(define (sample-json app)
  (string-append "{\"name\": " (json-string (path-strip-directory app)) ", \"files\": "
                 (files-json (map (lambda (file) (cons file (path-join app file))) (filter text-file? (tree-files app ""))))
                 "}"))

(define (write-json path text)
  (call-with-output-file path (lambda (port) (write-string text port) (newline port))))

;; Each entry's name with the text of the file it names.
(define (files-json entries)
  (string-append "{"
                 (let loop ((entries entries) (out ""))
                   (if (null? entries)
                       out
                       (loop (cdr entries) (string-append out (if (string=? out "") "" ",\n") (json-string (caar entries)) ": "
                                                          (json-string (read-file (cdar entries)))))))
                 "}"))

;; The files a project keeps, as the IDE reads a folder (src/ide/project.mjs).
(define (text-file? path)
  (any (lambda (suffix) (string-suffix? suffix path)) '(".sld" ".scm" ".html" ".css" ".js" ".mjs" ".json" ".svg" ".txt" ".md")))

;; The files under `directory`/`relative`, as paths relative to
;; `directory`, leaving out what the IDE leaves out of a folder.
(define (tree-files directory relative)
  (let loop ((names (directory-names (path-join directory relative))) (out '()))
    (if (null? names)
        out
        (let ((path (if (string=? relative "") (car names) (string-append relative "/" (car names)))))
          (loop (cdr names)
                (cond ((skipped? (car names)) out)
                      ((file-directory? (path-join directory path)) (append out (tree-files directory path)))
                      (else (append out (list path)))))))))

;; Hidden files, build output and installed packages.
(define (skipped? name)
  (or (char=? (string-ref name 0) #\.) (member name '("build" "node_modules"))))

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
