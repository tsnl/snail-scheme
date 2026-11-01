(import
 (snail core base))
(effect exn ((ctl raise (-> String Never))))
(: integer (-> Any I64 ! exn))
(define (integer value) value)
