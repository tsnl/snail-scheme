(import
 (snail core base)
 (snail core io))

(effect Log
  ((log (dyn (Fn String → Unit)))))

(effect Counter
  ((tick (dyn (Fn → I64)))))

(define (work (n I64)) (→ I64) (! Log)
  (log (string-append "working on " (show n)))
  (* n 2))

(define (quietly (action (dyn (Fn → A ! Log e)))) (→ A) (! e) (∀ A e)
  (handle Log
      ((log (lambda (message) (unit))))
    (action)))

(define (loudly (action (dyn (Fn → A ! Log console e)))) (→ A) (! console e) (∀ A e)
  (handle Log
      ((log (lambda (message) (write-line (string-append "log: " message)))))
    (action)))

(display (loudly (lambda () (work 21))))
(newline)
(display (quietly (lambda () (work 5))))
(newline)
(display (handle Counter
             ((tick (lambda () 2)))
           (+ (tick) (+ (tick) (tick)))))
(newline)
(loudly (lambda ()
          (handle Log
              ((log (lambda (message) (log (string-append "outer sees " message)))))
            (log "inner"))))
