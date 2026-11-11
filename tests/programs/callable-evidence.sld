(import
 (snail core base)
 (snail core io))

;; A shared-call requirement permits repeated calls without making F Copy.
;; The owner is still consumed explicitly after the two loans end.
(define (twice (function F) (value I64)) (→ I64) (∀ F) (⊨ (Fn F I64 → I64) (Drop (!) F))
  (let* ((first (function value))
         (second (function first)))
    (drop function)
    second))

(define (consume (function F) (value I64)) (→ I64) (∀ F) (⊨ (FnOnce F I64 → I64))
  (function value))

(define (increment (value I64)) (→ I64)
  (+ value 1))

(write-line (show (twice increment 10)))
(write-line (show (consume increment 20)))
(write-line (show (consume (once increment) 30)))

;; Argument impl introduces a fresh callable type and the same evidence.
(define (through-impl (function (impl (FnOnce I64 → I64))) (value I64)) (→ I64)
  (function value))

(write-line (show (through-impl (once increment) 40)))

;; Shared callability supplies exclusive callability, without adding Copy.
(define (exclusive-twice (function F) (value I64))
  (→ I64)
  (∀ F)
  (⊨ (FnMut F I64 → I64) (Drop (!) F))
  (let* ((first (function value))
         (answer (function first)))
    (drop function)
    answer))

(write-line (show (exclusive-twice increment 50)))
(write-line (show (map (ann increment (fn I64 → I64)) (list 60 70))))
