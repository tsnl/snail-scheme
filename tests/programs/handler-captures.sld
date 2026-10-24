(import
 (lofi base)
 (lofi io)
 (handler helper))

(effect Counter ((tick (-> I64))))

(: recursive (-> I64 I64))
(define (recursive n) (if (= n 0) 4 (recursive (- n 1))))

;; Local mutation belongs to each invocation, not to its reusable environment.
(display (handle Counter
             ((tick (lambda () (let ((cell (ref (ann 1 I64))))
                                 (ref-set! cell 7)
                                 (ref-get cell)))))
           (+ (tick) (tick))))
(newline)
(let* ((offset (ann 3 I64))
       (callback (lambda () (+ offset (recursive (answer)))))
       (alias callback))
  (display (handle Counter ((tick alias)) (tick)))
  (newline))
