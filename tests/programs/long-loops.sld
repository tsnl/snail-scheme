(import
 (snail core base)
 (snail core io))

;; Loops written with `when` run in constant stack space.
(struct Counter
  ((value I64)))

(define (make-text) (→ String) (make-string 200000 #\a))

;; So does the list library, however long the list.
(define (make-numbers) (→ (List I64)) (iota 1000000))

(define (main) (→ Unit) (! mut output-port)

  (let ((counter (Counter 0)) (text (make-text)) (numbers (make-numbers)))
    (let loop ((index 0))
      (when (< index 3000000)
        (set! (● counter value) (+ (● counter value) 1))
        (loop (+ index 1))))
    (display (● counter value))
    (newline)
    (write-line (substring text 0 3))
    (display (string-length (string-append text text)))
    (newline)
    (display (length (take (append numbers (map negate numbers)) 1500000)))
    (newline)
    (unit)))
