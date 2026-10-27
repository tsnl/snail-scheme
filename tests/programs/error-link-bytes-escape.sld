;; A linked file ships under a name made from its path, so the path may not
;; leave the directory of the file that names it.
(import
 (snail-core base)
 (snail-core resource))

(define image (link-bytes "data/../../programs/data/pixel.png"))
