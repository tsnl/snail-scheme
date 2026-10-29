(import
 (snail core base)
 (snail core io))

;; A function left by a yield returns a placeholder of its result type,
;; which no caller reads: each representation has one. The handler's
;; result is what the program sees.
(effect Abort
  ((ctl abort (-> I64 I64))))

(struct Point
  ((x I64)
   (y I64)))

(enum Shape
  (Dot)
  (Box
   ((width I64))))

(: point (-> Point ! Abort))
(define (point) (Point 1 (abort 2)))

(: shape (-> Shape ! Abort))
(define (shape) (Box (abort 3)))

(: text (-> String ! Abort))
(define (text) (string-append "x" (show (abort 4))))

(: adder (-> (-> I64 I64) ! Abort))
(define (adder) (let ((z (abort 5))) (lambda (y) (* y z))))

(: later (-> (FnOnce Unit ! console) ! Abort))
(define (later) (let ((value (abort 6))) (once (lambda () (write-line (show value))))))

(display (handle Abort ((abort (lambda (value resume) (drop resume) (* value 1000))))
           (+ (Point-x (point)) 1)))
(newline)
(display (handle Abort ((abort (lambda (value resume) (drop resume) value)))
           (match (shape) ((Dot) 0) ((Box width) width))))
(newline)
(write-line
 (handle Abort ((abort (lambda (value resume) (drop resume) (show value))))
   (string-append (text) "!")))
(display
 ((handle Abort ((abort (lambda (value resume) (drop resume) (lambda (y) (+ y value))))) (adder))
  1))
(newline)
((handle Abort ((abort (lambda (value resume)
                         (drop resume)
                         (once (lambda () (write-line "from the handler"))))))
   (later)))

;; A handler of an ordinary operation inside the handle is left behind with
;; the rest of the body; an effect may mix both kinds of operation.
(effect Log
  ((log (-> String Unit))))

(effect Probe
  ((peek (-> I64))
   (ctl bail (-> I64 Unit))))

(display (handle Abort ((abort (lambda (value resume) (drop resume) (* value 10))))
           (handle Log ((log (lambda (message) (write-line message))))
             (log "before")
             (+ 1 (abort 4)))))
(newline)
(display
 (handle Probe ((peek (lambda () 7)) (bail (lambda (value resume) (drop resume) (+ value 100))))
   (let ((x (peek))) (if (> x 5) (begin (bail x) 0) x))))
(newline)
