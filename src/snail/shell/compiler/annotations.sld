;; Declaration metadata is syntax with an owner, not executable code. One
;; optional trailing `(annotations ...)` list works on declarations and
;; fields. Each supported annotation parses its own arguments into a typed
;; value; consumers never need to interpret comments or unchecked syntax.
(define-library (snail shell compiler annotations)
  (export
   Annotation
   Documentation
   parse-annotations
   split-annotations
   annotation-documentation)
  (import
   (snail core base)
   (snail shell compiler read))
  (begin

    ;; ---- Annotation values ----

    ;; Documentation is repeatable. Keep its fragments and locations in
    ;; source order; tooling joins them only when presenting the text.
    ;; A future annotation adds its own arguments, target rules and consumer.
    (enum Annotation
      (Documentation
       ((text String)
        (loc Loc))))

    ;; ---- Parsing ----

    (define (parse-annotations (form Syntax)) (→ (List Annotation)) (! compile)
      (match form
        ((Form (Cons (Ident "annotations" _ _) entries) _) (map parse-annotation entries))
        (_ (compile-error (syntax-loc form) "expected (annotations annotation ...)"))))

    ;; Only declaration parsers call this, after identifying their required
    ;; operands. Never consume a required type or expression as metadata.

    (define (split-annotations (form Syntax) (required I64))
      (→ (Pair Syntax (List Annotation)))
      (! compile)
      (match form
        ((Form items loc)
         (if (> (length items) required)
             (match (reverse items)
               ((Cons (Form (Cons (Ident "annotations" _ _) entries) _) rest)
                (when (and (> (length rest) required) (annotation-list? (list-ref rest 0)))
                  (compile-error loc "a declaration has at most one annotation list"))
                (Pair (Form (reverse rest) loc) (map parse-annotation entries)))
               (_ (Pair form (Nil))))
             (Pair form (Nil))))
        (_ (Pair form (Nil)))))

    (define (annotation-list? (form Syntax)) (→ Bool)
      (match form
        ((Form (Cons (Ident "annotations" _ _) _) _) #t)
        (_ #f)))

    ;; Unknown names are errors: a misspelled annotation cannot disappear
    ;; into inert metadata. Arguments are never evaluated. `doc` applies to
    ;; supported declarations, enum cases and fields; expansion establishes
    ;; the owner. Outside those slots, `annotations` is an ordinary name.

    (define (parse-annotation (form Syntax)) (→ Annotation) (! compile)
      (match form
        ((Form (Cons (Ident "doc" _ _) (Cons (Atom (DString text) _) (Nil))) loc)
         (Documentation text loc))
        ((Form (Cons (Ident "doc" _ _) _) loc)
         (compile-error loc "doc needs exactly one literal string"))
        ((Form (Cons (Ident name _ _) _) loc)
         (compile-error loc (string-append "unknown annotation: " name)))
        (_ (compile-error (syntax-loc form)
                          "expected an annotation application, such as (doc \"text\")"))))

    ;; ---- Documentation ----

    (define (annotation-documentation (annotations (List Annotation))) (→ (Option String))
      (match annotations
        ((Nil) (None))
        (_ (Some (string-join (map (lambda (annotation)
                                     (match annotation
                                       ((Documentation text _) text)))
                                   annotations)
                              "\n")))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-annotations)
    (import
     (only (scheme base) car)
     (snail stage0 testing))
    (begin
      (define annotation-sample
        (lambda (text) (split-annotations (car (read-text text "sample.sld")) 2)))

      (define test-annotations
        (lambda () (expect (::second (annotation-sample "(field String)")) (Nil))
                (expect (::second (annotation-sample "(field String (annotations))")) (Nil))
                (expect (syntax->string (::first (annotation-sample "(field (annotations T))")))
                        "(field (annotations T))")
                (let* ((parsed (annotation-sample
                                "(field String (annotations\n(doc \"first\") (doc \"second\")))"))
                       (annotations (::second parsed)))
                  (expect (syntax->string (::first parsed)) "(field String)")
                  (expect (annotation-documentation annotations) (Some "first\nsecond"))
                  (expect (match annotations
                            ((Cons (Documentation _ loc) _)
                             (list (::file loc) (::line loc) (::column loc)))
                            (_ (Nil)))
                          (list "sample.sld" 2 1)))
                (expect (annotation-documentation (Nil)) (None))
                (for-each (lambda (text)
                            (expect (match (compiling (lambda () (annotation-sample text)))
                                      ((Err (Failed _)) #t)
                                      (_ #f))
                                    #t))
                          (list "(x T (annotations (doc 3)))"
                                "(x T (annotations (doc \"one\" \"two\")))"
                                "(x T (annotations (doc (show 3))))"
                                "(x T (annotations (dco \"typo\")))"
                                "(x T (annotations doc))"))))))
   (else)))
