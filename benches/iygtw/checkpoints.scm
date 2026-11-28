;; Save ordinary rides at three different approaches to measure the same roads.
(import
 (snail core base)
 (snail core io)
 (snail shell wire)
 (snail shell game physics)
 (apps iygtw ride))

(define (main (fs Fs)) (→ Unit)
  (let* ((read
          (lambda (name)
            (read-bytes fs (string-append "src/apps/iygtw/willowbank/main.resources/" name))))
         (v (read-valley (read "ground.bin") (read "surfaces.bin") (read "waymarks.bin"))))
    (define (save (name String) (p XZ) (yaw F64) (light I64)) (→ Unit)
      (let ((ride (Ride-light-set (start-ride v) light)))
        (set! (● ride bike) (body p yaw))
        (set! (● ride dog) (body (offset p (forward (+ yaw 1.5708)) 1.2) yaw))
        (write-bytes fs (string-append "build/" name ".ride") (serialize ride))))
    (save "lantern-row" (● (start-ride v) bike position) 0.065 0)
    (save "mill-bridge" (xz 15.75 -23.0) 0.0 0)
    (save "orchard" (xz -30.0 19.5) -0.72 2)))
