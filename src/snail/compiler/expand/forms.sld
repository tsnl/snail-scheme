;; What (snail core forms) offers the libraries that import it, the one
;; library without a file: each of the names (snail compiler builtins
;; forms) lists, meaning what it names there. A keyword is the core form
;; it names, and a builtin type or effect a Global of the library.
(define-library (snail compiler expand forms)
  (export
   forms-offer)
  (import
   (snail core base)
   (snail core table)
   (snail compiler names libraries)
   (only (snail compiler names globals) Global)
   (only (snail compiler builtins forms) keywords builtin-types builtin-effects)
   (snail compiler expand offer))
  (begin

    ;; ---- The offer ----

    (: keyword-export (impl (Fn String -> Export)))
    (define (keyword-export name)
      (Export name (Keyword name)))

    (: type-export (impl (Fn String -> Export)))
    (define (type-export name)
      (Export name (TypeName (Global forms-library name 0) #f)))

    (: effect-export (impl (Fn String -> Export)))
    (define (effect-export name)
      (Export name (EffectName (Global forms-library name 0))))

    ;; Its exports, each meaning what its name says, and nothing at its
    ;; top level, since it defines no macro.
    (: forms-offer Offer)
    (define forms-offer
      (Offer (append (map keyword-export keywords)
                     (append (map type-export (map ::first builtin-types))
                             (map effect-export builtin-effects)))
             (TopScope empty-table empty-table)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-forms)
    (import
     (snail stage0 testing))
    (begin
      (define (test-forms)
        (test-meanings)
        (test-names))

      (define (exported name)
        (match (find (lambda (export) (string=? (::name export) name)) (::exports forms-offer))
          ((Some export) (Some (::meaning export)))
          ((None) (None))))

      ;; A keyword means itself; a type and an effect are Globals of the
      ;; library, and no builtin type constructs.
      (define (test-meanings)
        (expect (exported "if") (Some (Keyword "if")))
        (expect (exported "fn") (Some (Keyword "fn")))
        (expect (exported "I64") (Some (TypeName (Global forms-library "I64" 0) #f)))
        (expect (exported "Borrow") (Some (TypeName (Global forms-library "Borrow" 0) #f)))
        (expect (exported "mut") (Some (EffectName (Global forms-library "mut" 0))))
        (expect (exported "host") (Some (EffectName (Global forms-library "host" 0))))
        (expect (exported "List") (None))
        (expect (exported "cond") (None))
        (expect (table-count (::definitions (::scope forms-offer))) 0)
        (expect (table-count (::imports (::scope forms-offer))) 0))

      ;; Keywords first, then types, then effects, each name once.
      (define (test-names)
        (let ((names (map ::name (::exports forms-offer))))
          (expect (length names) 48)
          (expect (list-ref names 0) "define")
          (expect (list-ref names 29) "link-handle")
          (expect (list-ref names 30) "Any")
          (expect (list-ref names 46) "mut")
          (expect (length (delete-duplicates string=? names)) 48)))))
   (else)))
