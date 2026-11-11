;; The new compiler's unit tests, on Chibi: each library of src/snail/compiler
;; that has logic tests itself, with inputs built by hand. Given the
;; repository's root, it then compares the new reader with the old one over
;; every tracked library and the adapter's texts; `make test-compiler` runs
;; both.
;;
;;   chibi-scheme -D snail-tests -I tests -I bootstrap/chibi-include tests/compiler.scm [ROOT]
(import
 (scheme base)
 (scheme cxr)
 (scheme file)
 (scheme process-context)
 (scheme write)
 (only (chibi string) string-split)
 (snail stage0 process)
 (only (snail core base) match Some None)
 (only (snail compiler source) test-source)
 (only (snail compiler read lexemes) test-lexemes)
 (only (snail compiler read lines) test-lines)
 (only (snail compiler read literals) test-literals)
 (only (snail compiler read pass) test-read)
 (only (snail compiler adapter read)
       read-difference
       malformed-texts
       unusual-texts
       misread-texts
       text-differences))

;; ---- Unit tests ----

(define (unit-tests)
  (test-source)
  (test-lexemes)
  (test-lines)
  (test-literals)
  (test-read)
  (report "the new compiler's unit tests passed"))

;; ---- Reader comparison ----

;; Every tracked library, relative to `root`.
(define (tracked-libraries root)
  (let ((captured (capture-process (list "git" "-C" root "ls-files" "-z" "--" "*.sld"))))
    (unless (zero? (caddr captured))
      (error "git ls-files failed" (cadr captured)))
    (filter-nonempty (string-split (car captured) (integer->char 0)))))

(define (filter-nonempty texts)
  (cond ((null? texts) '())
        ((string=? (car texts) "") (filter-nonempty (cdr texts)))
        (else (cons (car texts) (filter-nonempty (cdr texts))))))

(define (file-text path)
  (call-with-input-file path
    (lambda (port)
      (let loop ((chunks '()))
        (let ((chunk (read-string 65536 port)))
          (if (eof-object? chunk)
              (apply string-append (reverse chunks))
              (loop (cons chunk chunks))))))))

;; The differences the readers show on the tracked libraries, one line each.
(define (library-differences root files)
  (let loop ((files files) (found '()))
    (if (null? files)
        (reverse found)
        (match (read-difference (car files) (file-text (string-append root "/" (car files))))
          ((None) (loop (cdr files) found))
          ((Some difference)
           (loop (cdr files) (cons (string-append (car files) ": " difference) found)))))))

(define (compare-readers root)
  (let* ((files (tracked-libraries root))
         (differences (append (library-differences root files) (text-differences))))
    (for-each report differences)
    (report (string-append "compared the readers on "
                           (number->string (length files))
                           " libraries and "
                           (number->string (+ (length malformed-texts)
                                              (length unusual-texts)
                                              (length misread-texts)))
                           " texts: "
                           (number->string (length differences))
                           " differences"))
    (null? differences)))

;; ---- Main ----

(define (report line)
  (display line)
  (newline))

(unit-tests)
(let ((arguments (command-line)))
  (when (pair? (cdr arguments))
    (unless (compare-readers (cadr arguments))
      (exit 1))))
