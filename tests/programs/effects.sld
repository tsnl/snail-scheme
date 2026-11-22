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

(define (quietly (action (Fn → A ! Log e))) (→ A) (! e) (∀ (A e))
  (handle Log
      ((log (lambda (message) (unit))))
    (action)))

(define (loudly (out OutputPort) (action (Fn → A ! Log mut e))) (→ A) (! mut e) (∀ (A e))
  (handle Log
      ((log (lambda (message) (write-line out (string-append "log: " message)))))
    (action)))

(define (main (out OutputPort)) (→ Unit) (! mut)

  (display out (loudly out (lambda () (work 21))))
  (newline out)
  (display out (quietly (lambda () (work 5))))
  (newline out)
  (display out (handle Counter
               ((tick (lambda () 2)))
             (+ (tick) (+ (tick) (tick)))))
  (newline out)
  (loudly out (lambda ()
            (handle Log
                ((log (lambda (message) (log (string-append "outer sees " message)))))
              (log "inner"))))
  (unit))
