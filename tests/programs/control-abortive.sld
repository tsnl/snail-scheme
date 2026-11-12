(import
 (snail core base)
 (snail core io))

;; An operation that answers Never never returns to its performer: its
;; implementation is handed no `resume`, and `absurd` gives the call any
;; type. Nothing after it runs, so its yields save no frames.
;; ANCHOR: fail
(effect Fail
  ((ctl fail (dyn (Fn String → Never)))))

(define (checked (n I64)) (→ I64) (! Fail)
  (if (< n 0) (absurd (fail (string-append "negative: " (show n)))) n))

(define (total (items (List I64))) (→ I64) (! Fail output-port)
  (fold-left (lambda (sum item)
               (let ((value (checked item)))
                 (write-line (string-append "added " (show value)))
                 (+ sum value)))
             0
             items))

(define (run (items (List I64))) (→ String) (! output-port)
  (handle Fail ((fail (lambda (message) (string-append "failed: " message))))
    (show (total items))))
;; ANCHOR_END: fail

(write-line (run (list 1 2 3)))
(write-line (run (list 1 -2 3)))

;; A failure inside a resumed computation: the generator's rest runs from
;; its frames after each `emit`, and fails there, past the Emit handler.
(effect Emit
  ((ctl emit (dyn (Fn I64 → Unit)))))

(define (emit-all (items (List I64))) (→ Unit) (! Emit Fail)
  (for-each (lambda (item) (emit (checked item))) items))

(define (sum-emitted (items (List I64))) (→ I64) (! Fail output-port)
  (handle Emit ((emit (lambda (value resume)
                        (write-line (string-append "emitted " (show value)))
                        (+ value (resume (unit))))))
    (emit-all items)
    0))

(define (run-emitted (items (List I64))) (→ String) (! output-port)
  (handle Fail ((fail (lambda (message) (string-append "failed: " message))))
    (show (sum-emitted items))))

(write-line (run-emitted (list 4 5 6)))
(write-line (run-emitted (list 4 -5 6)))
