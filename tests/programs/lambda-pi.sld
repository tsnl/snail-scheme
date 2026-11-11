;; Behavioral checks of the experimental checker, evaluated as linked Wasm.
(import
 (except (snail core base) ann)
 (snail core io)
 (snail experiment lambda-pi language)
 (snail experiment lambda-pi normal)
 (snail experiment lambda-pi driver))

(: demand (-> Bool String Unit))
(define (demand condition message) (if condition (unit) (panic message)))

(: context-of (-> (Result Context Error) Context))
(define (context-of result)
  (match result ((Ok context) context) ((Err error) (panic (error->string error)))))

(: checked-of (-> (Result Checked Error) Checked))
(define (checked-of result)
  (match result ((Ok checked) checked) ((Err error) (panic (error->string error)))))

;; Recheck a normal form at its normalized type, then normalize again.
;; This tests preservation as well as normalization's idempotence.
(: roundtrip (-> Context Infer Checked))
(define (roundtrip context term)
  (let* ((first (checked-of (infer context term)))
         (second (checked-of (check context (normal->term (term-normal first))
                                    (normal->term (type-normal first))))))
    (demand (normal=? (term-normal first) (term-normal second)) "normalization is not idempotent")
    (demand (normal=? (type-normal first) (type-normal second)) "readback changed the type")
    first))

(: expect (-> Context Infer String String Unit))
(define (expect context term type normal)
  (let ((checked (roundtrip context term)))
    (demand (string=? type (normal->string (type-normal checked))) "unexpected type")
    (demand (string=? normal (normal->string (term-normal checked))) "unexpected normal form")))

(: reject (-> (Result Checked Error) String Unit))
(define (reject result expected)
  (match result
    ((Ok _) (panic "accepted an ill-typed term"))
    ((Err error) (demand (string=? (error->string error) expected) "wrong checking error"))))

(: reject-conversion (-> (Result Checked Error) Unit))
(define (reject-conversion result)
  (match result
    ((Err (ConversionMismatch _ _)) (unit))
    (_ (panic "expected a conversion failure"))))

;; ---- Binding, closure capture and conversion ----

(: context Context)
(define context
  (context-of
   (result-let* ((context (assume empty-context "A" star))
                 (context (assume context "x" (reference "A")))
                 (context (assume context "y" (reference "A"))))
     (assume context "f" (pi (reference "A") (reference "A"))))))

(: identity Infer)
(define identity (ann (lam (local 0)) (pi nat nat)))

(: constant Infer)
(define constant
  (ann (lam (lam (local 1)))
       (pi (reference "A") (pi (reference "A") (reference "A")))))

(expect context constant "(Pi A (Pi A A))" "(lambda (lambda #1))")
(expect context (app constant (reference "x")) "(Pi A A)" "(lambda x)")
(expect context (apps constant (list (reference "x") (reference "y"))) "A" "x")
(expect empty-context (app identity (number 3)) "Nat" "(succ (succ (succ zero)))")
(expect empty-context
        (ann (lam (Inf (app identity (local 0)))) (pi nat nat))
        "(Pi Nat Nat)" "(lambda #0)")

;; The result domain mentions the immediately enclosing binder; its result
;; mentions the same binder at index one. Confusing levels and indices fails.
(: poly Infer)
(define poly (ann (lam (lam (local 0))) (pi star (pi (local 0) (local 1)))))
(expect empty-context poly "(Pi * (Pi #0 #1))" "(lambda (lambda #0))")
(expect context (apps poly (list (reference "A") (reference "x"))) "A" "x")

(: computed-nat Check)
(define computed-nat (Inf (app (ann (lam (local 0)) (pi star star)) nat)))
(expect empty-context (ann (Zero) computed-nat) "Nat" "zero")
(expect empty-context (ann (lam (local 0)) (pi computed-nat computed-nat))
        "(Pi Nat Nat)" "(lambda #0)")

;; Normalization is beta/iota, without eta: an opaque f stays different
;; from lambda x. f x, even though both have the same function type.
(let ((f (roundtrip context (free "f")))
      (eta (roundtrip context
                      (ann (lam (Inf (app (free "f") (local 0))))
                           (pi (reference "A") (reference "A"))))))
  (demand (not (normal=? (term-normal f) (term-normal eta))) "unexpected eta conversion"))
(let ((families
       (context-of
        (result-let* ((context (assume context "H"
                                       (pi (pi (reference "A") (reference "A")) star))))
          (assume context "hf" (Inf (app (free "H") (reference "f"))))))))
  (reject-conversion
   (check families (reference "hf")
          (Inf (app (free "H") (lam (Inf (app (free "f") (local 0)))))))))
(write-line "binding, closures, beta conversion and no eta: ok")

;; ---- Global contexts are immutable snapshots ----

(: defined Context)
(define defined (context-of (define-global empty-context "id" identity)))
(: retained Checked)
(define retained (roundtrip defined (app (free "id") (number 2))))
(: extended Context)
(define extended (context-of (define-global defined "three" (ann (number 3) nat))))
(expect extended (app (free "id") (reference "three")) "Nat" "(succ (succ (succ zero)))")
(demand (string=? (normal->string (term-normal retained)) "(succ (succ zero))")
        "extending the context changed an old result")
(reject (infer defined (free "three")) "unknown name: three")
(match (assume context "x" nat)
  ((Err (DuplicateName name)) (demand (string=? name "x") "wrong duplicate name"))
  (_ (panic "allowed an assumption to shadow a global")))
