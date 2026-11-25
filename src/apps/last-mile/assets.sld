;; All geometry, images and streets are linked objects of the build. Reading
;; the six map bands together completes the city's only map download.
(define-library (apps last-mile assets)
  (export city-bands
          streets-model
          map-image
          horizon-model
          taxi-model
          other-model
          people-model
          art-reader)
  (import
   (snail core base)
   (snail shell resource))
  (begin
    (define city-bands (→ (List Resource))
      (list (link-file "assets/sf-0.bin")
            (link-file "assets/sf-1.bin")
            (link-file "assets/sf-2.bin")
            (link-file "assets/sf-3.bin")
            (link-file "assets/sf-4.bin")
            (link-file "assets/sf-5.bin")))
    (define streets-model (→ Resource) (link-file "assets/streets.nav"))
    (define map-image (→ Resource) (link-file "assets/sf-map.png"))
    (define horizon-model (→ Resource) (link-file "assets/horizon.glb"))
    (define taxi-model (→ Resource) (link-file "assets/taxi.glb"))
    (define other-model (→ Resource) (link-file "assets/sedan.glb"))
    (define people-model (→ Resource) (link-file "assets/crew.glb"))
    (define (art-reader (r Resources) (paths (List String))) (→ (List Bytes))
      (read-resources r (map (lambda (path)
                               (cond ((or (string=? path "Textures/colormap.png")
                                          (string=? path "./Textures/colormap.png"))
                                      (link-file "assets/Textures/colormap.png"))
                                     ((string=? path "sf-facade.png")
                                      (link-file "assets/sf-facade.png"))
                                     ((string=? path "sf-stucco.png")
                                      (link-file "assets/sf-stucco.png"))
                                     ((string=? path "sf-brick.png")
                                      (link-file "assets/sf-brick.png"))
                                     ((string=? path "sf-works.png")
                                      (link-file "assets/sf-works.png"))
                                     ((string=? path "sf-office.png")
                                      (link-file "assets/sf-office.png"))
                                     (else (panic
                                            (string-append "unknown linked scene texture " path)))))
                             paths)))))
