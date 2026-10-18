(define-library (tests draw3d instances)
  (export answer)
  (import
   (scheme base)
   (scheme immutable)
   (draw3d)
   (only (lofi core) ann -> I32))
  (begin

    ;; ---- Fixed composites, ordered runs and explicit opaque regrouping ----

    (define red (material 16711680 1.0))
    (define blue (material 255 1.0))
    (define camera
      (orthographic-camera (vec3 0.0 -10.0 10.0) (vec3 0.0 0.0 0.0)
                           (vec3 0.0 0.0 1.0) 20.0 1.5 0.1 100.0))
    (define body
      (model (list (mesh box-geometry red identity-transform)
                   (group (translation (vec3 0.0 0.0 1.0))
                          (list (mesh pyramid-geometry blue (scaling 0.5 0.5 0.5)))))))
    (define (alternating)
      (list (mesh box-geometry red identity-transform)
            (mesh box-geometry blue (translation (vec3 2.0 0.0 0.0)))
            (mesh box-geometry (material 16711680 1.0) (translation (vec3 4.0 0.0 0.0)))))
    (define (bodies)
      (list (moving-group (translation (vec3 -2.0 0.0 0.0)) (translation (vec3 2.0 0.0 0.0))
                          (list (model-instance body (scaling -2.0 3.0 4.0))))
            (model-instance body (translation (vec3 0.0 4.0 0.0)))))
    (define (picture batches)
      (batched-scene camera batches (directional-light (vec3 0.0 0.0 1.0) 0.0) (vec3 1.0 1.0 1.0) 0))
    (define (present-instances)
      (present-scene!
       (picture (list (retained-batch 101 1 (empty-list) alternating)
                      (unordered-batch (retained-batch 102 1 (empty-list) alternating))
                      (motion-batch 103 1 (empty-list) 100 bodies)))))
    (define (bad-model)
      (model (list (moving-group identity-transform (translation (vec3 1.0 0.0 0.0))
                                (list (mesh box-geometry red identity-transform))))))
    (define (scaled-picture x y)
      (picture (list (dynamic-batch (lambda () (list (mesh box-geometry red (scaling x y 1.0))))))))
    (define answer
      (ann (lambda (mode)
             (cond ((= mode 0) (present-instances) 1)
                   ((= mode 1) (model-instance (bad-model) identity-transform) 1)
                   ((= mode 2) (present-scene! (scaled-picture 1.0e-24 1.0e24)) 1)
                   ((= mode 3) (present-scene! (scaled-picture 1.0e-18 1.0e18)) 1)
                   ((= mode 4) (present-scene! (scaled-picture 0.0 1.0)) 1)
                   (else 0)))
           (-> I32 I32)))))
