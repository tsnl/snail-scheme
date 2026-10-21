;; The default kernel of the REPL and the notebook: Scheme with some of
;; Lofi's typed libraries bound as procedures. A generator from
;; (lofi random) crosses into Scheme as an opaque value.
(import
 (lofi base)
 (lofi math)
 (lofi number)
 (lofi random)
 (lofi text)
 (lofi kernel))

(define-opaque Random "random")

(define-kernel
  ("pi" pi)
  ("sqrt" (ann sqrt (-> F64 F64)))
  ("sin" sin)
  ("cos" cos)
  ("atan" atan2)
  ("exp" exp)
  ("log" log)
  ("expt" expt)
  ("exact->inexact" number-inexact)
  ("string->number" string->number)
  ("string-upcase" string-upcase)
  ("string-downcase" string-downcase)
  ("iota" iota)
  ("list-tail" (ann list-tail (-> (List Datum) I64 (List Datum))))
  ("list->vector" (ann list->vector (-> (List Datum) (Vector Datum))))
  ("vector->list" (ann vector->list (-> (Vector Datum) (List Datum))))
  ("make-random" make-random)
  ("random-next" random-next)
  ("random-value" random-value)
  ("random-below" random-below))
