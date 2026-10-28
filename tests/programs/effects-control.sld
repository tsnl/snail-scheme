(import
 (snail-core base)
 (snail-core io))

;; The examples of "Control handlers" in the book's chapter on effects and
;; handlers, doc/book/snail-core/effects.md, which includes the parts
;; between each ANCHOR and ANCHOR_END.

;; ANCHOR: collect
(effect Gen
  ((ctl yield (-> I64 Unit))))

;; Yields the numbers from `low` to `high`.
(: range (-> I64 I64 Unit ! Gen))
(define (range low high)
  (when (<= low high)
    (yield low)
    (range (+ low 1) high)))

;; Every value `body` yields, in order.
(: collect (-> (-> Unit ! Gen) (List I64)))
(define (collect body)
  (handle Gen
      ((yield (lambda (value resume) (Cons value (resume (unit))))))
    (body)
    (Nil)))
;; ANCHOR_END: collect

(: show-all (-> (List I64) Unit ! console))
(define (show-all values)
  (write-line (string-join (map show values) " ")))

;; ANCHOR: run-collect
(show-all (collect (lambda () (range 1 5))))
;; ANCHOR_END: run-collect

;; ANCHOR: first-above
;; The first value above `limit` that `body` yields, or -1.
(: first-above (-> I64 (-> Unit ! Gen) I64))
(define (first-above limit body)
  (handle Gen
      ((yield (lambda (value resume) (if (> value limit) value (resume (unit))))))
    (body)
    -1))

(write-line (show (first-above 3 (lambda () (range 1 5)))))
(write-line (show (first-above 9 (lambda () (range 1 5)))))
;; ANCHOR_END: first-above

;; ANCHOR: step
;; A generator stopped at a value, holding the rest of its body.
(enum Step
  (Done)
  (Yielded
   ((value I64)
    (next (Once (-> Unit Step))))))

;; Runs `body` to its first yield, and hands back the rest rather than
;; resuming it.
(: start (-> (-> Unit ! Gen) Step))
(define (start body)
  (handle Gen
      ((yield (lambda (value resume) (Yielded value resume))))
    (body)
    (Done)))

;; Takes turns between two generators until both are done.
(: interleave (-> Step Step (List I64)))
(define (interleave this other)
  (match this
    ((Done)
     (match other
       ((Done) (Nil))
       (rest (interleave rest (Done)))))
    ((Yielded value next)
     (Cons value (interleave other (next (unit)))))))

(show-all (interleave (start (lambda () (range 1 3))) (start (lambda () (range 10 14)))))
;; ANCHOR_END: step
