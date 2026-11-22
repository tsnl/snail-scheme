(import
 (snail core base)
 (snail core io))

;; An exception is a control operation with a resumable shape: `raise`
;; could hand its caller a number, but these handlers never call `resume`
;; and answer for the whole handled computation instead.
;; ANCHOR: parse-or
(effect Raise
  ((ctl raise (Fn String → I64))))

(define (digit (c Char)) (→ I64) (! Raise)
  (if (char-numeric? c)
      (- (char->integer c) 48)
      (raise (string-append "not a digit: " (list->string (list c))))))

(define (number (text String)) (→ I64) (! Raise)
  (fold-left (lambda (total c) (+ (* total 10) (digit c))) 0 (string->list text)))

;; The handler's answer is a default, after reporting the message.
(define (parse-or (out OutputPort) (text String) (default I64)) (→ I64) (! mut)
  (handle Raise ((raise (lambda (message resume) (write-line out message) default)))
    (number text)))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (display out (parse-or out "123" 0))
  (newline out)
  (display out (parse-or out "1x3" 0))
  (newline out)
  ;; ANCHOR_END: parse-or

  ;; Of two handlers of one effect, the inner one catches; its
  ;; implementation runs in the outer context, so raising there reaches the
  ;; outer handler, which answers for everything inside it.
  (display out
           (handle Raise ((raise (lambda (message resume)
                                   (write-line out (string-append "outer: " message))
                                   0)))
             (+ 100
                (handle Raise ((raise
                                (lambda (message resume)
                                  (write-line out (string-append "inner: " message))
                                  1)))
                  (raise "boom")))))
  (newline out)
  (display out
           (handle Raise ((raise (lambda (message resume)
                                   (write-line out (string-append "outer: " message))
                                   0)))
             (+ 100
                (handle Raise ((raise (lambda (message resume)
                                        (raise (string-append "again " message)))))
                  (raise "boom")))))
  (newline out)
  (unit))
