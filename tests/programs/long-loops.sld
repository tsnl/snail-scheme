(import
 (snail core base)
 (snail core io))

;; Loops written with `when` run in constant stack space.
(record Counter
  ((value I64)))

(define (make-text) (→ String) (make-string 200000 #\a))

;; So does the list library, however long the list.
(define (make-numbers) (→ (List I64)) (iota 1000000))

(define (main (out OutputPort)) (→ Unit) (! mut)

  (let ((counter (new Counter (value 0))) (text (make-text)) (numbers (make-numbers)))
    (let loop ((index 0))
      (when (< index 3000000)
        (set! (● counter value) (+ (● counter value) 1))
        (loop (+ index 1))))
    (display out (● counter value))
    (newline out)
    (write-line out (substring text 0 3))
    (display out (string-length (string-append text text)))
    (newline out)
    (display out (length (take (append numbers (map negate numbers)) 1500000)))
    (newline out)
    (unit)))
