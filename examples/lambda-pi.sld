;; Read these examples in order with the LambdaPi walkthrough in the book.
(import
 (snail core base)
 (snail core io)
 (snail experiment lambda-pi language)
 (snail experiment lambda-pi normal)
 (snail experiment lambda-pi driver))

(: context-of (-> (Result Context Error) Context))
(define (context-of result)
  (match result ((Ok context) context) ((Err problem) (panic (error->string problem)))))

(: example (-> String Context Infer Unit ! console))
(define (example title context term)
  (match (infer context term)
    ((Err problem) (panic (string-append title ": " (error->string problem))))
    ((Ok checked)
     (write-line title)
     (write-line (string-append "  type: " (normal->string (type-normal checked))))
     (write-line (string-append "  normal: " (normal->string (term-normal checked)))))))

;; ANCHOR: variable
(: abstract Context)
(define abstract
  (context-of
   (with-results ((context (assume empty-context "A" star))
                  (context (assume context "x" (reference "A"))))
                 (assume context "f" (pi (reference "A") (reference "A"))))))

(example "1. A variable" abstract (free "x"))
;; ANCHOR_END: variable

;; ANCHOR: call
(example "2. A call with an unknown function" abstract
         (app (free "f") (reference "x")))
;; ANCHOR_END: call

;; ANCHOR: identity
(: identity Infer)
(define identity (typed (lam (local 0)) (pi (reference "A") (reference "A"))))

(example "3. An annotated identity" abstract identity)
(example "4. Beta reduction" abstract (app identity (reference "x")))
;; ANCHOR_END: identity

;; ANCHOR: polymorphic
;; Pi A:*. Pi x:A. A. The second Pi adds a binder, so its result is #1.
(: polymorphic-identity Infer)
(define polymorphic-identity (typed (lam (lam (local 0))) (pi star (pi (local 0) (local 1)))))

(example "5. A dependent identity" empty-context polymorphic-identity)
(example "6. Instantiate the dependent identity" empty-context
         (apps polymorphic-identity (list nat (number 2))))
;; ANCHOR_END: polymorphic

;; ANCHOR: conversion
(: type-identity Infer)
(define type-identity (typed (lam (local 0)) (pi star star)))

(example "7. A type that computes" empty-context
         (typed (Zero) (Inf (app type-identity nat))))

(example "8. Normalization beneath a binder" empty-context
         (typed (lam (Inf (app (typed (lam (local 0)) (pi nat nat)) (local 0))))
                (pi nat nat)))
;; ANCHOR_END: conversion

;; ANCHOR: naturals
;; add m n = nat-elim (lambda k. Nat) m (lambda k ih. succ ih) n.
(: addition Infer)
(define addition
  (typed (lam (lam (Inf (nat-elim (lam nat) (local 1)
                                  (lam (lam (successor (local 0)))) (local 0)))))
         (pi nat (pi nat nat))))

(example "9. Natural-number elimination: 2 + 3" empty-context
         (apps addition (list (number 2) (number 3))))
;; ANCHOR_END: naturals

;; ANCHOR: vector
(: singleton Check)
(define singleton (vcons nat (Zero) (number 2) (vnil nat)))

(example "10. A length-indexed vector" empty-context
         (typed singleton (vec nat (number 1))))

;; A dependent identity on vectors: Pi n:Nat. Pi xs:(Vec Nat n). Vec Nat n.
(: vector-identity Infer)
(define vector-identity
  (typed (lam (lam (local 0))) (pi nat (pi (vec nat (local 0)) (vec nat (local 1))))))

(example "11. An index supplied by an earlier argument" empty-context
         (apps vector-identity (list (number 1) singleton)))
;; ANCHOR_END: vector

;; ANCHOR: vector-elimination
;; Rebuild every constructor. This motive depends on the vector's length.
(: vector-copy Infer)
(define vector-copy
  (typed
   (lam (lam (Inf (vec-elim nat (lam (lam (vec nat (local 1)))) (vnil nat)
                            (lam (lam (lam (lam (vcons nat (local 3) (local 2) (local 0))))))
                            (local 1) (local 0)))))
   (pi nat (pi (vec nat (local 0)) (vec nat (local 1))))))

(example "12. Dependent vector elimination" empty-context
         (apps vector-copy (list (number 1) singleton)))
;; ANCHOR_END: vector-elimination

;; ANCHOR: inhabitant-motive
;; tag-type zero = Nat; tag-type (succ n) = Nat -> Nat.
(: tag-type Infer)
(define tag-type
  (typed (lam (Inf (nat-elim (lam star) nat (lam (lam (pi nat nat))) (local 0))))
         (pi nat star)))

;; tag-value n : tag-type n. Its result is zero or the identity function.
(: tag-value Infer)
(define tag-value
  (typed (lam (Inf (nat-elim (lam (Inf (app (free "tag-type") (local 0))))
                             (Zero) (lam (lam (lam (local 0)))) (local 0))))
         (pi nat (Inf (app (free "tag-type") (local 0))))))

;; vector-type nil = Nat; vector-type (cons h t) = tag-type h.
(: vector-type Infer)
(define vector-type
  (typed
   (lam (lam (Inf (vec-elim nat (lam (lam star)) nat
                            (lam (lam (lam (lam (Inf (app (free "tag-type") (local 2)))))))
                            (local 1) (local 0)))))
   (pi nat (pi (vec nat (local 0)) star))))

(: vector-value Infer)
(define vector-value
  (typed
   (lam (lam (Inf (vec-elim nat (reference "vector-type") (Zero)
                            (lam (lam (lam (lam (Inf (app (free "tag-value") (local 2)))))))
                            (local 1) (local 0)))))
   (pi nat (pi (vec nat (local 0))
               (Inf (apps (free "vector-type") (list (local 1) (local 0))))))))

(: dependent Context)
(define dependent
  (context-of
   (with-results ((context (define-global empty-context "tag-type" tag-type))
                  (context (define-global context "tag-value" tag-value))
                  (context (define-global context "vector-type" vector-type)))
                 (define-global context "vector-value" vector-value))))

(example "13. Same length, zero head: result type Nat" dependent
         (apps (free "vector-value") (list (number 1) (vcons nat (Zero) (Zero) (vnil nat)))))
(example "14. Same length, successor head: result type Nat -> Nat" dependent
         (apps (free "vector-value") (list (number 1) (vcons nat (Zero) (number 1) (vnil nat)))))

;; With an unknown head, both the result and its type retain a blocked
;; elimination. No decision can be made from the length alone.
(example "15. Same length, unknown head: computation stays open"
         (context-of (assume dependent "h" nat))
         (apps (free "vector-value")
               (list (number 1) (vcons nat (Zero) (reference "h") (vnil nat)))))
;; ANCHOR_END: inhabitant-motive
