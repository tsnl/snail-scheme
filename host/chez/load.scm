;; Load the compiler's explicit stage-zero closure as native Chez libraries.
;; The .sld envelope belongs to Snail Scheme; Chez executes only its erased
;; compiler bodies, never an arbitrary application's source.
(import
 (chezscheme))

(define root (cadr (command-line)))
(define mode (caddr (command-line)))
(define test-feature? (string=? mode "test"))
(library-directories (cons (string-append root "/host/chez") (library-directories)))

(import
 (only (snail stage0 system) error-text))

(define (joined-name name)
  (let loop ([parts name])
    (if (null? (cdr parts)) (symbol->string (car parts))
        (string-append (symbol->string (car parts)) "/" (loop (cdr parts))))))

(define (stage-zero-source name)
  (let ([path (joined-name name)])
    (cond [(file-exists? (string-append root "/host/chez/" path ".sld"))
           (string-append root "/host/chez/" path ".sld")]
          [(or (equal? name '(snail shell compiler))
               (and (>= (length name) 3) (equal? (list-head name 3) '(snail shell compiler))))
           (string-append root "/src/" path ".sld")]
          [(and test-feature? (or (equal? name '(snail stage0 testing))
                                  (equal? name '(snail shell project))
                                  (equal? name '(snail shell project plan))))
           (string-append root "/tests/" path ".sld")]
          [else (error 'bootstrap "library is outside the compiler's stage-zero closure" name)])))

(define (feature? name)
  (cond [(eq? name 'else) #t] [(eq? name 'snail-tests) test-feature?]
        [(pair? name)
         (case (car name)
           [(and) (for-all feature? (cdr name))]
           [(or) (exists feature? (cdr name))]
           [(not) (not (feature? (cadr name)))]
           [else #f])]
        [else #f]))

(define (sections declarations)
  (apply append
         (map (lambda (form)
                (if (eq? (car form) 'cond-expand)
                    (let ([selected (find (lambda (clause) (feature? (car clause))) (cdr form))])
                      (if selected (sections (cdr selected)) '()))
                    (list form))) declarations)))

(define (section-values name declarations)
  (apply append (map cdr (filter (lambda (form) (eq? (car form) name)) declarations))))

(define (import-name specification)
  (if (memq (car specification) '(only except rename prefix for))
      (import-name (cadr specification)) specification))

;; Snail lets a definition shadow an imported name. R6RS libraries require
;; the unused import to be excluded explicitly, so establish that boundary
;; once while translating the library envelope.
(define (defined-names forms)
  (apply append
         (map (lambda (form)
                (case (car form)
                  [(define define-syntax struct type)
                   (list (if (pair? (cadr form)) (caadr form) (cadr form)))]
                  [(enum) (cons (if (pair? (cadr form)) (caadr form) (cadr form))
                                (map car (filter (lambda (case) (not (eq? (car case) 'annotations)))
                                                 (cddr form))))]
                  [(begin) (defined-names (cdr form))]
                  [else '()])) forms)))
(define (unshadowed-import specification names)
  (let* ([exported (environment-symbols (environment specification))]
         [hidden (filter (lambda (name) (memq name exported)) names)])
    (if (null? hidden) specification `(except ,specification ,@hidden))))

(define loaded '())
(define (load-compiler-library name)
  (unless (or (member name loaded)
              (equal? name '(chezscheme))
              (file-exists? (string-append root "/host/chez/" (joined-name name) ".sls")))
    (let* ([path (stage-zero-source name)] [form (call-with-input-file path read)]
           [declarations (sections (cddr form))]
           [imports (section-values 'import declarations)])
      (unless (and (eq? (car form) 'define-library) (equal? (cadr form) name))
        (error 'bootstrap "library name does not match its source" path name))
      (for-each (lambda (spec) (load-compiler-library (import-name spec))) imports)
      (guard (failure [else (error 'bootstrap (string-append path ": " (error-text failure)))])
        (eval `(library ,name
                 (export ,@(section-values 'export declarations))
                 (import ,@(map (lambda (spec)
                                  (unshadowed-import spec
                                                     (defined-names (section-values 'begin
                                                                                    declarations))))
                                imports))
                 ,@(section-values 'begin declarations))))
      (set! loaded (cons name loaded)))))

(guard (failure [else
                 (display "snail: " (current-error-port))
                 (display (error-text failure) (current-error-port))
                 (newline (current-error-port))
                 (exit 1)])
  (cond [(string=? mode "compile")
         (load-compiler-library '(snail shell compiler driver))
         (command-line (cons "snail-compiler" (cdddr (command-line))))
         (eval '(import
                 (snail shell compiler driver)))
         (eval '(compile-command-line))]
        [(string=? mode "test")
         (let* ([entry (string-append root "/tests/run.scm")]
                [imports (call-with-input-file entry read)])
           (for-each (lambda (spec) (load-compiler-library (import-name spec))) (cdr imports))
           (command-line (cons "snail-tests" (cons root (cdddr (command-line)))))
           (load entry))]
        [(string=? mode "tool")
         (load-compiler-library '(snail stage0 build))
         (command-line (cons "snail-tool" (cons root (cdddr (command-line)))))
         (load (string-append root "/scripts/snail.scm"))]
        [else (error 'bootstrap "unknown stage-zero entry" mode)])
  )
