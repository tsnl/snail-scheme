(import
 (snail-core base)
 (snail-core io))

;; One generic function used with a callback that may stop it and with one
;; that cannot: each use is its own specialization, and only the first
;; tests for a yield after each call.
(effect Stop
  ((ctl stop (-> I64 I64))))

(: sum-until-negative (-> (List I64) I64))
(define (sum-until-negative items)
  (handle Stop ((stop (lambda (total resume) total)))
    (fold-left (lambda (total item) (if (< item 0) (stop total) (+ total item)))
               0
               items)))

(: sum (-> (List I64) I64))
(define (sum items)
  (fold-left (lambda (total item) (+ total item)) 0 items))

(display (sum-until-negative (list 1 2 3 -4 5)))
(newline)
(display (sum (list 1 2 3 -4 5)))
(newline)
(for-each (lambda (item) (display item) (newline)) (list 7 8))
(display (handle Stop ((stop (lambda (item resume) item)))
           (for-each (lambda (item) (when (> item 7) (stop item) (unit)))
                     (list 7 8 9))
           0))
(newline)
