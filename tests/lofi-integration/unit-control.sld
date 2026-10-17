(import (lofi base))

(def state
     (ref (ann 0 I64)))
(ann (unit) Unit)
(ann (ann (unit) Any) Unit)
(if #t
    (begin (ref-set! state (ann 40 I64))
           (unit))
    (unit))
(if #f
    (begin (unreachable)
           (unit))
    (unit))
(if #f
    (unit)
    (begin (ref-set! state (+ (ref-get state) (ann 2 I64)))
           (unit)))
(if #t
    (unit)
    (begin (unreachable)
           (unit)))
(if #t
    (begin
      (unit))
    (unit))
(if #f
    (begin
      (unit))
    (unit))
(if #t
    (unit)
    (begin
      (unit)))
(if #f
    (unit)
    (begin
      (unit)))
(ref-get state)
