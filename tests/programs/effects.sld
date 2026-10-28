(import
 (snail core base)
 (snail core io))

(effect Log
  ((log (-> String Unit))))

(effect Counter
  ((tick (-> I64))))

(: work (-> I64 I64 ! Log))
(define (work n)
  (log (string-append "working on " (show n)))
  (* n 2))

(: quietly (All (A e) (-> (-> A ! Log e) A ! e)))
(define (quietly action)
  (handle Log
      ((log (lambda (message) (unit))))
    (action)))

(: loudly (All (A e) (-> (-> A ! Log console e) A ! console e)))
(define (loudly action)
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
