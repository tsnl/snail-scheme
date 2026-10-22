(import
 (lofi base))

(: magic? (-> Bytes Bool))
(define (magic? bytes)
  (match bytes
    (#u8(137 80) #t)
    (_ #f)))
