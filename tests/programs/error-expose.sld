(import
 (snail core base))

(: use (-> (Once (-> Unit)) Unit))
(define (use work)
  (call-once work))

(expose use "use")
