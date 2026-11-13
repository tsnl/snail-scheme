(import
 (snail core base)
 (snail core io))

(struct Point
  ((x I64)
   (y I64)))

(struct Scene
  ((point Point)))

(define (apply-twice (f (Fn I64 → I64)) (value I64)) (→ I64)
  (f (f value)))

(define (main) (→ Unit) (! mut output-port)
  (let* ((point (Point 1 2))
         (scene (Scene point))
         (alias scene)
         (copied (Scene-point-set scene (Point 10 20))))
    (set! (● alias point x) 3)
    (display (● point x))
    (display (● copied point x))
    (display (replace! (● scene point y) 4))
    (display (● point y))
    (newline))
  (let* ((items (make-vector 2 (Point 5 6)))
         (point (vector-ref items 1)))
    (set! (● point x) 7)
    (display (● (vector-ref items 0) x))
    (vector-set! items 1 (Point 8 9))
    (display (● (vector-ref items 1) x))
    (newline))
  (display (apply-twice (lambda (value) (+ value 1)) 40))
  (newline)
  (let ((work (ann (lambda (value) (+ value 1)) (FnOnce I64 → I64))))
    (display (work 41))
    (newline))
  (unit))
