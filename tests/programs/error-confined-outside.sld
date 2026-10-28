(import
 (snail core base))

;; The counter belongs to the program, not to the call.
(define counter (ref 0))

(: bump (-> I64))
(define (bump)
  (ref-set! counter (+ (ref-get counter) 1))
  (ref-get counter))
