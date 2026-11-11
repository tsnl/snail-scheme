;; The new compiler's unit tests, on Chibi: each library of src/snail/compiler
;; that has logic tests itself, with inputs built by hand. Given the
;; repository's root, it then compares the new passes with the old compiler
;; over every tracked library and the adapters' texts: the readers, the
;; outlines, then loading's problems. `make test-compiler` runs it all;
;; the comparisons that expand whole programs are tests/compare-compiler.sld.
;;
;;   chibi-scheme -D snail-tests -I tests -I bootstrap/chibi-include tests/compiler.scm [ROOT]
(import
 (scheme base)
 (scheme cxr)
 (scheme file)
 (scheme process-context)
 (scheme write)
 (only (chibi string) string-split)
 (only (chibi filesystem) create-directory*)
 (snail stage0 process)
 (only (snail core base) match Some None ::main)
 (only (snail compiler source) test-source)
 (only (snail compiler read lexemes) test-lexemes)
 (only (snail compiler read lines) test-lines)
 (only (snail compiler read literals) test-literals)
 (only (snail compiler read pass) test-read)
 (only (snail compiler read location) test-location)
 (only (snail compiler include inclusion) test-inclusion)
 (only (snail compiler include paths) test-paths)
 (only (snail compiler include pass) test-include)
 (only (snail compiler outline pass) test-outline)
 (only (snail compiler outline imports) test-imports)
 (only (snail compiler outline names) test-names)
 (only (snail compiler integrate files) test-files)
 (only (snail compiler integrate walk) test-walk)
 (only (snail compiler integrate load) test-load)
 (only (snail compiler adapter read)
       read-difference
       malformed-texts
       unusual-texts
       misread-texts
       text-differences)
 (only (snail compiler adapter outline)
       Agreed
       Differed
       Uncompared
       file-comparison
       LibraryHeader
       ProgramHeader
       malformed-headers
       header-comparison)
 (only (snail compiler adapter load)
       load-cases
       load-case-comparison))

;; ---- Unit tests ----

;; The tests that read files write them under `root`'s
;; build/test-compiler/.
(define (unit-tests root)
  (test-source)
  (test-lexemes)
  (test-lines)
  (test-literals)
  (test-read)
  (test-location)
  (test-inclusion)
  (test-paths)
  (test-include)
  (test-outline)
  (test-imports)
  (test-names)
  (test-files (string-append root "/build/test-compiler/files"))
  (test-walk)
  (test-load (string-append root "/build/test-compiler/load"))
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

(define (compare-readers root files)
  (let ((differences (append (library-differences root files) (text-differences))))
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

;; ---- Outline comparison ----

;; What comparing each item found, other than agreement: a pair of
;; `differed` or `uncompared` and a line naming the item.
(define (findings compare name items)
  (let loop ((items items) (found '()))
    (if (null? items)
        (reverse found)
        (loop (cdr items)
              (match (compare (car items))
                ((Agreed) found)
                ((Differed difference)
                 (cons (cons 'differed (string-append (name (car items)) ": " difference)) found))
                ((Uncompared reason)
                 (cons
                  (cons 'uncompared (string-append (name (car items)) ": not compared: " reason))
                  found)))))))

(define (header-name header)
  (let ((port (open-output-string)))
    (match header
      ((LibraryHeader text) (write-string "library " port) (write text port))
      ((ProgramHeader text) (write-string "program " port) (write text port)))
    (get-output-string port)))

;; The headers are written in build/test-compiler/outline/, beside the
;; files they include.
(define (compare-outlines root files)
  (let ((directory (string-append root "/build/test-compiler/outline")))
    (create-directory* (string-append directory "/sample"))
    (let* ((found (append (findings (lambda (file) (file-comparison (string-append root "/" file)))
                                    (lambda (file) file)
                                    files)
                          (findings (lambda (header) (header-comparison directory header))
                                    header-name
                                    malformed-headers)))
           (differences (filter-kind 'differed found)))
      (for-each (lambda (finding) (report (cdr finding))) found)
      (report (string-append "compared the outlines of "
                             (number->string (length files))
                             " files and "
                             (number->string (length malformed-headers))
                             " headers: "
                             (number->string (length differences))
                             " differences, "
                             (number->string (length (filter-kind 'uncompared found)))
                             " not compared"))
      (null? differences))))

(define (filter-kind kind found)
  (cond ((null? found) '())
        ((eq? (caar found) kind) (cons (car found) (filter-kind kind (cdr found))))
        (else (filter-kind kind (cdr found)))))

;; ---- Loading comparison ----

;; The cases are written in build/test-compiler/loads/.
(define (compare-loads root)
  (let ((directory (string-append root "/build/test-compiler/loads")))
    (create-directory* (string-append directory "/sample"))
    (let* ((found (findings (lambda (load-case) (load-case-comparison directory load-case))
                            ::main
                            load-cases))
           (differences (filter-kind 'differed found)))
      (for-each (lambda (finding) (report (cdr finding))) found)
      (report (string-append "compared loading on "
                             (number->string (length load-cases))
                             " problems: "
                             (number->string (length differences))
                             " differences, "
                             (number->string (length (filter-kind 'uncompared found)))
                             " not compared"))
      (null? differences))))

;; ---- Main ----

(define (report line)
  (display line)
  (newline))

(let ((arguments (command-line)))
  (unit-tests (if (pair? (cdr arguments)) (cadr arguments) "."))
  (when (pair? (cdr arguments))
    (let* ((root (cadr arguments))
           (files (tracked-libraries root))
           (readers (compare-readers root files))
           (outlines (compare-outlines root files))
           (loads (compare-loads root)))
      (unless (and readers outlines loads)
        (exit 1)))))
