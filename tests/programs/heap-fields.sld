(import
 (snail core base)
 (snail core io))

(record Point
  ((x I64)
   (y I64)))

(record Scene
  ((point Point)))

(define (apply-twice (f (Fn I64 → I64)) (value I64)) (→ I64)
  (f (f value)))

(define (main) (→ Unit) (! mut output-port)
  (let* ((point (new Point (x 1) (y 2)))
         (scene (new Scene (point point)))
         (alias scene)
         (copied (Scene-point-set scene (new Point (x 10) (y 20)))))
    (set! (● alias point x) 3)
    (display (● point x))
    (display (● copied point x))
    (display (● scene point y))
    (set! (● scene point y) 4)
    (display (● point y))
    (newline))
  (let* ((items (make-vector 2 (new Point (x 5) (y 6))))
         (point (vector-ref items 1)))
    (set! (● point x) 7)
    (display (● (vector-ref items 0) x))
    (vector-set! items 1 (new Point (x 8) (y 9)))
    (display (● (vector-ref items 1) x))
    (newline))
  (display (apply-twice (lambda (value) (+ value 1)) 40))
  (newline)
  (let ((work (ann (lambda (value) (+ value 1)) (Fn I64 → I64))))
    (display (work 41))
    (newline))
  (unit))
