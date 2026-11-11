;; What (snail core forms) offers, the one library without a file: the
;; keywords of the core forms, the builtin types, and the builtin effects,
;; which no handler implements: `mut`, which the compiler itself performs,
;; and `host`, the effect of code that may run anything the host
;; implements. `fn` is a keyword, not a type, though the compiler has a
;; type it writes. The lists are the old compiler's, in its order, in
;; src/snail/shell/compiler/core.sld; the adapter compares them.
(define-library (snail compiler expand forms)
  (export
   forms-library
   forms-offer)
  (import
   (snail core base)
   (snail core table)
   (only (snail compiler outline language) LibraryName)
   (only (snail compiler expand language) Global)
   (snail compiler expand offer))
  (begin

    ;; ---- Names ----

    (: forms-library LibraryName)
    (define forms-library
      (list "snail" "core" "forms"))

    (: keywords (List String))
    (define keywords
      (list "define"
            "lambda"
            "fn"
            "if"
            "begin"
            "let"
            "define-syntax"
            "syntax-rules"
            "quote"
            ":"
            "struct"
            "enum"
            "type"
            "typeclass"
            "instance"
            "define-instance-set"
            "with-instances"
            "match"
            "ann"
            "extern"
            "primitive"
            "effect"
            "handle"
            "expose"
            "case-id"
            "type-convert"
            "try-convert"
            "type-test"
            "artifact-files"
            "link-handle"))

    (: types (List String))
    (define types
      (list "Any"
            "Borrow"
            "Funcref"
            "U8"
            "I32"
            "I64"
            "F32"
            "F64"
            "Bool"
            "Char"
            "Unit"
            "String"
            "Array"
            "Vector"
            "FnOnce"
            "FnMut"))

    (: effects (List String))
    (define effects
      (list "mut" "host"))

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
                     (append (map type-export types) (map effect-export effects)))
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
