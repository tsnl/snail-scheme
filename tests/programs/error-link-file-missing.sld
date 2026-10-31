;; A build fails when a file a library links is not there, naming the
;; library and the path.
(import
 (snail core base)
 (snail shell resource))

(define image (link-file "data/missing.bin"))
