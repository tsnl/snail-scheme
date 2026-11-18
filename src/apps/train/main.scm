;; Train: 3D Gaussian Splatting trained on a COLMAP scene in the page, as
;; (apps train trainer) describes: the page's query gives the settings,
;; the scene's files are fetched from its URL, and the canvas shows each
;; 50th step's image. The page is ready as soon as training starts.
;; Nothing is saved; a reload trains again.
(import
 (snail core base)
 (only (snail shell task) tasks)
 (only (snail shell page) report-ready)
 (only (snail shell gpu) request-device)
 (only (snail shell fetch) fetch fetch-bytes page-address)
 (snail shell fetch page)
 (apps train trainer))

(define (fetched (url String)) (→ Bytes) (! fetch tasks)
  (match (fetch-bytes url)
    ((Ok bytes) bytes)
    ((Err why) (panic why))))

(with-page-fetch (lambda ()
                   (report-ready)
                   (handle dataset
                       ((dataset-bytes fetched))
                     (train (settings-of (page-address))
                            (shown-on-canvas (● (request-device) format))))))
