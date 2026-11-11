(import
 (snail core base))

(type Ping Pong)
(type Pong Ping)

(: f (impl (Fn Ping -> I64)))
(define (f x) 0)
