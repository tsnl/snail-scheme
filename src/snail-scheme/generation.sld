;; A generator returns source declarations and completed artifact dependencies.
;; This data-only protocol is shared by its process and the compiler's loader.
(define-library (snail-scheme generation)
  (export generated-library generation-source-path generation-output-path
          write-generation-result generator-program generated-library-form
          decode-generation-artifacts datum->located)
  (import (scheme base) (scheme cxr) (scheme file) (scheme write)
          (snail-scheme syntax) (snail-scheme source)
          (snail-scheme artifacts) (snail-scheme build-host) (snail-scheme chromium-trace))
  (begin

    ;; ---- Generator result and relative paths ----

    (define-record-type <generated-library>
      (generated-library declarations artifacts) generated-library?
      (declarations generated-declarations) (artifacts generated-artifacts))

    (define source-directory (make-parameter #f))
    (define output-directory (make-parameter #f))

    (define (relative-to directory path)
      (unless directory (error "generation path used outside a generator"))
      (absolute-path (if (and (> (string-length path) 0) (char=? (string-ref path 0) #\/)) path
                         (string-append directory "/" path))))
    (define (generation-source-path path) (relative-to (source-directory) path))
    (define (generation-output-path path) (relative-to (output-directory) path))

    ;; ---- Located source transport ----

    (define (datum->located value loc)
      (cond ((syntax? value) value)
            ((vector? value) (make-vector-syntax (map (lambda (value) (datum->located value loc)) (vector->list value)) loc))
            ((or (pair? value) (null? value))
             (let loop ((rest value) (items '()))
               (if (pair? rest) (loop (cdr rest) (cons (datum->located (car rest) loc) items))
                   (make-list-syntax (reverse items) (if (null? rest) '() (datum->located rest loc)) loc))))
            (else (make-atom-syntax value loc))))

    (define (encode-location loc)
      (and loc (list (loc-filename loc) (loc-line loc) (loc-column loc))))
    (define (decode-location data fallback)
      (unless (or (not data)
                  (and (list? data) (= (length data) 3) (string? (car data))
                       (integer? (cadr data)) (positive? (cadr data))
                       (integer? (caddr data)) (positive? (caddr data))))
        (error "invalid generated source location" data))
      (if data (apply make-loc data) fallback))

    (define (encode-syntax value)
      (cond ((list-syntax? value)
             (list 'list (encode-location (syntax-loc value))
                   (map encode-syntax (list-syntax-elements value))
                   (and (not (null? (list-syntax-improper-tail value))) (encode-syntax (list-syntax-improper-tail value)))))
            ((vector-syntax? value)
             (list 'vector (encode-location (syntax-loc value)) (map encode-syntax (vector-syntax-elements value))))
            (else (list 'atom (encode-location (syntax-loc value)) (atom-syntax-value value)))))

    (define (decode-syntax value fallback)
      (unless (and (list? value) (pair? value)
                   (case (car value)
                     ((list) (and (= (length value) 4) (list? (caddr value))))
                     ((vector) (and (= (length value) 3) (list? (caddr value))))
                     ((atom) (and (= (length value) 3)
                                  (not (or (pair? (caddr value)) (vector? (caddr value))))))
                     (else #f)))
        (error "invalid generated syntax" value))
      (let ((loc (decode-location (cadr value) fallback)))
        (case (car value)
          ((list) (make-list-syntax (map (lambda (value) (decode-syntax value fallback)) (caddr value))
                                    (if (cadddr value) (decode-syntax (cadddr value) fallback) '()) loc))
          ((vector) (make-vector-syntax (map (lambda (value) (decode-syntax value fallback)) (caddr value)) loc))
          ((atom) (make-atom-syntax (caddr value) loc))
          (else (error "invalid generated syntax" value)))))

    (define (encode-artifact artifact)
      (list (artifact-name artifact) (artifact-source artifact) (map artifact-name (artifact-dependencies artifact))))

    (define (write-generation-result output source directory thunk)
      (with-chromium-trace-to (string-append directory "/generator.trace.json")
                              (lambda ()
                                (parameterize ((source-directory source) (output-directory directory))
                                  (save-generation-result output (thunk))))))

    (define (save-generation-result output result)
      (unless (generated-library? result) (error "generator must return generated-library"))
      (unless (list? (generated-declarations result)) (error "generated declarations must be a list"))
      (call-with-output-file output
        (lambda (port)
          (write `(snail-generation 1
                                    ,(map (lambda (value) (encode-syntax (datum->located value #f))) (generated-declarations result))
                                    ,(map encode-artifact (artifact-closure (generated-artifacts result)))
                                    ,(map artifact-name (generated-artifacts result))) port)
          (newline port))))

    (define (generation-result? result)
      (and (list? result) (= (length result) 5) (eq? (car result) 'snail-generation)
           (eqv? (cadr result) 1) (list? (caddr result)) (list? (cadddr result)) (list? (car (cddddr result)))))

    (define (decode-generation-artifacts result)
      (unless (generation-result? result) (error "invalid generator result" result))
      (let ((done '()) (declarations (cadddr result)))
        (define (resolve name active)
          (when (member name active) (error "generated artifact dependency cycle" name active))
          (let ((prior (assoc name done)) (declaration (assoc name declarations)))
            (if prior (cdr prior)
                (begin
                  (unless (and declaration (= (length declaration) 3)) (error "missing generated artifact" name))
                  (let ((artifact (make-artifact name (cadr declaration)
                                                 (map (lambda (dependency) (resolve dependency (cons name active))) (caddr declaration)))))
                    (set! done (cons (cons name artifact) done)) artifact)))))
        (validate-artifact-declarations declarations)
        (map (lambda (name) (resolve name '())) (car (cddddr result)))))

    (define (validate-artifact-declarations declarations)
      (let loop ((rest declarations) (names '()))
        (unless (null? rest)
          (let ((fields (car rest)))
            (unless (and (list? fields) (= (length fields) 3) (string? (car fields))
                         (string? (cadr fields)) (> (string-length (cadr fields)) 0)
                         (char=? (string-ref (cadr fields) 0) #\/)
                         (list? (caddr fields)))
              (error "invalid generated artifact" fields))
            (when (member (car fields) names) (error "duplicate generated artifact" (car fields)))
            (for-each (lambda (name) (unless (string? name) (error "invalid artifact dependency" name))) (caddr fields))
            (loop (cdr rest) (cons (car fields) names))))))

    ;; ---- Wrapper validation and generator program ----

    (define (form-fields form)
      (unless (and (list-syntax? form) (null? (list-syntax-improper-tail form)))
        (error "expected a proper declaration" (syntax-loc form)))
      (list-syntax-elements form))

    (define (form-tag form)
      (let ((fields (form-fields form)))
        (and (pair? fields) (syntax->datum (car fields)))))

    (define (clauses form tag)
      (unless (>= (length (form-fields form)) 2) (error "missing generated library name" (syntax-loc form)))
      (let loop ((rest (cddr (form-fields form))) (found '()))
        (cond ((null? rest) (reverse found))
              ((eq? (form-tag (car rest)) tag) (loop (cdr rest) (cons (car rest) found)))
              (else (loop (cdr rest) found)))))

    (define (generator-program form output source directory)
      (let ((begins (clauses form 'begin)) (loc (syntax-loc form)))
        (for-each (lambda (clause)
                    (unless (memq (form-tag clause) '(import export begin))
                      (error "unsupported generator clause" (syntax-loc clause)))) (cddr (form-fields form)))
        (unless (= (length begins) 1) (error "generate-library requires exactly one begin" loc))
        (append (clauses form 'import)
                (list (datum->located '(import (rename (only (snail-scheme generation) write-generation-result)
                                                       (write-generation-result %snail-write-generation-result))) loc)
                      (datum->located `(%snail-write-generation-result ,output ,source ,directory
                                                                       (lambda () ,@(cdr (form-fields (car begins))))) loc)))))

    (define (check-generated-declaration form)
      (unless (memq (form-tag form) '(import begin))
        (error "generator may return only import and begin declarations" (syntax-loc form))))

    (define (generated-library-form wrapper result)
      (unless (generation-result? result) (error "invalid generator result" result))
      (let* ((loc (syntax-loc wrapper))
             (declarations (map (lambda (value) (decode-syntax value loc)) (caddr result))))
        (for-each check-generated-declaration declarations)
        (datum->located `(define-library ,(cadr (form-fields wrapper))
                           ,@(clauses wrapper 'export) ,@declarations) loc))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-generation)
    (import (snail-scheme test-utils))
    (begin
      (define (test-generation-stages)
        (let* ((loc (make-loc "wrapper.sld" 1 1))
               (wrapper (datum->located '(generate-library (example value) (export value)
                                                           (import (generator only)) (begin 42)) loc))
               (body (datum->located '(begin (define value 42)) (make-loc "template.scm" 8 3)))
               (result `(snail-generation 1 (,(encode-syntax body)) () ()))
               (library (generated-library-form wrapper result)))
          (expect (syntax->datum library) '(define-library (example value) (export value) (begin (define value 42))))
          (expect (loc-filename (syntax-loc (cadddr (list-syntax-elements library)))) "template.scm")
          (expect (syntax->datum (car (generator-program wrapper "result" "source" "output"))) '(import (generator only)))))

      (define (test-generation-artifacts)
        (let* ((result '(snail-generation 1 () (("data" "/data" ())
                                                ("left" "/left" ("data")) ("right" "/right" ("data"))) ("left" "right")))
               (roots (decode-generation-artifacts result)))
          (expect (eq? (car (artifact-dependencies (car roots))) (car (artifact-dependencies (cadr roots)))) #t))
        (for-each
         (lambda (result) (expect (guard (failure (else #t)) (decode-generation-artifacts result) #f) #t))
         '((snail-generation 2 () () ())
           (snail-generation 1 () (("a" "/a" ()) ("a" "/b" ())) ("a"))
           (snail-generation 1 () (("a" "/a" ("b")) ("b" "/b" ("a"))) ("a"))
           (snail-generation 1 () (("a" "/a" ("missing"))) ("a")))))

      (define (test-generation)
        (run-test test-generation-stages)
        (run-test test-generation-artifacts))))))
