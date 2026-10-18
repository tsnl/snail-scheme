(define-library (tests draw3d frame)
  (export answer)
  (import
   (scheme base)
   (scheme immutable)
   (draw3d)
   (siegework model)
   (siegework view)
   (only (lofi core) ann -> I32))
  (begin
    (define answer
      (ann (lambda ()
             (present-scene! (colony-scene (initial-world) (initial-world) (colony-camera 196000 122000 960 640) 12 20 3 (list))) 1)
           (-> I32)))))
