(import (scheme base) (scheme write) (snail typing))

;; ---- User-defined static overloads ----

(define (check expected actual)
  (unless (equal? expected actual) (error "typeclass mismatch" expected actual)))

(define-class (Combine T)
  (: combine (-> T T T)))

(define-instance (Combine i32)
  (combine (lambda (x y) (+ x y))))
(define-instance (Combine String)
  (combine (lambda (x y) (string-append x y))))

(: twice (All (T) (=> ((Combine T)) (-> T T))))
(define (twice x) (combine x x))
(define twice-alias twice)
(define combine-alias combine)

(check 42 (twice 21))
(check "hellohello" (twice "hello"))
(check 10 (twice-alias 5))
(check "ab" (combine-alias "a" "b"))

;; Each explicit view is an ordinary first-class procedure after selection.
(: concat (-> String String String))
(define concat combine)
(define string-twice (inst twice String))
(check "ab" (apply concat '("a" "b")))
(check "xx" (string-twice "x"))
(check #t (eq? string-twice (inst twice String)))
(check #f (eq? string-twice (inst twice i32)))

(: repeated (All (A) (=> ((Combine A)) (-> A i32 A))))
(define (repeated x n)
  (if (= n 0) x (let ((next (- n 1))) (repeated (combine x x) next))))
(check 32 (repeated 1 5))
(check "zzzz" (repeated "z" 2))

;; Fresh local identities keep captures and predicate refinements independent
;; across concrete specializations of the same source definition.
(: delayed (All (T) (=> ((Combine T)) (-> T Procedure))))
(define (delayed x) (lambda () (combine x x)))
(define integer-step (delayed 21))
(define string-step (delayed "x"))
(check 42 (integer-step))
(check "xx" (string-step))
(: refined (All (T) (=> ((Combine T)) (-> T T))))
(define (refined x) (if (string? x) (combine x x) x))
(check 21 (refined 21))
(check "yy" (refined "y"))

;; Class names may be shadowed by ordinary mutable lexical bindings.
(: shadowed (All (T) (=> ((Combine T)) (-> T T))))
(define (shadowed x)
  (let ((Combine 0)) (set! Combine 1))
  (combine x x))
(check "ss" (shadowed "s"))

(: even (All (A) (=> ((Combine A)) (-> A i32 A))))
(: odd (All (B) (=> ((Combine B)) (-> B i32 B))))
(define (even x n) (if (= n 0) x (odd (combine x x) (- n 1))))
(define (odd x n) (if (= n 0) x (even x (- n 1))))
(check 8 (even 1 6))
(check "zz" (even "z" 2))

;; ---- Multiparameter classes and result-directed selection ----

(define-class (Convert From To)
  (: convert (-> From To)))
(define-instance (Convert i32 String)
  (convert (lambda (x) (number->string x))))
(: converted String)
(define converted (convert 42))
(check "42" converted)
(check "7" ((inst convert i32 String) 7))

;; An input refinement does not promise that its class method preserves it.
;; Refine the returned value, or explicitly select the concrete String instance.
(define-class (Keep T) (: keep (-> T T)))
(define-instance (Keep Any) (keep (lambda (x) 42)))
(define-instance (Keep String)
  (keep (lambda (x) (let ((combine-alias 0)) (set! combine-alias 1)) x)))
(: measured (All (T) (=> ((Keep T)) (-> T ExactInteger))))
(define (measured x)
  (let ((value (keep x))) (if (string? value) (string-length value) 0)))
(check 1 (measured "s"))
(check 0 ((inst measured Any) "s"))
(: selected-measure (All (T) (=> ((Keep T)) (-> T ExactInteger))))
(define (selected-measure x)
  (if (string? x) (string-length ((inst keep String) x)) 0))
(check 1 ((inst selected-measure Any) "s"))

;; Recursive calls retain class parameters absent from the ordinary arrow.
(define-class (Tag T) (: tagged (-> T T)))
(define-instance (Tag i32) (tagged (lambda (x) x)))
(: count-down (All (T) (=> ((Tag T)) (-> i32 i32))))
(define (count-down n) (if (= n 0) 0 (count-down (- n 1))))
(check 0 ((inst count-down i32) 3))

(define-class (Zero T) (: zero (-> T)))
(define-instance (Zero String) (zero (lambda () "")))
(: empty String)
(define empty (zero))
(check "" empty)

;; An explicit static view may admit a checked dynamic argument.
(: dynamic-twice (-> ? String))
(define (dynamic-twice x) ((inst twice String) x))
(check "okok" (dynamic-twice "ok"))

;; Plain polymorphic views preserve compound payload effects and check their
;; class operations under the surrounding generic's declared obligations.
(: identity (All (A) (-> A A)))
(define (identity x) x)
(: view-effect (All (T) (=> ((Combine T)) (-> T T))))
(define (view-effect x) ((inst (begin (display (combine x x)) identity) i32) 1) x)
(let ((output (open-output-string)))
  (parameterize ((current-output-port output)) (check "v" (view-effect "v")))
  (check "vv" (get-output-string output)))

(display "typeclass checks passed\n")
