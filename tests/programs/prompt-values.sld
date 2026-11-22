(import
 (snail core base)
 (snail core io))

;; A function left by a suspension returns zero or null for its inactive
;; result, which no caller reads: whatever the type, the value the program
;; sees is the handler's, or the one the body is resumed with.
(define asking (→ (Prompt I64 I64)) (make-prompt))

(define (ask (n I64)) (→ I64)
  (suspend asking n))

(record Point
  ((x I64)
   (y I64)))

(enum Shape
  (Dot)
  (Box
   ((width I64))))

(define (point) (→ Point) (new Point (x 1) (y (ask 2))))

(define (shape) (→ Shape) (Box (ask 3)))

(define (text) (→ String) (string-append "x" (show (ask 4))))

(define (adder) (→ (Fn I64 → I64)) (let ((z (ask 5))) (lambda (y) (* y z))))

(define (ratio) (→ F64) (/ (i64->f64 (ask 6)) 4.0))

(define (flag) (→ Bool) (> (ask 7) 100))

;; `body`'s value when each question is answered with ten times itself.
(define (answered (body (Fn → A))) (→ A) (∀ (A))
  (with-prompt asking body (lambda (n resume) (resume (* n 10)))))

;; A prompt carries whatever its type says: records out, strings back.
(define naming (→ (Prompt Point String)) (make-prompt))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (write-line out (show (● (answered point) y)))
  (write-line out (show (match (answered shape) ((Dot) 0) ((Box width) width))))
  (write-line out (answered text))
  (write-line out (show ((answered adder) 2)))
  (write-line out (show (answered ratio)))
  (write-line out (show (answered flag)))
  ;; A handler that does not resume answers for the whole body.
  (write-line out (show (with-prompt asking (lambda () (● (point) x)) (lambda (n resume) (* n 1000)))))
  (write-line out
              (with-prompt naming
                           (lambda ()
                             (string-append "named "
                                            (suspend naming (new Point (x 3) (y 4)))))
                           (lambda (point resume)
                             (resume (string-append (show (● point x)) "," (show (● point y)))))))
  (unit))
