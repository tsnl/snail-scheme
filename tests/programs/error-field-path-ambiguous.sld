(import
 (snail core base))

;; Without a signature, nothing says which record `(● record x)` reads.
(define first-x
  (lambda (record) (● record x)))
