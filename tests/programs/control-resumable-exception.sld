(import
 (snail-core base)
 (snail-core io))

;; A resumable exception: `fail` reports a problem and asks for a value to
;; go on with, which the handler supplies by resuming.
(effect Fail
  ((ctl fail (-> String I64))))

;; A log whose handler prints each line and resumes, so performing it
;; leaves the computation and comes back.
(effect Log
  ((ctl log (-> String Unit))))

(: digit (-> Char I64 ! Fail))
(define (digit c)
  (if (char-numeric? c)
      (- (char->integer c) 48)
      (fail (string-append "not a digit: " (list->string (list c))))))

(: number (-> String I64 ! Fail))
(define (number text)
  (fold-left (lambda (total c) (+ (* total 10) (digit c)))
             0
             (string->list text)))

;; Each bad digit counts as the default, and parsing goes on.
(: parse-with (-> String I64 I64 ! console))
(define (parse-with text default)
  (handle Fail ((fail (lambda (message resume)
                        (write-line message)
                        (resume default))))
    (number text)))

(display (parse-with "123" 0))
(newline)
(display (parse-with "1x3y" 9))
(newline)

;; Of two handlers of one effect, the inner one catches the body's `fail`.
;; Its implementation runs outside it, so its own `fail` reaches the outer
;; handler, which resumes it; the inner one then resumes the body.
(display (handle Fail ((fail (lambda (message resume)
                               (write-line (string-append "outer: " message))
                               (resume 100))))
           (handle Fail ((fail (lambda (message resume)
                                 (write-line (string-append "inner: " message))
                                 (+ 1
                                    (resume (fail (string-append "again "
                                                                 message)))))))
             (+ (fail "boom") 1))))
(newline)

;; The resumed part of the body performs `log`, a control operation of a
;; handler outside the one that resumed it: the yield leaves the resumed
;; frames, the inner handler and its implementation, reaches the log's
;; handler, and comes back through all of them when that resumes.
(: checked (-> String I64 ! Fail Log))
(define (checked text)
  (log (string-append "checking " text))
  (let ((value (number text)))
    (log (string-append "value " (show value)))
    value))

(: logged (-> (-> I64 ! Log) I64 ! console))
(define (logged body)
  (handle Log ((log (lambda (line resume)
                      (write-line (string-append "log: " line))
                      (resume (unit)))))
    (body)))

(display (logged (lambda ()
                   (handle Fail ((fail (lambda (message resume)
                                         (log (string-append "recovering from "
                                                             message))
                                         (* 2 (resume 5)))))
                     (+ (checked "4z") (checked "7"))))))
(newline)
