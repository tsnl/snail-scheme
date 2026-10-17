;; Right-handed world coordinates: X right, Y forward, Z up. Cameras look
;; along their forward axis; WebGPU clip depth is zero at near and one at far.
(define-library (draw3d math)
  (export Vec3 vec3 vec3-x vec3-y vec3-z v+ v- v* dot cross normalize
          scalar finite? Transform transform transform-x transform-y transform-z transform-origin
          identity-transform translation scaling compose transform-point transform-vector transform-normal
          look-at Camera orthographic-camera perspective-camera camera-matrix camera-ray
          camera-eye camera-right camera-up camera-forward Ray ray ray-origin ray-direction ray-ground
          Bounds bounds ray-box test-math)
  (import
   (scheme base)
   (only (scheme immutable) list)
   (only (lofi base) sqrt i64->f64 i32->i64 unreachable)
   (only (lofi core) datatype ann F64 I32))
  (begin

    ;; ---- Vectors and non-singular affine transforms ----

    (define Vec3
      (datatype ()
        (vec3
         (x F64 vec3-x)
         (y F64 vec3-y)
         (z F64 vec3-z))))
    (define (scalar value) (i64->f64 (i32->i64 value)))
    (define (finite? value) (and (>= value -1.0e30) (<= value 1.0e30)))
    (define (v+ a b) (vec3 (+ (vec3-x a) (vec3-x b)) (+ (vec3-y a) (vec3-y b)) (+ (vec3-z a) (vec3-z b))))
    (define (v- a b) (vec3 (- (vec3-x a) (vec3-x b)) (- (vec3-y a) (vec3-y b)) (- (vec3-z a) (vec3-z b))))
    (define (v* a scale) (vec3 (* (vec3-x a) scale) (* (vec3-y a) scale) (* (vec3-z a) scale)))
    (define (dot a b)
      (+ (+ (* (vec3-x a) (vec3-x b)) (* (vec3-y a) (vec3-y b))) (* (vec3-z a) (vec3-z b))))
    (define (cross a b)
      (vec3 (- (* (vec3-y a) (vec3-z b)) (* (vec3-z a) (vec3-y b)))
            (- (* (vec3-z a) (vec3-x b)) (* (vec3-x a) (vec3-z b)))
            (- (* (vec3-x a) (vec3-y b)) (* (vec3-y a) (vec3-x b)))))
    (define (normalize value)
      (let ((length (sqrt (dot value value))))
        (if (and (finite? length) (> length 0.000001)) (v* value (/ 1.0 length)) (unreachable))))
    (define Transform
      (datatype ()
        (affine
         (x Vec3 transform-x)
         (y Vec3 transform-y)
         (z Vec3 transform-z)
         (origin Vec3 transform-origin))))
    (define (finite-vector? value)
      (and (finite? (vec3-x value)) (finite? (vec3-y value)) (finite? (vec3-z value))))
    (define (transform x y z origin)
      (let ((determinant (dot x (cross y z))))
        (if (and (finite-vector? x) (finite-vector? y) (finite-vector? z) (finite-vector? origin)
                 (finite? determinant) (or (> determinant 0.00000001) (< determinant -0.00000001)))
            (affine x y z origin) (unreachable))))
    (define identity-transform
      (affine (vec3 1.0 0.0 0.0) (vec3 0.0 1.0 0.0) (vec3 0.0 0.0 1.0) (vec3 0.0 0.0 0.0)))
    (define (translation position)
      (transform (transform-x identity-transform) (transform-y identity-transform)
                 (transform-z identity-transform) position))
    (define (scaling x y z)
      (transform (vec3 x 0.0 0.0) (vec3 0.0 y 0.0) (vec3 0.0 0.0 z) (vec3 0.0 0.0 0.0)))
    (define (transform-vector frame value)
      (v+ (v+ (v* (transform-x frame) (vec3-x value)) (v* (transform-y frame) (vec3-y value)))
          (v* (transform-z frame) (vec3-z value))))
    (define (transform-point frame value) (v+ (transform-origin frame) (transform-vector frame value)))
    (define (compose parent local)
      (transform (transform-vector parent (transform-x local)) (transform-vector parent (transform-y local))
                 (transform-vector parent (transform-z local)) (transform-point parent (transform-origin local))))
    ;; Inverse transpose preserves lighting under nonuniform scale and reflection.
    (define (transform-normal frame value)
      (let* ((x (transform-x frame)) (y (transform-y frame)) (z (transform-z frame))
             (cofactor (v+ (v+ (v* (cross y z) (vec3-x value)) (v* (cross z x) (vec3-y value)))
                           (v* (cross x y) (vec3-z value)))))
        (normalize (v* cofactor (/ 1.0 (dot x (cross y z)))))))
    (define (look-at eye target up)
      (let* ((forward (normalize (v- target eye))) (right (normalize (cross forward up))))
        (transform right forward (normalize (cross right forward)) eye)))

    ;; ---- Explicit camera values ----

    (define Camera
      (datatype ()
        (camera
         (pose Transform camera-pose)
         (perspective Bool camera-perspective?)
         (scale F64 camera-scale)
         (aspect F64 camera-aspect)
         (near F64 camera-near)
         (far F64 camera-far))))
    (define (checked-camera eye target up perspective scale aspect near far)
      (if (and (finite? scale) (> scale 0.0) (finite? aspect) (> aspect 0.0)
               (finite? near) (>= near 0.0) (finite? far) (> far near)
               (or (not perspective) (> near 0.0)))
          (camera (look-at eye target up) perspective scale aspect near far) (unreachable)))
    (define (orthographic-camera eye target up height aspect near far)
      (checked-camera eye target up #f (/ height 2.0) aspect near far))
    ;; Focal length is measured in half viewport heights. 1.7320508 gives 60
    ;; degrees vertically. This explicit lens parameter needs no host trigonometry.
    (define (perspective-camera eye target up focal-length aspect near far)
      (checked-camera eye target up #t focal-length aspect near far))
    (define (camera-eye value) (transform-origin (camera-pose value)))
    (define (camera-right value) (transform-x (camera-pose value)))
    (define (camera-forward value) (transform-y (camera-pose value)))
    (define (camera-up value) (transform-z (camera-pose value)))
    (define (camera-matrix value)
      (let* ((perspective (camera-perspective? value))
             (sx (/ (if perspective (camera-scale value) (/ 1.0 (camera-scale value))) (camera-aspect value)))
             (sy (if perspective (camera-scale value) (/ 1.0 (camera-scale value))))
             (az (/ (if perspective (camera-far value) 1.0) (- (camera-far value) (camera-near value))))
             (r (v* (camera-right value) sx)) (u (v* (camera-up value) sy))
             (f (v* (camera-forward value) az))
             (w (v* (camera-forward value) (if perspective 1.0 0.0))) (eye (camera-eye value)))
        (vector (vec3-x r) (vec3-x u) (vec3-x f) (vec3-x w)
                (vec3-y r) (vec3-y u) (vec3-y f) (vec3-y w)
                (vec3-z r) (vec3-z u) (vec3-z f) (vec3-z w)
                (- 0.0 (dot r eye)) (- 0.0 (dot u eye))
                (- (- 0.0 (dot f eye)) (* (camera-near value) az))
                (if perspective (- 0.0 (dot w eye)) 1.0))))

    ;; ---- Picking uses the same camera as rendering ----

    (define Ray
      (datatype ()
        (ray
         (origin Vec3 ray-origin)
         (direction Vec3 ray-direction))))
    (define (camera-ray value x y)
      (let* ((perspective (camera-perspective? value))
             (scale (if perspective (/ 1.0 (camera-scale value)) (camera-scale value)))
             (offset (v+ (v* (camera-right value) (* (* x scale) (camera-aspect value)))
                         (v* (camera-up value) (* y scale)))))
        (if perspective (ray (camera-eye value) (normalize (v+ (camera-forward value) offset)))
            (ray (v+ (camera-eye value) offset) (camera-forward value)))))
    (define (ray-ground value height)
      (let ((dz (vec3-z (ray-direction value))))
        (if (and (> dz -0.000001) (< dz 0.000001)) (empty-list)
            (let ((time (/ (- height (vec3-z (ray-origin value))) dz)))
              (if (< time 0.0) (empty-list)
                  (cons (v+ (ray-origin value) (v* (ray-direction value) time)) (empty-list)))))))
    (define Bounds
      (datatype ()
        (checked-bounds
         (minimum Vec3 bounds-minimum)
         (maximum Vec3 bounds-maximum))))
    (define (bounds minimum maximum)
      (if (and (finite-vector? minimum) (finite-vector? maximum)
               (<= (vec3-x minimum) (vec3-x maximum))
               (<= (vec3-y minimum) (vec3-y maximum))
               (<= (vec3-z minimum) (vec3-z maximum)))
          (checked-bounds minimum maximum) (unreachable)))
    (define Interval
      (datatype ()
        (interval
         (near F64 interval-near)
         (far F64 interval-far))))
    (define (smaller a b) (if (< (ann a F64) b) a b))
    (define (larger a b) (if (> (ann a F64) b) a b))
    (define (clip-slab spans origin direction low high)
      (if (null? spans) spans
          (if (= direction 0.0)
              (if (and (>= origin low) (<= origin high)) spans (empty-list))
              (let* ((a (/ (- low origin) direction)) (b (/ (- high origin) direction))
                     (near (larger (interval-near (car spans)) (smaller a b)))
                     (far (smaller (interval-far (car spans)) (larger a b))))
                (if (<= near far) (list (interval near far)) (empty-list))))))
    ;; Slab clipping returns the first forward point, including a ray that
    ;; starts inside the box. Parallel axes never divide by zero.
    (define (ray-box value box)
      (let* ((origin (ray-origin value)) (direction (ray-direction value))
             (low (bounds-minimum box)) (high (bounds-maximum box))
             (x (clip-slab (list (interval 0.0 1.0e30))
                           (vec3-x origin) (vec3-x direction) (vec3-x low) (vec3-x high)))
             (y (clip-slab x (vec3-y origin) (vec3-y direction) (vec3-y low) (vec3-y high)))
             (z (clip-slab y (vec3-z origin) (vec3-z direction) (vec3-z low) (vec3-z high))))
        (if (null? z) (empty-list)
            (list (v+ origin (v* direction (interval-near (car z))))))))

    ;; ---- Tests ----

    ;; Product libraries follow the current Lofi test convention: one ordinary
    ;; entry point, because this surface does not implement cond-expand.
    (define (near? a b) (and (< (- a b) 0.0001) (> (- a b) -0.0001)))
    (define (test-transforms)
      (let* ((frame (compose (translation (vec3 3.0 4.0 5.0)) (scaling 2.0 3.0 4.0)))
             (point (transform-point frame (vec3 1.0 2.0 3.0)))
             (normal (transform-normal frame (normalize (vec3 1.0 1.0 0.0)))))
        (and (= (vec3-x point) 5.0) (= (vec3-y point) 10.0) (= (vec3-z point) 17.0)
             (near? (/ (vec3-x normal) (vec3-y normal)) 1.5)
             (= (vec3-x (transform-normal (scaling -2.0 1.0 1.0) (vec3 1.0 0.0 0.0))) -1.0))))
    (define (test-cameras)
      (let* ((eye (vec3 0.0 -10.0 10.0)) (target (vec3 0.0 0.0 0.0)) (up (vec3 0.0 0.0 1.0))
             (ortho (orthographic-camera eye target up 10.0 1.5 0.1 100.0))
             (perspective (perspective-camera eye target up 1.7320508 1.5 0.1 100.0))
             (hit (ray-ground (camera-ray ortho 0.0 0.0) 0.0))
             (other (ray-ground (camera-ray perspective 0.0 0.0) 0.0)))
        (and (not (null? hit)) (not (null? other)) (near? (vec3-y (car hit)) 0.0)
             (near? (vec3-y (car other)) 0.0)
             (null? (ray-ground (ray eye (vec3 1.0 0.0 0.0)) 0.0))
             (null? (ray-ground (ray eye (vec3 0.0 0.0 1.0)) 0.0)))))
    (define (test-box-picking)
      (let* ((box (bounds (vec3 -1.0 -1.0 0.0) (vec3 1.0 1.0 2.0)))
             (front (ray-box (ray (vec3 0.0 -3.0 1.0) (vec3 0.0 1.0 0.0)) box))
             (inside (ray-box (ray (vec3 0.0 0.0 1.0) (vec3 0.0 0.0 -1.0)) box)))
        (and (near? (vec3-y (car front)) -1.0) (near? (vec3-z (car inside)) 1.0)
             (null? (ray-box (ray (vec3 2.0 -3.0 1.0) (vec3 0.0 1.0 0.0)) box))
             (null? (ray-box (ray (vec3 0.0 -3.0 1.0) (vec3 0.0 -1.0 0.0)) box)))))
    (define (test-math) (and (test-transforms) (test-cameras) (test-box-picking)))))
