(import
 (snail core base)
 (snail core io))

;; A function left by a yield returns a placeholder of its result type,
;; which no caller reads: each representation has one. The handler's
;; result is what the program sees.
(effect Abort
  ((ctl abort (dyn (Fn I64 -> I64)))))

(struct Point
  ((x I64)
   (y I64)))

(enum Shape
  (Dot)
  (Box
   ((width I64))))

(: point (impl (Fn -> Point ! Abort)))
(define (point) (Point 1 (abort 2)))

(: shape (impl (Fn -> Shape ! Abort)))
(define (shape) (Box (abort 3)))

(: text (impl (Fn -> String ! Abort)))
(define (text) (string-append "x" (show (abort 4))))

(: adder (impl (Fn -> (dyn (Fn I64 -> I64)) ! Abort)))
(define (adder) (let ((z (abort 5))) (lambda (y) (* y z))))

(: later (impl (Fn -> (dyn (FnOnce -> Unit ! console)) ! Abort)))
(define (later) (let ((value (abort 6))) (once (lambda () (write-line (show value))))))

(display (handle Abort ((abort (lambda (value resume) (drop resume) (* value 1000))))
           (+ (::x (point)) 1)))
(newline)
(display (handle Abort ((abort (lambda (value resume) (drop resume) value)))
           (match (shape) ((Dot) 0) ((Box width) width))))
(newline)
(write-line
 (handle Abort ((abort (lambda (value resume) (drop resume) (show value))))
   (string-append (text) "!")))
(display
 ((handle Abort ((abort (lambda (value resume)
                          (drop resume)
                          (ann (lambda (y) (+ y value)) (dyn (Fn I64 -> I64)))))) (adder))
  1))
(newline)
((handle Abort ((abort (lambda (value resume)
                         (drop resume)
                         (once (lambda () (write-line "from the handler"))))))
   (later)))

;; A handler of an ordinary operation inside the handle is left behind with
;; the rest of the body; an effect may mix both kinds of operation.
(effect Log
  ((log (dyn (Fn String -> Unit)))))

(effect Probe
  ((peek (dyn (Fn -> I64)))
   (ctl bail (dyn (Fn I64 -> Unit)))))

(display (handle Abort ((abort (lambda (value resume) (drop resume) (* value 10))))
           (handle Log ((log (lambda (message) (write-line message))))
             (log "before")
             (+ 1 (abort 4)))))
(newline)
(display
 (handle Probe ((peek (lambda () 7)) (bail (lambda (value resume) (drop resume) (+ value 100))))
   (let ((x (peek))) (if (> x 5) (begin (bail x) 0) x))))
(newline)
