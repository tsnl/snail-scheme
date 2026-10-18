(define-library (tests draw3d motion)
  (export answer)
  (import
   (scheme base)
   (scheme immutable)
   (draw3d)
   (only (lofi core) ann -> I32))
  (begin

    ;; ---- Both complete transform hierarchies reach the scalar boundary ----

    (define red (material 16711680 1.0))
    (define camera
      (orthographic-camera (vec3 0.0 -10.0 10.0) (vec3 0.0 0.0 0.0)
                           (vec3 0.0 0.0 1.0) 20.0 1.5 0.1 100.0))
    (define (moving-nodes)
      (list (moving-group (translation (vec3 1.0 2.0 3.0)) (translation (vec3 4.0 5.0 6.0))
                          (list (group (scaling 2.0 3.0 4.0)
                                       (list (mesh plane-geometry red identity-transform)))
                                (moving-group (translation (vec3 -1.0 0.0 0.0))
                                              (translation (vec3 1.0 0.0 0.0))
                                              (list (mesh box-geometry red identity-transform)))))))
    (define (still-nodes)
      (list (group (translation (vec3 7.0 8.0 9.0))
                   (list (mesh box-geometry red identity-transform)))))
    (define (inset-picture nodes height)
      (batched-scene
       (orthographic-camera (vec3 0.0 -10.0 10.0) (vec3 0.0 0.0 0.0)
                            (vec3 0.0 0.0 1.0) height 1.5 0.1 100.0)
       (list (reveal-batch (retained-batch 10 0 (empty-list) nodes) 91 0.0 0.0 20.0 0.7 250 3000))
       (directional-light (vec3 0.0 0.0 1.0) 0.0) (vec3 1.0 1.0 1.0) 0))
    (define answer
      (ann (lambda ()
             (present-scene!
              (batched-scene camera
                             (list (retained-batch 10 0 (empty-list) still-nodes)
                                   (reveal-batch (motion-batch 11 1 (empty-list) 100 moving-nodes)
                                                 91 0.0 0.0 20.0 0.7 250 3000)
                                   (motion-batch 12 0 (empty-list) 200 still-nodes))
                             (directional-light (vec3 0.0 0.0 1.0) 0.0)
                             (vec3 1.0 1.0 1.0) 0))
             (present-scene-inset! 7 (inset-picture moving-nodes 10.0) 10 20 96 72)
             (present-scene-inset! 8 (inset-picture still-nodes 20.0) 110 20 96 72) 1)
           (-> I32)))))
