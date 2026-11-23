;; Train on Node: 3D Gaussian Splatting trained by (apps train trainer),
;; on Mip-NeRF 360's bicycle as (datasets mipnerf360 bicycle) links it,
;; on the GPU Dawn finds and with nothing shown. The arguments are the
;; options (apps train dataset) reads, and `cloud=PATH` keeps what was
;; trained, as the .ply file the reference implementation writes. The
;; file is made before training starts, empty, so a path that cannot be
;; written stops the run then and not half an hour on:
;;
;;   node main.mjs steps=30000 cloud=bicycle.ply
;;
;; A photograph is read from the package's store as a task waits, and
;; decoded on the host's threads, so the next steps' photographs come
;; while a step trains.
(import
 (snail core base)
 (only (snail core io) Host Arguments Fs command-line write-bytes write-line OutputPort Clock)
 (only (snail shell resource) Resources)
 (only (snail shell gpu) host-gpu)
 (only (snail shell graphics ply) write-ply)
 (apps train dataset)
 (apps train trainer)
 (only (datasets mipnerf360 bicycle) files photographs))

(define (main (host Host)
              (arguments Arguments)
              (resources Resources)
              (fs Fs)
              (clock Clock)
              (out OutputPort))
  (→ Unit)
  (let ((gpu (host-gpu host)))
    ((● gpu request-device))
    (let* ((address (string-append "?" (string-join (list-tail (command-line arguments) 1) "&")))
           (dataset (linked-dataset resources files photographs))
           (cloud (setting address "cloud")))
      (match cloud
        ((Some path) (write-bytes fs path (make-array 0 (i32->u8 0))))
        ((None) (unit)))
      (let ((trained (train (new Photographs
                              (photograph (lambda (image) (dataset-photograph gpu dataset image))))
                            gpu
                            clock
                            out
                            (dataset-scene gpu dataset)
                            (options-of address)
                            shown-nowhere)))
        (match cloud
          ((Some path)
           (write-bytes fs path (write-ply (trained-cloud gpu trained)))
           (write-line out (string-append "kept the cloud in " path)))
          ((None) (unit))))))
  (unit))
