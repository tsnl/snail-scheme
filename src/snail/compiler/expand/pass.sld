;; The pass `expand`: one library's outline, and the offers of the
;; libraries its imports reach, become the library expanded and what it
;; offers its importers. Its imports are bound first, then its body is
;; expanded at its top level, then its exports are found there. The
;; body of (snail core primitive) holds only primitive declarations; any
;; other's is scanned, its signatures and declarations expanded, then its
;; bodies, as (snail compiler expand declarations) says. A program has no
;; exports, and its statements are its body.
(define-library (snail compiler expand pass)
  (export
   expand)
  (import
   (snail core base)
   (snail core table)
   (snail compiler source)
   (prefix (snail compiler read language) syntax-)
   (prefix (snail compiler outline language) outline-)
   (only (snail compiler outline names) same-library?)
   (snail compiler expand language)
   (snail compiler expand marked)
   (snail compiler expand offer)
   (snail compiler expand forms)
   (snail compiler expand scopes)
   (snail compiler expand state)
   (snail compiler expand imports)
   (snail compiler expand types)
   (snail compiler expand declaration-shapes)
   (snail compiler expand expressions)
   (snail compiler expand scan)
   (snail compiler expand declarations))
  (begin

    ;; ---- The pass ----

    ;; `offers` holds the offer of every library the outline's imports
    ;; reach, but (snail core forms)'s, which `expand` knows.
    (: expand
       (impl (Fn outline-Library (List Offered) -> (Result Expansion (List Feedback)))))
    (define (expand library offers)
      (let ((name (library-name library))
            (known (Cons (Offered forms-library forms-offer) offers)))
        (result-let* ((imported (imported-names (library-imports library) known)))
          (let ((scopes (Scopes name (TopScope empty-table imported) known))
                (body (map written (library-body library))))
            (if (same-library? name primitive-library)
                (result-let* ((declared (primitives scopes body)))
                  (expansion library (::second declared) (::first declared) (None)))
                (result-let* ((expanded (top-level scopes body (program? library))))
                  (expansion library
                             (::scopes expanded)
                             (::tops expanded)
                             (::body expanded))))))))

    (: library-name (impl (Fn outline-Library -> outline-LibraryName)))
    (define (library-name library)
      (match library
        ((outline-Defined name _ _ _ _) name)
        ((outline-Program _ _ _ _) (list "main"))))

    (: library-imports (impl (Fn outline-Library -> (List outline-Import))))
    (define (library-imports library)
      (match library
        ((outline-Defined _ imports _ _ _) imports)
        ((outline-Program _ _ imports _) imports)))

    (: library-body (impl (Fn outline-Library -> (List syntax-Syntax))))
    (define (library-body library)
      (match library
        ((outline-Defined _ _ _ body _) body)
        ((outline-Program _ _ _ body) body)))

    (: program? (impl (Fn outline-Library -> Bool)))
    (define (program? library)
      (match library
        ((outline-Defined _ _ _ _ _) #f)
        ((outline-Program _ _ _ _) #t)))

    ;; The library expanded, and its offer: a program's body, a library's
    ;; exports.
    (: expansion
       (impl
        (Fn outline-Library Scopes (List Top) (Option Expr) -> (Result Expansion (List Feedback)))))
    (define (expansion library scopes tops body)
      (match library
        ((outline-Defined name _ exports _ loc)
         (result-let* ((exported (map-results (lambda (export) (exported scopes export)) exports)))
           (Ok (Expansion (Defined name tops loc) (Offer exported (::top scopes))))))
        ((outline-Program _ _ _ _)
         (Ok (Expansion (Program tops body) (Offer (Nil) (::top scopes)))))))

    ;; An export means what its identifier means at the top level, defined
    ;; there or imported.
    (: exported (impl (Fn Scopes outline-Export -> (Result Export (List Feedback)))))
    (define (exported scopes export)
      (let ((identifier (::identifier export)))
        (match (resolve scopes
                        (Env (Nil) (::library scopes))
                        (Identifier (::name identifier) (Nil)))
          ((BoundAtTop meaning) (Ok (Export (::name export) meaning)))
          (_
           (fail (::loc identifier)
                 (string-append "exported name is not defined: " (::name identifier)))))))

    ;; ---- The top level ----

    (struct TopExpansion
      ((tops (List Top))
       (body (Option Expr))
       (scopes Scopes)))

    ;; The scan and the declarations stop at their first problem; the
    ;; bodies report every one.
    (: top-level (impl (Fn Scopes (List Marked) Bool -> (Result TopExpansion (List Feedback)))))
    (define (top-level scopes body program?)
      (expanding-let* ((scan state (scan-forms (Expanding 1) scopes (Nil) body))
                       (signed state
                               (unchanged state
                                          (checked-signatures (::scopes scan) (::items scan))))
                       (declared state
                                 (unchanged state (declared-items (::scopes scan) (::items scan)))))
        (let ((bodies (expanded-bodies state (::scopes scan) declared program?)))
          (if (null? (::feedback bodies))
              (Ok (TopExpansion (::tops bodies) (sequenced (::statements bodies)) (::scopes scan)))
              (Err (::feedback bodies))))))

    ;; A program's statements, in order, as one expression.
    (: sequenced (impl (Fn (List Expr) -> (Option Expr))))
    (define (sequenced statements)
      (match statements
        ((Nil) (None))
        ((Cons first rest)
         (Some (match (sequenced rest)
                 ((Some more) (Seq first more (expr-loc first)))
                 ((None) first))))))

    ;; ---- Primitives ----

    (: primitive-library outline-LibraryName)
    (define primitive-library
      (list "snail" "core" "primitive"))

    ;; Each form of (snail core primitive) is `(primitive name type)`,
    ;; which binds `name` to a Global of the library ("prim"); the first
    ;; problem stops them. `once` alone may be typed `callable-once`.
    (: primitives
       (impl (Fn Scopes (List Marked) -> (Result (Pair (List Top) Scopes) (List Feedback)))))
    (define (primitives scopes forms)
      (let loop ((scopes scopes)
                 (forms forms)
                 (tops (Nil)))
        (match forms
          ((Nil) (Ok (Pair (reverse tops) scopes)))
          ((Cons form rest)
           (result-let* ((declared (primitive scopes form)))
             (loop (::second declared) rest (Cons (::first declared) tops)))))))

    (: primitive (impl (Fn Scopes Marked -> (Result (Pair Top Scopes) (List Feedback)))))
    (define (primitive scopes form)
      (if (primitive-form? scopes form)
          (result-let* ((parts (refused (primitive-form form)))
                        (global
                         (Ok (Global (list "prim") (::name (::identifier (::name parts))) 0)))
                        (bound (bind scopes
                                     (::identifier (::name parts))
                                     (::loc (::name parts))
                                     (Value (TopGlobal global))))
                        (type (primitive-type bound global (::type parts))))
            (Ok (Pair (Primitive global type (marked-loc form)) bound)))
          (fail (marked-loc form) "(snail core primitive) holds only primitive declarations")))

    (: primitive-form? (impl (Fn Scopes Marked -> Bool)))
    (define (primitive-form? scopes form)
      (match (head-resolution scopes (Env (Nil) (::library scopes)) form)
        ((BoundAtTop (Keyword "primitive")) #t)
        (_ #f)))

    (: primitive-type
       (impl (Fn Scopes Global Marked -> (Result PrimitiveType (List Feedback)))))
    (define (primitive-type scopes global syntax)
      (if (and (string=? (::name global) "once") (callable-once? syntax))
          (Ok (CallableOnce))
          (result-let* ((scheme (expand-scheme scopes (Env (Nil) (::library scopes)) syntax)))
            (Ok (PrimitiveScheme scheme)))))

    (: refused (All (T) (impl (Fn (Result T Malformed) -> (Result T (List Feedback))))))
    (define (refused answer)
      (match answer
        ((Ok value) (Ok value))
        ((Err malformed) (fail (::loc malformed) (::message malformed)))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-expand)
    (import
     (only (scheme base) pair? symbol? symbol->string string? exact-integer? boolean?)
     (snail stage0 testing))
    (begin
      (define (test-expand)
        (test-libraries)
        (test-programs)
        (test-primitives))

      (define loc (Loc "t.sld" 1 1))

      (define (syntax datum)
        (cond ((or (null? datum) (pair? datum)) (syntax-Form (map syntax datum) loc))
              ((symbol? datum) (syntax-Ident (symbol->string datum) loc))
              ((string? datum) (syntax-Text-form datum))
              ((exact-integer? datum) (syntax-Atom (syntax-Integer datum) loc))
              (else (panic "no syntax for this datum"))))

      (define (syntax-Text-form text)
        (syntax-Atom (syntax-Text text) loc))

      (define forms-import
        (outline-Whole forms-library loc))

      (define (library name exports body)
        (outline-Defined name
                         (list forms-import)
                         (map (lambda (export)
                                (outline-Export (outline-Identifier export loc) export))
                              exports)
                         (map syntax body)
                         loc))

      (define (messages result)
        (match result
          ((Ok _) (list))
          ((Err feedback) (map ::message feedback))))

      (define a (list "a"))

      ;; A library offers its exports and its top level.
      (define (test-libraries)
        (match (expand (library a (list "x" "I64") '((define x 1))) (list))
          ((Ok expansion)
           (expect (::expanded expansion)
                   (Defined a (list (Define (Global a "x" 0) (Literal (Integer 1) loc) loc)) loc))
           (expect (map ::name (::exports (::offer expansion))) (list "x" "I64")))
          ((Err feedback) (expect feedback (list))))
        (expect (messages (expand (library a (list "y") '((define x 1))) (list)))
                (list "exported name is not defined: y"))
        (expect (messages (expand (library a (list "y") '((define x z) (define w v))) (list)))
                (list "unbound identifier z" "unbound identifier v")))

      ;; A program's statements are its body, in order.
      (define (test-programs)
        (match (expand
                (outline-Program (list) (None) (list forms-import) (map syntax '(1 (define x 2) x)))
                (list))
          ((Ok expansion)
           (expect (::expanded expansion)
                   (Program
                    (list (Define (Global (list "main") "x" 0) (Literal (Integer 2) loc) loc))
                    (Some (Seq (Literal (Integer 1) loc)
                               (TopRef (TopGlobal (Global (list "main") "x" 0)) loc)
                               loc)))))
          ((Err feedback) (expect feedback (list)))))

      (define (test-primitives)
        (let ((primitive (list "snail" "core" "primitive")))
          (match (expand (library primitive (list "once") '((primitive once callable-once))) (list))
            ((Ok expansion)
             (expect (::expanded expansion)
                     (Defined primitive
                       (list (Primitive (Global (list "prim") "once" 0) (CallableOnce) loc))
                       loc)))
            ((Err feedback) (expect feedback (list))))
          (expect (messages (expand (library primitive (list) '((define x 1))) (list)))
                  (list "(snail core primitive) holds only primitive declarations"))
          (expect (messages (expand (library primitive (list) '((primitive 1 I64))) (list)))
                  (list "expected a primitive name"))))))
   (else)))
