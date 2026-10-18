;; Public scene drawing API. Scene values are rebuilt from explicit application
;; state; a browser renderer owns and disposes their copied GPU representation.
(define-library (draw3d)
  (export Vec3 vec3 vec3-x vec3-y vec3-z v+ v- v* dot cross normalize scalar
          Transform transform identity-transform translation scaling compose look-at
          transform-point transform-vector transform-normal
          Camera orthographic-camera perspective-camera camera-matrix camera-ray
          Ray ray ray-origin ray-direction ray-ground Bounds bounds ray-box
          Vertex vertex Geometry indexed-geometry box-geometry plane-geometry pyramid-geometry
          Material material Node mesh group SceneBatch retained-batch dynamic-batch
          Scene scene batched-scene directional-light present-scene!)
  (import
   (draw3d math)
   (draw3d scene)
   (draw3d renderer)))
