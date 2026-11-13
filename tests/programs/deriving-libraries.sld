;; Two libraries derive Serialize and Deserialize, and neither imports
;; (snail shell wire), which the program imports only after them. The first
;; deriving clause loads the wire, whose items come before that library's
;; own rather than among them, and a route round-trips through the wire.
(import
 (snail core base)
 (snail core io)
 (sample shape)
 (sample route)
 (snail shell wire))

(define (route) (→ Route) (Route (list (Stop "dock" (Square 3)) (Stop "yard" (Rectangle 2 5))) 7))

(define (copy) (→ Route) (ann (deserialize (serialize (route))) Route))

(define (main) (→ Unit) (! output-port)
  (for-each (lambda (stop)
              (display (● stop label))
              (display " ")
              (display (shape-area (● stop shape)))
              (newline))
            (● (copy) stops))
  (display (● (copy) length))
  (newline)
  (unit))