(match (define-global defined "id" identity)
  ((Err (DuplicateName name)) (demand (string=? name "id") "wrong duplicate name"))
  (_ (panic "allowed a definition to shadow a global")))
(match (assume empty-context "bad" (local 0))
  ((Err (InvalidIndex index)) (demand (= index 0) "wrong invalid index"))
  (_ (panic "published an invalid declaration")))
(write-line "checked declarations and immutable context snapshots: ok")

;; ---- Natural elimination: closed and blocked computations ----

(: nat-step Check)
(define nat-step (lam (lam (successor (local 0)))))
(: open-nat Context)
(define open-nat (context-of (assume empty-context "n" nat)))

(expect empty-context (nat-elim (lam nat) (number 2) nat-step (number 3))
        "Nat" "(succ (succ (succ (succ (succ zero)))))")
(expect empty-context (nat-elim (lam nat) (number 2) nat-step (Zero))
        "Nat" "(succ (succ zero))")
(expect open-nat (nat-elim (lam nat) (Zero) nat-step (reference "n"))
        "Nat" "(nat-elim (lambda Nat) zero (lambda (lambda (succ #0))) n)")
(roundtrip empty-context
           (ann (lam (Inf (nat-elim (lam nat) (Zero) nat-step (local 0)))) (pi nat nat)))
(reject-conversion (infer empty-context (nat-elim (lam nat) nat nat-step (Zero))))
(reject (infer empty-context (nat-elim (lam (Zero)) (Zero) nat-step (Zero))) "expected Nat")
(reject (infer empty-context (nat-elim (lam nat) (Zero) (lam (lam star)) (Zero)))
        "expected Nat; found *")
(reject-conversion (infer empty-context (nat-elim (lam nat) (Zero) nat-step star)))
(write-line "natural elimination, blocked neutrals and branch rejection: ok")

;; ---- Vector elimination and its dependent induction hypothesis ----

(: one Check)
(define one (vcons nat (Zero) (number 1) (vnil nat)))
(: two Check)
(define two (vcons nat (number 1) (number 2) one))
(: vector-copy Infer)
(define vector-copy
  (ann
   (lam (lam (Inf (vec-elim nat (lam (lam (vec nat (local 1)))) (vnil nat)
                            (lam (lam (lam (lam (vcons nat (local 3) (local 2) (local 0))))))
                            (local 1) (local 0)))))
   (pi nat (pi (vec nat (local 0)) (vec nat (local 1))))))

(expect empty-context (apps vector-copy (list (Zero) (vnil nat)))
        "(Vec Nat zero)" "(nil Nat)")
(expect empty-context (apps vector-copy (list (number 2) two))
        "(Vec Nat (succ (succ zero)))"
        "(cons Nat (succ zero) (succ (succ zero)) (cons Nat zero (succ zero) (nil Nat)))")
(roundtrip empty-context vector-copy)
(let ((open (context-of (assume open-nat "xs" (vec nat (reference "n"))))))
  (expect open (apps vector-copy (list (reference "n") (reference "xs")))
          "(Vec Nat n)"
          "(vec-elim Nat (lambda (lambda (Vec Nat #1))) (nil Nat) (lambda (lambda (lambda (lambda (cons Nat #3 #2 #0))))) n xs)"))
(reject-conversion (check empty-context one (vec nat (Zero))))
(reject-conversion (check empty-context (vnil nat) (vec nat (number 1))))
(reject-conversion (infer empty-context
                          (ann (vcons nat (Zero) star (vnil nat)) (vec nat (number 1)))))
(reject-conversion (infer empty-context
                          (ann (vcons nat (number 1) (Zero) (vnil nat)) (vec nat (number 2)))))
(reject-conversion (infer empty-context (apps vector-copy (list (number 2) one))))
(reject-conversion (infer empty-context
                          (vec-elim nat (lam (lam nat)) nat
                                    (lam (lam (lam (lam (local 0))))) (Zero) (vnil nat))))
(reject-conversion (infer empty-context
                          (vec-elim nat (lam (lam (vec nat (local 1)))) (vnil nat)
                                    (lam (lam (lam (lam (local 0))))) (Zero) (vnil nat))))
(reject (infer empty-context
               (vec-elim nat (lam (lam (Zero))) (Zero)
                         (lam (lam (lam (lam (Zero))))) (Zero) (vnil nat)))
        "expected Nat")
(write-line "vectors, dependent induction, readback and index rejection: ok")

;; ---- Invalid syntax is rejected before evaluation ----

(reject (infer empty-context (free "missing")) "unknown name: missing")
(reject (infer empty-context (IBound (Index 0))) "out-of-scope index: 0")
(reject (infer empty-context (IBound (Index -1))) "out-of-scope index: -1")
(reject (infer empty-context (ann (lam (local 1)) (pi nat nat))) "out-of-scope index: 1")
(reject (infer empty-context (app (ann (Zero) nat) (Zero))) "expected a dependent function type")
(reject (check empty-context (lam (local 0)) nat) "expected a dependent function type")
(reject (check empty-context (Zero) star) "expected Nat")
(reject-conversion (infer empty-context (app identity star)))
(reject-conversion (check empty-context star nat))
(reject-conversion (infer empty-context
                          (ann (Zero) (Inf (nat-elim (lam nat) (Zero) nat-step (Zero))))))
(write-line "invalid terms rejected before evaluation: ok")
