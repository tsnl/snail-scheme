;; Quoted type-headed declarations become a validated argument specification.
;; Both parsers share that specification; each creates its own result values.
(define-library (snail-scheme options)
  (export <args-spec> make-args-spec args-spec?
          <args> make-args args? args-posargs args-options args-ref
          parse-options parse-options-prefix options-usage options-help)
  (import (scheme base))
  (begin

    ;; ---- Option specifications and parsed arguments ----

    (define-record-type <option>
      (%make-option type names description metavar)
      option-spec?
      (names option-names)
      (type option-type)
      (description option-description)
      (metavar option-metavar))

    (define-record-type <args-spec>
      (%make-args-spec program description options aliases)
      args-spec?
      (program args-spec-program)
      (description args-spec-description)
      (options args-spec-options)
      (aliases args-spec-aliases))

    (define-record-type <args>
      (make-args posargs options)
      args?
      (posargs args-posargs)
      (options args-options))

    (define (make-option type names description . metavar)
      (if (not (memq type '(flag counter key-val key-val-list)))
          (error "unknown argument type" type))
      (if (or (not (list? names)) (null? names))
          (error "expected a nonempty list of option names" names))
      (if (or (not (string? description))
              (and (pair? metavar) (not (string? (car metavar)))))
          (error "expected description and metavar strings"))
      (for-each validate-option-name names)
      (%make-option type (map string-append names) (string-append description)
                    (if (null? metavar) "VALUE" (string-append (car metavar)))))

    (define (read-option declaration)
      (if (or (not (list? declaration)) (not (memv (length declaration) '(3 4))))
          (error "expected (TYPE (NAME ...) DESCRIPTION [METAVAR])" declaration))
      (apply make-option declaration))

    ;; Construction owns the configuration and establishes unique aliases once.
    ;; string-append with one string copies it using the bootstrap's primitives.
    (define (make-args-spec declarations program . help)
      (if (not (list? declarations)) (error "expected a list of option declarations" declarations))
      (if (or (not (string? program)) (string=? program ""))
          (error "expected a nonempty program name string" program))
      (if (or (> (length help) 1) (and (pair? help) (not (string? (car help)))))
          (error "expected at most one help string" help))
      (let ((options (map read-option declarations)))
        (%make-args-spec (string-append program) (if (null? help) "" (string-append (car help)))
                         options (option-table options))))

    (define (option-key entry)
      (car (option-names entry)))

    (define (option-takes-value? entry)
      (memq (option-type entry) '(key-val key-val-list)))

    (define (option-default entry)
      (case (option-type entry)
        ((flag key-val) #f)
        ((counter) 0)
        ((key-val-list) '())))

    (define (args-ref args key)
      (let ((entry (assoc key (args-options args))))
        (if entry (cdr entry) (error "unknown argument key" key))))

    ;; ---- Help text ----

    (define (option-label entry)
      (let names ((remaining (option-names entry)))
        (if (null? (cdr remaining))
            (string-append (car remaining)
                           (if (option-takes-value? entry)
                               (string-append " " (option-metavar entry)) ""))
            (string-append (car remaining) ", " (names (cdr remaining))))))

    (define (option-help entry)
      (string-append "  " (option-label entry) "\n    " (option-description entry) "\n"))

    (define (option-usage entry)
      (string-append " [" (option-key entry)
                     (if (option-takes-value? entry) (string-append " " (option-metavar entry)) "")
                     "]" (if (memq (option-type entry) '(counter key-val-list)) "..." "")))

    (define (options-usage specification)
      (string-append "usage: " (args-spec-program specification)
                     (apply string-append (map option-usage (args-spec-options specification)))
                     " [--] [ARGUMENT ...]"))

    (define (options-help specification)
      (let ((options (args-spec-options specification))
            (description (args-spec-description specification)))
        (string-append (options-usage specification) "\n"
                       (if (string=? description "") "" (string-append "\n" description "\n"))
                       (if (null? options) ""
                           (string-append "\nOptions:\n" (apply string-append (map option-help options)))))))

    ;; ---- Names and alias lookup ----

    (define (option? argument)
      (and (> (string-length argument) 1) (char=? (string-ref argument 0) #\-)))

    ;; #f means no attachment; an empty string is still a supplied operand.
    ;; Long options split at the first =, preserving every later character.
    (define (split-long-option argument)
      (let ((end (string-length argument)))
        (let search ((index 2))
          (cond ((= index end) (values argument #f))
                ((char=? (string-ref argument index) #\=)
                 (values (substring argument 0 index) (substring argument (+ index 1) end)))
                (else (search (+ index 1)))))))

    (define (validate-option-name name)
      (if (or (not (string? name)) (not (option? name)) (string=? name "--")
              (char=? (string-ref name 1) #\=))
          (error "invalid option name" name))
      (if (> (string-length name) 2)
          (let-values (((decoded attached) (split-long-option name)))
            (if (or (not (char=? (string-ref name 1) #\-)) attached)
                (error "invalid option name" name)))))

    (define (register-option aliases entry)
      (let register ((names (option-names entry)) (table aliases))
        (cond ((null? names) table)
              ((assoc (car names) table) (error "duplicate option name" (car names)))
              (else (register (cdr names) (cons (cons (car names) entry) table))))))

    (define (option-table options)
      (let build ((remaining options) (aliases '()))
        (if (null? remaining) aliases
            (build (cdr remaining) (register-option aliases (car remaining))))))

    (define (find-option aliases name help)
      (let ((entry (assoc name aliases)))
        (if entry (cdr entry) (error "unknown option" name help))))

    ;; ---- Applying typed occurrences ----

    ;; Every parse allocates fresh result entries. Only those owned entries
    ;; change; descriptors, alias tables, and input argument lists remain intact.
    (define (apply-option! entry settings value)
      (let ((cell (assoc (option-key entry) settings)))
        (set-cdr! cell
                  (case (option-type entry)
                    ((flag) #t)
                    ((counter) (+ (cdr cell) 1))
                    ((key-val) value)
                    ((key-val-list) (cons value (cdr cell)))))))

    (define (take-operand entry attached remaining help)
      (cond (attached (values attached remaining))
            ((or (null? remaining) (string=? (car remaining) "--"))
             (error "option requires an argument" (option-key entry) help))
            (else (values (car remaining) (cdr remaining)))))

    (define (consume-option! entry attached remaining settings help)
      (if (option-takes-value? entry)
          (let-values (((value rest) (take-operand entry attached remaining help)))
            (apply-option! entry settings value) rest)
          (begin
            (if attached (error "option does not take an argument" (option-key entry) help))
            (apply-option! entry settings #f) remaining)))

    ;; A short cluster walks left to right. Zero-argument options continue;
    ;; the first value option consumes the remaining suffix or the next token.
    (define (consume-short! aliases argument remaining settings help)
      (let ((end (string-length argument)))
        (let scan ((index 1))
          (if (= index end) remaining
              (let* ((name (string-append "-" (substring argument index (+ index 1))))
                     (entry (find-option aliases name help)))
                (if (option-takes-value? entry)
                    (consume-option! entry (if (< (+ index 1) end)
                                               (substring argument (+ index 1) end) #f)
                                     remaining settings help)
                    (begin (apply-option! entry settings #f) (scan (+ index 1)))))))))

    (define (consume-word! aliases arguments settings help)
      (let ((argument (car arguments)) (remaining (cdr arguments)))
        (if (char=? (string-ref argument 1) #\-)
            (let-values (((name attached) (split-long-option argument)))
              (consume-option! (find-option aliases name help) attached remaining settings help))
            (consume-short! aliases argument remaining settings help))))

    ;; ---- Full and prefix parsing ----

    (define (finish-args positionals settings tail)
      (make-args (append (reverse positionals) tail) settings))

    ;; Both grammars share alias lookup, arity validation, and typed updates.
    ;; Prefix mode alone stops at the first positional, preserving its full tail.
    ;; Exact -- always ends interpretation and is consumed only once.
    (define (collect-options specification arguments prefix?)
      (let ((aliases (args-spec-aliases specification))
            (help (options-help specification))
            (settings (map (lambda (entry) (cons (string-append (option-key entry)) (option-default entry)))
                           (args-spec-options specification))))
        (let scan ((remaining arguments) (positionals '()))
          (cond ((null? remaining) (finish-args positionals settings '()))
                ((string=? (car remaining) "--") (finish-args positionals settings (cdr remaining)))
                ((option? (car remaining))
                 (scan (consume-word! aliases remaining settings help) positionals))
                (prefix? (finish-args positionals settings remaining))
                (else (scan (cdr remaining) (cons (car remaining) positionals)))))))

    (define (parse-options specification arguments)
      (collect-options specification arguments #f))

    (define (parse-options-prefix specification arguments)
      (collect-options specification arguments #t)))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (import (snail-scheme test-utils))
    (export test-options)
    (begin
      (define test-specification
        (make-args-spec
         '((counter ("-v" "--verbose") "Increase verbosity.")
           (flag ("-h" "--help") "Show help.")
           (key-val ("--output" "-o") "Write a file." "FILE")
           (key-val-list ("--file" "-f") "Read files." "FILE")
           (key-val-list ("-I") "Prepend library directories." "DIRECTORY"))
         "sample"))

      (define (parse-error arguments)
        (guard (failure (else (list (error-object-message failure) (car (error-object-irritants failure)))))
          (parse-options test-specification arguments)))

      (define (spec-error . arguments)
        (guard (failure (else (error-object-message failure)))
          (apply make-args-spec arguments) #f))

      (define (test-option-defaults)
        (let ((result (parse-options test-specification '())))
          (expect (args-spec? test-specification) #t)
          (expect (args? result) #t)
          (expect (args-posargs result) '())
          (expect (args-ref result "-v") 0)
          (expect (args-ref result "-h") #f)
          (expect (args-ref result "--output") #f)
          (expect (args-ref result "--file") '())
          (expect (args-ref result "-I") '())))

      (define (test-option-actions)
        (let ((result (parse-options test-specification
                                     '("first" "-vv" "--verbose" "-h" "-voout" "-finput"
                                       "--file=other" "-Isrc" "-I" "lib" "second"))))
          (expect (args-posargs result) '("first" "second"))
          (expect (args-ref result "-v") 4)
          (expect (args-ref result "-h") #t)
          (expect (args-ref result "--output") "out")
          (expect (args-ref result "--file") '("other" "input"))
          (expect (args-ref result "-I") '("lib" "src")))
        (let ((result (parse-options test-specification '("--output" "a" "-ob" "--output=c"))))
          (expect (args-ref result "--output") "c")))

      (define (test-option-spelling)
        (let ((result (parse-options test-specification '("-I=src" "--file=a=b" "--file" ""
                                                          "--output=" "-I" "-src" "-I--"))))
          (expect (args-ref result "-I") '("--" "-src" "=src"))
          (expect (args-ref result "--file") '("" "a=b"))
          (expect (args-ref result "--output") ""))
        (let ((result (parse-options test-specification '("-vvv" "--verbose"))))
          (expect (args-ref result "-v") 4))
        (let ((result (parse-options test-specification '("-vvf" "--help"))))
          (expect (args-ref result "-v") 2)
          (expect (args-ref result "--file") '("--help"))
          (expect (args-ref result "-h") #f)))

      (define (test-option-boundaries)
        (expect (args-posargs (parse-options test-specification
                                             '("" "-v" "first" "--file" "a" "second" "-")))
                '("" "first" "second" "-"))
        (let* ((tail '("-v" "--file" "b" "--" "")) (arguments (cons "--" tail))
               (result (parse-options test-specification arguments)))
          (expect (eq? (args-posargs result) tail) #t)
          (expect (args-ref result "-v") 0)
          (expect arguments '("--" "-v" "--file" "b" "--" "")))
        (expect (args-posargs (parse-options test-specification '("first" "--" "-v" "--")))
                '("first" "-v" "--")))

      (define (test-option-prefix)
        (let* ((tail '("script.scm" "--unknown" "-Ithird" "--" ""))
               (arguments (cons "-Ifirst" (cons "-Isecond" tail)))
               (result (parse-options-prefix test-specification arguments)))
          (expect (args-ref result "-I") '("second" "first"))
          (expect (eq? (args-posargs result) tail) #t))
        (expect (args-posargs (parse-options-prefix test-specification '("--" "-v" "--")))
                '("-v" "--")))

      (define (test-option-errors)
        (expect (parse-error '("-I")) '("option requires an argument" "-I"))
        (expect (parse-error '("-Isrc" "-I")) '("option requires an argument" "-I"))
        (expect (parse-error '("--file" "a" "--file")) '("option requires an argument" "--file"))
        (expect (parse-error '("-vvf")) '("option requires an argument" "--file"))
        (expect (parse-error '("--file" "--" "-v")) '("option requires an argument" "--file"))
        (expect (parse-error '("--help=")) '("option does not take an argument" "-h"))
        (expect (parse-error '("--verbose=3")) '("option does not take an argument" "-v"))
        (expect (parse-error '("--output-more=x")) '("unknown option" "--output-more"))
        (expect (parse-error '("-vx")) '("unknown option" "-x"))
        (expect (parse-error '("first" "--unknown")) '("unknown option" "--unknown"))
        (expect (guard (failure (else (cadr (error-object-irritants failure))))
                  (parse-options test-specification '("-x")) #f)
                (options-help test-specification)))

      (define (test-option-ownership)
        (let* ((arguments '("-vv" "-Ione")) (first (parse-options test-specification arguments))
               (second (parse-options test-specification '())))
          (expect (args-ref first "-v") 2)
          (expect (args-ref first "-I") '("one"))
          (expect (args-ref second "-v") 0)
          (expect (args-ref second "-I") '())
          (expect arguments '("-vv" "-Ione"))))

      (define (test-option-declarations)
        (for-each
         (lambda (name)
           (expect (spec-error (list (list 'flag (list name) "Invalid.")) "sample")
                   "invalid option name"))
         '("" "-" "--" "-vv" "--file=value" "-= " 1))
        (expect (spec-error '((unknown ("-v") "Invalid.")) "sample") "unknown argument type")
        (expect (spec-error '((counter "-v" "Invalid.")) "sample")
                "expected a nonempty list of option names")
        (expect (spec-error '((counter () "Invalid.")) "sample")
                "expected a nonempty list of option names")
        (expect (spec-error '((counter ("-v" . "--verbose") "Invalid.")) "sample")
                "expected a nonempty list of option names")
        (expect (spec-error '((counter ("-v"))) "sample")
                "expected (TYPE (NAME ...) DESCRIPTION [METAVAR])")
        (expect (spec-error '((counter ("-v") "Invalid." "VALUE" "EXTRA")) "sample")
                "expected (TYPE (NAME ...) DESCRIPTION [METAVAR])")
        (expect (spec-error '(counter) "sample") "expected (TYPE (NAME ...) DESCRIPTION [METAVAR])")
        (expect (spec-error #f "sample") "expected a list of option declarations")
        (expect (spec-error '((flag ("-x") "First.") (counter ("--other" "-x") "Second.")) "sample")
                "duplicate option name")
        (expect (spec-error '((flag ("-x" "-x") "Repeated.")) "sample") "duplicate option name")
        (expect (guard (failure (else (error-object-message failure)))
                  (args-ref (parse-options test-specification '()) "--undeclared") #f)
                "unknown argument key"))

      (define (test-specification-metadata)
        (expect (spec-error '() "") "expected a nonempty program name string")
        (expect (spec-error '() 1) "expected a nonempty program name string")
        (expect (spec-error '() "sample" 1) "expected at most one help string")
        (expect (spec-error '() "sample" "first" "second") "expected at most one help string")
        (expect (spec-error '((key-val ("-o") 1)) "sample")
                "expected description and metavar strings")
        (expect (spec-error '((key-val ("-o") "Invalid." #f)) "sample")
                "expected description and metavar strings"))

      (define (test-specification-ownership)
        (let* ((name (string-append "-v")) (names (list name))
               (description (string-append "Increase.")) (program (string-append "sample"))
               (help (string-append "Long help."))
               (specification (make-args-spec (list (list 'counter names description)) program help)))
          (set-car! names "--replaced")
          (for-each (lambda (text) (string-set! text 0 #\x)) (list name description program help))
          (expect (options-help specification)
                  "usage: sample [-v]... [--] [ARGUMENT ...]\n\nLong help.\n\nOptions:\n  -v\n    Increase.\n")
          (let ((result (parse-options specification '("-vv"))))
            (expect (args-ref result "-v") 2)
            (string-set! (caar (args-options result)) 0 #\x)
            (expect (args-ref (parse-options specification '("-v")) "-v") 1))))

      (define (test-empty-specification)
        (let* ((specification (make-args-spec '() "app"))
               (result (parse-options specification '("first" "--" "-v" "--"))))
          (expect (args-options result) '())
          (expect (args-posargs result) '("first" "-v" "--"))
          (expect (options-usage specification) "usage: app [--] [ARGUMENT ...]")
          (expect (options-help specification) "usage: app [--] [ARGUMENT ...]\n")
          (expect (options-help (make-args-spec '() "app" "Long help."))
                  "usage: app [--] [ARGUMENT ...]\n\nLong help.\n")))

      (define (test-option-help)
        (let ((specification
               (make-args-spec
                '((counter ("-v" "--verbose") "Increase verbosity.")
                  (key-val ("-o" "--output") "Write a file.")
                  (key-val-list ("-I") "Search a directory." "DIR")
                  (flag ("-h" "--help") "Show help."))
                "app" "Long help.\nMore help.")))
          (expect (options-usage specification)
                  "usage: app [-v]... [-o VALUE] [-I DIR]... [-h] [--] [ARGUMENT ...]")
          (expect (options-help specification)
                  (string-append
                   "usage: app [-v]... [-o VALUE] [-I DIR]... [-h] [--] [ARGUMENT ...]\n\n"
                   "Long help.\nMore help.\n\nOptions:\n  -v, --verbose\n    Increase verbosity.\n"
                   "  -o, --output VALUE\n    Write a file.\n  -I DIR\n    Search a directory.\n"
                   "  -h, --help\n    Show help.\n"))))

      (define (test-options)
        (run-test test-option-defaults)
        (run-test test-option-actions)
        (run-test test-option-spelling)
        (run-test test-option-boundaries)
        (run-test test-option-prefix)
        (run-test test-option-errors)
        (run-test test-option-ownership)
        (run-test test-option-declarations)
        (run-test test-specification-metadata)
        (run-test test-specification-ownership)
        (run-test test-empty-specification)
        (run-test test-option-help))))
   (else)))
