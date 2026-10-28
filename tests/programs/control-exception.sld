(import
 (snail-core base)
 (snail-core io))

;; An exception is a control operation with a resumable shape: `raise`
;; could hand its caller a number, but these handlers drop `resume` and
;; answer for the whole handled computation instead.
(effect Raise
  ((ctl raise (-> String I64))))

(: digit (-> Char I64 ! Raise))
(define (digit c)
  (if (char-numeric? c)
      (- (char->integer c) 48)
      (raise (string-append "not a digit: " (list->string (list c))))))

(: number (-> String I64 ! Raise))
(define (number text)
  (fold-left (lambda (total c) (+ (* total 10) (digit c))) 0 (string->list text)))

;; The handler's answer is a default, after reporting the message.
(: parse-or (-> String I64 I64 ! console))
(define (parse-or text default)
  (handle Raise ((raise (lambda (message resume) (write-line message) default)))
    (number text)))

(display (parse-or "123" 0))
(newline)
(display (parse-or "1x3" 0))
(newline)

;; Of two handlers of one effect, the inner one catches; its
;; implementation runs in the outer context, so raising there reaches the
;; outer handler, which answers for everything inside it.
(display
 (handle Raise ((raise (lambda (message resume) (write-line (string-append "outer: " message)) 0)))
   (+ 100
      (handle Raise ((raise
                      (lambda (message resume) (write-line (string-append "inner: " message)) 1)))
        (raise "boom")))))
(newline)
(display
 (handle Raise ((raise (lambda (message resume) (write-line (string-append "outer: " message)) 0)))
   (+ 100 (handle Raise ((raise (lambda (message resume) (raise (string-append "again " message)))))
            (raise "boom")))))
(newline)
