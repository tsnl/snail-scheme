;; Exact optical depths, a bisector tie, the derivatives on both sides of
;; a moving face, and the density interface that the photograph cannot name.
(import
 (snail core base)
 (only (snail core io) OutputPort write-line)
 (only (snail shell math) log)
 (snail shell graphics radiant-foam))

(define red (→ Vec3d) (vec3d 1.0 0.0 0.0))
(define blue (→ Vec3d) (vec3d 0.0 0.0 1.0))
(define dark (→ Vec3d) (vec3d 0.0 0.0 0.0))
(define left (→ Vec3d) (vec3d -0.5 0.0 0.0))
(define right (→ Vec3d) (vec3d 0.5 0.0 0.0))
(define oblique (→ Ray) (ray (vec3d -2.0 0.15 0.1) (vec3d 1.0 0.12 -0.05)))

(define (check (out OutputPort) (label String) (ok Bool)) (→ Unit)
  (if ok (write-line out label) (panic label)))

(define (close (a Vec3d) (b Vec3d)) (→ Bool)
  (let ((v (v- a b))) (< (dot v v) 1e-18)))

(define (optics (out OutputPort)) (→ Unit)
  (let* ((foam (make-foam (list (site left (log 2.0) red) (site right (log 4.0) blue))))
         (along (lambda (x dx) (ray (vec3d x 0.0 0.0) (vec3d dx 0.0 0.0)))))
    (check out "front and back have different weights in opposite views"
           (and (close (render-ray foam (along -2.0 3.0)) (vec3d 0.5 0.0 0.375))
                (close (render-ray foam (along 2.0 -1.0)) (vec3d 0.125 0.0 0.75))))
    (check out "a ray on a bisector has one owner"
           (close (render-ray foam (ray (vec3d 0.0 -2.0 0.0) (vec3d 0.0 1.0 0.0)))
                  (vec3d 0.75 0.0 0.0)))
    (check out "a ray starting inside sees only the remaining distance"
           (close (render-ray foam (along 0.0 1.0)) (vec3d 0.0 0.0 0.75)))
    (check out "a missed box and a transparent cell give black"
           (and (close (render-ray foam (along 2.0 1.0)) dark)
                (close (render-ray (make-foam (list (site left 0.0 red))) oblique) dark)))))

(define target (→ Vec3d) (vec3d 0.1 0.6 0.7))
(define a (→ Site) (site left 0.9 (vec3d 0.8 0.2 0.1)))
(define b (→ Site) (site right 0.35 (vec3d 0.3 0.4 0.7)))

(define (loss (a Site) (b Site)) (→ F64)
  (let ((diff (v- (render-ray (make-foam (list a b)) oblique) target)))
    (/ (dot diff diff) 3.0)))

(define (parameters (s Site)) (→ (List F64))
  (let ((p (● s position)) (c (● s rgb)))
    (list (● p x) (● p y) (● p z) (● s density) (● c x) (● c y) (● c z))))

;; Change exactly one coordinate, extinction, or channel at a time.
(define (perturb (s Site) (i I64) (delta F64)) (→ Site)
  (let* ((values (parameters s))
         (at (lambda (j) (+ (list-ref values j) (if (= i j) delta 0.0)))))
    (site (vec3d (at 0) (at 1) (at 2)) (at 3) (vec3d (at 4) (at 5) (at 6)))))

(define (agrees? (s Site) (stepped Site) (objective (Fn Site → F64))) (→ Bool)
  (let ((before (parameters s)) (after (parameters stepped)) (eps 1e-5))
    (every? (lambda (i)
              (let ((observed
                     (/ (- (objective (perturb s i eps)) (objective (perturb s i (negate eps))))
                        (* 2.0 eps)))
                    (analytic (/ (- (list-ref before i) (list-ref after i)) 0.01)))
                (< (abs (- analytic observed)) 1e-8)))
            (iota 7))))

(define (derivatives (out OutputPort)) (→ Unit)
  (let* ((samples (list (new Sample (ray oblique) (rgb target))))
         (next (array->list (fit-step (make-foam (list a b)) samples 0.01))))
    (check out "both sites' position, density and RGB gradients match finite differences"
           (and (agrees? a (list-ref next 0) (lambda (s) (loss s b)))
                (agrees? b (list-ref next 1) (lambda (s) (loss a s)))))
    (check out "a fitting step reduces RGB error"
           (< (loss (list-ref next 0) (list-ref next 1)) (loss a b)))))

(define (interfaces (out OutputPort)) (→ Unit)
  (let* ((sites (list (site left 2.0 red) (site right 0.0 blue)))
         (face (list-ref (density-faces (make-foam sites) 1.0) 0))
         (third (site (vec3d 0.0 0.5 0.0) 0.0 blue))
         (clipped (density-faces (make-foam (append sites (list third))) 1.0)))
    (check out "one square lies on the bisector and reaches all four box edges"
           (and (= (length (density-faces (make-foam sites) 1.0)) 1) (= (length face) 4)
                (every? (lambda (p) (and (= (● p x) 0.0) (= (abs (● p y)) 1.0)
                                         (= (abs (● p z)) 1.0))) face)))
    (check out "a third site clips the face at the shared edge"
           (and (= (length clipped) 2)
                (every? (lambda (p) (<= (● p y) 1e-12)) (list-ref clipped 0))))
    (check out "uniform classification emits no surface"
           (and (null? (density-faces (make-foam sites) 0.0))
                (null? (density-faces (make-foam sites) 3.0))))))

(define (degeneracies (out OutputPort)) (→ Unit)
  (let* ((s (lambda (x y density) (site (vec3d x y 0.0) density red)))
         (square (make-foam (list (s -0.5 -0.5 2.0) (s 0.5 0.5 0.0)
                                  (s -0.5 0.5 2.0) (s 0.5 -0.5 2.0))))
         (duplicate (make-foam (list (site left 1.0 red) (site left 5.0 blue))))
         (face
          (list-ref (density-faces (make-foam (list (site left 2.0 red) (site right 0.0 blue))) 1.0)
                    0))
         (u (v- (list-ref face 1) (list-ref face 0))) (v (v- (list-ref face 2) (list-ref face 0))))
    (check out "edge contact between opposite cells emits no extra face"
           (= (length (density-faces square 1.0)) 2))
    (check out "coincident sites keep the first material"
           (and (= (length (array->list duplicate)) 1)
                (close (● (list-ref (array->list duplicate) 0) rgb) red)))
    (check out "face winding points from dense to sparse"
           (> (- (* (● u y) (● v z)) (* (● u z) (● v y))) 0.0))))

(define (corner-crossing (out OutputPort)) (→ Unit)
  (let* ((sigma (/ (log 2.0) (sqrt 2.0)))
         (sites (list (site (vec3d -0.5 -0.5 0.0) sigma red)
                      (site (vec3d 0.5 -0.5 0.0) 100.0 blue)
                      (site (vec3d -0.5 0.5 0.0) 100.0 blue)
                      (site (vec3d 0.5 0.5 0.0) sigma blue)))
         (diagonal (ray (vec3d -2.0 -2.0 0.0) (vec3d 1.0 1.0 0.0))))
    (check out "crossing a four-cell edge gives no weight to zero-length visits"
           (every?
            (lambda (order) (close (render-ray (make-foam order) diagonal) (vec3d 0.5 0.0 0.25)))
            (list sites (reverse sites))))))

(define (main (out OutputPort)) (→ Unit)
  (optics out)
  (derivatives out)
  (interfaces out)
  (degeneracies out)
  (corner-crossing out))
