(import
 (snail core base)
 (snail core io))

(effect Log
  ((log (Fn String → Unit))))

(effect Counter
  ((tick (Fn → I64))))

(define (work (n I64)) (→ I64) (! Log)
  (log (string-append "working on " (show n)))
  (* n 2))

(define (quietly (action (Fn → A ! Log e))) (→ A) (! e) (∀ A e)
  (handle Log
      ((log (lambda (message) (unit))))
    (action)))

(define (loudly (action (Fn → A ! Log output-port e))) (→ A) (! output-port e) (∀ A e)
  (handle Log
      ((log (lambda (message) (write-line (string-append "log: " message)))))
    (action)))

(define main
  (lambda ()
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
    (unit)))
