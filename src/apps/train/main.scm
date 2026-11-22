;; Train: 3D Gaussian Splatting trained in the page by (apps train
;; trainer), on a COLMAP dataset as (apps train dataset) reads one: the
;; page's query gives the settings, the dataset's files are fetched from
;; its URL, and the canvas shows each 50th step's image. The page is
;; ready as soon as training starts. Nothing is kept; a reload trains
;; again.
(import
 (snail core base)
 (only (snail shell page))
 (only (snail shell gpu))
 (only (snail shell fetch) Fetch fetch-bytes)
 (apps train dataset)
 (apps train trainer)
 (only (snail shell gpu) Gpu)
 (only (snail shell page) Events)
 (only (snail core io) Clock)
 (only (snail core io) OutputPort))

(define (fetched (fetch Fetch) (url String)) (→ Bytes)
  (match (fetch-bytes fetch url)
    ((Ok bytes) bytes)
    ((Err why) (panic why))))

(define (main (gpu Gpu) (fetch Fetch) (events Events) (clock Clock) (out OutputPort))
  (→ Unit)
  (events::report-ready)
  (let ((settings (settings-of (fetch::page-address))) (format (● (gpu::request-device) format)))
    (let ((photographs (new Photographs
                         (photograph (lambda (image)
                                       (dataset-photograph gpu
                                                           (lambda (url) (fetched fetch url))
                                                           settings
                                                           image))))))
      (train photographs
             gpu
             clock
             out
             (dataset-scene gpu (lambda (url) (fetched fetch url)) settings)
             (● settings options)
             (shown-on-canvas gpu format))))
  (unit))
