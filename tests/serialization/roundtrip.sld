(define-library (tests serialization roundtrip)
  (export answer)
  (import
   (scheme base)
   (lofi serialization)
   (only (lofi core) data deriving ann I32))
  (begin
    (data Stock ()
      (stock
       (ore I32 stock-ore))
      (deriving derive-serialize derive-deserialize))
    (define (answer)
      (stock-ore (ann (deserialize (serialize (stock 42))) Stock)))
    (answer)))
