(import
 (snail core base)
 (snail core io))

(struct Point
  ((x I64)
   (y I64)))
(struct Scene
  ((position Point)
   (target (Ref Point))))
;; Follow references at every step, but keep a final Ref field intact.
(let ((scene (ref (Scene (Point 1 2) (ref (Point 3 4))))))
  (write-line (show (● scene position x)))
  (write-line (show (● scene target y)))
  (ref-set! (● scene target) (Point 5 6))
  (set! (● scene position x) 7)
  (write-line (show (replace! (● scene target y) 8)))
  (write-line (show (● scene position x)))
  (write-line (show (● scene target y))))
(write-line (show (● (ref (ref (Point 9 10))) x)))

;; Receiver evaluation happens once for the entire path.
(define (visit (calls (Ref I64)) (scene (Ref Scene))) (→ (Ref Scene)) (! mut)
  (ref-set! calls (+ (ref-get calls) 1))
  scene)
(let ((calls (ref 0)) (scene (ref (Scene (Point 13 14) (ref (Point 15 16))))))
  (write-line (show (● (visit calls scene) target x)))
  (write-line (show (ref-get calls))))

;; A deferred receiver learns both its nominal type and mutation effect.
(define (read-x (point (Ref Point))) (→ I64) (! mut)
  (let ((select (lambda (record) (● record x))))
    (select point)))
(write-line (show (read-x (ref (Point 17 18)))))
