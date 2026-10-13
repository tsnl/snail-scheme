(import (scheme base) (scheme read) (scheme write) (scheme time))

;; ---- Shared scalar cell with two distinct escaping closures ----

(define (make-state)
  (let ((value 0.25))
    (cons (lambda () (set! value (+ value 0.5))) (lambda () value))))
(define rounds (read))
(define state (make-state))
(define update (car state))
(define observe (cdr state))
(define (run)
  (let loop ((index 0))
    (when (< index rounds) (update) (loop (+ index 1)))))

;; The updating closure returns unspecified. A generic scalar return therefore
;; cannot conceal a removed cell-store box with a new per-update return box.
(define start (current-jiffy))
(run)
(define elapsed (/ (exact (- (current-jiffy) start)) (inexact (jiffies-per-second))))
(define actual (observe))
(unless (= actual (+ 0.25 (* rounds 0.5))) (error "shared cell mismatch" actual))
(display "+!STORAGE!+shared-cell,") (write rounds) (display ",")
(write actual) (display ",") (write elapsed) (newline)
