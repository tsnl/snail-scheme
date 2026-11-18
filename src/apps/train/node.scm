;; Train on Node: 3D Gaussian Splatting trained on a COLMAP scene in a
;; folder, as (apps train trainer) describes, on the GPU Dawn finds and
;; with nothing shown. The arguments are the settings, and `scene` is the
;; folder's path, ending in a slash:
;;
;;   node main.mjs scene=build/datasets/bicycle/ steps=30000
;;
;; A photograph is read as a task waits, and decoded on the host's
;; threads, so the next steps' photographs come while a step trains.
(import
 (snail core base)
 (only (snail core io) fs command-line read-bytes)
 (only (snail shell task) tasks)
 (only (snail shell gpu) provide-gpu request-device)
 (only (snail shell async-files) files read-file TooLarge)
 (apps train trainer))

;; A file of the scene. One within the 16 MiB a waiting read allows, as
;; every photograph is, is read while the other tasks run; a larger one,
;; as the scene's list of images may be, at once.
(define (read (path String)) (→ Bytes) (! files fs tasks)
  (match (read-file path 16777216)
    ((Ok bytes) bytes)
    ((Err (TooLarge)) (read-bytes path))
    ((Err _) (panic (string-append "cannot read " path)))))

(provide-gpu (lambda ()
               (request-device)
               (handle dataset
                   ((dataset-bytes read))
                 (train (settings-of (string-append "?"
                                                    (string-join (list-tail (command-line) 1) "&")))
                        shown-nowhere))))
