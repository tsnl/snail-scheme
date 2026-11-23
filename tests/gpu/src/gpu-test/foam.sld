;; Render the F64 reference's rays and descend its minibatches on a device.
(define-library (gpu-test foam)
  (export check-foam)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics radiant-foam)
   (snail shell graphics radiant-foam-gpu))
  (begin

    (define (close? (a Vec3d) (b Vec3d)) (→ Bool)
      (let ((d (v- a b))) (< (dot d d) 1e-9)))

    (define (same-site? (a Site) (b Site)) (→ Bool)
      (and (close? (● a position) (● b position)) (< (abs (- (● a density) (● b density))) 3e-5)
           (close? (● a rgb) (● b rgb))))

    (define target (→ Vec3d) (vec3d 0.13 0.78 0.41))

    ;; A shuffled line of cells spans three Morton groups. The axial ray
    ;; crosses all 35, including the last partial group. The oblique rays
    ;; give the moving bisectors nonzero gradients on all three axes.
    (define line (→ Foam)
      (make-foam (map (lambda (i)
                        (let* ((j (modulo (* i 11) 35)) (u (/ (i64->f64 j) 34.0))
                               (p (vec3d (- (* 1.9 u) 0.95) 0.0 0.0)))
                          (site p (+ 0.4 u) (vec3d u (- 1.0 u) (* u u)))))
                      (iota 35))))

    (define samples (→ (Array Sample))
      (let ((toward (lambda (x y z dx dy dz)
                      (new Sample (ray (ray (vec3d x y z) (vec3d dx dy dz))) (rgb target)))))
        (list->array (list (toward -2.0 0.0 0.0 1.0 0.0 0.0)
                           (toward 2.0 0.05 0.1 -1.0 -0.02 0.06)
                           (toward 0.01 0.0 0.2 0.9 0.1 0.08)
                           (toward -2.0 0.2 -0.15 1.0 0.09 0.04)
                           (toward -2.0 1.5 0.0 1.0 0.0 0.0)))))

    (define zero (→ Vec3d) (vec3d 0.0 0.0 0.0))

    (define (single-pixel (r Ray)) (→ RayCamera)
      (new RayCamera
        (eye (● r origin))
        (corner (● r direction))
        (dx zero)
        (dy zero)
        (width 1)
        (height 1)))

    (define (frame (gpu Gpu) (view FoamView)) (→ (Array Vec3d))
      (let* ((encoder ((● gpu create-command-encoder))) (pass ((● gpu begin-compute-pass) encoder)))
        (dispatch-foam-view gpu pass view)
        ((● gpu end-compute-pass) pass)
        ((● gpu submit) (list ((● gpu finish) encoder)))
        (read-foam-view gpu view)))

    (define (check-draw (gpu Gpu) (device DeviceFoam) (cpu Foam) (rays (Array Sample))) (→ Unit)
      (let ((view (make-foam-view gpu device (single-pixel (● (array-ref rays 0) ray)) 1 1)))
        (array-for-each (lambda (sample)
                          (write-foam-camera! gpu view (single-pixel (● sample ray)))
                          (unless (close? (array-ref (frame gpu view) 0)
                                          (render-ray cpu (● sample ray)))
                            (panic "foam GPU radiance differs from the CPU"))) rays)
        (release-foam-view gpu view)))

    ;; Native pixel centers from a 17×11 camera, rendered to a 7×5 view.
    (define (check-camera (gpu Gpu) (device DeviceFoam)) (→ Unit)
      (let* ((cam (new RayCamera (eye (vec3d -2.0 0.0 0.0)) (corner (vec3d 1.0 -0.6 -0.4))
                       (dx (vec3d 0.0 0.08 0.0)) (dy (vec3d 0.0 0.0 0.08)) (width 17) (height 11)))
             (view (make-foam-view gpu device cam 7 5)) (image (frame gpu view)))
        (do ((i 0 (+ i 1))) ((= i 35) (unit))
          (let ((x (quotient (* (+ (* 2 (remainder i 7)) 1) 17) 14))
                (y (quotient (* (+ (* 2 (quotient i 7)) 1) 11) 10)))
            (unless (close? (array-ref image i) (render-ray line (camera-ray cam x y)))
              (panic "foam camera samples the wrong source pixel"))))
        (release-foam-view gpu view)))

    (define (check-steps (gpu Gpu) (device DeviceFoam) (trainer FoamTrainer) (cpu Foam)
                         (start I64) (steps I64)) (→ Foam)
                         (let ((reference
                                (do ((k start (+ k 1))
                                     (sites cpu
                                            (fit-step sites (map (lambda (i) (array-ref samples i))
                                                                 (sample-batch
                                                                  (array-length samples)
                                                                  67
                                                                  k))
                                                      0.01)))
                                    ((= k (+ start steps)) sites))))
                           (train-foam! gpu trainer start steps 0.01)
                           (let ((sites (read-foam gpu device)))
                             (unless (and (= (array-length reference) (array-length sites))
                                          (every? (lambda (i)
                                                    (same-site? (array-ref reference i)
                                                                (array-ref sites i)))
                                                  (iota (array-length reference))))
                               (panic "foam GPU update differs in position, density or RGB")))
                           reference))

    (define (check-foam (gpu Gpu)) (→ String)
      (let* ((device (make-device-foam gpu line))
             (trainer (make-foam-trainer gpu device samples 67)))
        (check-camera gpu device)
        (check-draw gpu device line samples)
        (let* ((first (check-steps gpu device trainer line 0 1))
               (trained (check-steps gpu device trainer first 1 34)))
          (check-draw gpu device trained samples))
        (release-foam-trainer gpu trainer)
        (release-device-foam gpu device))
      ;; At x=0 the ray lies on a whole face. The first site's index
      ;; decides the tie even when its Morton key puts it last.
      (let* ((a (site (vec3d 0.5 0.0 0.0) 200.0 target))
             (b (site (vec3d -0.5 0.0 0.0) 0.0 (vec3d 0.0 0.0 0.0)))
             (tied (new Sample (ray (ray (vec3d 0.0 -1.0 0.0) (vec3d 0.0 1.0 0.0))) (rgb target))))
        (for-each (lambda (cpu)
                    (let ((device (make-device-foam gpu cpu)))
                      (check-draw gpu device cpu (list->array (list tied)))
                      (check-draw gpu device cpu samples)
                      (release-device-foam gpu device)))
                  (list (make-foam (list a b)) (make-foam (list b)) (make-foam (Nil)))))
      "rays and all seven fitted site parameters agree with the CPU")

    ))
