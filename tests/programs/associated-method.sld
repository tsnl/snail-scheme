(import
 (snail core base)
 (snail core io))

(struct (Box A)
  ((value A)))

(typeclass (Extract A) (type Output) (declare (extract (value A)) (→ Output)))

(instance (Extract I64) (type Output I64) (define (extract (value I64)) (→ I64)
                                            value))

(instance (Extract Bool)
  (type Output String)
  (define (extract (value Bool)) (→ String)
    (if value "yes" "no")))

(typeclass (Combine A)
  (type Output)
  (declare (combine (left A) (right B))
    (→ (Pair Output (Extract.Output B)))
    (∀ (B))
    (⊨ (Extract B))))

(instance (Combine (Box A))
  (⊨ (Extract A))
  (type Output (Extract.Output A))
  (define (combine (a (Box A)) (b B))
    (→ (Pair (Extract.Output A) (Extract.Output B)))
    (∀ (B))
    (⊨ (Extract B))
    (match a ((Box value) (Pair (extract value) (extract b))))))

(define (main) (→ Unit) (! output-port)
  (match (combine (Box (ann 1 I64)) #t)
    ((Pair a b) (display a) (newline) (write-line b)))
  (unit))
