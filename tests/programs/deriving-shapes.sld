(import
 (snail core base)
 (snail core io)
 (snail shell wire))

;; Shapes a derived instance must not trip on: fields named like the
;; variables a deriving macro introduces, a label that a case repeats, a
;; field named `_`, a record and an enum with nothing in them, and a type
;; with a parameter.
(enum Odd
  (Both ((encoder I64) (decoder String)))
  (Twice ((x I64) (x I64)))
  (Named ((value I64) (id I64) (case I64) (field0 I64) (text String) (label String)))
  (Bare)
  (deriving Repr Serialize Deserialize))

(record Under
  ((_ I64)
   (kept I64))
  (deriving Repr Serialize Deserialize))

(record Nothing
  ()
  (deriving Repr Serialize Deserialize))

(enum Nobody
  (deriving Repr Serialize Deserialize))

(record (Wrap T)
  ((value T)
   (name String))
  (deriving Repr Serialize Deserialize))

(define (round (thing T)) (→ T) (∀ (T)) (⊨ (Serialize T) (Deserialize T))
  (deserialize (serialize thing)))

(define (main) (→ Unit) (! output-port)
  (for-each (lambda (odd) (write-line (repr (ann (round odd) Odd))))
            (list (Both 1 "two") (Twice 3 4) (Named 5 6 7 8 "nine" "ten") (Bare)))
  (write-line (repr (ann (round (new Under (_ 1) (kept 2))) Under)))
  (write-line (repr (ann (round (new Nothing)) Nothing)))
  (write-line (repr (ann (round (new Wrap (value (Twice 5 6)) (name "wrapped"))) (Wrap Odd)))))
