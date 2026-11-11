;; Query: where a piece of Syntax is. Every node knows where it starts,
;; and this answers it for a node of any kind.
(define-library (snail compiler read location)
  (export
   syntax-loc)
  (import
   (snail core base)
   (snail compiler source)
   (snail compiler read language))
  (begin

    ;; ---- Locations ----

    (: syntax-loc (impl (Fn Syntax -> Loc)))
    (define (syntax-loc syntax)
      (match syntax
        ((Atom _ loc) loc)
        ((Ident _ loc) loc)
        ((Form _ loc) loc)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-location)
    (import
     (snail stage0 testing))
    (begin
      (define (test-location)
        (expect (syntax-loc (Atom (Integer 1) (Loc "t.sld" 1 2))) (Loc "t.sld" 1 2))
        (expect (syntax-loc (Ident "x" (Loc "t.sld" 3 4))) (Loc "t.sld" 3 4))
        (expect (syntax-loc (Form (list (Ident "x" (Loc "t.sld" 5 7))) (Loc "t.sld" 5 6)))
                (Loc "t.sld" 5 6)))))
   (else)))
