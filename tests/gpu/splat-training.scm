(import
 (snail core base)
 (snail core io)
 (snail shell gpu)
 (gpu-test splat-train))

(define (main (host Host) (out OutputPort)) (→ Unit)
  (let ((gpu (host-gpu host)))
    ((● gpu request-device))
    (splat-checks gpu out)
    (training-checks gpu out)
    ((● gpu work-done))))
