(import
 (snail core base)
 (snail core io)
 (snail shell number))

(: real (-> String F64))
(define (real text)
  (match (string->number text)
    ((Some (Inexact value)) value)
    (_ (panic "expected a real"))))

;; Each parse replaces only its private result. Failure and NaN differ.
(write-line (show (string->number "12.5")))
(write-line (show (string->number "invalid")))
(write-line (show (string->number "-2.5e1")))
(write-line (show (= (real "+nan.0") (real "+nan.0"))))
(write-line (show (f64->bits (real "-0.0"))))
(write-line (show (f64->bits (real "4.9406564584124654e-324"))))
(write-line (show (f64->bits (real "1.00000000000000011102230246251565404236316680908203125"))))

;; Returned strings own their characters after the next conversion.
(: first String)
(define first (f64->string 1.25))
(write-line (f64->string -0.0))
(write-line (f64->string (real "+inf.0")))
(write-line (f64->string (real "-inf.0")))
(write-line (f64->string (real "+nan.0")))
(write-line first)
(let loop ((n 0))
  (when (< n 1000)
    (f64->string (i64->f64 n))
    (loop (+ n 1))))
(write-line first)
