;; A build that embeds itself: the producer of the library own.scm
;; imports builds own.scm, whose build would run it again.
(generate-library (embedded own)
                  (import
                   (snail core base)
                   (snail shell project build)
                   (embedded linking)
 (only (snail core io) Fs Clock)
 (only (snail shell process) Processes))
                  (lambda ((processes Processes) (fs Fs) (clock Clock))
(files-library fs (list "embedded" "own")
                                 "own-files"
                                 (build-script processes fs clock (producer-tools)
                                               (script-at fs "own.scm")
                                               (Node)
                                               (Debug)))))
