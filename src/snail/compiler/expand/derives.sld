;; Query: whether a library derives an instance, which a `deriving`
;; clause naming Serialize or Deserialize asks for, and where the first
;; declaration that does is. Move derives none: it makes a type linear.
;; A library that derives one needs the implicit libraries `derive`
;; writes its instances with.
(define-library (snail compiler expand derives)
  (export
   first-derivation)
  (import
   (snail core base)
   (snail compiler source)
   (snail compiler expand language))
  (begin

    (: first-derivation (impl (Fn Expanded -> (Option Loc))))
    (define (first-derivation expanded)
      (match expanded
        ((Defined _ tops _) (tops-derivation tops))
        ((Program tops _) (tops-derivation tops))))

    (: tops-derivation (impl (Fn (List Top) -> (Option Loc))))
    (define (tops-derivation tops)
      (match tops
        ((Nil) (None))
        ((Cons top rest)
         (match (top-derivation top)
           ((Some loc) (Some loc))
           ((None) (tops-derivation rest))))))

    (: top-derivation (impl (Fn Top -> (Option Loc))))
    (define (top-derivation top)
      (match top
        ((Struct _ _ _ derivations _ _ loc)
         (if (any? instance-derivation? derivations) (Some loc) (None)))
        ((Enum _ _ _ derivations _ loc)
         (if (any? instance-derivation? derivations) (Some loc) (None)))
        ((InstanceScope _ tops _) (tops-derivation tops))
        (_ (None))))

    (: instance-derivation? (impl (Fn Derivation -> Bool)))
    (define (instance-derivation? derivation)
      (match derivation
        ((DeriveMove _) #f)
        ((DeriveSerialize _) #t)
        ((DeriveDeserialize _) #t)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-derives)
    (import

     (snail stage0 testing))
    (begin
      (define (test-derives)
        (define (data derivations)
          (Struct (Global (list "a") "P" 0) (list) (list) derivations (list) loc (Loc "t.sld" 4 1)))
        (expect (first-derivation (Defined (list "a") (list (data (list (DeriveMove loc)))) loc))
                (None))
        (expect (first-derivation
                 (Program
                  (list (InstanceScope (list) (list (data (list (DeriveSerialize loc)))) loc))
                  (None)))
                (Some (Loc "t.sld" 4 1))))

      (define loc (Loc "t.sld" 1 1))
      ))
   (else)))
