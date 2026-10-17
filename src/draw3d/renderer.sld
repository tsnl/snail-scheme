;; The Scheme renderer traverses the scene, resolves transforms and copies one
;; indexed frame to the host. GPU buffers belong to the browser renderer alone.
(define-library (draw3d renderer)
  (export present-scene!)
  (import
   (scheme base)
   (draw3d math)
   (draw3d scene)
   (only (lofi base) f32->bits f64->f32 i32->i64)
   (only (lofi core) define-extern -> I32 match))
  (begin

    ;; ---- A copied scalar frame; no managed references escape Wasm ----

    (define-extern stage-uniform "snail.scene" "uniform" (-> I32 I32 Unit))
    (define-extern stage-vertex "snail.scene" "vertex" (-> I32 I32 I32 I32 I32 I32 I32 I32 Unit))
    (define-extern stage-triangle "snail.scene" "triangle" (-> I32 I32 I32 Unit))
    (define-extern stage-background "snail.scene" "background" (-> I32 Unit))
    (define (float-bits value) (f32->bits (f64->f32 value)))
    (define (uniform! offset value) (stage-uniform offset (float-bits value)))
    (define (uniform-vector! offset value)
      (uniform! offset (vec3-x value)) (uniform! (+ offset 1) (vec3-y value))
      (uniform! (+ offset 2) (vec3-z value)))
    (define (scene-uniforms! value)
      (let ((matrix (camera-matrix (scene-camera value))) (light (scene-light value)))
        (let loop ((index 0))
          (when (< index 16) (uniform! index (vector-ref matrix (i32->i64 index))) (loop (+ index 1))))
        (uniform-vector! 16 (light-direction light)) (uniform! 19 (light-intensity light))
        (uniform-vector! 20 (scene-ambient value)) (uniform! 23 1.0)
        (stage-background (scene-background value))))

    ;; ---- Transform positions and inverse-transpose normals exactly once ----

    (define (vertex! value surface frame)
      (let ((point (transform-point frame (vertex-position value)))
            (normal (transform-normal frame (vertex-normal value))))
        (stage-vertex (float-bits (vec3-x point)) (float-bits (vec3-y point)) (float-bits (vec3-z point))
                      (float-bits (vec3-x normal)) (float-bits (vec3-y normal)) (float-bits (vec3-z normal))
                      (material-rgb surface) (float-bits (material-emission surface)))))
    (define (geometry! value surface frame first)
      (let loop ((index 0))
        (when (< index (geometry-vertex-count value))
          (vertex! (geometry-vertex value index) surface frame) (loop (+ index 1))))
      (let loop ((index 0))
        (when (< index (geometry-index-count value))
          (stage-triangle (+ first (geometry-index value index))
                          (+ first (geometry-index value (+ index 1))) (+ first (geometry-index value (+ index 2))))
          (loop (+ index 3))))
      (+ first (geometry-vertex-count value)))
    (define (nodes! nodes parent first)
      (if (null? nodes) first
          (let ((next (match (car nodes)
                        ((mesh geometry material local) (geometry! geometry material (compose parent local) first))
                        ((group local children) (nodes! children (compose parent local) first)))))
            (nodes! (cdr nodes) parent next))))
    (define (present-scene! value)
      (scene-uniforms! value)
      (nodes! (scene-nodes value) identity-transform 0) (unit))))
