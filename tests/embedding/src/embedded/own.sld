;; A build that embeds itself: the producer of the library own.scm
;; imports builds own.scm, whose build would run it again.
(generate-library (embedded own)
                  (import
                   (snail core base)
                   (snail shell project build)
                   (embedded linking))
                  (files-library (list "embedded" "own")
                                 "own-files"
                                 (build-script (producer-tools)
                                               (script-at "own.scm")
                                               (Node)
                                               (Debug))))
