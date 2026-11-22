;; Train on Node: 3D Gaussian Splatting trained by (apps train trainer),
;; on a COLMAP dataset as (apps train dataset) reads one, on the GPU Dawn
;; finds and with nothing shown. The arguments are the settings, and
;; `scene` is the dataset's folder, ending in a slash. `cloud=PATH` keeps
;; what was trained, as the .ply file the reference implementation
;; writes. The file is made before training starts, empty, so a path that
;; cannot be written stops the run then and not half an hour on:
;;
;;   node main.mjs scene=build/datasets/bicycle/ steps=30000 cloud=bicycle.ply
;;
;; A photograph is read as a task waits, and decoded on the host's
;; threads, so the next steps' photographs come while a step trains.
(import
 (snail core base)
 (only (snail core io) Fs command-line read-bytes write-bytes write-line OutputPort)
 (only (snail shell task) tasks)
 (only (snail shell gpu) host-gpu request-device)
 (only (snail shell async-files) Files read-file TooLarge)
 (only (snail shell graphics ply) write-ply)
 (apps train dataset)
 (apps train trainer)
 (only (snail core io) Clock))

;; A file of the dataset. One within the 16 MiB a waiting read allows, as
;; every photograph is, is read while the other tasks run; a larger one,
;; as the dataset's list of images may be, at once.
(define (read (files Files) (fs Fs) (path String)) (→ Bytes) (! mut tasks)
  (match (read-file files path 16777216)
    ((Ok bytes) bytes)
    ((Err (TooLarge)) (read-bytes fs path))
    ((Err _) (panic (string-append "cannot read " path)))))

(define (main (files Files) (fs Fs) (clock Clock) (out OutputPort)) (→ Unit) (! mut host tasks)
  (let ((gpu (host-gpu)))
(request-device gpu)
   (let* ((address (string-append "?" (string-join (list-tail (command-line) 1) "&")))
          (settings (settings-of address))
          (cloud (setting address "cloud")))
     (match cloud
       ((Some path) (write-bytes fs path (make-array 0 (i32->u8 0))))
       ((None) (unit)))
     (let ((trained (handle photographs
                        ((photograph (lambda (image) (dataset-photograph gpu (lambda (files top paths) (read files fs files top paths)) settings image))))
                      (train photographs gpu clock out (dataset-scene gpu (lambda (files top paths) (read files fs files top paths)) settings) (● settings options) shown-nowhere))))
       (match cloud
         ((Some path)
          (write-bytes fs path (write-ply (trained-cloud gpu trained)))
          (write-line out (string-append "kept the cloud in " path)))
         ((None) (unit))))))
  (unit))
