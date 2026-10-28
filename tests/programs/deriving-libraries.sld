;; Two libraries derive Serialize and Deserialize, and neither imports
;; (snail-core wire), which the program imports only after them. The first
;; deriving clause loads the wire, whose items come before that library's
;; own rather than among them, and a route round-trips through the wire.
(import
 (snail-core base)
 (snail-core io)
 (sample shape)
 (sample route)
 (snail-core wire))

(define route (Route (list (Stop "dock" (Square 3)) (Stop "yard" (Rectangle 2 5))) 7))
(define copy (ann (deserialize (serialize route)) Route))
(for-each (lambda (stop)
            (display (Stop-label stop))
            (display " ")
            (display (shape-area (Stop-shape stop)))
            (newline))
          (Route-stops copy))
(display (Route-length copy))
(newline)
