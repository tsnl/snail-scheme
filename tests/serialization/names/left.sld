(define-library (names left)
  (export Stock stock stock-ore)
  (import
   (lofi serialization))
  (begin
    (data Stock ()
      (stock
       (ore I32 stock-ore))
      (deriving derive-serialize derive-deserialize))))
