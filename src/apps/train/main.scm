;; Train: 3D Gaussian Splatting trained on a COLMAP scene in the page, as
;; (apps train trainer) describes. The page is ready as soon as training
;; starts. Nothing is saved; a reload trains again.
(import
 (snail core base)
 (only (snail shell page) report-ready)
 (snail shell fetch page)
 (apps train trainer))

(with-page-fetch (lambda ()
                   (report-ready)
                   (train)))
