;; Structural operations on the normal-form language. Conversion compares
;; trees, never rendered text; readback makes preservation tests executable.
(define-library (snail experiment lambda-pi normal)
  (export normal=? normal->term normal->string error->string)
  (import
   (snail core base)
   (snail experiment lambda-pi language))
  (begin

    ;; ---- Structural equality ----

    (: normal=? (-> Normal Normal Bool))
    (define (normal=? left right)
      (match (Pair left right)
        ((Pair (NormalStar) (NormalStar)) #t)
        ((Pair (NormalNat) (NormalNat)) #t)
        ((Pair (NormalZero) (NormalZero)) #t)
        ((Pair (NormalPi a) (NormalPi b))
         (and (normal=? (::domain a) (::domain b)) (normal=? (::codomain a) (::codomain b))))
        ((Pair (NormalLam (Binder a)) (NormalLam (Binder b))) (normal=? a b))
        ((Pair (NormalNeutral a) (NormalNeutral b)) (neutral=? a b))
        ((Pair (NormalSucc (Successor a)) (NormalSucc (Successor b))) (normal=? a b))
        ((Pair (NormalVec a) (NormalVec b))
         (and (normal=? (::element a) (::element b)) (normal=? (::size a) (::size b))))
        ((Pair (NormalNil a) (NormalNil b)) (normal=? a b))
        ((Pair (NormalCons a) (NormalCons b))
         (and (normal=? (::element a) (::element b)) (normal=? (::size a) (::size b))
              (normal=? (::head a) (::head b)) (normal=? (::tail a) (::tail b))))
        (_ #f)))

    (: neutral=? (-> NeutralNormal NeutralNormal Bool))
    (define (neutral=? left right)
      (match (Pair left right)
        ((Pair (NormalFree (Identifier a)) (NormalFree (Identifier b))) (string=? a b))
        ((Pair (NormalBound (Index a)) (NormalBound (Index b))) (= a b))
        ((Pair (NormalApp a) (NormalApp b))
         (and (neutral=? (::function a) (::function b))
              (normal=? (::argument a) (::argument b))))
        ((Pair (NormalNatElim a) (NormalNatElim b))
         (and (normal=? (::motive a) (::motive b)) (normal=? (::base a) (::base b))
              (normal=? (::step a) (::step b)) (neutral=? (::scrutinee a) (::scrutinee b))))
        ((Pair (NormalVecElim a) (NormalVecElim b))
         (and (normal=? (::element a) (::element b)) (normal=? (::motive a) (::motive b))
              (normal=? (::base a) (::base b)) (normal=? (::step a) (::step b))
              (normal=? (::size a) (::size b)) (neutral=? (::scrutinee a) (::scrutinee b))))
        (_ #f)))

    ;; ---- Readback into checkable syntax ----

    (: normal->term (-> Normal Check))
    (define (normal->term normal)
      (match normal
        ((NormalStar) star)
        ((NormalPi node) (pi (normal->term (::domain node)) (normal->term (::codomain node))))
        ((NormalLam (Binder body)) (lam (normal->term body)))
        ((NormalNeutral neutral) (Inf (neutral->term neutral)))
        ((NormalNat) nat)
        ((NormalZero) (Zero))
        ((NormalSucc (Successor previous)) (successor (normal->term previous)))
        ((NormalVec node) (vec (normal->term (::element node)) (normal->term (::size node))))
        ((NormalNil element) (vnil (normal->term element)))
        ((NormalCons node)
         (vcons (normal->term (::element node)) (normal->term (::size node))
                (normal->term (::head node)) (normal->term (::tail node))))))

    (: neutral->term (-> NeutralNormal Infer))
    (define (neutral->term neutral)
      (match neutral
        ((NormalFree node) (IFree node))
        ((NormalBound node) (IBound node))
        ((NormalApp node) (app (neutral->term (::function node)) (normal->term (::argument node))))
        ((NormalNatElim node)
         (nat-elim (normal->term (::motive node)) (normal->term (::base node))
                   (normal->term (::step node)) (Inf (neutral->term (::scrutinee node)))))
        ((NormalVecElim node)
         (vec-elim (normal->term (::element node)) (normal->term (::motive node))
                   (normal->term (::base node)) (normal->term (::step node))
                   (normal->term (::size node)) (Inf (neutral->term (::scrutinee node)))))))

    ;; ---- Screen-readable output ----

    ;; #0 names the innermost binder. This is a debug notation, not a parser
    ;; contract. Conversion compares constructors and identifiers, never
    ;; rendered output.
    (: form (-> String (List String) String))
    (define (form name arguments)
      (string-append "(" name " " (string-join arguments " ") ")"))

    (: normal->string (-> Normal String))
    (define (normal->string normal)
      (match normal
        ((NormalStar) "*")
        ((NormalNat) "Nat")
        ((NormalZero) "zero")
        ((NormalPi node)
         (form "Pi" (list (normal->string (::domain node)) (normal->string (::codomain node)))))
        ((NormalLam (Binder body)) (form "lambda" (list (normal->string body))))
        ((NormalNeutral neutral) (neutral->string neutral))
        ((NormalSucc (Successor previous)) (form "succ" (list (normal->string previous))))
        ((NormalVec node)
         (form "Vec" (list (normal->string (::element node)) (normal->string (::size node)))))
        ((NormalNil element) (form "nil" (list (normal->string element))))
        ((NormalCons node)
         (form "cons" (list (normal->string (::element node)) (normal->string (::size node))
                            (normal->string (::head node)) (normal->string (::tail node)))))))

    (: neutral->string (-> NeutralNormal String))
    (define (neutral->string neutral)
      (match neutral
        ((NormalFree (Identifier name)) name)
        ((NormalBound (Index index)) (string-append "#" (i64->string index)))
        ((NormalApp node)
         (form "app" (list (neutral->string (::function node)) (normal->string (::argument node)))))
        ((NormalNatElim node)
         (form "nat-elim" (list (normal->string (::motive node)) (normal->string (::base node))
                                (normal->string (::step node))
                                (neutral->string (::scrutinee node)))))
        ((NormalVecElim node)
         (form "vec-elim" (list (normal->string (::element node)) (normal->string (::motive node))
                                (normal->string (::base node)) (normal->string (::step node))
                                (normal->string (::size node))
                                (neutral->string (::scrutinee node)))))))

    (: error->string (-> Error String))
    (define (error->string error)
      (match error
        ((UnknownName name) (string-append "unknown name: " name))
        ((InvalidIndex index) (string-append "out-of-scope index: " (i64->string index)))
        ((ExpectedFunction) "expected a dependent function type")
        ((ExpectedNatural) "expected Nat")
        ((ConversionMismatch expected actual)
         (string-append "expected " (normal->string expected) "; found " (normal->string actual)))
        ((DuplicateName name) (string-append "duplicate global: " name))))))
