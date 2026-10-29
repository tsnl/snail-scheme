(import
 (snail core base))

(: use (-> (FnOnce Unit) Unit))
(define (use work)
  (call-once work))

(expose use "use")
