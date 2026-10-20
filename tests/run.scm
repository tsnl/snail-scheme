;; The test suite: the compiler's unit tests, then every program suite. A
;; program NAME.sld must print NAME.out exactly, or fail to compile with the
;; text of NAME.err in its diagnostic. Finally the Siegework package is
;; built and driven headlessly.
;;
;;   chibi-scheme -D snail-tests -I src -I tests tests/run.scm ROOT [NAME ...]
(import
 (scheme base)
 (scheme cxr)
 (scheme file)
 (scheme process-context)
 (scheme write)
 (chibi filesystem)
 (chibi process)
 (only (chibi string) string-contains string-suffix?)
 (srfi 1)
 (lofi compiler build)
 (only (lofi compiler read) test-read)
 (only (lofi compiler core) test-core)
 (only (lofi compiler wasm) test-wasm))

;; ---- Cases ----

(define (read-text path)
  (call-with-input-file path (lambda (port) (let loop ((chunks '()))
                                              (let ((chunk (read-string 65536 port)))
                                                (if (eof-object? chunk) (apply string-append (reverse chunks)) (loop (cons chunk chunks))))))))

(define (case-names directory)
  (sort-strings (filter-map (lambda (file) (and (string-suffix? ".sld" file) (substring file 0 (- (string-length file) 4))))
                            (directory-files directory))))

(define (sort-strings strings)
  (if (null? strings)
      '()
      (let ((pivot (car strings)))
        (append (sort-strings (filter (lambda (s) (string<? s pivot)) (cdr strings)))
                (list pivot)
                (sort-strings (filter (lambda (s) (string>=? s pivot)) (cdr strings)))))))

(define (error-text failure)
  (let ((port (open-output-string)))
    (if (error-object? failure)
        (begin (write-string (error-object-message failure) port)
               (for-each (lambda (irritant) (write-string " " port) (write irritant port)) (error-object-irritants failure)))
        (write failure port))
    (get-output-string port)))

(define (trim-newline text)
  (let ((length (string-length text)))
    (if (and (> length 0) (char=? (string-ref text (- length 1)) #\newline)) (substring text 0 (- length 1)) text)))

(define (report name problem detail)
  (display (string-append "FAIL " name ": " problem "\n" detail "\n") (current-error-port))
  #f)

;; ---- Programs ----

(define (run-wasm root program)
  (let ((result (process->output+error+status (list "node" "--no-warnings" (path-join root "scripts/run-lofi.mjs") program))))
    (string-append (car result) (cadr result))))

(define (run-case root directories directory build name)
  (let ((source (path-join directory (string-append name ".sld")))
        (expected-output (path-join directory (string-append name ".out")))
        (expected-error (path-join directory (string-append name ".err")))
        (program (path-join build (string-append name ".wasm"))))
    (guard (failure
            ((file-exists? expected-error)
             (let ((text (error-text failure)) (wanted (trim-newline (read-text expected-error))))
               (or (string-contains text wanted) (report name "wrong diagnostic" (string-append text "\nexpected: " wanted)))))
            (#t (report name "compile failed" (error-text failure))))
           (build-program root directories source program #f)
           (cond ((file-exists? expected-error) (report name "compiled, but a diagnostic was expected" ""))
                 ((not (file-exists? expected-output)) (report name "no expected output" ""))
                 (else (let ((output (run-wasm root program)) (expected (read-text expected-output)))
                         (or (equal? output expected) (report name "wrong output" (string-append output "\nexpected:\n" expected)))))))))

(define (run-suite root suite libraries selected)
  (let* ((directory (path-join root suite)) (build (path-join root "build/tests" suite))
         (names (filter (lambda (name) (or (null? selected) (member name selected))) (case-names directory))))
    (create-directory* build)
    (map (lambda (name)
           (run-case root (append (map (lambda (library) (path-join root library)) libraries) (list (path-join root "lib")))
                     directory build name))
         names)))

;; ---- Applications ----

(define (run-siegework root)
  (guard (failure (#t (report "siegework" "headless run failed" (error-text failure))))
         (let ((program (path-join root "build/tests/siegework/app.wasm")))
           (build-program root (list (path-join root "apps/siegework/src") (path-join root "lib"))
                          (path-join root "apps/siegework/main.sld") program #f)
           (let ((result (process->output+error+status (list "node" "--no-warnings" (path-join root "apps/siegework/tests/headless.mjs") program))))
             (or (zero? (caddr result)) (report "siegework" "headless run failed" (string-append (car result) (cadr result))))))))

(define (main root selected)
  (test-read)
  (test-core)
  (test-wasm)
  (let* ((results (append (run-suite root "tests/programs" '("tests/programs" "tests/programs/lib") selected)
                          (run-suite root "apps/siegework/tests" '("apps/siegework/src") selected)
                          (if (null? selected) (list (run-siegework root)) '())))
         (failures (count not results)))
    (display (string-append (number->string (- (length results) failures)) "/" (number->string (length results)) " passed\n"))
    (if (zero? failures) 0 1)))

(let ((arguments (command-line)))
  (exit (main (cadr arguments) (cddr arguments))))
