(import
 (snail core base)
 (snail core io))

;; The examples of "Basic effects" in the book's chapter on effects and
;; handlers, doc/book/snail-core/effects.md, which includes the parts
;; between each ANCHOR and ANCHOR_END.

;; ANCHOR: rows
;; Total: no row, so a call can only compute its result.
(record Total
  ((value I64)))

(define (square (n I64)) (→ I64)
  (* n n))

;; Writes to the output-port, and its type says so.
(define (report (label String) (n I64)) (→ Unit) (! output-port)
  (write-line (string-append label " " (show n))))

;; ANCHOR_END: rows

;; ANCHOR: inferred
;; No signature: the row, output-port, is inferred from the body.
(define (report-square (n I64)) (→ Unit) (! output-port)
  (report "squared" (square n)))

;; ANCHOR_END: inferred

;; ANCHOR: polymorphic
;; Calls `action` on 1 to `count`, performing whatever `action` performs.
(define (repeat (count I64) (action (Fn I64 → Unit ! e))) (→ Unit) (! e) (∀ (e))
  (let loop ((i 1))
    (when (<= i count)
      (action i)
      (loop (+ i 1)))))

;; ANCHOR_END: polymorphic

;; ANCHOR: local
;; Mutation is explicit even when the scratch never leaves this function.
(define (sum-of-squares (count I64)) (→ I64) (! mut)
  (let ((total (new Total (value 0))))
    (repeat count (lambda (i) (set! (● total value) (+ (● total value) (square i)))))
    (● total value)))

(define (main) (→ Unit) (! mut output-port)

  (report-square 7)
  (repeat 3 report-square)
  (report "sum" (sum-of-squares 3))
  (unit))
