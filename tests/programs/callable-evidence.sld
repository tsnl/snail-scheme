(import
 (snail core base)
 (snail core io))

;; A shared-call requirement permits repeated calls without making F Copy.
;; The owner is still consumed explicitly after the two loans end.
(: twice
   (All (F)
        (requires (Fn F I64 -> I64) (Drop (!) F))
        (impl (Fn F I64 -> I64))))
(define (twice function value)
  (let* ((first (function value))
         (second (function first)))
    (drop function)
    second))

(: consume
   (All (F)
        (requires (FnOnce F I64 -> I64))
        (impl (Fn F I64 -> I64))))
(define (consume function value)
  (function value))

(: increment (impl (Fn I64 -> I64)))
(define (increment value)
  (+ value 1))

(write-line (show (twice increment 10)))
(write-line (show (consume increment 20)))
(write-line (show (consume (once increment) 30)))

;; Argument impl introduces a fresh callable type and the same evidence.
(: through-impl (impl (Fn (impl (FnOnce I64 -> I64)) I64 -> I64)))
(define (through-impl function value)
  (function value))

(write-line (show (through-impl (once increment) 40)))

;; Shared callability supplies exclusive callability, without adding Copy.
(: exclusive-twice
   (All (F)
        (requires (FnMut F I64 -> I64) (Drop (!) F))
        (impl (Fn F I64 -> I64))))
(define (exclusive-twice function value)
  (let* ((first (function value))
         (answer (function first)))
    (drop function)
    answer))

(write-line (show (exclusive-twice increment 50)))
(write-line (show (map (ann increment (fn I64 -> I64)) (list 60 70))))
