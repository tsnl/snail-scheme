(import
 (snail core base)
 (snail core io)
 (lazy values)
 (lazy reader))

(define (main) (→ Unit) (! mut output-port)
  (write-line (show (bump)))
  (write-line (show (read-cell)))
  (set! (● alias value) 5)
  (write-line (show (read-cell)))
  (write-line (show (next)))
  (write-line (show (● cell value)))
  (write-line (show (+ (length (ann empty (List I64))) (length (ann empty (List String)))))))
