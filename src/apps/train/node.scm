;; Train on Node: 3D Gaussian Splatting trained on a COLMAP scene in a
;; folder, as (apps train trainer) describes, on the GPU Dawn finds and
;; with nothing shown. The arguments are the settings, and `scene` is the
;; folder's path, ending in a slash. `cloud=PATH` keeps what was trained,
;; as the .ply file the reference implementation writes. The file is made
;; before training starts, empty, so a path that cannot be written stops
;; the run then and not half an hour on:
;;
;;   node main.mjs scene=build/datasets/bicycle/ steps=30000 cloud=bicycle.ply
;;
;; A photograph is read as a task waits, and decoded on the host's
;; threads, so the next steps' photographs come while a step trains.
(import
 (snail core base)
 (only (snail core io) fs command-line read-bytes write-bytes write-line output-port)
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

;; The path the arguments give `cloud`, if they name one.
(define (cloud-path (arguments (List String))) (→ (Option String))
  (match (find (lambda (argument)
                 (and (> (string-length argument) 6) (string=? (substring argument 0 6) "cloud=")))
               arguments)
    ((Some argument) (Some (substring argument 6 (string-length argument))))
    ((None) (None))))

(provide-gpu (lambda ()
               (request-device)
               (let* ((arguments (list-tail (command-line) 1))
                      (_ (match (cloud-path arguments)
                           ((Some path) (write-bytes path (make-array 0 (i32->u8 0))))
                           ((None) (unit))))
                      (trained (handle dataset
                                   ((dataset-bytes read))
                                 (train (settings-of (string-append "?"
                                                                    (string-join arguments "&")))
                                        shown-nowhere))))
                 (match (cloud-path arguments)
                   ((Some path)
                    (write-bytes path (trained-ply trained))
                    (write-line (string-append "kept the cloud in " path)))
                   ((None) (unit))))))
