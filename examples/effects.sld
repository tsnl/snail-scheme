;; Effect rows and handlers. `log` performs Log; a handler decides what
;; logging means, and the type system tracks which code may perform it.
(import
 (snail core base)
 (snail core io))

(effect Log
  ((log (-> String Unit))))

(: total-cost (-> (List I64) I64 ! Log))
(define (total-cost prices)
  (fold-left (lambda (total price)
               (log (string-append "adding " (show price)))
               (+ total price))
             0 prices))

;; The same function, quiet or verbose, depending only on its handler.
(: quietly (All (A e) (-> (-> A ! Log e) A ! e)))
(define (quietly action)
  (handle Log
      ((log (lambda (message) (unit))))
    (action)))

(display (quietly (lambda () (total-cost (list 3 4 5)))))
(newline)
(display (handle Log
             ((log (lambda (message) (write-line message))))
           (total-cost (list 1 2))))
(newline)
