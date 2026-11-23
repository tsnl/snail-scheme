;; Mip-NeRF 360's kitchen, one of its indoor scenes: its sparse
;; reconstruction and its 279 photographs at a half of their size,
;; images_2, at which 3D Gaussian Splatting trains the indoor scenes. They
;; are read into the machine's cache the first time this library is built,
;; and linked from there ((datasets mipnerf360)).
(generate-library (datasets mipnerf360 kitchen)
                  (import
                   (snail core base)
                   (only (snail core io) Fs ProcessEnvironment)
                   (only (snail shell web) Web)
                   (datasets mipnerf360))
                  (lambda ((fs Fs) (web Web) (environment ProcessEnvironment))
                    (scene-library fs web environment
                                   (list "datasets" "mipnerf360" "kitchen")
                                   "kitchen"
                                   "images_2")))
