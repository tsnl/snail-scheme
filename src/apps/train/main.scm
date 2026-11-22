;; Train: 3D Gaussian Splatting trained in the page by (apps train
;; trainer), on a COLMAP dataset as (apps train dataset) reads one: the
;; page's query gives the settings, the dataset's files are fetched from
;; its URL, and the canvas shows each 50th step's image. The page is
;; ready as soon as training starts. Nothing is kept; a reload trains
;; again.
(import
 (snail core base)
 (only (snail shell task) tasks)
 (only (snail shell page) report-ready)
 (only (snail shell gpu) request-device)
 (only (snail shell fetch) Fetch fetch-bytes page-address)
 (snail shell fetch page)
 (apps train dataset)
 (apps train trainer))

(define (fetched (fetch Fetch) (url String)) (→ Bytes) (! mut tasks)
  (match (fetch-bytes fetch url)
    ((Ok bytes) bytes)
    ((Err why) (panic why))))

(with-page-fetch
 (lambda ()
   (report-ready events)
   (let ((settings (settings-of (page-address fetch))) (format (● (request-device gpu) format)))
     (handle photographs
         ((photograph (lambda (image) (dataset-photograph gpu (lambda () (fetched fetch)) settings image))))
       (train photographs gpu clock out (dataset-scene gpu (lambda () (fetched fetch)) settings) (● settings options) (shown-on-canvas gpu format))))))
