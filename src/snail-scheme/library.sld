;; Compilation containers, independent of their bodies' representation.
;; A named library and an unnamed script share this record. Expansion supplies
;; ordered HIR items; lowering supplies MIR code and data. This module neither
;; interprets those bodies nor distinguishes value identities from macro identities.
;; Resolved imports retain dependencies even when they expose no bindings.
(define-library (snail-scheme library)
  (export
   <library> make-library library? library-name library-imports library-exports
   library-dependencies library-body library-loc library-dependency-order
   <import-declaration> make-import-declaration import-declaration? import-declaration-libraries
   import-declaration-bindings import-declaration-source import-declaration-loc
   <named-binding> make-named-binding named-binding? named-binding-name named-binding-definition)
  (import (scheme base))
  (begin

    ;; ---- Library ----

    (define-record-type <library>
      (make-library name imports exports dependencies body loc)
      library?
      (name library-name) ; library-name datum, or #f for the executable's script
      (imports library-imports) ; resolved import-declarations
      (exports library-exports) ; named-bindings with external names
      (dependencies library-dependencies) ; dependency names retained for provenance
      (body library-body) ; the current compiler pass owns this payload's grammar
      (loc library-loc))

    ;; ---- Resolved interface ----

    (define-record-type <import-declaration>
      (make-import-declaration libraries bindings source loc)
      import-declaration?
      (libraries import-declaration-libraries) ; resolved libraries, in import-set order
      (bindings import-declaration-bindings) ; named-bindings with local names
      (source import-declaration-source) ; original located import syntax
      (loc import-declaration-loc))

    (define-record-type <named-binding>
      (make-named-binding name definition)
      named-binding?
      (name named-binding-name) ; visible symbol in an import or export interface
      (definition named-binding-definition)) ; original identity, unchanged by renaming

    ;; ---- Initialization order ----

    ;; Expansion rejects import cycles. Identity-based visitation handles diamonds
    ;; and repeated import sets; every dependency precedes its importer exactly once.
    (define (library-dependency-order root)
      (let ((seen '()) (ordered '()))
        (define (visit library)
          (if (not (memq library seen))
              (begin
                (set! seen (cons library seen))
                (for-each
                 (lambda (declaration)
                   (for-each visit (import-declaration-libraries declaration)))
                 (library-imports library))
                (set! ordered (cons library ordered)))))
        (visit root)
        (reverse ordered))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-library)
    (import (snail-scheme test-utils))
    (begin
      (define (test-dependency-order)
        (define (unit name imports)
          (make-library name (list (make-import-declaration imports '() #f #f))
                        '() '() 'opaque-body #f))
        (let* ((base (unit '(base) '()))
               (left (unit '(left) (list base)))
               (right (unit '(right) (list base)))
               (root (unit #f (list left right base))))
          (expect (library-dependency-order root) (list base left right root))
          (expect (library-body root) 'opaque-body)))

      (define (test-library)
        (run-test test-dependency-order))))))
