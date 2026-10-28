(import
 (snail core base))

(type Ping Pong)
(type Pong Ping)

(: f (-> Ping I64))
(define (f x) 0)
