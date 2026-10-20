;; Runs each tests/new program: NAME.sld must print NAME.out exactly, or fail
;; to compile with the text of NAME.err in its diagnostic.
(import
 (scheme base)
 (scheme file)
 (scheme process-context)
 (scheme write)
 (chibi filesystem)
 (only (chibi string) string-contains string-suffix?)
 (srfi 1)
 (lofi host process)
 (lofi compiler build))

;; ---- Cases ----

(define (case-names directory)
  (sort-strings
   (filter-map (lambda (file) (and (string-suffix? ".sld" file) (substring file 0 (- (string-length file) 4))))
               (directory-files directory))))

(define (sort-strings strings)
  (if (null? strings)
      '()
      (let ((pivot (car strings)))
        (append (sort-strings (filter (lambda (s) (string<? s pivot)) (cdr strings)))
                (list pivot)
                (sort-strings (filter (lambda (s) (string>=? s pivot)) (cdr strings)))))))

(define (error-text failure)
  (if (error-object? failure)
      (apply string-append (error-object-message failure)
             (map (lambda (irritant) (let ((port (open-output-string))) (write-string " " port) (write irritant port) (get-output-string port)))
                  (error-object-irritants failure)))
      (let ((port (open-output-string))) (write failure port) (get-output-string port))))

;; ---- Running ----

(define (run-case root directory build name)
  (let* ((source (path-join directory (string-append name ".sld")))
         (expected-output (path-join directory (string-append name ".out")))
         (expected-error (path-join directory (string-append name ".err")))
         (program (path-join build (string-append name ".wasm"))))
    (guard (failure
            (#t (if (file-exists? expected-error)
                    (let ((text (error-text failure)) (wanted (string-trim-newline (read-text expected-error))))
                      (or (string-contains text wanted) (report name "wrong diagnostic" (string-append text "\nexpected: " wanted))))
                    (report name "compile failed" (error-text failure)))))
      (build-program root (list (path-join root "lib") directory (path-join directory "lib") (path-join root "apps/siegework/src")) source program #f)
      (if (file-exists? expected-error)
          (report name "compiled, but a diagnostic was expected" "")
          (let ((record (run-command/capture (list (tool-name "NODE" "node") "--no-warnings" (path-join root "scripts/run-lofi.mjs") program)
                                             '((include-output-hex? . #f)))))
            (let ((output (string-append (option-ref record 'stdout "") (option-ref record 'stderr ""))))
              (or (equal? output (read-text expected-output))
                  (report name "wrong output" (string-append output "\nexpected:\n" (read-text expected-output))))))))))

(define (string-trim-newline text)
  (if (and (> (string-length text) 0) (char=? (string-ref text (- (string-length text) 1)) #\newline))
      (substring text 0 (- (string-length text) 1))
      text))

(define (report name problem detail)
  (display (string-append "FAIL " name ": " problem "\n" detail "\n") (current-error-port))
  #f)

(define (main root selected)
  (let* ((directory (path-join root "tests/new")) (build (make-build-directory (path-join root "build/tests-new") "run-"))
         (names (if (null? selected) (case-names directory) selected))
         (results (map (lambda (name) (run-case root directory build name)) names))
         (failures (count not results)))
    (display (string-append (number->string (- (length names) failures)) "/" (number->string (length names)) " passed\n"))
    (if (zero? failures) 0 1)))

(let ((arguments (command-line)))
  (exit (main (cadr arguments) (cddr arguments))))
