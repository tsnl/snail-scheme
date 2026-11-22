(import
 (snail core base)
 (snail core io))

;; A prompt is a value: a function may make its own, which no other code
;; can suspend to, and hand it to the code it runs. Two prompts of one
;; type never catch each other's suspensions.

;; ANCHOR: local
;; Every value `body` hands the function it is given, in order.
(define (collect (body (Fn (Fn A → Unit) → Unit))) (→ (List A)) (∀ (A))
  (let ((prompt (ann (make-prompt) (Prompt A Unit))))
    (with-prompt prompt
                 (lambda ()
                   (body (lambda (value) (suspend prompt value)))
                   (Nil))
                 (lambda (value resume) (Cons value (resume (unit)))))))

;; The collection inside sees only its own values, and the one outside
;; the rest, though both prompts carry an I64.
(define (nested) (→ (List I64))
  (collect (lambda (emit)
             (emit 1)
             (for-each emit (collect (lambda (inner) (inner 10) (emit 2) (inner 20))))
             (emit 3))))

;; ANCHOR_END: local

;; A prompt of its own is an early exit no caller can intercept: the first
;; item `matches?` accepts, without looking at the rest.
(define (find-first (matches? (Fn A → Bool ! e)) (items (List A))) (→ (Option A)) (! e) (∀ (A e))
  (let ((found (ann (make-prompt) (Prompt A Never))))
    (with-prompt found
                 (lambda ()
                   (for-each (lambda (item)
                               (when (matches? item)
                                 (absurd (suspend found item))))
                             items)
                   (None))
                 (lambda (item resume) (Some item)))))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (write-line out (repr (collect (lambda (emit) (for-each emit (list "a" "b" "c"))))))
  (write-line out (repr (nested)))
  (write-line out
              (repr (find-first (lambda (n)
                                  (write-line out (string-append "looking at " (show n)))
                                  (> n 2))
                                (list 1 2 3 4 5))))
  (write-line out (repr (find-first (lambda (n) (> n 9)) (list 1 2 3))))
  (unit))
