(import
 (snail core base)
 (snail core io)
 (snail shell gpu)
 (gpu-test tensor))

(define (main (host Host) (out OutputPort)) (→ Unit)
  (let ((gpu (host-gpu host)))
    ((● gpu request-device))
    (tensor-checks gpu out)
    ((● gpu work-done))))
