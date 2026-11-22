(import
 (snail core base)
 (snail core io))

;; One generic function used with a callback that may stop it and with one
;; that cannot: each use is its own specialization, and only the first
;; tests for a yield after each call.
(effect Stop
  ((ctl stop (Fn I64 → I64))))

(define (sum-until-negative (items (List I64))) (→ I64)
  (handle Stop ((stop (lambda (total resume) total)))
    (fold-left (lambda (total item) (if (< item 0) (stop total) (+ total item))) 0 items)))

(define (sum (items (List I64))) (→ I64)
  (fold-left (lambda (total item) (+ total item)) 0 items))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (display out (sum-until-negative (list 1 2 3 -4 5)))
  (newline out)
  (display out (sum (list 1 2 3 -4 5)))
  (newline out)
  (for-each (lambda (item) (display out item) (newline out)) (list 7 8))
  (display out (handle Stop ((stop (lambda (item resume) item)))
             (for-each (lambda (item) (when (> item 7) (stop item) (unit))) (list 7 8 9))
             0))
  (newline out)
  (unit))
