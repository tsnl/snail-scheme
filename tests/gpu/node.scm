;; Render and read back textures and buffers on the device from Dawn.
(import
 (snail core base)
 (snail core io)
 (snail shell resource)
 (snail shell gpu)
 (gpu-test device))

(define (main (resources Resources) (host Host) (out OutputPort)) (→ Unit)
  (let* ((gpu (host-gpu host)) (info ((● gpu request-device))))
    (write-line out (string-append "format: " (texture-format-name (● info format))))
    (device-checks gpu out resources)
    ((● gpu work-done))))
