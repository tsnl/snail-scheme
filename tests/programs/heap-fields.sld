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

(define (main (out OutputPort)) (→ Unit) (! mut)
  (let* ((point (new Point (x 1) (y 2)))
         (scene (new Scene (point point)))
         (alias scene)
         (copied (Scene-point-set scene (new Point (x 10) (y 20)))))
    (set! (● alias point x) 3)
    (display out (● point x))
    (display out (● copied point x))
    (display out (● scene point y))
    (set! (● scene point y) 4)
    (display out (● point y))
    (newline out))
  (let* ((items (make-array 2 (new Point (x 5) (y 6))))
         (point (array-ref items 1)))
    (set! (● point x) 7)
    (display out (● (array-ref items 0) x))
    (array-set! items 1 (new Point (x 8) (y 9)))
    (display out (● (array-ref items 1) x))
    (newline out))
  (display out (apply-twice (lambda (value) (+ value 1)) 40))
  (newline out)
  (let ((work (ann (lambda (value) (+ value 1)) (Fn I64 → I64))))
    (display out (work 41))
    (newline out))
  (unit))
