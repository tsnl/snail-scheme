(import
 (snail core base)
 (snail core io))

;; The examples of "Basic effects" in the book's chapter on effects and
;; handlers, doc/book/snail-core/effects.md, which includes the parts
;; between each ANCHOR and ANCHOR_END.

;; ANCHOR: rows
;; Total: no row, so a call can only compute its result.
(: square (-> I64 I64))
(define (square n)
  (* n n))

;; Writes to the console, and its type says so.
(: report (-> String I64 Unit ! console))
(define (report label n)
  (write-line (string-append label " " (show n))))
;; ANCHOR_END: rows

;; ANCHOR: inferred
;; No signature: the row, console, is inferred from the body.
(define (report-square n)
  (report "squared" (square n)))

(report-square 7)
;; ANCHOR_END: inferred

;; ANCHOR: polymorphic
;; Calls `action` on 1 to `count`, performing whatever `action` performs.
(: repeat (All (e) (-> I64 (-> I64 Unit ! e) Unit ! e)))
(define (repeat count action)
  (let loop ((i 1))
    (when (<= i count)
      (action i)
      (loop (+ i 1)))))

(repeat 3 report-square)
;; ANCHOR_END: polymorphic

;; ANCHOR: local
;; Mutates a cell it allocates, which nothing keeps once it returns.
(: sum-of-squares (-> I64 I64))
(define (sum-of-squares count)
  (let ((total (ref 0)))
    (repeat count (lambda (i) (ref-set! total (+ (ref-get total) (square i)))))
    (ref-get total)))

(report "sum" (sum-of-squares 3))
;; ANCHOR_END: local
