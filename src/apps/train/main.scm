;; Train: 3D Gaussian Splatting trained in the page by (apps train
;; trainer), on Mip-NeRF 360's bicycle as (datasets mipnerf360 bicycle)
;; links it: the page's query gives the options (apps train dataset)
;; reads, the dataset's files are fetched from the page's store as the
;; trainer asks for them, and the canvas shows each 50th step's image. The
;; page is ready as soon as training starts. Nothing is kept; a reload
;; trains again.
(import
 (snail core base)
 (only (snail shell fetch) Fetch)
 (only (snail shell resource) Resources)
 (apps train dataset)
 (apps train trainer)
 (only (datasets mipnerf360 bicycle) files photographs)
 (only (snail shell gpu) Gpu)
 (only (snail shell page) Events)
 (only (snail core io) Clock OutputPort))

(define (main (gpu Gpu)
              (fetch Fetch)
              (resources Resources)
              (events Events)
              (clock Clock)
              (out OutputPort))
  (→ Unit)
  ((● events report-ready))
  (let ((dataset (linked-dataset resources files photographs))
        (format (● ((● gpu request-device)) format)))
    (train (new Photographs (photograph (lambda (image) (dataset-photograph gpu dataset image))))
           gpu
           clock
           out
           (dataset-scene gpu dataset)
           (options-of ((● fetch page-address)))
           (shown-on-canvas gpu format)))
  (unit))
