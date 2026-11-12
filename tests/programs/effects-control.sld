(import
 (snail core base)
 (snail core io))

;; The examples of "Control handlers" in the book's chapter on effects and
;; handlers, doc/book/snail-core/effects.md, which includes the parts
;; between each ANCHOR and ANCHOR_END.

;; ANCHOR: collect
(effect Gen
  ((ctl yield (dyn (Fn I64 → Unit)))))

;; Yields the numbers from `low` to `high`.
(define (range (low I64) (high I64)) (→ Unit) (! Gen)
  (when (<= low high)
    (yield low)
    (range (+ low 1) high)))

;; Every value `body` yields, in order.
(define (collect (body (dyn (Fn → Unit ! Gen)))) (→ (List I64))
  (handle Gen
      ((yield (lambda (value resume) (Cons value (resume (unit))))))
    (body)
    (Nil)))
;; ANCHOR_END: collect

(define (show-all (values (List I64))) (→ Unit) (! output-port)
  (write-line (string-join (map show values) " ")))

;; ANCHOR: run-collect
(show-all (collect (lambda () (range 1 5))))
;; ANCHOR_END: run-collect

;; ANCHOR: first-above
;; The first value above `limit` that `body` yields, or -1.
(define (first-above (limit I64) (body (dyn (Fn → Unit ! Gen)))) (→ I64)
  (handle Gen
      ((yield (lambda (value resume)
                (if (> value limit)
                    (begin
                      (drop resume)
                      value)
                    (resume (unit))))))
    (body)
    -1))

(write-line (repr (first-above 3 (lambda () (range 1 5)))))
(write-line (repr (first-above 9 (lambda () (range 1 5)))))
;; ANCHOR_END: first-above

;; ANCHOR: step
;; A generator stopped at a value, holding the rest of its body.
(enum Step
  (Done)
  (Yielded
   ((value I64)
    (next (dyn (FnOnce Unit → Step))))))

;; Runs `body` to its first yield, and hands back the rest rather than
;; resuming it.
(define (start (body (dyn (Fn → Unit ! Gen)))) (→ Step)
  (handle Gen
      ((yield (lambda (value resume) (Yielded value resume))))
    (body)
    (Done)))

;; Takes turns between two generators until both are done.
(define (interleave (this Step) (other Step)) (→ (List I64))
  (match this
    ((Done)
     (match other
       ((Done) (Nil))
       (rest (interleave rest (Done)))))
    ((Yielded value next)
     (Cons value (interleave other (next (unit)))))))

(show-all (interleave (start (lambda () (range 1 3))) (start (lambda () (range 10 14)))))
;; ANCHOR_END: step
