(import
 (snail core base)
 (snail core io))

;; `capability` declares a record of functions and, for each, a function
;; of the record: operations of no, one and several arguments.
(capability Counter
  ((current (Fn → I64))
   (advance (Fn I64 → Unit))
   (describe (Fn String I64 Bool → String))))

(record Cell
  ((value I64)))

;; A capability is a record, so a program makes one with `new`.
(define (counter-over (cell Cell)) (→ Counter)
  (new Counter
    (current (lambda () (● cell value)))
    (advance (lambda (by) (set! (● cell value) (+ (● cell value) by))))
    (describe (lambda (name scale loud?)
                (string-append name (if loud? "! " ": ") (show (* scale (● cell value))))))))

(define (main (out OutputPort)) (→ Unit)
  (let ((counter (counter-over (new Cell (value 1)))))
    (advance counter 4)
    (write-line out (show (current counter)))
    (write-line out (describe counter "count" 10 #t))
    ;; An operation is an ordinary function, and a field still reads as one.
    (write-line out (repr (map (lambda (step) (begin (advance counter step) (current counter)))
                               (list 1 2))))
    (write-line out (show ((● counter current))))))
