(import
 (snail core base)
 (snail core io))

(record Holder
  ((prompt (Prompt I64 I64))))

(define holder (→ Holder) (new Holder (prompt (make-prompt))))

;; A nullary function, not a top-level value: it answers whichever prompt
;; the holder has now.
(define (current) (→ (Prompt I64 I64))
  (● holder prompt))

(define (main (out OutputPort)) (→ Unit)
  (let ((first (current)))
    (display out
             (with-prompt first
                          (lambda ()
                            (set! (● holder prompt) (make-prompt))
                            (let ((inner (with-prompt (current)
                                                      (lambda ()
                                                        (set! (● holder prompt) first)
                                                        (+ 1 (suspend (current) 5)))
                                                      (lambda (value resume) 100))))
                              (write-line out "after inner")
                              (+ inner 1000)))
                          (lambda (value resume) (resume (* value 2)))))
    (newline out)
    (unit)))
