(import
 (snail core base))

(define (magic? (bytes Bytes)) (→ Bool)
  (match bytes
    (#u8(137 80) #t)
    (_ #f)))
