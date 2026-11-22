(import
 (snail core base)
 (snail core io))

;; The examples of the book's chapter on suspension,
;; doc/book/snail-scheme/suspension.md, which includes the parts between
;; each ANCHOR and ANCHOR_END.

;; ANCHOR: exception
;; A prompt whose answer is Never: a suspension to it never comes back.
(define failing (→ (Prompt String Never)) (make-prompt))

(define (fail (why String)) (→ A) (∀ (A))
  (absurd (suspend failing why)))

(define (digit (c Char)) (→ I64)
  (if (char-numeric? c)
      (- (char->integer c) (char->integer #\0))
      (fail (string-append "not a digit: " (make-string 1 c)))))

(define (number (text String)) (→ I64)
  (fold-left (lambda (value c) (+ (* value 10) (digit c))) 0 (string->list text)))

;; `text` as a number, or `default`, after saying why not.
(define (parse-or (out OutputPort) (default I64) (text String)) (→ I64) (! mut)
  (with-prompt failing
               (lambda () (number text))
               (lambda (why resume)
                 (write-line out why)
                 default)))

;; ANCHOR_END: exception

;; ANCHOR: collect
(define yielding (→ (Prompt I64 Unit)) (make-prompt))

(define (yield (value I64)) (→ Unit)
  (suspend yielding value))

;; Yields the numbers from `low` to `high`.
(define (range (low I64) (high I64)) (→ Unit)
  (when (<= low high)
    (yield low)
    (range (+ low 1) high)))

;; Every value `body` yields, in order.
(define (collect (body (Fn → Unit))) (→ (List I64))
  (with-prompt yielding
               (lambda ()
                 (body)
                 (Nil))
               (lambda (value resume) (Cons value (resume (unit))))))

;; ANCHOR_END: collect

(define (show-all (out OutputPort) (values (List I64))) (→ Unit) (! mut)
  (write-line out (string-join (map show values) " ")))

;; ANCHOR: first-above
;; The first value above `limit` that `body` yields, or -1.
(define (first-above (limit I64) (body (Fn → Unit))) (→ I64)
  (with-prompt yielding
               (lambda ()
                 (body)
                 -1)
               (lambda (value resume) (if (> value limit) value (resume (unit))))))

;; ANCHOR_END: first-above

;; ANCHOR: step
;; A generator stopped at a value, holding the rest of its body.
(enum Step
  (Done)
  (Yielded
   ((value I64)
    (next (Fn Unit → Step)))))

;; Runs `body` to its first yield, and hands back the rest rather than
;; resuming it.
(define (start (body (Fn → Unit))) (→ Step)
  (with-prompt yielding
               (lambda ()
                 (body)
                 (Done))
               (lambda (value resume) (Yielded value resume))))

;; Takes turns between two generators until both are done.
(define (interleave (this Step) (other Step)) (→ (List I64))
  (match this
    ((Done)
     (match other
       ((Done) (Nil))
       (rest (interleave rest (Done)))))
    ((Yielded value next) (Cons value (interleave other (next (unit)))))))

;; ANCHOR_END: step

(define (main (out OutputPort)) (→ Unit) (! mut)
  ;; ANCHOR: run-exception
  (write-line out (show (parse-or out 0 "123")))
  (write-line out (show (parse-or out 0 "12x")))
  ;; ANCHOR_END: run-exception
  ;; ANCHOR: run-collect
  (show-all out (collect (lambda () (range 1 5))))
  ;; ANCHOR_END: run-collect
  (write-line out (repr (first-above 3 (lambda () (range 1 5)))))
  (write-line out (repr (first-above 9 (lambda () (range 1 5)))))
  (show-all out (interleave (start (lambda () (range 1 3))) (start (lambda () (range 10 14)))))
  (unit))
