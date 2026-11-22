(import
 (snail core base)
 (snail core io))

;; A function value fits a type that allows more effects than it
;; performs: passed, returned, stored and listed. Rows are the only
;; difference subsumption allows, so nothing is converted. The book's
;; chapter on effects includes the text between ANCHOR and ANCHOR_END.
(effect Log
  ((log (Fn String → Unit))))

(record Slot
  ((action (Fn → Unit ! mut Log))))

(define (twice (out OutputPort) (action (Fn → Unit ! mut Log))) (→ Unit) (! mut Log)
  (action)
  (action))

;; ANCHOR: subsumption
;; A parameter passed where a function with more effects is expected.
(define (forward (out OutputPort) (action (Fn → Unit ! mut))) (→ Unit) (! mut Log)
  (twice out action))

;; A function returned at a wider type.
(define (widened (action (Fn → Unit))) (→ (Fn → Unit ! mut Log))
  action)

;; A list widens with its elements, since an enum's fields are never written.
(define (run-all (out OutputPort) (actions (List (Fn → Unit ! mut Log)))) (→ Unit) (! mut Log)
  (for-each (lambda (action) (action)) actions))

(define (run-narrow (out OutputPort) (actions (List (Fn → Unit ! mut)))) (→ Unit) (! mut Log)
  (run-all out actions))

;; A call's result fits as any value does.
(define (printing (line String)) (→ (List (Fn → Unit ! mut)))
  (list (lambda () (write-line out line))))

(define (run-printing (out OutputPort)) (→ Unit) (! mut Log)
  (run-all out (printing "printed")))

;; A narrower function stored in a wider field, by construction and by write.
(define (stored (action (Fn → Unit ! mut))) (→ Slot) (! mut)
  (let ((slot (new Slot (action (lambda () (unit))))))
    (set! (● slot action) action)
    slot))

;; A function that accepts any printing thunk fits where only pure thunks
;; will be passed: parameters narrow.
(define (call-printing (out OutputPort) (thunk (Fn → Unit ! mut))) (→ Unit) (! mut)
  (write-line out "calling")
  (thunk))

(define (with-pure (out OutputPort) (runner (Fn (Fn → Unit) → Unit ! mut))) (→ Unit) (! mut)
  (runner (lambda () (unit))))

;; ANCHOR_END: subsumption

;; An expected row still being inferred names a value's effects and stays
;; open for what the rest of the call performs.
(define (each-then (out OutputPort) (actions (List (Fn → Unit ! mut e))) (after (Fn → Unit ! e)))
  (→ Unit)
  (! mut e)
  (∀ (e))
  (for-each (lambda (action) (action)) actions)
  (after))

;; A row with a tail widens with more labels before the same tail.
(define (widen-tail (action (Fn → A ! e))) (→ (Fn → A ! mut e)) (∀ (A e))
  action)

(define (main (out OutputPort)) (→ Unit) (! mut)
  (handle Log
      ((log (lambda (line) (write-line out (string-append "log: " line)))))
    (forward out (lambda () (write-line out "forwarded")))
    ((widened (lambda () (unit))))
    (run-narrow out (list (lambda () (write-line out "listed"))))
    (run-printing out)
    (let ((actions (printing "open row")))
      (each-then out actions (lambda () (log "after"))))
    (twice out (● (stored (lambda () (write-line out "stored"))) action))
    (log "done"))
  (with-pure out (lambda (thunk) (call-printing out thunk)))
  ((widen-tail (lambda () (write-line out "widened tail"))))
  (unit))
