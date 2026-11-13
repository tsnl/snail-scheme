(import
 (snail core base)
 (snail core io))

(struct Point
  ((x I64)
   (y I64)))

(struct Scene
  ((position Point)
   (target Point)))

(struct Calls
  ((count I64)))

;; Receiver evaluation happens once for the entire path.
(define (visit (calls Calls) (scene Scene)) (→ Scene) (! mut)
  (set! (● calls count) (+ (● calls count) 1))
  scene)

;; Reads through a deferred receiver are pure.
(define (read-x (point Point)) (→ I64)
  (let ((select (lambda (record) (● record x))))
    (select point)))

(define main
  (lambda ()
    ;; Both child fields refer to independently mutable objects.
    (let ((scene (Scene (Point 1 2) (Point 3 4))))
      (write-line (show (● scene position x)))
      (write-line (show (● scene target y)))
      (set! (● scene target) (Point 5 6))
      (set! (● scene position x) 7)
      (write-line (show (replace! (● scene target y) 8)))
      (write-line (show (● scene position x)))
      (write-line (show (● scene target y))))
    (write-line (show (● (Point 9 10) x)))
    (let ((calls (Calls 0)) (scene (Scene (Point 13 14) (Point 15 16))))
      (write-line (show (● (visit calls scene) target x)))
      (write-line (show (● calls count))))
    (write-line (show (read-x (Point 17 18))))
    (unit)))
