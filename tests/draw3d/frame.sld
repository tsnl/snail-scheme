(define-library (tests draw3d frame)
  (export answer)
  (import
   (scheme base)
   (draw3d)
   (siegework model)
   (siegework view)
   (only (lofi core) ann -> I32))
  (begin
    (define answer
      (ann (lambda ()
             (present-scene! (colony-scene (initial-world) (colony-camera 10000 22000 960 640) 12 20)) 1)
           (-> I32)))))
