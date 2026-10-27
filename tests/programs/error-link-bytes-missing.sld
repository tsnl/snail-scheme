;; A build fails when a file a library links is not there, naming the
;; library and the path.
(import
 (snail-core base)
 (snail-core resource))

(define image (link-bytes "data/missing.bin"))
