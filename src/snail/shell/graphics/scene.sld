;; The public mesh frame is ordinary scene data. Recording it does not
;; retain a device, command encoder, texture, or a closure over the game.
(define-library (snail shell graphics scene)
  (export SceneNode
          ModelNode
          GroupNode
          scene-geometry
          load-scene-node
          DirectionalLight
          SceneFrame
          scene-frame
          render-scene!
          present-scene!
          SkySource BakedSky Panorama SceneDescription SceneRecording recording-frame)
  (import
   (snail core base)
   (snail shell wire)
   (only (snail shell graphics gltf) Gltf Gltf-placed-set gltf-transformed append-gltf unreadable)
   (only (snail shell graphics pod) Vec4f Mat4x4f)
   (only (snail shell graphics animation) unit-matrix matrix-product)
   (only (snail shell graphics forward scene) Scene load-scene read-model-file upload-scene)
   (snail shell gpu)
   (only (snail shell graphics passes) Tone)
   (only (snail shell graphics raster) Camera3D Plane)
   (snail shell graphics forward render)
   (snail shell graphics compositor))
  (begin
    ;; glTF supplies geometry and materials. A group's local transform places its children.
    (enum SceneNode
      (ModelNode ((asset String)))
      (GroupNode ((transform Mat4x4f) (children (List SceneNode))))
      (deriving Serialize Deserialize))

    (define (placements (node SceneNode) (world Mat4x4f)) (→ (List (Pair String Mat4x4f)))
      (match node
        ((ModelNode asset) (list (new Pair (first asset) (second world))))
        ((GroupNode local children)
         (let ((parent (matrix-product world local)))
           (concatenate (map (lambda (child) (placements child parent)) children))))))
    (define (columns (m Mat4x4f)) (→ (List F64))
      (concatenate (map (lambda ((v Vec4f)) (→ (List F64))
                          (map f32->f64 (list (● v x) (● v y) (● v z) (● v w))))
                        (list (● m x) (● m y) (● m z) (● m w)))))
    ;; Read each referenced asset once. Repeated placements share its buffers and materials.
    (define (scene-geometry (node SceneNode) (load (Fn String → Gltf))) (→ Gltf)
      (let* ((items (placements node unit-matrix))
             (assets (delete-duplicates string=? (map (lambda (p) (● p first)) items)))
             (models (map (lambda (asset)
                            (let* ((g (load asset))
                                   (copies
                                    (filter (lambda (p) (string=? asset (● p first))) items)))
                              (Gltf-placed-set g (concatenate (map (lambda (p)
                                                                     (● (gltf-transformed g
                                                                                          (columns
                                                                                           (● p
                                                                                              second)))
                                                                        placed))
                                                                   copies)))))
                          assets)))
        (match models ((Nil) (unreadable "the scene has no models"))
               ((Cons first rest) (fold-left append-gltf first rest)))))
    (define (load-scene-node (gpu Gpu) (read (Fn (List String) → (List Bytes))) (node SceneNode))
      (→ Scene)
      (match node
        ((ModelNode path) (load-scene gpu read path))
        ((GroupNode _ _)
         (upload-scene gpu read (scene-geometry node (lambda (p) (read-model-file read p)))))))

    (enum SkySource
      (BakedSky ((period I64)))
      (Panorama ((file String)))
      (deriving Serialize Deserialize))
    (record SceneDescription
      ((root SceneNode)
       (sky SkySource)
       (tone Tone))
      (deriving Serialize Deserialize))
    (record SceneFrame
      ((camera Camera3D)
       (width I32)
       (height I32)
       (samples I32)
       (exposure F32)
       (lights (List DirectionalLight))
       (shadows Bool)
       (shading Shading)
       (cascade I32))
      (deriving Serialize Deserialize))
    (record SceneRecording
      ((scene SceneDescription)
       (frames (List SceneFrame)))
      (deriving Serialize Deserialize))

    (define (scene-frame (camera Camera3D) (w I32) (h I32) (samples I32) (exposure F32))
      (→ SceneFrame)
      (new SceneFrame
        (camera camera)
        (width w)
        (height h)
        (samples samples)
        (exposure exposure)
        (lights (Nil))
        (shadows #t) (shading (MetallicRoughness)) (cascade -1)))
    (define (recording-frame (recording SceneRecording) (index I64)) (→ SceneFrame)
      (unless (and (>= index 0) (< index (length (● recording frames))))
        (panic "frame outside recorded scene"))
      (list-ref (● recording frames) index))

    (define (encode-frame (gpu Gpu) (encoder GpuCommandEncoder) (r Forward) (frame SceneFrame))
      (→ Plane)
      (let ((w (● frame width))
            (h (● frame height))
            (samples (● frame samples))
            (cascade (● frame cascade)))
        (unless (and (> w 0) (<= w 16384) (> h 0) (<= h 16384) (or (= samples 1) (= samples 4))
                     (> (● frame exposure) 0.0) (>= cascade -1) (<= cascade 2))
          (panic "invalid scene frame"))
        (set-directional-lights! gpu r (● frame lights))
        (set! (● r inspect) cascade) (set! (● r shading) (● frame shading))
        (draw-forward gpu
                      encoder
                      (resize-forward gpu r w h samples)
                      (● frame camera)
                      (● frame exposure)
                      (● frame shadows))))

    (define (render-scene! (r Forward) (frame SceneFrame)) (→ Plane)
      (let* ((gpu (● r gpu))
             (encoder ((● gpu create-command-encoder)))
             (image (encode-frame gpu encoder r frame)))
        ((● gpu submit) (list ((● gpu finish) encoder))) image))
    (define (present-scene! (r Forward)
                            (frame SceneFrame)
                            (compositor Compositor)
                            (surface Image))
      (→ Unit)
      (let* ((gpu (● r gpu))
             (encoder ((● gpu create-command-encoder)))
             (image (encode-frame gpu encoder r frame)))
        (present! gpu compositor encoder (● image view) surface)
        ((● gpu submit) (list ((● gpu finish) encoder)))))))
