;; The offline renderer and native fixtures link the same published city files.
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
      (list (link-file "main.resources/sf-0.bin")
            (link-file "main.resources/sf-1.bin")
            (link-file "main.resources/sf-2.bin")
            (link-file "main.resources/sf-3.bin")
            (link-file "main.resources/sf-4.bin")
            (link-file "main.resources/sf-5.bin")))
    (define streets-model (→ Resource) (link-file "main.resources/streets.nav"))
    (define map-image (→ Resource) (link-file "main.resources/sf-map.png"))
    (define horizon-model (→ Resource) (link-file "main.resources/horizon.glb"))
    (define taxi-model (→ Resource) (link-file "main.resources/taxi.glb"))
    (define other-model (→ Resource) (link-file "main.resources/sedan.glb"))
    (define people-model (→ Resource) (link-file "main.resources/crew.glb"))
    (define (art-reader (r Resources) (paths (List String))) (→ (List Bytes))
      (read-resources r (map (lambda (path)
                               (cond ((or (string=? path "Textures/colormap.png")
                                          (string=? path "./Textures/colormap.png"))
                                      (link-file "main.resources/Textures/colormap.png"))
                                     ((string=? path "sf-facade.png")
                                      (link-file "main.resources/sf-facade.png"))
                                     ((string=? path "sf-stucco.png")
                                      (link-file "main.resources/sf-stucco.png"))
                                     ((string=? path "sf-brick.png")
                                      (link-file "main.resources/sf-brick.png"))
                                     ((string=? path "sf-works.png")
                                      (link-file "main.resources/sf-works.png"))
                                     ((string=? path "sf-office.png")
                                      (link-file "main.resources/sf-office.png"))
                                     (else (panic
                                            (string-append "unknown linked scene texture " path)))))
                             paths)))))
