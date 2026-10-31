;; A linked file ships under a name made from its path, so the path may not
;; leave the directory of the file that names it.
(import
 (snail core base)
 (snail shell resource))

(define image (link-file "data/../../programs/data/pixel.png"))
