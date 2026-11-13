(import
 (snail core base)
 (snail core io))

(record Point
  ((x I64)
   (y I64)))

(record Scene
  ((position Point)
   (target Point)))

(record Calls
  ((count I64)))

;; Receiver evaluation happens once for the entire path.
(define (visit (calls Calls) (scene Scene)) (→ Scene) (! mut)
  (set! (● calls count) (+ (● calls count) 1))
  scene)

;; Reads through a deferred receiver are pure.
(define (read-x (point Point)) (→ I64)
  (let ((select (lambda (record) (● record x))))
    (select point)))

(define (main) (→ Unit) (! mut output-port)

  ;; Both child fields refer to independently mutable objects.
  (let ((scene (new Scene (position (new Point (x 1) (y 2))) (target (new Point (x 3) (y 4))))))
    (write-line (show (● scene position x)))
    (write-line (show (● scene target y)))
    (set! (● scene target) (new Point (x 5) (y 6)))
    (set! (● scene position x) 7)
    (write-line (show (replace! (● scene target y) 8)))
    (write-line (show (● scene position x)))
    (write-line (show (● scene target y))))
  (write-line (show (● (new Point (x 9) (y 10)) x)))
  (let ((calls (new Calls (count 0)))
        (scene (new Scene (position (new Point (x 13) (y 14))) (target (new Point (x 15) (y 16))))))
    (write-line (show (● (visit calls scene) target x)))
    (write-line (show (● calls count))))
  (write-line (show (read-x (new Point (x 17) (y 18)))))
  (unit))
