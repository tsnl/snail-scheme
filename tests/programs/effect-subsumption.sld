(import
 (snail core base)
 (snail core io))

;; A function value fits a type that allows more than it performs:
;; passed, returned, stored and listed. Rows are the only difference
;; subsumption allows, so nothing is converted. The book's chapter on
;; effects includes the text between ANCHOR and ANCHOR_END.
(record Slot
  ((action (Fn → Unit ! mut))))

(define (twice (action (Fn → Unit ! mut))) (→ Unit) (! mut)
  (action)
  (action))

;; ANCHOR: subsumption
;; A parameter passed where a function that may perform `mut` is expected.
(define (forward (action (Fn → Unit))) (→ Unit) (! mut)
  (twice action))

;; A function returned at a wider type.
(define (widened (action (Fn → Unit))) (→ (Fn → Unit ! mut))
  action)

;; A list widens with its elements, since an enum's fields are never written.
(define (run-all (actions (List (Fn → Unit ! mut)))) (→ Unit) (! mut)
  (for-each (lambda (action) (action)) actions))

(define (run-pure (actions (List (Fn → Unit)))) (→ Unit) (! mut)
  (run-all actions))

;; A call's result fits as any value does.
(define (idle) (→ (List (Fn → Unit)))
  (list (lambda () (unit))))

(define (run-idle) (→ Unit) (! mut)
  (run-all (idle)))

;; A pure function stored in a wider field, by construction and by write.
(define (stored (action (Fn → Unit))) (→ Slot) (! mut)
  (let ((slot (new Slot (action (lambda () (unit))))))
    (set! (● slot action) action)
    slot))

;; A function that accepts any writing thunk fits where only pure thunks
;; will be passed: parameters narrow.
(define (call-writing (out OutputPort) (thunk (Fn → Unit ! mut))) (→ Unit) (! mut)
  (write-line out "calling")
  (thunk))

(define (with-pure (runner (Fn (Fn → Unit) → Unit ! mut))) (→ Unit) (! mut)
  (runner (lambda () (unit))))

;; ANCHOR_END: subsumption

;; An expected row still being inferred names a value's effects and stays
;; open for what the rest of the call performs.
(define (each-then (actions (List (Fn → Unit ! mut e))) (after (Fn → Unit ! e)))
  (→ Unit)
  (! mut e)
  (∀ (e))
  (for-each (lambda (action) (action)) actions)
  (after))

;; A row with a tail widens with more labels before the same tail.
(define (widen-tail (action (Fn → A ! e))) (→ (Fn → A ! mut e)) (∀ (A e))
  action)

(define (main (out OutputPort)) (→ Unit) (! mut)
  (forward (lambda () (unit)))
  ((widened (lambda () (unit))))
  (run-pure (list (lambda () (unit))))
  (run-idle)
  (each-then (list (lambda () (write-line out "open row"))) (lambda () (write-line out "after")))
  (twice (● (stored (lambda () (unit))) action))
  (twice (lambda () (write-line out "twice")))
  (with-pure (lambda (thunk) (call-writing out thunk)))
  ((widen-tail (lambda () (write-line out "widened tail"))))
  (unit))
