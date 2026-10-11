;; Completed files and their deployment dependencies. Building a file remains
;; an ordinary Scheme computation; this module owns the graph and package data.
(define-library (snail-scheme artifacts)
  (export make-artifact artifact? artifact-name artifact-source artifact-dependencies artifact-inputs
          artifact-closure snapshot-artifacts stage-artifacts)
  (import (scheme base) (scheme file) (scheme write) (snail-scheme build-host))
  (begin

    ;; ---- Named files and dependency closure ----

    (define-record-type <artifact>
      (%make-artifact name source dependencies inputs) artifact?
      (name artifact-name) (source artifact-source) (dependencies artifact-dependencies) (inputs artifact-inputs))

    (define (artifact-name? name)
      (and (string? name) (> (string-length name) 0) (not (member name '("." "..")))
           (let loop ((characters (string->list name)))
             (or (null? characters)
                 (and (not (memv (char->integer (car characters)) '(0 47 92)))
                      (loop (cdr characters)))))))

    (define (make-artifact name source dependencies)
      (unless (artifact-name? name) (error "artifact name must be a filename" name))
      (unless (and (string? source) (list? dependencies)) (error "invalid artifact declaration" name))
      (for-each (lambda (dependency)
                  (unless (artifact? dependency) (error "expected an artifact dependency" name))) dependencies)
      (%make-artifact name (absolute-path source) dependencies (list (absolute-path source))))

    ;; Identity distinguishes a diamond from two conflicting declarations.
    ;; Names form one package namespace, including transitive dependencies.
    (define (artifact-closure roots)
      (let ((names '()) (done '()) (ordered '()))
        (define (visit artifact active)
          (unless (artifact? artifact) (error "expected an artifact" artifact))
          (let* ((name (artifact-name artifact)) (previous (assoc name names)))
            (when (and previous (not (eq? (cdr previous) artifact)))
              (error "conflicting artifact name" name))
            (when (memq artifact active) (error "artifact dependency cycle" (map artifact-name (cons artifact active))))
            (unless (memq artifact done)
              (set! names (cons (cons name artifact) names))
              (for-each (lambda (dependency) (visit dependency (cons artifact active))) (artifact-dependencies artifact))
              (set! done (cons artifact done)) (set! ordered (cons artifact ordered)))))
        (for-each (lambda (root) (visit root '())) roots)
        (reverse ordered)))

    ;; ---- Package files and manifest ----

    ;; Snapshot before another generator can rebuild the same Cargo output.
    ;; Keep original input names for the final input/output alias checks.
    (define (snapshot-artifacts dependencies directory)
      (let ((copies '()))
        (create-directory* directory)
        (for-each
         (lambda (artifact)
           (let ((path (string-append directory "/" (artifact-name artifact))))
             (copy-file (artifact-source artifact) path)
             (set! copies (cons (cons artifact (%make-artifact (artifact-name artifact) path
                                                               (map (lambda (dependency) (cdr (assq dependency copies)))
                                                                    (artifact-dependencies artifact))
                                                               (cons (artifact-source artifact) (artifact-inputs artifact)))) copies))))
         (artifact-closure dependencies))
        (map (lambda (artifact) (cdr (assq artifact copies))) dependencies)))

    (define (artifact-description artifact)
      (list (artifact-name artifact)
            (cons 'dependencies (map artifact-name (artifact-dependencies artifact)))))

    (define (stage-artifacts dependencies directory entry)
      (let ((artifacts (artifact-closure dependencies)) (files (string-append directory "/artifacts")))
        (create-directory* files)
        (for-each (lambda (artifact)
                    (copy-file (artifact-source artifact) (string-append files "/" (artifact-name artifact)))) artifacts)
        (call-with-output-file (string-append directory "/manifest.scm")
          (lambda (port)
            (write `(snail-artifacts (version 1) (entry ,entry)
                                     (roots ,@(map artifact-name dependencies))
                                     (files ,@(map artifact-description artifacts))) port)
            (newline port))))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-artifacts)
    (import (snail-scheme test-utils))
    (begin
      (define (test-artifact-graph)
        (let* ((data (make-artifact "runtime.wat" "runtime.wat" '()))
               (left (make-artifact "left" "left" (list data)))
               (right (make-artifact "right" "right" (list data))))
          (expect (artifact-closure (list left right)) (list data left right))
          (expect (guard (failure (else #t))
                    (artifact-closure (list data (make-artifact "runtime.wat" "other" '()))) #f) #t)))

      (define (test-artifact-names)
        (for-each (lambda (name) (expect (artifact-name? name) #f)) '("" "." ".." "a/b" "a\\b"))
        (expect (artifact-name? (string #\a (integer->char 0))) #f)
        (expect (artifact-name? "runtime 'λ.wat") #t))

      (define (test-artifacts)
        (run-test test-artifact-graph)
        (run-test test-artifact-names))))))
