(import
 (snail core base)
 (snail core io))

;; The examples of "Writing" in the book's chapter on capabilities,
;; doc/book/snail-scheme/effects.md, which includes the parts between
;; each ANCHOR and ANCHOR_END.

;; ANCHOR: compute
;; Handed nothing to write with and nothing that reaches the host, so a
;; call can only compute its result.
(define (square (n I64)) (→ I64)
  (* n n))

;; Handed a port, so it may write to that port.
(define (report (out OutputPort) (label String) (n I64)) (→ Unit)
  (write-line out (string-append label " " (show n))))
;; ANCHOR_END: compute

;; ANCHOR: mut
(record Counter
  ((value I64)))

;; Handed a `Mut`, so it may write: here, the counter it is also handed.
(define (bump! (mut Mut) (counter Counter) (by I64)) (→ Unit)
  (set! mut (● counter value) (+ (● counter value) by)))

;; Reads a field, which needs nothing.
(define (count-of (counter Counter)) (→ I64)
  (● counter value))
;; ANCHOR_END: mut

;; ANCHOR: closure
;; Calls `action` on 1 to `count`. It holds no `Mut` itself: what a call
;; of `action` does is whatever `action` was made with.
(define (repeat (count I64) (action (Fn I64 → Unit))) (→ Unit)
  (let loop ((i 1))
    (when (<= i count)
      (action i)
      (loop (+ i 1)))))

(define (sum-of-squares (mut Mut) (count I64)) (→ I64)
  (let ((total (new Counter (value 0))))
    (repeat count (lambda (i) (bump! mut total (square i))))
    (count-of total)))
;; ANCHOR_END: closure

;; ANCHOR: owner
;; A tally keeps the `Mut` it was made with, so adding to it takes none:
;; the tally is the one thing its holder can change.
(record Tally
  ((mut Mut)
   (total I64)))

(define (make-tally (mut Mut)) (→ Tally)
  (new Tally (mut mut) (total 0)))

(define (tally! (tally Tally) (n I64)) (→ Unit)
  (set! (● tally mut) (● tally total) (+ (● tally total) n)))
;; ANCHOR_END: owner

;; ANCHOR: local
;; The array is this call's own and nothing else can reach it, so the
;; function makes the `Mut` it fills it with, and its callers need none.
(define (squares (count I64)) (→ (Array I64))
  (let ((mut (unsafe-mut)) (out (make-array count 0)))
    (repeat count (lambda (i) (array-set! mut out (- i 1) (square i))))
    out))
;; ANCHOR_END: local

(define (main (mut Mut) (out OutputPort)) (→ Unit)
  (report out "squared" (square 7))
  (let ((counter (new Counter (value 0))))
    (bump! mut counter 2)
    (bump! mut counter 3)
    (report out "counted" (count-of counter)))
  (report out "sum" (sum-of-squares mut 3))
  (let ((tally (make-tally mut)))
    (repeat 4 (lambda (n) (tally! tally n)))
    (report out "tallied" (● tally total)))
  (report out "last" (array-ref (squares 5) 4))
  (unit))
