(import (lofi base))

;; Both concrete factories own their nested creation at this first event.
;; A later demand must not lend its initialized globals to the earlier code.
(def make
     (lambda (ignored) (lambda () later)))
(def early
     ((make #t)))
(def later
     (ann 42 I64))
(def late
     (make (ann 1 I64)))
early
