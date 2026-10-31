(import
 (snail core base))

;; Without a signature, nothing says which record `::x` reads.
(define (first-x record)
  (::x record))
