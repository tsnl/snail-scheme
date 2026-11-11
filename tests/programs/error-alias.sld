(import
 (snail core base))

(type Ping Pong)
(type Pong Ping)

(define (f (x Ping)) (→ I64) 0)
