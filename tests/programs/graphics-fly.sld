;; The fly camera's arithmetic: a scene's up turned to +y, as its transform
;; is written, and a fly put looking along a direction, which its eye and
;; target give back.
(import
 (snail core base)
 (snail core io)
 (snail shell graphics pod)
 (snail shell graphics fly))

;; `m`, column by column, applied to `v`.
(define (turned (m (List F64)) (v (List F64))) (→ (List F64))
  (map (lambda (row)
         (fold-left +
                    0.0
                    (map (lambda (k) (* (list-ref m (+ (* 3 k) row)) (list-ref v k))) (iota 3))))
       (iota 3)))

(define (near? (a (List F64)) (b (List F64))) (→ Bool)
  (every? (lambda (k) (< (abs (- (list-ref a k) (list-ref b k))) 1e-6)) (iota 3)))

(define (stands (out OutputPort) (up (List F64))) (→ Unit) (! mut)
  (write-line out (string-append "up "
                             (string-join (map f64->string up) " ")
                             (if (near? (turned (upright up) up) (list 0.0 1.0 0.0))
                                 " stands"
                                 " leans"))))

(define (floats (v Vec3f)) (→ (List F64))
  (list (f32->f64 (● v x)) (f32->f64 (● v y)) (f32->f64 (● v z))))

(define (looks (out OutputPort) (toward (List F64))) (→ Unit) (! mut)
  (let* ((fly
          (fly-toward (fly-over (list 0.0 0.0 0.0) (list 1.0 1.0 1.0)) (list 3.0 4.0 5.0) toward))
         (eye (floats (fly-eye fly)))
         (target (floats (fly-target fly))))
    (write-line out (string-append "from "
                               (string-join (map f64->string eye) " ")
                               (if (near? (map (lambda (k) (- (list-ref target k) (list-ref eye k)))
                                               (iota 3))
                                          toward)
                                   " it looks along "
                                   " it misses ")
                               (string-join (map f64->string toward) " ")))))

(stands out (list 0.0 1.0 0.0))
(stands out (list 0.6 0.0 0.8))
(stands out (list -0.48 -0.6 0.64))
(stands out (list 0.0 -1.0 0.0))
(write-line out (string-append "half a turn: "
                           (string-join (map f64->string (upright (list 0.0 -1.0 0.0))) " ")))
(looks out (list 0.0 0.0 -1.0))
(looks out (list 0.48 0.6 -0.64))
(looks out (list -0.8 -0.6 0.0))
