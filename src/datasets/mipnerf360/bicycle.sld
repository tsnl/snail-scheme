;; Mip-NeRF 360's bicycle, one of its outdoor scenes: its sparse
;; reconstruction and its 194 photographs at a quarter of their size,
;; images_4, at which 3D Gaussian Splatting trains the outdoor scenes. They
;; are read into the machine's cache the first time this library is built,
;; and linked from there ((datasets mipnerf360)).
(generate-library (datasets mipnerf360 bicycle)
                  (import
                   (snail core base)
                   (only (snail core io) Fs ProcessEnvironment)
                   (only (snail shell web) Web)
                   (datasets mipnerf360))
                  (lambda ((fs Fs) (web Web) (environment ProcessEnvironment))
                    (scene-library fs web environment
                                   (list "datasets" "mipnerf360" "bicycle")
                                   "bicycle"
                                   "images_4")))
