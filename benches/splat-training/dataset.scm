;; Mip-NeRF 360's bicycle as the bench's trainers read it: its sparse
;; reconstruction, and its photographs at full size, which gsplat lists,
;; and at a quarter of it, which every trainer trains on. They are read
;; into the machine's cache as the train app's build reads them
;; ((datasets mipnerf360)), and this prints the folder that holds them:
;;
;;   ./snail-scheme run --target node benches/splat-training/dataset.scm
(import
 (snail core base)
 (only (snail core io) Fs ProcessEnvironment OutputPort write-line)
 (only (snail shell web) Web)
 (datasets mipnerf360))

(define (main (fs Fs) (web Web) (environment ProcessEnvironment) (out OutputPort))
  (→ Unit)
  (write-line out (scene-folder fs web environment "bicycle" (list "images" "images_4"))))
