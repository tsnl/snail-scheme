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
  ((action (Fn → Unit ! Output-port Log))))

(define (twice (action (Fn → Unit ! Output-port Log))) (→ Unit) (! Output-port Log)
  (action)
  (action))

;; ANCHOR: subsumption
;; A parameter passed where a function with more effects is expected.
(define (forward (action (Fn → Unit ! Output-port))) (→ Unit) (! Output-port Log)
  (twice action))

;; A function returned at a wider type.
(define (widened (action (Fn → Unit))) (→ (Fn → Unit ! Output-port Log))
  action)

;; A list widens with its elements, since an enum's fields are never written.
(define (run-all (actions (List (Fn → Unit ! Output-port Log)))) (→ Unit) (! Output-port Log)
  (for-each (lambda (action) (action)) actions))

(define (run-narrow (actions (List (Fn → Unit ! Output-port)))) (→ Unit) (! Output-port Log)
  (run-all actions))

;; A call's result fits as any value does.
(define (printing (line String)) (→ (List (Fn → Unit ! Output-port)))
  (list (lambda () (write-line line))))

(define (run-printing) (→ Unit) (! Output-port Log)
  (run-all (printing "printed")))

;; A narrower function stored in a wider field, by construction and by write.
(define (stored (action (Fn → Unit ! Output-port))) (→ Slot) (! Mut)
  (let ((slot (new Slot (action (lambda () (unit))))))
    (set! (● slot action) action)
    slot))

;; A function that accepts any printing thunk fits where only pure thunks
;; will be passed: parameters narrow.
(define (call-printing (thunk (Fn → Unit ! Output-port))) (→ Unit) (! Output-port)
  (write-line "calling")
  (thunk))

(define (with-pure (runner (Fn (Fn → Unit) → Unit ! Output-port))) (→ Unit) (! Output-port)
  (runner (lambda () (unit))))

;; ANCHOR_END: subsumption

;; An expected row still being inferred names a value's effects and stays
;; open for what the rest of the call performs.
(define (each-then (actions (List (Fn → Unit ! Output-port e))) (after (Fn → Unit ! e)))
  (→ Unit)
  (! Output-port e)
  (∀ (e))
  (for-each (lambda (action) (action)) actions)
  (after))

;; A row with a tail widens with more labels before the same tail.
(define (widen-tail (action (Fn → A ! e))) (→ (Fn → A ! Output-port e)) (∀ (A e))
  action)

(define (main) (→ Unit) (! Mut Output-port)
  (handle Log
      ((log (lambda (line) (write-line (string-append "log: " line)))))
    (forward (lambda () (write-line "forwarded")))
    ((widened (lambda () (unit))))
    (run-narrow (list (lambda () (write-line "listed"))))
    (run-printing)
    (let ((actions (printing "open row")))
      (each-then actions (lambda () (log "after"))))
    (twice (● (stored (lambda () (write-line "stored"))) action))
    (log "done"))
  (with-pure call-printing)
  ((widen-tail (lambda () (write-line "widened tail"))))
  (unit))
