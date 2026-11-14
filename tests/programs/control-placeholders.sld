(import
 (snail core base)
 (snail core io))

;; A function left by a yield returns zero or null for its inactive result,
;; which no caller reads. The handler's result is what the program sees.
(effect Abort
  ((ctl abort (Fn I64 → I64))))

(record Point
  ((x I64)
   (y I64)))

(enum Shape
  (Dot)
  (Box
   ((width I64))))

(define (point) (→ Point) (! Abort) (new Point (x 1) (y (abort 2))))

(define (shape) (→ Shape) (! Abort) (Box (abort 3)))

(define (text) (→ String) (! Abort) (string-append "x" (show (abort 4))))

(define (adder) (→ (Fn I64 → I64)) (! Abort) (let ((z (abort 5))) (lambda (y) (* y z))))

(define (later)
  (→ (FnOnce → Unit ! output-port))
  (! Abort)
  (let ((value (abort 6))) (once (lambda () (write-line (show value))))))

;; A handler of an ordinary operation inside the handle is left behind with
;; the rest of the body; an effect may mix both kinds of operation.
(effect Log
  ((log (Fn String → Unit))))

(effect Probe
  ((peek (Fn → I64))
   (ctl bail (Fn I64 → Unit))))

(define (main) (→ Unit) (! output-port)
  (display (handle Abort ((abort (lambda (value resume) (drop resume) (* value 1000))))
             (+ (● (point) x) 1)))
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
                            (ann (lambda (y) (+ y value)) (Fn I64 → I64))))) (adder))
    1))
  (newline)
  ((handle Abort ((abort (lambda (value resume)
                           (drop resume)
                           (once (lambda () (write-line "from the handler"))))))
     (later)))
  (display (handle Abort ((abort (lambda (value resume) (drop resume) (* value 10))))
             (handle Log ((log (lambda (message) (write-line message))))
               (log "before")
               (+ 1 (abort 4)))))
  (newline)
  (display
   (handle Probe ((peek (lambda () 7)) (bail (lambda (value resume) (drop resume) (+ value 100))))
     (let ((x (peek))) (if (> x 5) (begin (bail x) 0) x))))
  (newline)
  (unit))
